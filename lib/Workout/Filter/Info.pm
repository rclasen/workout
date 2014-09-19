#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::Info - collect info about the workout

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = Workout::Filter::Info->new( $src, { spdmin => 0.5 } );
  $it->finish;

  print "average speed: ", $it->spd, " m/sec\n";

=head1 DESCRIPTION

Calculates some overall data for the whole workout.

=cut

package Workout::Filter::Info;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;
use Math::Trig;

our $VERSION = '0.01';

our %default = (
	elefuzz	=> 7,		# (m)		minimum elevatin change threshold
	elemax	=> 10000,	# (m)		maximim elevation (Mt. Everest: 8848 m)
	spdmin	=> 1,		# (m/s)		minimum speed
	kphmin	=> .00001,	# (kph)		minimum speed
	pwrmin	=> 40,		# (W)
	cadmin	=> 0,		# (rpm)
	# currently unused:
	vspdmax	=> 4,		# (m/s)		maximum vertical speed
	gradmax => 40,		# (%)           maximum gradient/slope
	accelmax => 6,		# (m/s²)	maximum acceleration
);

our %init = (
	cntcalc	=> 0,
	chunk_first	=> undef,
	chunk_last	=> undef,
	lele	=> undef,
	dur_rec	=> 0,
	dur_mov	=> 0,
	dur_cad	=> 0,
	dur_ncad => 0,
	dur_hr	=> 0,
	dist	=> 0,
	vspd_max	=> 0,
	vspd_max_time	=> undef,
	spd_min	=> undef,
	spd_min_time	=> undef,
	spd_max	=> 0,
	spd_max_time	=> undef,
	kph_min	=> undef,
	kph_min_time	=> undef,
	kph_max	=> 0,
	kph_max_time	=> undef,
	accel_max	=> 0,
	accel_max_time	=> undef,
	temp_sum	=> 0,
	dur_temp	=> 0,
	temp_start	=> undef,
	temp_end	=> undef,
	temp_min	=> undef,
	temp_min_time	=> undef,
	temp_max	=> 0,
	temp_max_time	=> undef,
	dur_ele		=> 0,
	ele_start	=> undef,
	ele_end	=> undef,
	ele_sum		=> 0,
	ele_min	=> undef,
	ele_min_time	=> undef,
	ele_max	=> 0,
	ele_max_time	=> undef,
	grad_max	=> 0,
	grad_max_time	=> undef,
	ascent	=> 0,
	descent	=> 0,
	work	=> 0,
	pwr_min	=> undef,
	pwr_min_time	=> undef,
	pwr_max	=> 0,
	pwr_max_time	=> undef,
	torque_max	=> 0,
	torque_max_time	=> undef,
	hr_sum	=> 0,
	hr_min	=> undef,
	hr_min_time	=> undef,
	hr_max	=> 0,
	hr_max_time	=> undef,
	cad_sum	=> 0,
	cad_nsum	=> 0,
	cad_min	=> undef,
	cad_min_time	=> undef,
	cad_max	=> 0,
	cad_max_time	=> undef,
	fields_used	=> {},
);

my %calc = (
	time_end	=> undef,
	time_start	=> undef,
	dur	=> undef,
	dur_coast	=> undef,
	dur_creep	=> undef,
	dur_gap	=> undef,
	cad_avg	=> undef,
	cad_navg	=> undef,
	cad_percent	=> undef,
	ele_avg	=> undef,
	hr_avg	=> undef,
	pwr_avg	=> undef,
	spd_avg	=> undef,
	kph_avg	=> undef,
	temp_avg	=> undef,
	torque_avg	=> undef,
	vspd_avg	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );
__PACKAGE__->mk_ro_accessors( keys %init );
__PACKAGE__->mk_calc_accessors( keys %calc );

{ no strict 'refs';

sub mk_calc_accessors {
	my $class = shift;

	foreach my $f ( @_ ){
		*{"${class}::${f}"} = sub {
			my( $self ) = @_;
			$self->calculate;
			$self->{$f};
		};
	}
}
}

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( $iter, { 
		%default, 
		%$a, 
		%init,
	});

	$self->{fields_used} = { 
		map { $_ => 0 } $self->fields_supported,
	};
	
	$self;
}

=head1 METHODS

=head2 calculcate

update some calculated fields. Automatically invoked when such fields are
retrieved.

=cut

sub calculate {
	my( $self ) = @_;

	return if $self->{cntin} <= $self->{cntcalc};
	$self->{cntcalc} = $self->{cntin};

	if( my $c = $self->{chunk_last} ){
		$self->{time_end} = $c->time;
	}

	if( my $c = $self->{chunk_first} ){
		$self->{time_start} = $c->stime;
	}

	if( my $s = $self->{time_start}
		and my $e = $self->{time_end} ){

		$self->{dur} = $e - $s;
	}

	if( my $m = $self->{dur_mov}
		and my $c = $self->{dur_ncad} ){

		$self->{dur_coast} = $c < $m ? $m - $c : 0;
	}

	if( my $t = $self->{dur} ){
		$self->{dur_creep} = $t - $self->{dur_mov};
		$self->{dur_gap} = $t - $self->{dur_rec};
	}


	if( my $d = $self->{dur_cad} || $self->{dur} ){
		$self->{cad_avg} = $self->{cad_sum} / $d;
	}

	if( my $d = $self->{dur_ncad} || $self->{dur} ){
		$self->{cad_navg} = $self->{cad_nsum} / $d;
	}

	if( my $m = $self->{dur_mov} ){
		$self->{cad_percent} = 100 * ($self->{dur_ncad} ||0) / $m;
	}

	if( my $dur = $self->{dur_ele} || $self->{dur} ){
		$self->{ele_avg} = $self->{ele_sum} / $dur;
	}

	if( my $d = $self->{dur_hr} || $self->{dur} ){
		$self->{hr_avg} = $self->{hr_sum} / $d;
	}


	if( my $dur = $self->{dur_mov} || $self->{dur} ){
		$self->{pwr_avg} = $self->{work} / $dur;
	}

	if( my $d = $self->{dur_mov} ){
		$self->{spd_avg} = $self->{dist} / $d;
		$self->{kph_avg} = ($self->{dist} / $d)*3.6;
	}

	if( my $dur = $self->{dur_temp} || $self->{dur} ){
		$self->{temp_avg} = $self->{temp_sum} / $dur;
	}

	if( my $cad = $self->{cad_avg}
		and defined(my $pwr = $self->{pwr_avg}) ){

		$self->{torque_avg} = $pwr / (2 * pi * $cad ) * 60;
	}

	if( my $c = $self->{ascent}
		and my $d = $self->{dur_mov} ){

		$self->{vspd_avg} = $c/$d;
	}
}

=head1 ACCESSOR METHODS

These methods set parameters that influence the calculations. You need to
set them before passing data through this filter or you'll get bad
results. You can pass these values to the constructor, aswell.

=head2 accelmax

maximum acceleration that's realistic (m/s²). Larger values are ignored.

=head2 elefuzz

minimum elevation change threshold (m). Used for smoothing the elevation
changes.

=head2 elemax

maximum valid elevation (m) to use for calculations. Don't confuse with
ele_max. This might move to some seperate Filter in future versions.

=head2 gradmax

maximum gradient/slope that's realistic (%). Larger values are ignored.
Used for smoothing the elevation changes.

=head2 pwrmin

minimum power before you're considered "moving" in Watt (W). 

=head2 spdmin

minimum speed before you're considered "moving" (m/s).

=head2 vspdmax

maximum vertical speed that's realistic (m/s). Larger values are ignored.
Used for smoothing the elevation changes.




=head1 INFO METHODS

=head2 meta( [$meta] )

returns a copy of the provided meta hash where missing bits are
automatically populated by the calculated values.

=cut

sub meta {
	my( $self, $in ) = @_;

	$self->calculate;

	$in ||= {};
	my %out = ( %$in );

	foreach my $k ( keys %init, keys %calc ){
		next if defined $out{$k};
		$out{$k} = $self->{$k};
	}

	return \%out;
}


=head2 accel_max

maximum acceleration seen in the workout (m/s²).

=head2 accel_max_time

end time of chunk with maximum acceleration.

=head2 cad_avg

average cadence for all samples with cadence value (1/min).

=head2 cad_navg

average cadence excluding time without pedaling (1/min).

=head2 cad_min

minimum cadence seen in the workout (1/min)

=head2 cad_min_time

end time of chunk with minimum cadence.

=head2 cad_max

maximum cadence seen in the workout (1/min)

=head2 cad_max_time

end time of chunk with maximum cadence.

=head2 cad_nsum

total number of crank revolutions.

=head2 cad_percent

percent of moving time where cranks were spinning (%).

=head2 cad_sum

total number of crank revolutions. Internally used for calculating the
average cadence.

=head2 chunk_first

returns first chunk.

=head2 chunk_last

returns last chunk.

=head2 dist

total cumulated distance (m).

=head2 dur

total duration (sec).

=head2 dur_cad

total duration with cadence recording (sec)

=head2 dur_coast

time spent not pedaling (sec).

=head2 dur_creep

time (sec) spent not moving - or moving too slow.

=head2 dur_hr

total duration with heartrat recording (sec)

=head2 dur_rec

total time covered by Chunks. (sec)

=head2 dur_gap

total time not covered by Chunks. (sec)

=head2 dur_mov

total moving time. (sec)

=head2 dur_ncad

total duration while pedaling (sec)

=head2 dur_temp

total duration with temperature recording (sec)

=head2 dur_ele

total duration with elevation recording (sec)

=head2 ele_start

elevation at start of workout (m).

=head2 ele_end

elevation at end of workout (m).

=head2 ele_max

maximum elevation seen in the workout (m). Don't confuse with elemax!

=head2 ele_max_time

end time of chunk with maximum elevation.

=head2 ele_min

minimum elevation seen in the workout (m).

=head2 ele_min_time

end time of chunk with minimum elevation.

=head2 ele_avg

average elevation (m).

=head2 lele

last "smoothed" elevation. For internal use.

=head2 ascent

sum of all positive elevation changes. Takes elefuzz and other
smoothing into account.

=head2 descent

sum of all negative elevation changes. Takes elefuzz and other
smoothing into account.

=head2 fields_used

builds and returns a hashref with fields that are actually used.

=head2 grad_max

maximum gradient seen in the workout (%).

=head2 grad_max_time

end time of chunk with maximum gradient.

=head2 hr_avg

average heartrate (1/min)

=head2 hr_max

maximum heartrate seen in the workout (1/min).

=head2 hr_max_time

end time of chunk with maximum heartrate.

=head2 hr_min

minimum heartrate seen in the workout (1/min).

=head2 hr_min_time

end time of chunk with minimum heartrate.

=head2 hr_sum

total number of heartbeats. Used for calculating average heartrate.

=head2 pwr_avg

average power (W)

=head2 pwr_min

minimum power seen in the workout (W).

=head2 pwr_min_time

end time of chunk with minimum power.

=head2 pwr_max

maximum power seen in the workout (W).

=head2 pwr_max_time

end time of chunk with maximum power.

=head2 spd_avg

average speed (m/s)

=head2 spd_min

minimum speed seen in the workout (m/s).

=head2 spd_min_time

end time of chunk with minimum speed.

=head2 spd_min

maximum speed seen in the workout (m/s).

=head2 spd_max_time

end time of chunk with maximum speed.

=head2 temp_avg

average temperature (°C)

=head2 temp_max

maximum temperature seen in the workout (°C).

=head2 temp_max_time

end time of chunk with maximum temperature.

=head2 temp_min

minimum temperature seen in the workout (°C).

=head2 temp_min_time

end time of chunk with minimum temperature.

=head2 temp_sum

Sum of temperature values (°C * sec). Used for calculating the average
temperature.

=head2 temp_start

temperature at start of workout (°C).

=head2 temp_end

temperature at end of workout (°C).

=head2 time_end

time at end of workout (unix timestamp).

=head2 time_start

time at start of workout (unix timestamp).

=head2 torque_avg

average torque (Nm).

=head2 torque_max

maximum torque seen in the workout (Nm).

=head2 torque_max_time

end time of chunk with maximum torque.

=head2 vspd_avg

average vertical speed (m/s):

=head2 vspd_max

maximum vertical speed seen in the workout (m/s).

=head2 vspd_max_time

end time of chunk with maximum vertical speed.

=head2 work

total energy spent in Joule (J).

=cut


sub set_min {
	my( $self, $ck ) = splice @_,0,2;

	foreach my $field (@_){
		my $val = $ck->$field;
		defined $val or next;

		my $fn = $field .'_min';
		if( ! defined $self->{$fn} || $self->{$fn} > $val ){
			$self->{$fn} = $val;
			$self->{$fn .'_time'} = $ck->time;
		}
	}
}

sub set_zmin {
	my( $self, $ck ) = splice @_,0,2;

	foreach my $field (@_){
		my $val = $ck->$field;
		$val or next;

		my $fn = $field .'_min';
		if( ! defined $self->{$fn} || $self->{$fn} > $val ){
			$self->{$fn} = $val;
			$self->{$fn .'_time'} = $ck->time;
		}
	}
}

sub set_max {
	my( $self, $ck ) = splice @_,0,2;

	foreach my $field (@_){
		my $val = $ck->$field;
		defined $val or next;

		my $fn = $field .'_max';
		if( $self->{$fn} < $val ){
			$self->{$fn} = $val;
			$self->{$fn .'_time'} = $ck->time;
		}
	}
}

sub set_asum {
	my( $self, $ck ) = splice @_,0,2;

	foreach my $field (@_){
		my $val = $ck->$field;
		defined $val or next;

		$self->{$field.'_sum'} += $val * $ck->dur;
		$self->{'dur_'.$field} += $ck->dur;
	}
}

sub set_nsum {
	my( $self, $ck ) = splice @_,0,2;

	foreach my $field (@_){
		my $val = $ck->$field;
		(defined $val && $val > 0) or next;

		$self->{$field.'_nsum'} += $val * $ck->dur;
		$self->{'dur_n'.$field} += $ck->dur;
	}
}

sub process {
	my( $self ) = @_;

	my $d = $self->src->next
		or return;
	$self->{cntin}++;

	$self->{chunk_first} ||= $d;
	$self->{chunk_last} = $d;

	foreach my $f ( keys %{$self->{fields_used}} ){
		# HACK: should check if field is defined, but this handles bad files better
		++$self->{fields_used}{$f} if $d->$f;
	}

	$self->{dist} += $d->dist ||0;

	# HACK: should check if ele is defined, but this handles bad files better
	if( $d->ele && $d->ele < $self->elemax ){
		# TODO: instead of checking for elemax a previous filter
		# should've nuked/fixed all unrealistic values

		if( defined $self->{lele} ){
			my $climb = $d->ele - $self->{lele};
			# TODO: better fix climb calculation in Calc.pm

			if( abs($climb) >= $self->elefuzz ){
				$self->{lele} = $d->ele;
				if( $climb > 0 ){
					$self->{ascent} += $climb;
				} else {
					$self->{descent} += abs($climb);
				}
			}

		} else {
			$self->{lele} = $d->ele;
		}

		if( ! defined $self->{ele_start} ){
			$self->{ele_start} = $d->ele;
		}

		$self->{ele_ele} = $d->ele;

	}

	if( $d->temp ){
		if( ! defined $self->{temp_start} ){
			$self->{temp_start} = $d->temp;
		}

		$self->{temp_end} = $d->temp;
	}

	if( (my $work = $d->work||0) > 0 ){
		$self->{work} += $work;
	}
	
	# Duration
	$self->{dur_rec} += $d->dur;
	
	# Time Riding
	if( ($d->pwr||0) > $self->pwrmin ) {
		$self->{dur_mov} += $d->dur;
	} elsif ( ($d->cad||0) > $self->cadmin ) {
		$self->{dur_mov} += $d->dur;
	} elsif ( ($d->kph||0) > $self->kphmin ) {
		$self->{dur_mov} += $d->dur;
	} elsif ( ($d->spd||0) > $self->spdmin ){
		$self->{dur_mov} += $d->dur;
	}

	$self->set_nsum( $d, qw( cad ));
	$self->set_asum( $d, qw( hr cad ele temp ));
	$self->set_max( $d, qw( pwr torque hr cad spd kph vspd accel temp ele grad ));
	$self->set_min( $d, qw( temp ele ));
	$self->set_zmin( $d, qw( cad hr pwr spd kph ));

	$d;
}

1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut

