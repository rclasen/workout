#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Iterator - Virtual base class for iterating through workout
chunks

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = $src->iterate;
  while( $c = $it->next ){
	print join(",",$c->time, $c->dur, $c->pwr ),"\n";
  }

=head1 DESCRIPTION

Subclass of Workout::Base. Virtual base class for common interface and
shared functionality of Filters and Store Iterators. Allows retrieving
chunks from a store - optionally through a filter pipeline.

=cut

package Workout::Iterator;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Carp;

our $VERSION = '0.01';

our %init = (
	src	=> undef,
	cntin	=> 0,
	cntout	=> 0,
	last	=> undef,
);

__PACKAGE__->mk_ro_accessors( keys %init );


=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

create empty Iterator that pulls chunks from $src. $src is either another
Workout::Iterator or a Workout::Store.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a ||= {};
	$class->SUPER::new( {
		%$a,
		%init,
		src	=> $src,
	});
}

=head1 METHODS

=head2 src

return the source of which this iterator pulls it's values. This is either
another iterator oder a store.

=head2 stores

return list of stores where this iterator (-pipeline) is pulling chunks of.

=cut

sub stores { $_[0]->src->stores };



=head2 recint

return the recording interval of chunks that are pulled off this iterator.

=cut

sub recint { $_[0]->src->recint };



=head2 cap_block

returns the blocking capability of this iterator - i.e. if you have to
expect gaps between chunks pulled of this iterator.

=cut

sub cap_block { $_[0]->src->recint };



=head2 cntin

number of chunks passed into this iterator

=head2 cntout

number of chunks passed out of this iterator

=head2 last

returns the previous chunk.

=head2 next

return next chunk

=cut

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
	while( my $c = $self->next ){
		push @all, $c;
	}

	@all;
}


=head2 finish

process all chunks, returns nothing.

=cut

sub finish {
	my( $self ) = @_;

	while( $self->next ){}
}



=head2 process

method to overload in derived classed. That's the place where actual work
is done - i.e. where the "next" chunk is retrieved/calculated/...

=cut

sub process { croak "not implemented"; };



=head2 fields_supported( [ <field> .. ] )

return list of fields supported by this iterator pipeline.

=cut

sub fields_supported { shift->src->fields_supported( @_ ); }



=head2 fields_unsupported( <field> ... )

returns list of fields unsupported by this iterator pipeline.

=cut

sub fields_unsupported {
	my $self = shift;

	my %ok = map {
		$_ => 1;
	} $self->fields_supported;

	grep { ! exists $ok{$_} } @_;
}



=head2 fields_io

get list of fields that were read 

=cut

sub fields_io { shift->src->fields_io; }





1;
__END__

=head1 SEE ALSO

Workout::Base, Workout::Store, Workout::Filter::*

=head1 AUTHOR

Rainer Clasen


=cut
