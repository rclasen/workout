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
	vspdmax	=> 4,		# (m/s)		maximum vertical speed
	gradmax => 40,		# (%)           maximum gradient/slope
	accelmax => 6,		# (m/s²)	maximum acceleration
	elefuzz	=> 7,		# (m)		minimum elevatin change threshold
	spdmin	=> 1,		# (m/s)		minimum speed
	pwrmin	=> 40,		# (W)
);

our %init = (
	chunk_first	=> undef,
	chunk_last	=> undef,
	lele	=> undef,
	dur_mov	=> 0,
	dur_cad	=> 0,
	dur_ncad => 0,
	dur_hr	=> 0,
	dist	=> 0,
	vspd_max	=> 0,
	vspd_max_time	=> undef,
	spd_max	=> 0,
	spd_max_time	=> undef,
	accel_max	=> 0,
	accel_max_time	=> undef,
	temp_sum	=> 0,
	dur_temp	=> 0,
	temp_min	=> undef,
	temp_min_time	=> undef,
	temp_max	=> 0,
	temp_max_time	=> undef,
	ele_min	=> undef,
	ele_min_time	=> undef,
	ele_max	=> 0,
	ele_max_time	=> undef,
	grad_max	=> 0,
	grad_max_time	=> undef,
	incline	=> 0,
	work	=> 0,
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
	cad_max	=> 0,
	cad_max_time	=> undef,
	fields_used	=> {},
);

__PACKAGE__->mk_accessors( keys %default );
__PACKAGE__->mk_ro_accessors( keys %init );

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

=head1 ACCESSOR METHODS

=head2 accelmax

maximum acceleration that's realistic (m/s²). Larger values are ignored.

=head2 elefuzz

minimum elevation change threshold (m). Used for smoothing the elevation
changes.

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

=head2 accel_max

maximum acceleration seen in the workout (m/s²).

=head2 accel_max_time

end time of chunk with maximum acceleration.

=head2 cad_avg

average cadence (1/min).

=cut

sub cad_avg {
	my( $self ) = @_;
	my $d = $self->dur_cad || $self->dur
		or return;
	$self->cad_sum / $d;
}

=head2 cad_max

maximum cadence seen in the workout (1/min)

=head2 cad_max_time

end time of chunk with maximum cadence.

=head2 cad_nsum

total number of crank revolutions.

=head2 cad_percent

percent of moving time where cranks were spinning (%).

=cut

sub cad_percent {
	my( $self ) = @_;
	my $m = $self->dur_mov
		or return;
	100 * ($self->dur_ncad ||0) / $m;
}

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

=cut

sub dur {
	my( $self ) = @_;

	my $s = $self->time_start
		or return;
	my $e = $self->time_end
		or return;

	$e - $s;
}

=head2 dur_cad

total duration with cadence recording (sec)

=head2 dur_coast

time spent not pedaling (sec).

=cut

sub dur_coast {
	my( $self ) = @_;

	my $m = $self->dur_mov
		or return;

	my $c = $self->dur_ncad;
	return $c < $m ? $m - $c : 0;
}

=head2 dur_creep

time (sec) spent not moving - or moving too slow.

=cut

sub dur_creep {
	my( $self ) = @_;

	my $t = $self->dur
		or return;

	$t - $self->dur_mov;
}

=head2 dur_hr

total duration with heartrat recording (sec)

=head2 dur_mov

total moving time. (sec)

=head2 dur_ncad

total duration while pedaling (sec)

=head2 dur_temp

total duration with temperature recording (sec)

=head2 ele_start

elevation at start of workout (m).

=cut

sub ele_start {
	my( $self ) = @_;

	my $s = $self->chunk_first
		or return;
	$s->ele;
}

=head2 ele_max

maximum elevation seen in the workout (m).

=head2 ele_max_time

end time of chunk with maximum elevation.

=head2 ele_min

minimum elevation seen in the workout (m).

=head2 ele_min_time

end time of chunk with minimum elevation.

=head2 lele

last "smoothed" elevation. For internal use.

=head2 fields_used

builds and returns a hashref with fields that are actually used.

=head2 grad_max

maximum gradient seen in the workout (%).

=head2 grad_max_time

end time of chunk with maximum gradient.

=head2 hr_avg

average heartrate (1/min)

=cut

sub hr_avg {
	my( $self ) = @_;
	my $d = $self->dur_hr ||$self->dur
		or return;
	$self->hr_sum / $d;
}

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

=head2 incline

sum of all positive elevation changes (climbs). Takes elefuzz and other
smoothing into account.

=head2 pwr_avg

average power (W)

=cut

sub pwr_avg {
	my( $self ) = @_;

	my $dur = $self->dur_mov || $self->dur
		or return;

	$self->work / $dur;
}

=head2 pwr_max

maximum power seen in the workout (W).

=head2 pwr_max_time

end time of chunk with maximum power.

=head2 spd_avg

average speed (m/s)

=cut

sub spd_avg {
	my( $self ) = @_;
	my $d = $self->dur_mov
		or return;
	$self->dist / $d;
}

=head2 spd_max

maximum speed seen in the workout (m/s).

=head2 spd_max_time

end time of chunk with maximum speed.

=head2 temp_avg

average temperature (°C)

=cut

sub temp_avg {
	my( $self ) = @_;

	my $dur = $self->dur_temp || $self->dur
		or return;

	$self->temp_sum / $dur;
}

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

=cut

sub temp_start {
	my( $self ) = @_;

	my $s = $self->chunk_first
		or return;
	$s->temp;
}

=head2 time_end

time at end of workout (unix timestamp).

=cut

sub time_end {
	my( $self ) = @_;

	my $c = $self->chunk_last
		or return;
	$c->time;
}

=head2 time_start

time at start of workout (unix timestamp).

=cut

sub time_start {
	my( $self ) = @_;

	my $c = $self->chunk_first
		or return;
	$c->stime;
}

=head2 torque_avg

average torque (Nm).

=cut

sub torque_avg {
	my( $self ) = @_;
	my $cad = $self->cad_avg or return;
	defined(my $pwr = $self->pwr_avg) or return;

	$pwr / (2 * pi * $cad ) * 60;
}

=head2 torque_max

maximum torque seen in the workout (Nm).

=head2 torque_max_time

end time of chunk with maximum torque.

=head2 vspd_avg

average vertical speed (m/s):

=cut

sub vspd_avg {
	my $self = shift;
	my $c = $self->incline
		or return;
	my $d = $self->dur_mov
		or return;
	$c/$d;
}

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
		defined $val && $val > 0 or next;

		$self->{$field.'_nsum'} += $val * $ck->dur;
		$self->{'dur_n'.$field} += $ck->dur;
	}
}

sub process {
	my( $self ) = @_;

	my $d = $self->_fetch
		or return;

	$self->{chunk_first} ||= $d;
	$self->{chunk_last} = $d;

	foreach my $f ( keys %{$self->{fields_used}} ){
		++$self->{fields_used}{$f} if $d->$f;
	}

	$self->{dist} += $d->dist ||0;

	if( $d->ele ){
		if( defined $self->{lele} ){
			my $climb = $d->ele - $self->{lele};
			# TODO: better fix climb calculation in Calc.pm

			if( abs($climb) >= $self->elefuzz ){
				$self->{lele} = $d->ele;
				if( $climb > 0 ){
					$self->{incline} += $climb;
				}
			}

		} else {
			$self->{lele} = $d->ele;
		}
	}

	if( (my $work = $d->work||0) > 0 ){
		$self->{work} += $work;
	}


	if( ($d->pwr||0) > $self->pwrmin
		|| ($d->spd||0) > $self->spdmin ){

		$self->{dur_mov} += $d->dur;
		$self->set_asum( $d, 'hr' );
	}

	$self->set_nsum( $d, qw( cad ));
	$self->set_asum( $d, qw( cad temp ));
	$self->set_max( $d, qw( pwr torque hr cad spd vspd accel temp ele grad ));
	$self->set_min( $d, qw( temp ele ));
	$self->set_zmin( $d, qw( hr ));

	$d;
}

1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut

