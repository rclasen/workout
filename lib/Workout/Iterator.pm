#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Iterator - Base Class to iterate through Workout Stores

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = $src->iterate;
  while( defined(my $chunk = $it->next)){
  	print join(",",@$chunk{qw(time dur pwr)}),"\n";
  }

=head1 DESCRIPTION

Base Class to iterate through Workout Stores.

=cut

package Workout::Iterator;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Carp;

our $VERSION = '0.01';

our %init = (
	store	=> undef,
	cntin	=> 0,
	cntout	=> 0,
	last	=> undef,
);

__PACKAGE__->mk_ro_accessors( keys %init );

=head2 new( $store, $arg )

create empty Iterator.

=cut

sub new {
	my( $class, $store, $a ) = @_;

	$a ||= {};
	$class->SUPER::new( {
		%$a,
		%init,
		store	=> $store,
	});
}


=head2 next

return next chunk

=cut

sub process { croak "not implemented" ; };

sub next {
	my $self = shift;

	my $r = $self->process( @_ )
		or return;
	$self->{cntout}++;

	return $self->{last} = $r;
}

=head2 all

return list with all chunks

=cut

sub all {
	my( $self ) = @_;

	my @all;
	while( defined(my $c = $self->next)){
		push @all, $c;
	}

	@all;
}

=head2 finish

process all chunks, returns nothing.

=cut

sub finish {
	my( $self ) = @_;

	while( defined($self->next)){
	}
}

=head2 store

return store that's the source for this iterator (-chain).

=cut


=head2 cntin

number of chunks passed into this iterator

=cut

=head2 cntout

number of chunks passed out of this iterator

=cut


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen


=cut
