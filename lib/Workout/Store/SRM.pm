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


############################################################
# SRM6
############################################################

package Workout::Store::SRM::v6;
use strict;
use warnings;
use Carp;
use Encode;

sub new {
	return bless {
		store	=> $_[1],
		fh	=> $_[2],
	}, $_[0];
};

sub version { 6 };
sub magic { 'SRM6' };

sub fpos { sprintf( "0x%x/%d", $_[0], $_[0] ) };
############################################################
# marker

# id	start	len	what
# 0	0	3/255	char* string, zero-terminated+padded
# 1	255/3	1	uint8/bool - active
# 2	256/4	2	uint16 - first chunk index +1
# 3	258/6	2	uint16 - last chunk index +1
# 4	260/8	2	uint16 - average power * 8
# 5	262/10	2	uint16 - average hr * 64
# 6	264/12	2	uint16 - average cad * 32 - unused?
# 7	266/14	2	uint16 - average speed * $x
# 8	268/16	2	uint16 - pwc - unused?

sub marker_clen { 255 };
sub marker_len { $_[0]->marker_clen + 15 };
sub marker_fmt { "Z[". $_[0]->marker_clen ."]Cvvvvvvv"; };

sub marker_read {
	my( $v, $markcnt ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $len = $v->marker_len;
	my $fmt = $v->marker_fmt;

	$self->debug( "starting to read $markcnt * $len byte marker at ",
	fpos(tell $fh) );

	my @marker;
	my $buf;
	while( $markcnt-- >= 0 ){
		CORE::read( $fh, $buf, $len ) == $len
			or croak "failed to read marker";
		@_ = unpack( $fmt, $buf );
		my %mark = (
			note	=> decode('cp850',$_[0]),
			active	=> $_[1],
			ckfirst	=> $_[2] -1, # 1..
			cklast	=> $_[3] -1, # 1..
			apwr	=> $_[4],
			ahr	=> $_[5],
			acad	=> $_[6],
			aspd	=> $_[7] / 1000,
			pwc	=> $_[8], # unused? always=0
		);
		push @marker, \%mark;
		$self->debug( "marker ". $#marker. ": "
			. join(', ', map {
				"$_=$mark{$_}";
			} keys %mark ) );
	}

	# throw away whole-file marker:
	$self->meta_field('athletename', (shift @marker)->{note} );

	return \@marker;
}

sub marker_write {
	my( $v ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $fmt = $v->marker_fmt;
	foreach my $m ( sort {
		$a->start <=> $b->start;

	} $self->mark_workout, @{$self->marks} ){

		my $info = $m->info_meta;

		my $first = $self->chunk_time2idx( $m->start );
		my $last = $self->chunk_time2idx( $m->end );

		# TODO: hack. find better way to find chunk by start time
		my $fchunk = $self->chunk_get_idx( $first );
		if( $fchunk->time == $m->start ){
			++$first;
		}

		$self->debug( "write mark ". $first ." ". $last
			." ". $fchunk->stime );

		print $fh pack( $fmt,
			encode('cp850',($info->{note}||'')),
			0,
			$first + 1,
			$last + 1,
			($info->{pwr_avg}||0),
			($info->{hr_avg}||0),
			($info->{cad_avg}||0),
			($info->{spd_avg}||0) * 1000,
			0,			# pwc150
		) or croak "failed to write marker";
	}
}

############################################################
# read recording block info @86 + $marker*(15+$clen=255)
# 6 bytes

# id	start	len	what
# 0	0	4	uint32 - time since midnight
# 1	4	2	uint16 - num of chunks

sub blocks_len { 6 };
sub blocks_fmt { "Vv" };

sub blocks_read {
	my( $v, $blockcnt, $wtime ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $len = $v->blocks_len;
	my $fmt = $v->blocks_fmt;

	$self->debug( "starting to read $blockcnt*$len byte blocks at ",
	fpos(tell $fh) );

	my $block_cknext = 0;
	my @blocks;
	my $buf;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, $len ) == $len
			or croak "failed to read data block";

		@_ = unpack( $fmt, $buf );

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

	return \@blocks;
}

sub blocks_write {
	my( $v, $blocks, $wtime ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $fmt = $v->blocks_fmt;

	foreach my $b ( @$blocks ){
		my $delta = ($b->[0]->stime - $wtime) * 100;
		$self->debug( "write block ". $b->[0]->stime ." @". $delta ." ". @$b );
		print $fh pack( $fmt,
			$delta,
			scalar @$b,
		) or croak "failed to write recording block";
	}
}


############################################################
# calibration data, ff @86 + $marker*(15+$clen=255) + $blocks*6
# 7 bytes

# id	start	len	what
# 0	0	2	uint16 - zeropos
# 1	2	2	uint16 - slope * $something
# 2	4	2	uint16 - chunks
# 3	6	1	pad, zero

sub calibs_len { 7 };
sub calibs_fmt { 'vvvx' };

sub calibs_read {
	my( $v ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $len = $v->calibs_len;
	my $fmt = $v->calibs_fmt;

	$self->debug( "starting to read $len byte calibration at ",
	fpos(tell $fh) );

	my $buf;
	CORE::read( $fh, $buf, $len ) == $len
		or croak "failed to read calibration data";
	@_ = unpack( $fmt, $buf );
	$self->meta_field('zeropos', $_[0] );
	$self->meta_field('slope', $_[1] * 140 / 42781 );
	my $ckcnt = $_[2];

	$self->debug( "slope=". $self->meta_field('slope')
		." zero=". $self->meta_field('zeropos')
		." circum=". $self->meta_field('circum')
		);

	return $ckcnt;
}

sub calibs_write {
	my( $v, $info ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $fmt = $v->calibs_fmt;

	print $fh pack( $fmt,
		$info->{zeropos},
		$info->{slope} * 42781 / 140,
		$self->chunk_count,
	) or croak "failed to write calibration data";
}

############################################################
# chunks

# id	start	len	what
# 0	0	1	uint8 - c0
# 1	1	1	uint8 - c1
# 2	2	1	uint8 - c2
# 3	3	1	uint8 - cadence
# 4	4	1	uint8 - heartrate

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

sub chunks_len { 5 };
sub chunks_fmt { 'CCCCC' };

sub chunks_read {
	my( $v, $blocks, $temperature ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $len = $v->chunks_len;
	my $fmt = $v->chunks_fmt;

	my $ckread = 0;
	my $ckcnt = $blocks->[-1]{cklast};

	my $blk = shift @$blocks;
	my $cktime = $blk->{stime};

	my %io;
	my $buf;

	for( ; $ckread <= $ckcnt; ++$ckread ){

		while( $ckread > $blk->{cklast} && @$blocks ){
			$blk = shift @$blocks;
			$cktime = $blk->{stime};
		}

		$cktime += $self->recint;


		CORE::read( $fh, my $buf, $len ) == $len or last;

		@_ = unpack( $fmt, $buf );
		my $rspd = ( (($_[1]&0xf0) <<3) | ($_[0]&0x7f) );
		my $spd	= 3.0 / 26 * $rspd;
		my $pwr	= ( $_[1] & 0x0f) | ( $_[2] << 4 );
		my $hr = $_[4] > 20 ? $_[4] : undef;

		my $chunk = Workout::Chunk->new( {
			time	=> $cktime,
			dur	=> $self->recint,
			temp	=> $temperature,
			cad	=> $_[3],
			hr	=> $hr,
			dist	=> $spd/3.6 * $self->recint,
			work	=> $pwr * $self->recint,
		});

		$_[3] > 0 && ++$io{cad};
		defined $hr && ++$io{hr};
		$spd > 0 && ++$io{dist};
		$pwr > 0 && ++$io{work};

		$self->chunk_add( $chunk );
	}

	$self->fields_io( qw( time dur ), keys %io );

	$ckread;
}

sub chunks_write {
	my( $v ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $fmt = $v->chunks_fmt;

	my $it = $self->iterate;
	while( my $c = $it->next ){

		my $spd = int(($c->spd||0) * 26/3 * 3.6);
		my $pwr = int($c->pwr||0);

		my $c0 = $spd & 0x7f;
		my $c1 = ( ($spd >>3) & 0xf0) | ($pwr & 0x0f);
		my $c2 = ($pwr >> 4) & 0xff;

		print $fh pack( $fmt,
			$c0,
			$c1,
			$c2,
			$c->cad||0,	# $_[3],
			$c->hr||0,	# $_[4],
		) or croak "failed to write chunks";
	}
}

############################################################
# SRM5
############################################################

package Workout::Store::SRM::v5;
use strict;
use warnings;
use Carp;
use base 'Workout::Store::SRM::v6';

sub version { 5 };
sub magic { 'SRM5' };

sub marker_clen { 3 };

# doesn't have blocks, either, but that's handled automatically

############################################################
# SRM7
############################################################

package Workout::Store::SRM::v7;
use strict;
use warnings;
use Carp;
use base 'Workout::Store::SRM::v6';

use constant {
        SRM_SEMI_DEG    => 2 ** 31 / 180,
};

our $chunkfmt;
sub version { 7 };
sub magic { 'SRM7' };

############################################################
# chunks

# id	start	len	what
# 0	0	2	uint16 - power
# 1	2	1	uint8 - cadence
# 2	3	1	uint8 - heartrate
# 3	4	4	int32 - speed
# 4	8	4	int32 - elevation
# 5	12	2	int16 - temperature

sub chunks_len { 14 };
sub chunks_fmt { $chunkfmt };

sub fpos { sprintf( "0x%x/%d", $_[0], $_[0] ) };

sub chunks_read {
	my( $v, $blocks, $temperature ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $len = $v->chunks_len;
	my $fmt = $v->chunks_fmt;

	my $ckread = 0;
	my $ckcnt = $blocks->[-1]{cklast};

	my $blk = shift @$blocks;
	my $cktime = $blk->{stime};

	my %io;
	my $buf;

	for( ; $ckread <= $ckcnt; ++$ckread ){

		while( $ckread > $blk->{cklast} && @$blocks ){
			$blk = shift @$blocks;
			$cktime = $blk->{stime};
		}

		$cktime += $self->recint;

		CORE::read( $fh, my $buf, $len ) == $len or last;

		# HACK: elevation max of 65000 is a guess. This should be
		# sanitized in some extra filter to allow fixing elevation
		# data manually.

		#print join(" ",fpos(tell $fh), map { sprintf "%02x", $_ } unpack("C*",$buf) )."\n";
		@_ = unpack( $fmt, $buf );
		my $chunk = Workout::Chunk->new( {
			time	=> $cktime,
			dur	=> $self->recint,
			work	=> $_[0] * $self->recint,
			cad	=> $_[1],
			hr	=> $_[2] < 20 ? undef : $_[2],
			dist	=> $_[3] < 0 ? undef :  $_[3] / 1000 * $self->recint,
			ele	=> $_[4] > 65000 ? undef : $_[4],
			temp	=> $_[5] / 10,
			# for v9:
			lat	=> defined $_[6] ? $_[6] / SRM_SEMI_DEG : undef,
			lon	=> defined $_[7] ? $_[7] / SRM_SEMI_DEG : undef,
		});
		$_[0] > 0 && ++$io{work};
		$_[1] > 0 && ++$io{cad};
		$_[2] >= 20 && ++$io{hr};
		$_[3] > 0 && ++$io{dist};
		$_[4] > 0 && ++$io{ele};
		$_[5] != 0 && ++$io{temp};
		defined $_[6] && ++$io{lat};
		defined $_[7] && ++$io{lon};

		$self->chunk_add( $chunk );
	}

	$self->fields_io( qw( time dur ), keys %io );

	$ckread;
}

sub chunks_write {
	my( $v ) = @_;
	my $self = $v->{store};
	my $fh = $v->{fh};

	my $fmt = $v->chunks_fmt;

	my $it = $self->iterate;
	while( my $c = $it->next ){

		print $fh pack( $fmt,
			$c->pwr||0,
			$c->cad||0,
			$c->hr||0,
			($c->spd||0) * 1000,
			$c->ele||0,
			($c->temp||0) * 10,
			# for v9:
			($c->lat||0) * SRM_SEMI_DEG,
			($c->lon||0) * SRM_SEMI_DEG,
		) or croak "failed to write chunks";
	}
}

############################################################
# SRM9
############################################################

package Workout::Store::SRM::v9;
use strict;
use warnings;
use Carp;
use base 'Workout::Store::SRM::v7';

our $chunkfmt;
sub version { 9 };
sub magic { 'SRM9' };

############################################################
# marker

# id	start	len	what
# 0	0	255	char* string, zero-terminated+padded
# 1	255	1	uint8/bool - active
# 2	256	4	uint32 - first chunk index +1
# 3	260	4	uint32 - last chunk index +1
# 4	264	2	uint16 - average power
# 5	266	2	uint16 - average hr
# 6	268	2	uint16 - average cad
# 7	270	2	uint16 - average speed
# 8	272	2	uint16 - pwc - unused?

sub marker_len { 255 + 19 };
sub marker_fmt { "Z[255]CVVvvvvv"; };

############################################################
# blocks

# id	start	len	what
# 0	0	4	uint32 - time since midnight
# 1	4	4	uint32 - num of chunks

sub blocks_len { 8 };
sub blocks_fmt { "VV" };

############################################################
# calibs

# id	start	len	what
# 0	0	2	uint16 - zeropos
# 1	2	2	uint16 - slope * $something
# 2	4	4	uint32 - chunks
# 3	8	1	pad, zero

sub calibs_len { 9 };
sub calibs_fmt { 'vvVx' };

############################################################
# chunks

# id	start	len	what
# 0	0	2	uint16 - power
# 1	2	1	uint8 - cadence
# 2	3	1	uint8 - heartrate
# 3	4	4	int32 - speed
# 4	8	4	int32 - elevation
# 5	12	2	int16 - temperature
# 6	14	4	int32 - lat
# 7	18	4	int32 - lon

sub chunks_len { 22 };
sub chunks_fmt { $chunkfmt };


############################################################
# Store
############################################################


package Workout::Store::SRM;
use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Workout::Store';
use Carp;
use DateTime;
use Encode;

our $VERSION = '0.02';

sub fpos { sprintf( "0x%x/%d", $_[0], $_[0] ) };

if( $] > 5.009001 ){
	# perl supports byte-swapping itself:
	$Workout::Store::SRM::v7::chunkfmt = 'vCCl<l<s';
	$Workout::Store::SRM::v9::chunkfmt = 'vCCl<l<sl<l<';

} elsif( pack('l',0x04030201) eq "\x01\x02\x03\x04" ){
	# little endian doesn't need swapping:
	$Workout::Store::SRM::v7::chunkfmt = 'vCClls';
	$Workout::Store::SRM::v9::chunkfmt = 'vCCllsll';

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
	lat
	lon
};

our %defaults = (
	recint		=> 1,
	version		=> 7,
);
__PACKAGE__->mk_accessors( keys %defaults );

our %meta = (
	device		=> 'SRM',
	sport		=> 'Bike',
	circum		=> 2000,
	zeropos		=> 100,
	slope		=> 1,
	athletename	=> 'srm',
);

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class,$a ) = @_;

	$a||={};
	$a->{meta}||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		meta	=> {
			%meta,
			%{$a->{meta}},
		},
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,
	});

	$self;
}

=head1 METHODS

=head2 version

set/get file version: 5 (read only), 6 or 7

=cut

sub do_write {
	my( $self, $fh, $fname ) = @_;

	binmode( $fh );

	if( ! $self->version ){
		$self->version( 7 );
	}

	my $v;
	if( $self->version == 7 ){
		$v = Workout::Store::SRM::v7->new( $self, $fh );;
# TODO: srmx fails to open/read my srm9 files for whatever reason:
#	} elsif( $self->version == 9 ){
#		$v = Workout::Store::SRM::v9->new( $self, $fh );;
	} elsif( $self->version == 6 ){
		$v = Workout::Store::SRM::v6->new( $self, $fh );;
	} else {
		croak "don't know how to write format version ".  $self->version;
	}

	############################################################
	# file header

	my $info = $self->info_meta;
	my $stime = $info->{time_start};

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
	my $note = $info->{note} || '';
	my $blocks = $self->blocks;

	$self->debug( "writing ". @$blocks ." blocks, ".
		$self->mark_count ." marker" );
	print $fh pack( 'A4vvCCvvC(C/A*@71)',
		$v->magic,
		$days,
		$info->{circum}||$meta{circum},
		$r1,
		$r2,
		scalar @$blocks,
		$self->mark_count,
		6,
		substr(encode('cp850',$note)||'', 0, 70),
	) or croak "failed to write file header";

	$v->marker_write;
	$v->blocks_write( $blocks, $wtime );
	$v->calibs_write( $info );
	$v->chunks_write;

# SRM9 has this trailer:
#	print $fh pack( "C*",
#		0xff, 0xff, 0, 0,
#		0xff, 0xff, 0, 0,
#		0xff, 0xff, 0, 0,
#		0xff, 0xff, 0, 0,
#		0xff, 0xff, 0, 0,
#		0xff, 0xff, 0xff, 0xff);
}

sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $buf;
	binmode( $fh );

	############################################################
	# file header @0, 86 bytes

	# id	start	len	what
	# 0	0	4	4x char	- magic_tag
	# 1	4	2	uint16 - days since 1880-1-1
	# 2	6	2	uint16 - wheel circum
	# 3	8	1	uint8 - recint a (a/b)
	# 4	9	1	uint8 - recint b (a/b)
	# 5	10	2	uint16 - block count
	# 6	12	2	uint16 - marker count
	# 7	14	1	uint8 - pad?
	# -	15	1	uint8 - comment len
	# 8	16	70	char* - comment, padded (zero? space?)

	CORE::read( $fh, $buf, 86 ) == 86
		or croak "failed to read file header";
	@_ = unpack( 'A4vvCCvvC(C/A*@71)', $buf );

	my $v;
	if( $_[0] eq 'SRM7' ){
		$v = Workout::Store::SRM::v7->new( $self, $fh );

	} elsif( $_[0] eq 'SRM9' ){
		$v = Workout::Store::SRM::v9->new( $self, $fh );

	} elsif( $_[0] eq 'SRM6' ){
		$v = Workout::Store::SRM::v6->new( $self, $fh );

	} elsif( $_[0] eq 'SRM5' ){
		$v = Workout::Store::SRM::v5->new( $self, $fh );

	} else {
		croak "unrecognized file format";
	}
	$self->version( $v->version );

	my $date = DateTime->new( 
		year		=> 1880, 
		month		=> 1, 
		day		=> 1,
		time_zone	=> $self->tz,
	)->add( days => $_[1] );
	my $wtime = $date->hires_epoch;

	$self->meta_field('circum', $_[2] );
	$self->recint( $_[3] / $_[4] );
	my $blockcnt = $_[5];
	my $markcnt = $_[6];

	my $temperature;
	if( $_[8] ){
		$self->meta_field('note', decode('cp850',$_[8]) );

		if( $_[8] =~ s/^(\d+(?:[.,]\d+)?)[°ø]C// ){
			$temperature = $1;
			$temperature =~ s/\,/./;
		}
	}
	$self->debug( "version: ". $v->version .","
		." date: ". $date->ymd .","
		." days: ". $_[1] .","
		." wtime: $wtime,"
		." blocks: $blockcnt,"
		." marker: $markcnt,"
		." recint: ". $self->recint
		."=". $_[3] ."/". $_[4] );

	my $marker = $v->marker_read( $markcnt );
	my $blocks = $v->blocks_read( $blockcnt, $wtime );;
	my $ckcnt = $v->calibs_read;

	############################################################
	# consistency check, error correction
	# @93 + $marker*(15+$clen=255) + $blocks*6
	# min=369

	my $block_ckcnt = 0;
	if( @$blocks ){
		$block_ckcnt = $blocks->[-1]{cklast} +1;
	}

	$self->debug( "chunks: $ckcnt, blockchunks: $block_ckcnt" );

	if( $block_ckcnt < $ckcnt ){
		my $stime = $wtime + $self->recint;
		if( @$blocks ){
			carp "inconsistency: block chunks < total";
			$stime = $blocks->[-1]{etime} + $self->{recint};
		}

		my $cnt = $ckcnt - $block_ckcnt;
		push @$blocks, {
			stime   => $stime,
			ckcnt   => $cnt,
			ckfirst => $block_ckcnt,
			cklast  => $ckcnt,
			etime   => $stime + $ckcnt * $self->recint,
		};

	} elsif( $block_ckcnt > $ckcnt ){
		carp "inconsistency: block chunks > total, might truncating last blocks";
	}

	my $prev_block;
	foreach my $blk ( reverse @$blocks ){

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


	$self->debug( "starting to read $ckcnt chunks at ", fpos(tell $fh) );
	my $ckread = $v->chunks_read( $blocks, $temperature );

	$self->debug( "finished reading chunks at ", fpos(tell $fh) );
	if( ! eof( $fh ) ){
		carp "found extra data at end of file";
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

	foreach my $mark ( @$marker ){
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
			meta	=> {
				note	=> $mark->{note},
			},
		});
	}
}

sub mark_workout {
	my( $self ) = @_;
	Workout::Marker->new( {
		store	=> $self, 
		start	=> $self->time_start, 
		end	=> $self->time_end,
		meta	=> {
			note	=> substr( $self->meta_field('athletename'). '    ', 0, 4 ),
		},
	});
}



1;
__END__


=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
