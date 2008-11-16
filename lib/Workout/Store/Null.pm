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

=head2 block_add

open new data block.

=cut

sub block_add { }

=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add { }

sub _chunk_add { }


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
