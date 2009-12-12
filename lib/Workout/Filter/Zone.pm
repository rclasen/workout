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

  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = Workout::Filter::Zone->new( $src, { zones => [ {
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

  foreach $zone ( @{ $it->zones } ){
	  print "time in zone ", $zone->{zone}, ": ",
	  	$zone->{dur}, "\n";
  }

=head1 DESCRIPTION

calculates time spent in specified zones.

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

__PACKAGE__->mk_ro_accessors( keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

# TODO: document in-/output zone hash elements
# TODO: support other fields
# TODO: support multiple fields

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

=head1 METHODS

=head2 zones

returns an arrayref with the zones.

=cut

sub process {
	my( $self ) = @_;

	my $c = $self->src->next
		or return;
	$self->{cntin}++;

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
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut

