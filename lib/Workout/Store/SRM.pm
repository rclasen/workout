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
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.srm" );

=head1 DESCRIPTION

Interface to read/write SRM power meter files. Inherits from
Workout::Store and implements do_read/_write methods.

=cut


package Workout::Store::SRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use DateTime;
use Encode;
use Workout::Filter::Info;

our $VERSION = '0.01';

my %magic_tag = (
#	OK19	=> 1, # not supported
#	SRM2	=> 2, # not supported
#	SRM3	=> 3, # not supported
#	SRM4	=> 4, # not supported
#	SRM5	=> 5, # not supported
	SRM6	=> 6,
	SRM7	=> 7,
);

our $chunk7fmt;

if( $] > 5.009001 ){
	# perl supports byte-swapping itself:
	$chunk7fmt = 'vCCl<l<s';

} elsif( pack('l',0x04030201) eq "\x01\x02\x03\x04" ){
	# little endian doesn't need swapping:
	$chunk7fmt = 'vCClls';

} else {
	croak "require perl v5.9.1 except on little-endian machines";
}


sub filetypes {
	return "srm";
}

our %fields_supported = map { $_ => 1; } qw{
	dist
	work
	hr
	cad
	temp
	ele
};

our %defaults = (
	recint		=> 1,
	tz		=> 'local',
	circum		=> 2000,
	zeropos		=> 100,
	slope		=> 1,
	athletename	=> 'srm',
	version		=> 'SRM7',
);
__PACKAGE__->mk_accessors( keys %defaults );

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class,$a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,
		cap_note	=> 1,
	});

	$self;
}

=head1 METHODS

=head2 tz

set/get timezone for reading/writing timestamps as the SRM files store only a
local timestamp without timezone. See DateTime.

=head2 circum

set/get wheel circumference in millimeters (mm)

=head2 zeropos

set/get zero offset in Hertz (HZ)

=head2 slope

set/get slope as known from srmwin and PowerControl

=cut

# TODO: unit for slope

=head2 athletename

set/get name of athlete (as stored in the PowerControl)

=head2 version

set/get file version: SRM6 or SRM7

=cut

sub from_store {
	my( $self, $store ) = @_;

	$self->SUPER::from_store( $store );

	foreach my $f (qw( tz circum zeropos slope athletename )){
		$self->$f( $store->$f ) if $store->can( $f );
	}
}

sub do_write {
	my( $self, $fh, $fname ) = @_;

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
	if( $self->recint > 255 ){
		croak "recint too large";
	
	} elsif( $self->recint >= 1 ){
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
		? sprintf( '%.1f°C', $info->temp_avg )
		: "");
	my $blocks = $self->blocks;

	$self->debug( "writing ". @$blocks ." blocks, ".
		$self->mark_count ." marker" );
	print $fh pack( 'A4vvCCvvx(C/A*@71)', 
		$self->version || 'SRM6',
		$days,
		$self->circum,
		$r1,
		$r2,
		scalar @$blocks,
		$self->mark_count,
		substr(encode('cp850',$note)||'', 0, 70),
	) or croak "failed to write file header";

	############################################################
	# marker

	foreach my $m ( sort {
		$a->start <=> $b->start;

	} $self->mark_workout, @{$self->marks} ){

		my $info = $m->info;

		my $first = $self->chunk_time2idx( $m->start );
		my $last = $self->chunk_time2idx( $m->end );

		# TODO: hack. find better way to find chunk by start time
		my $fchunk = $self->chunk_get_idx( $first );
		if( $fchunk->time == $m->start ){
			++$first;
		}

		$self->debug( "write mark ". $first ." ". $last
			." ". $fchunk->stime );

		print $fh pack( 'Z255Cvvvvvvv', 
			encode('cp850',($m->note||'')),
			1,			# active
			$first + 1,
			$last + 1,
			($info->pwr_avg||0) * 8,
			($info->hr_avg||0) * 64,
			($info->cad_avg||0) * 32,
			($info->spd_avg||0) * 2500 / 9 * 3.6,
			0,			# pwc150
		) or croak "failed to write marker";
	}

	############################################
	# blocks

	foreach my $b ( @$blocks ){
		my $delta = ($b->[0]->time - $wtime) * 100;
		$self->debug( "write block ". $b->[0]->time ." @". $delta ." ". @$b );
		print $fh pack( 'Vv', 
			$delta,
			scalar @$b,
		) or croak "failed to write recording block";
	}

	############################################################
	# calibration data, ff

	print $fh pack( 'vvvx', 
		$self->zeropos,
		$self->slope * 42781 / 140,
		$self->chunk_count,
	) or croak "failed to write calibration data";

	############################################################
	# chunks 

	if( $self->version eq 'SRM7' ){
		$self->write_srm7( $fh );
	} else {
		$self->write_srm( $fh );
	}
}

sub write_srm {
	my( $self, $fh ) = @_;

	my $it = $self->iterate;
	while( my $c = $it->next ){

		# lsb byte order...
		#
		# c0       c1       c2
		# 11111111 11111111 11111111 bits
		#
		# -------- ----3210 ba987654 pwr
		#              0x0f     0xff
		#
		# -6543210 a987---- -------- speed
		#     0x7f 0xf0

		my $spd = int(($c->spd||0) * 26/3 * 3.6);
		my $pwr = int($c->pwr||0);

		my $c0 = $spd & 0x7f;
		my $c1 = ( ($spd >>3) & 0xf0) | ($pwr & 0x0f);
		my $c2 = ($pwr >> 4) & 0xff;

		print $fh pack( 'CCCCC', 
			$c0,
			$c1,
			$c2,
			$c->cad||0,	# $_[3],
			$c->hr||0,	# $_[4],
		) or croak "failed to write chunks";
	}
}

sub write_srm7 {
	my( $self, $fh ) = @_;

	my $it = $self->iterate;
	while( my $c = $it->next ){

		print $fh pack( $chunk7fmt,
			$c->pwr||0,
			$c->cad||0,
			$c->hr||0,
			($c->spd||0) * 1000,
			$c->ele||0,
			($c->temp||0) * 10,
		) or croak "failed to write chunks";
	}
}

sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $buf;

	############################################################
	# file header @0

	CORE::read( $fh, $buf, 86 ) == 86
		or croak "failed to read file header";
	@_ = unpack( 'A4vvCCvvx(C/A*@71)', $buf );
		
	exists $magic_tag{$_[0]}
		or croak "unrecognized file format";
	$self->version( $_[0] );

	my $clen;
	if( $_[0] eq 'SRM5' ){
		$clen = 3;

	} elsif( $_[0] =~ /^SRM[67]$/ ){
		$clen = 255;

	} else {
		croak "unsupported file version: $_[0]";
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

	$self->note( decode('cp850',$_[7]) );
	my $temperature;

	if( $_[7] =~ s/^(\d+(?:[.,]\d+)?)[°ø]C// ){
		$temperature = $1;
		$temperature =~ s/\,/./;
	}
	$self->debug( "date: ". $date->ymd 
		." days: ". $_[1] .","
		." wtime: $wtime,"
		." blocks: $blockcnt,"
		." marker: $markcnt,"
		." recint: ". $self->recint
		."=". $_[3] ."/". $_[4] );

	if( $blockcnt <= 0 ){
		# blocks carry the timestamps. So we can't recover
		# properly even if there are chunks.
		carp "empty file: no data blocks";
		return;
	}

	############################################################
	# read marker @86

	my @marker;
	while( $markcnt-- >= 0 ){
		CORE::read( $fh, $buf, $clen + 15 ) == $clen + 15
			or croak "failed to read marker";
		@_ = unpack( "Z[$clen]Cvvvvvvv", $buf );
		my %mark = (
			note	=> decode('cp850',$_[0]),
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
	$self->athletename( (shift @marker)->{note} );

	############################################################
	# read recording block info @86 + $marker*(15+$clen=255)

	my $block_cknext = 0;
	my @blocks;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( 'Vv', $buf );

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
	# calibration data, ff @86 + $marker*(15+$clen=255) + $blocks*6

	CORE::read( $fh, $buf, 7 ) == 7
		or croak "failed to read calibration data";
	@_ = unpack( 'vvvx', $buf );
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
	# @93 + $marker*(15+$clen=255) + $blocks*6
	# min=369

	if( $block_cknext < $ckcnt ){
		carp "inconsistency: block chunks < total";

	} elsif( $block_cknext > $ckcnt ){
		carp "inconsistency: block chunks > total, truncating last blocks";

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

			carp( "fixing block "
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

	my $ckread;
	
	$self->debug( "starting to read chunks at ", tell $fh );

	if( $self->version eq 'SRM7' ){
		$ckread = $self->read_srm7( $fh, \@blocks, $temperature );
	} else {
		$ckread = $self->read_srm( $fh, \@blocks, $temperature );
	}

	if( $ckread <= 0 ){
		croak "no chunks found";

	} elsif( $ckread < $ckcnt ){
		carp "cannot read all data chunks ($ckread/$ckcnt)";

	} elsif( $ckread > $ckcnt ){
		carp "found more data chunks as expeced ($ckread/$ckcnt)";

	}

	############################################################
	# add marker

	foreach my $mark ( @marker ){
		if( $mark->{ckfirst} >= $ckread ){
			carp "fixing marker start offset ". $mark->{ckfirst};
			$mark->{ckfirst} = $ckread -1;
		}

		if( $mark->{cklast} >= $ckread ){
			carp "fixing marker end offset ". $mark->{cklast};
			$mark->{cklast} = $ckread -1;
		}

		my $first = $self->chunk_get_idx( $mark->{ckfirst} );
		my $last = $self->chunk_get_idx( $mark->{cklast} );

		if( ! $first || ! $last ){
			carp "failed to build marker ".  $mark->{ckfirst};
			next;
		}

		$self->mark_new({
			start	=> $first->stime,
			end	=> $last->time,
			note	=> $mark->{note},
		});
	}
}

sub read_srm {
	my( $self, $fh, $blocks, $temperature ) = @_;

	my $ckread = 0;

	my $buf;
	my $blk = shift @$blocks;
	my $cktime = $blk->{stime};

	while( CORE::read( $fh, $buf, 5 ) == 5 ){

		$cktime += $self->recint if $ckread;

		while( $ckread > $blk->{cklast} && @$blocks ){
			$blk = shift @$blocks;
			$cktime = $blk->{stime};
		}

		$ckread++;

		@_ = unpack( 'CCCCC', $buf );
		my $rspd = ( (($_[1]&0xf0) <<3) | ($_[0]&0x7f) );
		my $spd	= 3.0 / 26 * $rspd;
		my $pwr	= ( $_[1] & 0x0f) | ( $_[2] << 4 );

		my $chunk = Workout::Chunk->new( {
			time	=> $cktime,
			dur	=> $self->recint,
			temp	=> $temperature,
			cad	=> $_[3],
			hr	=> ($_[4] || undef),
			dist	=> $spd/3.6 * $self->recint,
			work	=> $pwr * $self->recint,
		});

		$self->chunk_add( $chunk );
	}

	if( $ckread > $blk->{cklast} + 1){
		carp "found extra chunks: ".
			$ckread ." > ". ($blk->{cklast} + 1);
	}

	$self->fields_io( qw(
		time dur work cad hr dist
	));

	$ckread;
}


sub read_srm7 {
	my( $self, $fh, $blocks, $temperature ) = @_;

	my $ckread = 0;

	my $buf;
	my $blk = shift @$blocks;
	my $cktime = $blk->{stime};

	while( CORE::read( $fh, $buf, 14 ) == 14 ){

		$cktime += $self->recint if $ckread;

		while( $ckread > $blk->{cklast} && @$blocks ){
			$blk = shift @$blocks;
			$cktime = $blk->{stime};
		}

		$ckread++;

		@_ = unpack( $chunk7fmt, $buf );
		my $chunk = Workout::Chunk->new( {
			time	=> $cktime,
			dur	=> $self->recint,
			work	=> $_[0] * $self->recint,
			cad	=> $_[1],
			hr	=> $_[2],
			dist	=> $_[3] / 1000 * $self->recint,
			ele	=> $_[4],
			temp	=> $_[5] / 10,
		});

		$self->chunk_add( $chunk );
	}

	if( $ckread > $blk->{cklast} + 1){
		carp "found extra chunks: ".
			$ckread ." > ". ($blk->{cklast} + 1);
	}

	$self->fields_io( qw(
		time dur work cad hr dist ele temp
	));

	$ckread;
}


sub mark_workout {
	my( $self ) = @_;
	Workout::Marker->new( {
		store	=> $self, 
		start	=> $self->time_start, 
		end	=> $self->time_end,
		note	=> substr( $self->athletename. '    ', 0, 4 ),
	});
}


1;
__END__


=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
