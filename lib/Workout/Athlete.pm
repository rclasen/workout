#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Athlete - Athlete specific Data

=head1 SYNOPSIS

  $ath = Workout::Athlete->new( 
  	hrmax	=> 180,
	hrrest	=> 40,
	weight	=> 80,
  );
  $ath->vo2max( 50 );

  $src = Workout::Store::Gpx->read( "input.gpx" } );
  $pwr = Workout::Filter::Pwr->new( $src, { athlete => $ath } );

  $dst = Workout::Store::Hrm->new( { athlete => $ath } );
  $dst->from( $pwr );
  $dst->write( "out.hrm" );

=head1 DESCRIPTION

Class to hold athlete data.

=cut

package Workout::Athlete;

use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Class::Accessor::Fast';

our $VERSION = '0.01';

our %default = (
	hrrest	=> 40,
	hrmax	=> 180,
	weight	=> 80,
	vo2max	=> 50,
);
__PACKAGE__->mk_accessors( keys %default );


# TODO: training zones

=head1 CONSTRUCTOR

=head2 new( [ \%data ] )

create new Athlete object. It's used in some places for calculating
certain data.

The object is initialized with the values from the optional data hashref.

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	$class->SUPER::new({
		%default,
		%$a,
	});
}

=head1 METHODS

=head2 hrrest

get/set resting heart rate (1/min).

=head2 hrmax

get/set maximum heart rate (1/min).

=head2 weight

get/set weight (kg)

=head2 vo2max

get/set maximal oxygen consumption rate (ml/min/kg)

=cut



1;
__END__

=head1 SEE ALSO

Class::Accessor, Workout, Workout::Store::HRM, Workout::Filter::Pwr

=head1 AUTHOR

Rainer Clasen

=cut
