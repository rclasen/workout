#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::Join;

=head1 NAME

Workout::Filter::Join - Join blocks within Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );

  $join = Workout::Filter::Join->new( $src );

  while( my $chunk = $join->next ){
  	# do something
  }

=head1 DESCRIPTION

automagically fills the gaps between individual data blocks
with fake chunks.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::BaseQueue';
use Carp;

our $VERSION = '0.01';

our %default = (
	recint	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( $src, {
		%default,
		%$a,
	});
	$self->{stime} = undef;
	$self;
}

sub process {
	my( $self ) = @_;

	my $i = $self->_fetch
		or return;

	$self->{stime} ||= $i->stime;

	my $last = $self->last;

	if( $last && $i->isblockfirst( $last ) ){
		$self->_push( $i );

		if( $self->recint && $i->gap( $last) > $self->recint ){
			my $elapsed = $last->time - $self->{stime};
			my $time = $self->{stime} + $self->recint 
				* (1+int($elapsed/$self->recint));

			#$self->debug( "insert join from ". $last->time ." to ". $time );
			return $last->synthesize( $time, $i );
		}

		#$self->debug( "insert join from ". $last->time ." to ".  $i->stime );
		return $last->synthesize( $i->stime, $i );

	}

	return $i->clone({
		prev	=> $last,
	});
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::BaseQueue

=head1 AUTHOR

Rainer Clasen

=cut
