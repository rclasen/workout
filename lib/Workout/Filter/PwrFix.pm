#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::PwrFix;

=head1 NAME

Workout::Filter::PwrFix - Recalculate Power based on changed SRM
calibration data (slope, zeropos)

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );

  $iter = Workout::Filter::PwrFix->new( $src, {
	old_slope	=> 17.0,
  	new_slope	=> 17.7,
  });

  while( my $chunk = $iter->next ){
  	# do something
  }

=head1 DESCRIPTION

Recalculates Power based on changed SRM calibration data (slope, zeropos)

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;


our $VERSION = '0.01';

our %default = (
	old_slope	=> 1,
	new_slope	=> 1,
	old_zeropos	=> 0,
	new_zeropos	=> 0,
);

__PACKAGE__->mk_accessors(keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a ||= {};
	$class->SUPER::new( $src, {
		%default,
		%$a,
	});
}

=head1 METHODS

=head2 old_slope

get/set the slope used to record current power values

=head2 old_zeropos

get/set the zero offset used to record current power values

=head2 new_slope

get/set the slope for used to calculate new power

=head2 new_zeropos

get/set the zero offset used to calculate new power

=cut

sub process {
	my( $self ) = @_;

	my $i = $self->src->next
		or return;

	my $hz = $i->pwr * $self->old_slope + $self->old_zeropos;
	my $pwr = ( $hz - $self->new_zeropos ) / $self->new_slope;

	$i->clone({
		prev	=> $self->last,
		work	=> $pwr * $i->dur,
	});
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut
