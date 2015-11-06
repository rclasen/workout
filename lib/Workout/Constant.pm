package Workout::Constant;
use warnings;
use strict;

use Exporter;
our( @ISA, @EXPORT_OK, %EXPORT_TAGS );
BEGIN {
        @ISA = qw( Exporter );
	%EXPORT_TAGS = (
		all	=> [ qw(
			PI
			EULER

			NSEC
			HOUR
			KCAL
			KELVIN
			KMH
			FEET
			YARD
			MILE
			MPH

			GRAVITY
			RHO_0
			P_0
		)],
        );
	Exporter::export_ok_tags('all');
}

sub PI() { 3.14159265 }
sub EULER() { 2.718281 }	# ()		Eulersche Zahl

sub NSEC() { 1000000000 }	# (nsec)	factor / 1 sec = NSEC nanonsec
sub HOUR() { 3600 }	# (sec)		factor / 1 hour = HOUR seconds
sub KELVIN() { 273.15 }	# (C)		delta / 0 kelvin = KELVIN Celsius
sub KCAL() { 4186.8 }	# (J)		factor / 1 kcal = KCAL Joule
sub KMH() { 3.6 }		# (m/s)		factor / 1 km/h = KMH meter/sec
sub FEET() { 0.3048 }	# (m)		factor / 1 feet = FEET meter
sub YARD() { 0.9144 }	# (m)		factor / 1 yard = YARD meter
sub MILE() { 1609.344 }	# (m)		factor / 1 mile = MILE meter
sub MPH() { 0.44704 }	# (m/s)		factor / 1 mile/h = MPH m/sec

sub GRAVITY() { 9.81 }	# (m/s²)	Erdbeschleunigung
sub RHO_0() { 1.293 }	# (kg/m³)	Luftdichte auf Meereshöhe bei 0° Celsius
sub P_0() { 101325 }	# (Pa = kg/(ms²)) Luftdruck auf Meereshöhe bei 0° Celsius


1;
