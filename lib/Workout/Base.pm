#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Base - Base Class for Workout framework

=head1 DESCRIPTION

Base class for functionality shared accross the Workout framework.

=cut

package Workout::Base;

use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Class::Accessor::Fast';

our $VERSION = '0.01';


=head1 CONSTRUCTOR

=head2 new( \%arg )

create empty class. 

Arguments:

=over 4

=item debug => 0|1

enables debug logging. Defaults to off.

=back

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	$class->SUPER::new({
		debug => 0,
		%$a,
	});
}

=head1 METHODS

=head2 debug( @msg )

logs debug message to STDERR when initialized with debug=>1

=cut

sub debug {
	my $self = shift;
	return unless $self->{debug};
	print STDERR @_, "\n";
}

1;
__END__

=head1 SEE ALSO

Class::Accessor, Workout::Store, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
