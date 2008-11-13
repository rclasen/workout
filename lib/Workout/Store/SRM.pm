
=head1 NAME

Workout::Store::SRM - Perl extension to read/write SRM files

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );
  $iter = $src->iterate;
  while( $chunk = itersrc->next ){
  	...
  }

  $src->write( "out.srm" );

=head1 DESCRIPTION

Interface to read/write SRM power meter files

=cut


package Workout::Store::SRM::Chunk;
use base 'Workout::Chunk';

__PACKAGE__->mk_accessors(qw( pwr ));

sub spd {
	my $self = shift;
	if( @_ ){
		return $self->{spd} = $_[0] * 3.6;
	}
	($self->{spd}||0) / 3.6;
}

sub dist {
	my $self = shift;
	$self->spd * $self->dur;
}

sub work {
	my $self = shift;
	$self->pwr * $self->dur;
}

package Workout::Store::SRM::Iterator;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Iterator';
use Carp;


sub new {
	my $class = shift;
	my $self = $class->SUPER::new( @_ );

	$self->{nbk} = 0;
	$self->{nck} = 0;
	$self->{ctime} = undef;
	$self->{prev} = undef;
	$self;
}

=head2 next

=cut

sub next {
	my( $self ) = @_;

	my $store = $self->store;

	# find next chunk
	while( $self->{nbk} <= $#{$store->{blocks}} ){
		my $blk = $store->{blocks}[$self->{nbk}];

		if( $blk->{skip} ){
			$self->debug( "skipping junk block ". $self->{nbk} );
			$self->{nbk}++;
			$self->{prev} = undef;
			next;
		}

		if( $self->{nck} >= $blk->{ckcnt} ){
			$self->debug( "end of block ". $self->{nbk} );
			$self->{nck} = 0;
			$self->{nbk}++;
			$self->{prev} = undef;
			next;
		}

		# fix time to avoid overlapping
		if( defined $self->{ctime} ){
			$self->{ctime} += $store->recint;

			if( $self->{nck} == 0 ){
				if( $self->{ctime} >
				$blk->{stime}->hires_epoch ){
					my $t = DateTime->from_epoch( 
						epoch => $self->{ctime} );

					warn "fixing time of block "
						. $self->{nbk} 
						. " from ".  $blk->{stime}->hms
						. " to ". $t->hms;
				} else {
					$self->{ctime} = $blk->{stime}->hires_epoch;
				}
			}

		} else {
			$self->{ctime} = $blk->{stime}->hires_epoch
		}

		my $idx = $blk->{ckstart} + $self->{nck}++;
		my $ick = $store->{chunks}[$idx];
		my $ock = Workout::Store::SRM::Chunk->new( $ick );
		$ock->prev( $self->{prev} );
		$ock->time( $self->{ctime} );
		$ock->dur( $store->recint );

		$self->{prev} = $ock;
		$self->{cntin}++;
		$self->{cntout}++;

		return $ock;
	}

	# no chunk found, return nothing
	return;
}




package Workout::Store::SRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use DateTime;

# http://www.stephanmantler.com/?page_id=86

our $VERSION = '0.01';

my %magic_tag = (
	OK19	=> 1,
	SRM2	=> 2,
	SRM3	=> 3,
	SRM4	=> 4,
	SRM5	=> 5,
	SRM6	=> 6,
);

sub filetypes {
	return "srm";
}

# TODO: move blkmin + junk skipping to Filter

__PACKAGE__->mk_accessors(qw(
	tz
	blkmin
	date
	circum
	zeropos
	gradient
));

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class,$a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( {
		blkmin	=> 120, # min. block length/seconds
		tz	=> 'local',
		%$a,
	});

	$self->{blocks} = [];
	$self->{marker} = [];
	$self->{chunks} = [];

	$self;
}

# TODO: block_add
# TODO: chunk_add
# TODO: write

sub read {
	my( $class, $fname, $a ) = @_;
	my $self = $class->new( $a );

	my $fh;
	if( ref $fname ){
		$fh = $fname;
	} else {
		open( $fh, '<', $fname )
			or croak "open '$fname': $!";
	}

	my $buf;

	############################################################
	# file header
	CORE::read( $fh, $buf, 86 ) == 86
		or croak "failed to read file header";
	@_ = unpack( "A4vvCCvvxxA70", $buf );
		
	exists $magic_tag{$_[0]}
		or croak "unrecognized file format";
	my $version = $magic_tag{$_[0]};
	my $clen = 255;
	if( $version < 6 ){
		$clen = 3;
	}
	
	$self->date( DateTime->new( 
		year		=> 1880, 
		month		=> 1, 
		day		=> 1,
		time_zone	=> $self->{tz},
	)->add( days => $_[1] ));

	$self->circum( $_[2] );
	$self->recint( $_[3] / $_[4] );
	my $blockcnt = $_[5];
	my $markcnt = $_[6];

	$self->note( $_[7] );
	if( $_[7] =~ /^(\d+)øC/ ){
		$self->temperature( $1 );
	}
	$self->debug( "date: ". $self->date->ymd 
		." blocks: $blockcnt,"
		." marker: $markcnt,"
		." recint: ". $self->recint );

	############################################################
	# read marker
	while( $markcnt-- >= 0 ){
		CORE::read( $fh, $buf, $clen + 15 ) == $clen + 15
			or croak "failed to read marker";
		@_ = unpack( "A[$clen]Cvvvvvvv", $buf );
		push @{$self->{marker}}, {
			comment	=> $_[0],
			active	=> $_[1],
			ckstart	=> $_[2] -1, # 1..
			ckend	=> $_[3] -1, # 1..
			apwr	=> $_[4] / 8,
			ahr	=> $_[5] / 64,
			hcad	=> $_[6] / 32,
			aspd	=> $_[7] / 2500 * 9,
			pwc	=> $_[8],
		};
		$self->debug( "marker ". @{$self->{marker}}. ": " 
			. '"'. $_[0] .'"'
			. ", first: $_[2]"
			. ", last: $_[3]");
	}

	############################################################
	# data blocks

	my $blockcks = 0;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( "Vv", $buf );
		my $stime = $self->date->clone
			->add( seconds =>  $_[0] / 100 );

		my $ckcnt = $_[1];
		my $blk = {
			stime	=> $stime,
			ckcnt	=> $ckcnt,
			ckstart => $blockcks,
			skip	=> 0,
		};
		push @{$self->{blocks}}, $blk;

		if( $self->{debug} ){
			my $etime = $stime->clone->add( 
				seconds => $ckcnt * $self->recint );

			$self->debug( "block ". $#{$self->{blocks}} .": "
				. sprintf( '%5d+%5d=%5d', 
					$blockcks, $ckcnt, ($blockcks + $ckcnt) )
				." @". $_[0]
				." ".  $stime->hms . " (".  $stime->hires_epoch .")"
				." to ". $etime->hms . " (".  $etime->hires_epoch .")"
				);
		}

		$blockcks += $ckcnt;
	}
	############################################################
	# calibration data, ff

	CORE::read( $fh, $buf, 7 ) == 7
		or croak "failed to read calibration data";
	@_ = unpack( "vvvx", $buf );
	$self->zeropos( $_[0] );
	$self->gradient( $_[1] );
	my $ckcnt = $_[2];

	$self->debug( "chunks: $ckcnt, blockchunks: $blockcks" );

	if( $blockcks < $ckcnt ){
		warn "inconsistency: block chunks < total";

	} elsif( $blockcks > $ckcnt ){
		warn "inconsistency: block chunks > total, truncating last blocks";

		my $extra = $blockcks - $ckcnt;
		foreach my $blk ( reverse @{$self->{blocks}} ){
			if( $extra <= $blk->{ckcnt} ){
				$self->debug( "truncating block "
					. $blk->{stime}->hms
					." by $extra chunks" );

				$blk->{ckcnt} -= $extra;
				last;
			} else {
				$self->debug( "truncating block "
					. $blk->{stime}->hms
					. "to 0 chunks" );

				$extra -= $blk->{ckcnt};
				$blk->{ckcnt} = 0;
			}
		}
	}

	# mark too short leading blocks to be skipped
	foreach my $blk ( @{$self->{blocks}} ){
		last if $blk->{ckcnt} * $self->recint > $self->blkmin;
		$self->debug( "leading junk block ". $blk->{stime}->hms 
			." (< ".  $self->blkmin ."sec)" );
		$blk->{skip}++;
	}
	# mark too short trailing blocks to be skipped
	foreach my $blk ( reverse @{$self->{blocks}} ){
		last if $blk->{ckcnt} * $self->recint > $self->blkmin;
		$self->debug( "trailing junk block ". $blk->{stime}->hms 
			." (< ".  $self->blkmin ."sec)" );
		$blk->{skip}++;
	}

	############################################################
	# read data chunks 

	while( CORE::read( $fh, $buf, 5 ) == 5 ){

		@_ = unpack( "CCCCC", $buf );

		push @{$self->{chunks}}, {
			spd	=> 3.0 / 26 * 
				( (($_[1]&0xf0) <<3) | ($_[0]&0x7f) ),
			pwr	=> ( $_[1] & 0x0f) | ( $_[2] << 4 ),
			cad	=> $_[3],
			hr	=> $_[4],
		};
	}
	@{$self->{chunks}} < $ckcnt && warn "cannot read all data chunks";
	$self->debug( "read ". @{$self->{chunks}} ." chunks" );

	close($fh);
	$self;
}

=head2 iterate

read header (ie. non-chunk data) from file and return iterator

=cut

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::SRM::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}


1;
__END__


=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
