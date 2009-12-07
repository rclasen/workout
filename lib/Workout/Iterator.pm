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
	src	=> undef,
	cntin	=> 0,
	cntout	=> 0,
	last	=> undef,
);

__PACKAGE__->mk_ro_accessors( keys %init );

=head2 new( $src, \%arg )

create empty Iterator.

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

=head2 src

return the source of which this iterator pulls it's values. This is either
another iterator oder a store.

=cut


=head2 stores

return list of stores where this iterator (-chain) is pulling chunks of.

=cut

sub stores { $_[0]->src->stores };



=head2 next

return next chunk

=cut

sub process { croak "not implemented"; };

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

=head2 cntin

number of chunks passed into this iterator

=cut

=head2 cntout

number of chunks passed out of this iterator

=cut


=head2 fields_supported( [ <field> .. ] )

return list of fields supported by this Store.

=cut

sub fields_supported { shift->src->fields_supported( @_ ); }



=head2 fields_unsupported( <field> ... )

returns list of fields unsupported by this store.

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

Workout::Store

=head1 AUTHOR

Rainer Clasen


=cut
