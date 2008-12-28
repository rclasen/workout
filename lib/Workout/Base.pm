#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

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

=cut
