#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::BaseQueue - Base Class for queueing unprocessed chunks

=head1 DESCRIPTION

Base Class for queueing unprocessed chunks. Inherits from
Workout::Filter::Base.

=cut

package Workout::Filter::BaseQueue;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a ||= {};
	$class->SUPER::new( $iter, {
		%$a,
		queue	=> [],
	});
}

# TODO: POD

sub _push {
	my $self = shift;
	push @{$self->{queue}}, @_;
}

sub _pop {
	my $self = shift;
	pop @{$self->{queue}};
}

sub _fetch {
	my( $self ) = @_;

	if( my $r = $self->_pop ){
		return $r;
	}

	if( my $r = $self->src->next ){
		$self->{cntin}++;
		return $r;
	}

	return;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut

