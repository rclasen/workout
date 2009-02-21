#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

# based upon: Stephan Mantlers SRM format description:
# http://www.stephanmantler.com/wordpress/srm-file-format/en/


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


package Workout::Store::SRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store::Memory';
use Carp;
use DateTime;
use Workout::Filter::Info;


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

our %defaults = (
	recint		=> 1,
	tz		=> 'local',
	circum		=> 2000,
	zeropos		=> 100,
	slope		=> 1,
);
__PACKAGE__->mk_accessors( keys %defaults );

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class,$a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		cap_block	=> 1,
		cap_note	=> 1,
	});

	$self;
}

sub do_write {
	my( $self, $fh ) = @_;

	############################################################
	# file header

	my $stime = $self->time_start;
	my $info = $self->info;

	my $dateref = DateTime->new( 
		year		=> 1880, 
		month		=> 1, 
		day		=> 1,
		time_zone	=> $self->tz,
	);

	my $sdate = DateTime->from_epoch(
		epoch		=> $stime,
		time_zone	=> $self->tz,
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
	my $note = $self->note || ( $info->temp_avg 
		? $info->temp_avg ."øC"
		: "");
	my $blocks = $self->blocks;

	$self->debug( "writing ". @$blocks ." blocks, ".
		$self->mark_count ." marker" );
	print $fh pack( "A4vvCCvvxxA70", 
		'SRM6',
		$days,
		$self->circum,
		$r1,
		$r2,
		scalar @$blocks,
		$self->mark_count,
		$note,
	) or croak "failed to write file header";

	############################################################
	# marker

	# TODO: sort marker by ->start
	foreach my $m ( $self->mark_workout, @{$self->marks} ){

		my $info = $m->info;

		my $first = $self->chunk_time2idx( $m->start );
		my $last = $self->chunk_time2idx( $m->end );

		print $fh pack( "A255Cvvvvvvv", 
			($m->note||''),
			1,			# active
			$first + 1,
			$last + 1,
			($info->pwr_avg||0) * 8,
			($info->hr_avg||0) * 64,
			($info->cad_avg||0) * 32, # TODO: unused / 0?
			($info->spd_avg||0) * 2500 / 9 * 3.6,
			0,			# pwc150
		) or croak "failed to write marker";
	}

	############################################
	# blocks

	foreach my $b ( @$blocks ){
		$self->debug( "write block ". $b->[0]->stime ." ". @$b );
		print $fh pack( "Vv", 
			($b->[0]->stime - $wtime) * 100,
			scalar @$b,
		) or croak "failed to write recording block";
	}

	############################################################
	# calibration data, ff

	print $fh pack( "vvvx", 
		$self->zeropos,
		$self->slope * 42781 / 140,
		$self->chunk_count,
	) or croak "failed to write calibration data";

	############################################################
	# chunks 

	my $it = $self->iterate;
	while( my $c = $it->next ){

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

		my $spd = int($c->spd * 26/3 * 3.6);
		my $pwr = int($c->pwr);

		my $c0 = $spd & 0x7f;
		my $c1 = ( ($spd >>3) & 0xf0) | ($pwr & 0x0f);
		my $c2 = ($pwr >> 4) & 0x7f;

		print $fh pack( "CCCCC", 
			$c0,
			$c1,
			$c2,
			$c->cad,	# $_[3],
			$c->hr,	# $_[4],
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
		time_zone	=> $self->tz,
	)->add( days => $_[1] );
	my $wtime = $date->hires_epoch;

	$self->circum( $_[2] );
	$self->recint( $_[3] / $_[4] );
	my $blockcnt = $_[5];
	my $markcnt = $_[6];

	$self->note( $_[7] );
	my $temperature;

	if( $_[7] =~ /^(\d+)øC/ ){
		$temperature = $1;
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

	my @marker;
	while( $markcnt-- >= 0 ){
		CORE::read( $fh, $buf, $clen + 15 ) == $clen + 15
			or croak "failed to read marker";
		@_ = unpack( "A[$clen]Cvvvvvvv", $buf );
		my %mark = (
			note	=> $_[0],
			active	=> $_[1],
			ckfirst	=> $_[2] -1, # 1..
			cklast	=> $_[3] -1, # 1..
			apwr	=> $_[4] / 8,
			ahr	=> $_[5] / 64,
			acad	=> $_[6] / 32, # unused? always=0
			aspd	=> $_[7] / 2500 * 9 / 3.6,
			pwc	=> $_[8], # unused? always=0
		);
		push @marker, \%mark;
		$self->debug( "marker ". $#marker. ": " 
			. join(', ', map {
				"$_=$mark{$_}";
			} keys %mark ) );
	}
	# throw away whole-file marker:
	shift @marker; # TODO: get athlete from ->note

	############################################################
	# read recording block info

	my $block_cknext = 0;
	my @blocks;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( "Vv", $buf );

		my %blk = (
			stime	=> $wtime + $_[0] / 100,
			ckcnt	=> $_[1],
			ckfirst	=> $block_cknext,
			cklast	=> $block_cknext + $_[1] -1,
		);
		$blk{etime} = $blk{stime} + $blk{ckcnt} * $self->recint;

		push @blocks, \%blk;

		if( $self->{debug} ){
			my $sdate = DateTime->from_epoch( 
				epoch		=> $blk{stime}, 
				time_zone	=> $self->tz,
			);
			my $edate = DateTime->from_epoch(
				epoch		=> $blk{etime},
				time_zone	=> $self->tz,
			);

			$self->debug( "block ". $#blocks .": "
				. sprintf( '%5d+%5d=%5d', 
					$blk{ckfirst}, $blk{ckcnt}, $blk{cklast} )
				." @". $_[0]
				." ".  $sdate->hms . " (".  $blk{stime} .")"
				." to ". $edate->hms . " (".  $blk{etime} .")"
				);
		}

		$block_cknext += $blk{ckcnt};
	}

	############################################################
	# calibration data, ff

	CORE::read( $fh, $buf, 7 ) == 7
		or croak "failed to read calibration data";
	@_ = unpack( "vvvx", $buf );
	$self->zeropos( $_[0] );
	$self->slope( $_[1] * 140 / 42781 );
	my $ckcnt = $_[2];

	$self->debug( "slope=". $self->slope
		." zero=". $self->zeropos
		." circum=". $self->circum
		);
	$self->debug( "chunks: $ckcnt, blockchunks: $block_cknext" );


	############################################################
	# consistency check, error correction

	if( $block_cknext < $ckcnt ){
		warn "inconsistency: block chunks < total";

	} elsif( $block_cknext > $ckcnt ){
		warn "inconsistency: block chunks > total, truncating last blocks";

		my $extra = $block_cknext - $ckcnt;
		foreach my $blk ( reverse @blocks ){

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

	my $prev_block;
	foreach my $blk ( reverse @blocks ){

		if( $prev_block && $blk->{etime} > $prev_block->{stime} ){
			my $stime = $prev_block->{stime} 
				- $blk->{ckcnt} * ( $self->recint + 1);

			$self->debug( "fixing block "
				. $blk->{stime}
				. " start time to "
				. $stime
				. " ("
				. ($blk->{stime} - $stime)
				. ")" );

			$blk->{etime} = $prev_block->{stime};
			$blk->{stime} = $stime;
		}

		$prev_block = $blk;
	}

	############################################################
	# read data chunks 

	my $ckread = 0;
	my $prev_chunk;

	my $blk;
	my $cktime;

	while( CORE::read( $fh, $buf, 5 ) == 5 ){

		if( ! $ckread || $ckread > $blk->{cklast} ){
			if( @blocks  ){
				$blk = shift @blocks;
				$cktime = $blk->{stime};

			} else {
				warn "found extra chunk";
				$cktime += $self->recint;
			}

		} else {
			$cktime += $self->recint;
		}
		$ckread++;

		@_ = unpack( "CCCCC", $buf );
		my $spd	= 3.0 / 26 * ( (($_[1]&0xf0) <<3) | ($_[0]&0x7f) );
		my $pwr	= ( $_[1] & 0x0f) | ( $_[2] << 4 );

		my $chunk = Workout::Chunk->new( {
			prev	=> $prev_chunk,
			time	=> $cktime,
			dur	=> $self->recint,
			temp	=> $temperature,
			cad	=> $_[3],
			hr	=> $_[4],
			dist	=> $spd/3.6 * $self->recint,
			work	=> $pwr * $self->recint,
		});

		$self->_chunk_add( $chunk );
		$prev_chunk = $chunk;
	}

	$ckread < $ckcnt && warn "cannot read all data chunks";
	$ckread > $ckcnt && warn "found more data chunks as expeced";

	############################################################
	# add marker

	foreach my $mark ( @marker ){
		my $first = $self->chunk_get_idx( $mark->{ckfirst} )
			or next;
		my $last = $self->chunk_get_idx( $mark->{cklast} )
			or next;

		if( $self->{debug} ){
			my $sdate = DateTime->from_epoch( 
				epoch		=> $first->stime,
				time_zone	=> $self->tz,
			);
			my $edate = DateTime->from_epoch(
				epoch		=> $last->time,
				time_zone	=> $self->tz,
			);

			$self->debug( "mark"
				." ".  $sdate->hms . " (".  $first->stime .")"
				." to ". $edate->hms . " (".  $last->time .")"
				." ". $mark->{note}
			);
		}

		$self->mark_new({
			start	=> $first->stime,
			end	=> $last->time,
			note	=> $mark->{note},
		});
	}
}


1;
__END__


=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
