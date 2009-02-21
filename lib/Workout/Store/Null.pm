#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Null - Null storage for Workout data

=head1 SYNOPSIS

  $src = Workout::Store::Null->new;
  while( $chunk = $src->next ){
  	...
  }

=head1 DESCRIPTION

Interface to store Workout data in memory

=cut

package Workout::Store::Null::Iterator;
use strict;
use warnings;
use Carp;
use base 'Workout::Iterator';

sub process { }


package Workout::Store::Null;
use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Workout::Store';

our $VERSION = '0.01';

=head2 new( $arg )

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||={};
	$class->SUPER::new({
		%$a,
		cap_block	=> 1,
		cap_note	=> 1,
	});
}

sub iterate {
	my( $self ) = @_;
	Workout::Store::Null::Iterator->new( $self );
}

sub from { 
	my( $self, $iter ) = @_;

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	while( defined( $iter->next )){1};
}

=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add { }

sub _chunk_add { }

sub _mark_add {}

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
