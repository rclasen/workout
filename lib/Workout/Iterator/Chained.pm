=head1 NAME

Workout::Iterator::Chained - Base Class to iterate through Workout Stores

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->new( "input.srm" ); 
  $it = $src->iterate;
  while( defined(my $chunk = $it->next)){
  	print join(",",@$chunk{qw(time dur pwr)}),"\n";
  }

=head1 DESCRIPTION

Base Class to iterate through Workout Stores.

=cut

package Workout::Iterator::Chained;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Iterator';
use Carp;
use Workout::Calc;

our $VERSION = '0.01';


=head2 new( $iter, $arg )

create empty Iterator.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	my $self = $class->SUPER::new( $iter->store, $a );
	$self->{src} = $iter;

	return $self;
}

=head2 src

return the source of which this iterator pulls it's values. This is either
another iterator oder a store.

=cut

sub src {
	my( $self ) = @_;

	$self->{src};
}


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

