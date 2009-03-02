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
  $join = Workout::Filter::Timeshift->new( $src );
  while( my $chunk = $join->next ){
  	# do something
  }

=head1 DESCRIPTION

Iterator that automagically fills the gaps between individual data blocks
with fake chunks.

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

=head2 new( $src, $arg )

new iterator

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a ||= {};
	$class->SUPER::new( $src, {
		%default,
		%$a,
	});
}

=head2 next

get next data chunk

=cut

sub process {
	my( $self ) = @_;

	my $i = $self->_fetch
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
