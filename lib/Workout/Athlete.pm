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
  $dst = Workout::Store::Memory->new;
  $dst->from( $pwr );

=head1 DESCRIPTION

Container for Athlete Data.

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


=head2 new( <args> )

create new Athlete object

=cut


sub new {
	my( $class, %a ) = @_;

	my $self = bless { %default
	}, $class;

	foreach my $f ( keys %default ){
		$self->$f( $a{$f} ) if exists $a{$f};
	}

	return $self;
}

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
