#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::Zone - caculcate time in specified zones

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = Workout::Filter::Zone->new( $src->iterate, { zones => [ {
	zone	=> 'recovery',
  	field	=> 'pwr',
	min	=> 0,
	max	=> 150,
  }, {
	zone	=> 'no recovery',
  	field	=> 'pwr',
	min	=> 150,
	max	=> 320,
  } ] } );
  $it->finish;
  print $it->tss;

=head1 DESCRIPTION

Base Class for modifying and filtering the Chunks of a Workout.

=cut

package Workout::Filter::Zone;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

our %default = (
	zones	=> [],
);

__PACKAGE__->mk_accessors( keys %default );

sub new {
	my( $class, $iter, $a ) = @_;

	$a||={};
	$class->SUPER::new( $iter, { 
		%default, 
		%$a, 
		zones	=> [ map { { 
			zone	=> ($_->{zone} || ''),
			field	=> ($_->{field} || 'pwr'),
			min	=> ($_->{min} || 0),
			max	=> $_->{max},
			dur	=> 0,
		} } @{$a->{zones} || []} ],
	} );
}


sub process {
	my( $self ) = @_;

	my $c = $self->_fetch
		or return;

	foreach my $z ( @{$self->zones} ){
		my $f = $z->{field} or next;
		my $v = $c->$f;
		if( defined $v 
			&& $v >= $z->{min}
			&& ( ! defined $z->{max} || $v < $z->{max} ) ){

			$z->{dur} += $c->dur;
		}
	}

	$c;
}


1;

