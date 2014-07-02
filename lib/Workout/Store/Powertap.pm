#
# Copyright (c) 2009 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Powertap - read/write Powertap csv files

=head1 SYNOPSIS

  $src1 = Workout::Store::Powertap->read( "2009_12_10_19_42_03.csv" );

  $src2 = Workout::Store::Powertap->read( "foo.csv", {
  	default_time	=> time,
  });

=head1 DESCRIPTION

Interface to read/write Powertap csv files. Inherits from Workout::Store and
implements do_read/_write methods.

Powertap files do not contain the start date and time. Usually this is
part of the filename. As the filename might not be available (reading from
a pipe, ...), you can specify it manually. As fallback the current date is
taken.

=cut

# TODO: document timestamp in filename, provide method to build basename
# TODO: read/write altitude as GoldenCheetah does
# TODO: support extra date columns written by 'ptapdl -DTM'
# TODO: verify read values are numbers

# heavily inspired by GoldenCheetah and
# http://rick.mollprojects.com/power_meter_tools/csv_format.html

package Workout::Store::Powertap;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Workout::Chunk;
use Carp;
use DateTime;


our $VERSION = '0.01';

sub filetypes {
	return 'csv', 'ptap';
}

our %defaults = (
	recint	=> 1,
	tz	=> 'local',
	default_start	=> undef,
);

our %fields_supported = map { $_ => 1; } qw{
	dist
	cad
	hr
	work
};

our $re_fieldsep = qr/,/;
our $re_trim = qr/^\s+(.*)\s*$/;
our $re_stripnl = qr/[\r\n]+$/;

__PACKAGE__->mk_accessors( keys %defaults );

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$class->SUPER::new({
		%defaults,
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 0,
	});
}

=head1 METHODS

=head2 default_start

get/set the default start time (unix timestamp) in case it cannot be
determined from the filename.

=head2 tz

set/get timezone for getting the start time from the filename. See DateTime.

=cut


sub do_read {
	my( $self, $fh, $fname ) = @_;

	binmode( $fh, ':crlf:encoding(windows-1252)' );



	# get header:

	my $distconv;

	my $line = <$fh>;

	# TODO: cope with shuffled columns

	if( ! defined $line ){
		croak "empty file";

	} elsif( $line =~ /^\s*Minutes\s*,
		\s*Torq[^,]*,
		\s*(Km\/h|kph|kmh)\s*,
		\s*Watts\s*,
		\s*Km\s*,
		\s*Cadence\s*,
		\s*Hrate\s*,
		\s*ID
		/xi ){

		$distconv = 1000;

	} elsif( $line =~ /^\s*Minutes\s*,	# 0
		\s*Torq[^,]*,			# 1
		\s*(Miles\/h|m\/h|mph)\s*,	# 2
		\s*Watts\s*,			# 3
		\s*Miles\s*,			# 4
		\s*Cadence\s*,			# 5
		\s*Hrate\s*,			# 6
		\s*ID				# 7 lapid
		# optional: altitude		# 8
		/xi ){

		$distconv = 1000;
	

	} else {
		croak "unrecognised file format";

	}


	# guess recint

	my @data;
	while( defined($line = <$fh>) ){
		$line =~ s/$re_stripnl//;

		push @data, [ map {
			s/$re_trim/$1/;
			$_ eq '' ? undef : $_;
		} split( /$re_fieldsep/, $line ) ];
	}

	my $dur = 60 * $data[-1][0];
	my $recint = int( 100 * $dur / (1+ scalar @data) ) / 100;

	# TODO: other "known" recints
	foreach my $known ( 1.26, int($recint) ){
		if( abs($recint - $known) <= 0.04 ){
			$recint = $known;
			last;
		}
	}
	$self->recint( $recint );
	$self->debug( "guessed recint: $recint" );




	# guess start time

	my $stime;

	if( $self->default_start ){
		$self->debug( "using specified default_start time" );
		$stime = $self->default_start;

	} elsif( $fname && $fname =~ /
			(\d\d\d\d)	# year
			_(\d\d)		# month
			_(\d\d)		# day
			_(\d\d)		# hour
			_(\d\d)		# minute
			_(\d\d)		# second
			\.[^.]+$/x ){

		$stime = DateTime->new(
			year	=> $1,
			month	=> $2,
			day	=> $3,
			hour	=> $4,
			minute	=> $5,
			second	=> $6,
			time_zone	=> $self->tz,
		)->hires_epoch;
		$self->debug( "found start time in filename: ". $stime );

	} else {
		$stime = time - $dur;
		$self->debug( "no start time, using ". $stime );

	}



	# add chunks:

	my $elapsed = 0;
	my $lodo = 0;
	my $lapid = 0;
	my @laps;
	my $inconsistent;
	foreach my $chunk ( @data ){

		$elapsed += $recint;
		if( abs($elapsed - $chunk->[0] * 60) > 0.03 ){
			$inconsistent ||= $chunk->[0];
		}

		my $time = $stime + $elapsed;

		my $dist = defined( $chunk->[4] ) && $chunk->[4] >=0
			? ( ($chunk->[4] - $lodo) * $distconv )
			: undef;

		my $cad;
		if( defined $chunk->[5] && $chunk->[5] >= 0 ){
			$cad = $chunk->[5];
		}

		my $hr;
		if( defined $chunk->[6] && $chunk->[6] > 0 ){
			$hr = $chunk->[6];
		}

		my $work;
		if( defined $chunk->[3] && $chunk->[3] >= 0 ){
			$work = $recint * $chunk->[3];
		}

		$self->chunk_add( Workout::Chunk->new({
			time	=> $time,
			dur	=> $recint,
			dist	=> $dist,
			cad	=> $cad,
			hr	=> $hr,
			work	=> $work,
		}));

		if( $chunk->[7] && $lapid != $chunk->[7] ){

			push @laps, {
				note	=> $lapid++,
				end	=> $time,
			};
		}

		$lodo = $chunk->[4];
	}

	$inconsistent && carp "file has inconsistent timestamps: ".  $inconsistent;

	if( @laps ){
		push @laps, {
			note	=> $lapid,
			end	=> $stime + $elapsed,
		};

		$self->mark_new_laps( \@laps );
	}
}


sub do_write {
	my( $self, $fh, $fname ) = @_;

	$self->chunk_first
		or croak "no data";

	binmode( $fh, ':crlf:encoding(windows-1252)' );

	my @laps = $self->laps;

	print $fh " Minutes, Torq (N-m),  Km\/h, Watts,      Km, Cadence, Hrate,  ID\n";

	my $lapid = 0;
	my $iter = $self->iterate;
	my $elapsed = 0;
	my $odo = 0;
	while( my $c = $iter->next ){

		my $nextid;
		while( @laps && $laps[0]->end < $c->time ){
			++$nextid;
			shift @laps;
		}

		++$lapid if $nextid;

		$elapsed += $c->dur;
		$odo += ($c->dist || 0);

		# TODO: is it really necessary to limit the float precision?
		print $fh join(",",
			sprintf('%8.3f', $elapsed / 60),
			'           ',
			$c->spd ? sprintf('%6.1f', $c->spd * 3.6)
				: '      ',
			sprintf('%6d',$c->pwr||0),
			$odo ? sprintf('%8.3f', $odo / 1000)
				: '        ',
			sprintf('%8d', $c->cad||0),
			$c->hr ? sprintf('%6d', $c->hr)
				: '      ',
			sprintf('%4d', $lapid),
		),"\n";
	}

}


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
