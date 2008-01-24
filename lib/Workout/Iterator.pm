=head1 NAME

Workout::Iterator - Base Class to iterate through Workout Stores

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

package Workout::Iterator;

use 5.008008;
use strict;
use warnings;
use Carp;
use Workout::Calc;

our $VERSION = '0.01';


=head2 new( $src, $arg )

create empty Iterator.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	my $self = bless {
		src	=> $src,
		calc	=> $a->{calc},
	}, $class;

	return $self;
}

=head3 calc

returns the Workout::Calc object in use

=cut

sub calc {
	my( $self ) = @_;

	$self->{calc} ||= Workout::Calc->new;
}

=head2 next

return next chunk

=cut

sub next {
	croak "not implemented";
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

=head2 src

return src that's iterated

=cut

sub src {
	my( $self ) = @_;

	$self->{src};
}

=head2 store

return store that's iterated

=cut

sub store {
	my( $self ) = @_;

	$self->{src}->store;
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
