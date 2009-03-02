#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::Timespan;

=head1 NAME

Workout::Filter::Timespan - only returns chunks within a specified timespan

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );
  $cut = Workout::Filter::Timespan->new( $src, { 
  	start	=> $start_time,	# seconds since epoch
	end	=> $end_time,	# seconds since epoch
  });
  while( my $chunk = $cut->next ){
  	# do something
  }

=head1 DESCRIPTION

Iterator that supressed data outside the specified timespan.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

# TODO: filter marker, too

our $VERSION = '0.01';

our %default = (
	start	=> 0,
	end	=> undef,
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

	my $i;
	do {
		$i = $self->_fetch
			or return;

		my $end = $self->end;
		if( defined $end && $end < $i->time ){
			return 
		}

	} while( $i->stime < $self->start );

	$i;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut
