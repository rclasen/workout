#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::Timeshift;

=head1 NAME

Workout::Filter::Timeshift - Timeshift Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );

  $iter = Workout::Filter::Timeshift->new( $src, {
  	delta => 42,
  });

  while( my $chunk = $iter->next ){
  	# do something
  }

=head1 DESCRIPTION

Adjusts the timestamps in all chunks by adding the specified delta

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;


# TODO: also change marker?

our $VERSION = '0.01';

our %default = (
	delta	=> 0,
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

=head2 delta

get/set the delta that's added to all chunks.

=cut

sub process {
	my( $self ) = @_;

	my $i = $self->src->next
		or return;

	$i->clone({
		prev	=> $self->last,
		time	=> $i->time + $self->delta,
	});
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut
