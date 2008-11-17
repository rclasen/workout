
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
	$self;
}

=head2 next

=cut

sub process {
	my( $self ) = @_;

	my $store = $self->store;

	# find next chunk
	while( $self->{nbk} <= $#{$store->{blocks}} ){
		my $blk = $store->{blocks}[$self->{nbk}];

		if( $blk->{skip} ){
			$self->debug( "skipping junk block ". $self->{nbk} );
			$self->{nbk}++;
			next;
		}

		if( $self->{nck} >= $blk->{ckcnt} ){
			$self->debug( "end of block ". $self->{nbk} );
			$self->{nck} = 0;
			$self->{nbk}++;
			next;
		}

		# fix time to avoid overlapping
		if( defined $self->{ctime} ){
			$self->{ctime} += $store->recint;

			if( $self->{nck} == 0 ){
				if( $self->{ctime} > $blk->{stime} ){
					my $b = DateTime->from_epoch( 
						epoch => $blk->{stime},
						time_zone => $self->{tz},
					);
					my $t = DateTime->from_epoch( 
						epoch => $self->{ctime},
						time_zone => $self->{tz},
					);

					warn "fixing time of block "
						. $self->{nbk} 
						. " from ".  $b->hms
						. " to ". $t->hms;
				} else {
					$self->{ctime} = $blk->{stime};
				}
			}

		} else {
			$self->{ctime} = $blk->{stime};
		}

		my $idx = $blk->{ckstart} + $self->{nck}++;
		my $ick = $store->{chunks}[$idx];
		my $ock = Workout::Chunk->new( {
			%$ick,
			prev	=> $self->last,
			time	=> $self->{ctime},
			dur	=> $store->recint,
			temp	=> $store->temperature,
			dist	=> $ick->{spd}/3.6 * $store->recint,
			work	=> $ick->{pwr} * $store->recint,
		});

		$self->{cntin}++;

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
	SRM7	=> 7,
);

sub filetypes {
	return "srm";
}

# TODO: move blkmin + junk skipping to Filter

__PACKAGE__->mk_accessors(qw(
	tz
	blkmin
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
		cap_block	=> 1,
	});

	$self->{blocks} = [];
	$self->{marker} = [];
	$self->{chunks} = [];

	$self;
}

# TODO: chunk_add

sub do_write {
	my( $self, $fh ) = @_;

	my $buf;

	############################################################
	# file header

	my $stime = $self->{blocks}[0]{stime};

	my $dateref = DateTime->new( 
		year		=> 1880, 
		month		=> 1, 
		day		=> 1,
		time_zone	=> $self->{tz},
	);

	my $sdate = DateTime->from_epoch(
		epoch		=> $stime,
		time_zone	=> $self->{tz},
	);

	my $days = int( $sdate->subtract_datetime_absolute( $dateref )
		->seconds / (24*3600) );

	my $wtime = $dateref->clone->add(days=>$days)->hires_epoch;

	# TODO: less hackish recint 
	my( $r1, $r2 );
	if( $self->recint >= 1 ){
		(abs($self->recint - int($self->recint)) < 0.1 )
			or croak "cannot find apropriate recint";

		$r1 = int($self->recint);
		$r2 = 1;
	
	} else {
		$r2 = 10;
		$r1 = $self->recint * $r2;
		(abs($r1 - int($r1)) < 0.1 )
			or croak "cannot find apropriate recint";

	}
	my $note = $self->note || ( $self->temperature 
		? $self->temperature ."øC"
		: "");

	print $fh pack( "A4vvCCvvxxA70", 
		'SRM6',
		$days,
		$self->circum,
		$r1,
		$r2,
		scalar @{$self->{blocks}},
		scalar @{$self->{marker}} -1,
		$note,
	) or croak "failed to write file header";

	############################################################
	# marker

	foreach my $m ( @{$self->{marker}} ){
		print $fh pack( "A255Cvvvvvvv", 
			$m->{comment},
			$m->{active},
			$m->{ckstart} + 1,
			$m->{ckend} + 1,
			$m->{apwr} * 8,
			$m->{ahr} * 64,
			$m->{hcad} * 32,
			$m->{aspd} * 2500 / 9,
			$m->{pwc},
		) or croak "failed to write marker";
	}

	############################################
	# blocks

	foreach my $b ( @{$self->{blocks}} ){
		print $fh pack( "Vv", 
			($b->{stime} - $wtime) * 100,
			$b->{ckcnt},
		) or croak "failed to write data block";
	}

	############################################################
	# calibration data, ff

	print $fh pack( "vvvx", 
		$self->zeropos,
		$self->gradient,
		scalar @{$self->{chunks}},
	) or croak "failed to write calibration data";

	############################################################
	# chunks 

	foreach my $c ( @{$self->{chunks}} ){

		# lsb byte order...
		#
		# c0       c1       c2
		# 11111111 11111111 11111111 bits
		#
		# -------- ----3210 -a987654 pwr
		#              0x0f     0x7f
		#
		# -6543210 a987---- -------- speed
		#     0x7f 0xf0

		my $spd = int($c->{spd} * 26/3);
		my $pwr = int($c->{pwr});

		my $c0 = $spd & 0x7f;
		my $c1 = ( ($spd >>3) & 0xf0) | ($pwr & 0x0f);
		my $c2 = ($pwr >> 4) & 0x7f;

		print $fh pack( "CCCCC", 
			$c0,
			$c1,
			$c2,
			$c->{cad},	# $_[3],
			$c->{hr},	# $_[4],
		) or croak "failed to write chunks";
	}
}

sub do_read {
	my( $self, $fh ) = @_;

	my $buf;

	############################################################
	# file header
	CORE::read( $fh, $buf, 86 ) == 86
		or croak "failed to read file header";
	@_ = unpack( "A4vvCCvvxxA70", $buf );
		
	exists $magic_tag{$_[0]}
		or croak "unrecognized file format";
	my $version = $magic_tag{$_[0]};
	my $clen;
	if( $version == 5 ){
		$clen = 3;
	} elsif( $version == 6 ){
		$clen = 255;
	} else {
		croak "unsupported file version: $version";
	}

	my $date = DateTime->new( 
		year		=> 1880, 
		month		=> 1, 
		day		=> 1,
		time_zone	=> $self->{tz},
	)->add( days => $_[1] );
	my $wtime = $date->hires_epoch;

	$self->circum( $_[2] );
	$self->recint( $_[3] / $_[4] );
	my $blockcnt = $_[5];
	my $markcnt = $_[6];

	$self->note( $_[7] );
	if( $_[7] =~ /^(\d+)øC/ ){
		$self->temperature( $1 );
	}
	$self->debug( "date: ". $date->ymd 
		." days: ". $_[1] .","
		." wtime: $wtime,"
		." blocks: $blockcnt,"
		." marker: $markcnt,"
		." recint: ". $self->recint
		."=". $_[3] ."/". $_[4] );

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
	# blocks

	my $blockcks = 0;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( "Vv", $buf );
		my $stime = $wtime + $_[0] / 100;

		my $ckcnt = $_[1];
		my $blk = {
			stime	=> $stime,
			ckcnt	=> $ckcnt,
			ckstart => $blockcks,
			skip	=> 0,
		};
		push @{$self->{blocks}}, $blk;

		if( $self->{debug} ){
			my $sdate = DateTime->from_epoch( 
				epoch		=> $stime, 
				time_zone	=> $self->{tz},
			);
			my $etime = $stime + $ckcnt * $self->recint;
			my $edate = DateTime->from_epoch(
				epoch		=> $etime,
				time_zone	=> $self->{tz}),
			;

			$self->debug( "block ". $#{$self->{blocks}} .": "
				. sprintf( '%5d+%5d=%5d', 
					$blockcks, $ckcnt, ($blockcks + $ckcnt) )
				." @". $_[0]
				." ".  $sdate->hms . " (".  $stime .")"
				." to ". $edate->hms . " (".  $etime .")"
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
					. $blk->{stime}
					." by $extra chunks" );

				$blk->{ckcnt} -= $extra;
				last;
			} else {
				$self->debug( "truncating block "
					. $blk->{stime}
					. "to 0 chunks" );

				$extra -= $blk->{ckcnt};
				$blk->{ckcnt} = 0;
			}
		}
	}

	# mark too short leading blocks to be skipped
	foreach my $blk ( @{$self->{blocks}} ){
		last if $blk->{ckcnt} * $self->recint > $self->blkmin;
		$self->debug( "leading junk block ". $blk->{stime}
			." (< ".  $self->blkmin ."sec)" );
		$blk->{skip}++;
	}
	# mark too short trailing blocks to be skipped
	foreach my $blk ( reverse @{$self->{blocks}} ){
		last if $blk->{ckcnt} * $self->recint > $self->blkmin;
		$self->debug( "trailing junk block ". $blk->{stime}
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
