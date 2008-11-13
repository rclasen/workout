=head1 NAME

Workout::Base - Base Class for Workout framework

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = $src->iterate;
  while( defined(my $c = $it->next)){
  	print join(",",$c->time, $c->dur, $c->pwr),"\n";
  }

=head1 DESCRIPTION

Base Class to iterate through Workout Stores.

=cut

package Workout::Base;

use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Class::Accessor::Fast';

our $VERSION = '0.01';

=head2 new( $arg )

create empty class.

=cut

sub new {
	my( $class, $a ) = @_;

	my $self = $class->SUPER::new( $a );
	$self->{debug} = $a->{debug} || 0,

	return $self;
}

=head2 debug

log debug message when initialized with debug=>1

=cut

sub debug {
	my $self = shift;
	return unless $self->{debug};
	print STDERR @_, "\n";
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