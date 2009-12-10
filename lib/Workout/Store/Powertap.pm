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

our $re_fieldsep = qr/\s*,\s*/;
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
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 0,
		cap_note	=> 0,
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

	my $distconv;

	my $line = <$fh>;

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

	my @data;
	while( defined($line = <$fh>) ){
		$line =~ s/$re_stripnl//;

		push @data, [ map {
			$_ eq '' ? undef : $_;
		} split( /$re_fieldsep/, $line ) ];
	}

	my $dur = 60 * $data[-1][0];
	my $recint = int( 100 * $dur / scalar @data) / 100;
	$self->recint( $recint );
	$self->debug( "guessed recint: $recint" );

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
			\.[^.]$/x ){

		$self->debug( "found start time in filename" );
		$stime = DateTime->new(
			year	=> $1,
			month	=> $2,
			day	=> $3,
			hour	=> $4,
			minute	=> $5,
			second	=> $6,
			time_zone	=> $self->tz,
		);

	} else {
		$self->debug( "falling back to current time as start time");
		$stime = time - $dur;

	}

	my $lodo = 0;
	my $time = $stime;
	my @laps = {
		note	=> 0,
		start	=> $time,
		end	=> undef,
	};
	foreach my $chunk ( @data ){
		$time += $recint;

		my $dist = defined( $chunk->[4] )
			? ( ($chunk->[4] - $lodo) * $distconv )
			: undef;

		$self->chunk_add( Workout::Chunk->new({
			time	=> $time,
			dur	=> $recint,
			dist	=> $dist,
			cad	=> $chunk->[5],
			hr	=> $chunk->[6],
			work	=> defined( $chunk->[3] )
				? $recint * $chunk->[3]
				: undef,
		}));

		if( $chunk->[7] && $laps[-1]{note} != $chunk->[7] ){
			$laps[-1]{end} = $time;

			push @laps, {
				note	=> $chunk->[7],
				start	=> $time,
				end	=> undef,
			};
		}

		$lodo = $chunk->[4];
	}
	$laps[-1]{end} = $time;

	if( @laps > 1 ){
		foreach my $lap ( @laps ){
			$self->mark_new( $lap );
		}
	}
}


sub do_write {
	my( $self, $fh, $fname ) = @_;

	my $first = $self->chunk_first
		or croak "no data";

	binmode( $fh, ':crlf:encoding(windows-1252)' );

	my $marks = $self->marks;
	my @tics = sort { $a <=> $b } grep {
		$_ > $first->time;
	} map {
		$_->start, $_->end;
	} @$marks;


	print $fh " Minutes, Torq (N-m),  Km\/h, Watts,      Km, Cadence, Hrate,  ID\n";

	my $id = 0;
	my $iter = $self->iterate;
	my $time = 0;
	my $odo = 0;
	while( my $c = $iter->next ){

		my $nextid;
		while( @tics && $tics[0] < $c->time ){
			++$nextid;
			shift @tics;
		}

		++$id if $nextid;

		$time += $c->dur;
		$odo += $c->dist;

		print $fh join(",",
			sprintf('%8.3f', $time / 60),
			'           ',
			$c->spd ? sprintf('%6.1f', $c->spd * 3.6)
				: '      ',
			sprintf('%6d',$c->pwr||0),
			$odo ? sprintf('%8.3f', $odo / 1000)
				: '        ',
			sprintf('%8d', $c->cad||0),
			$c->hr ? sprintf('%6d', $c->hr)
				: '      ',
			sprintf('%4d', $id),
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
