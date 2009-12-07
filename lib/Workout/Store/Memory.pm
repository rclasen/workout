#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Memory - Migration helper

=head1 SYNOPSIS

  $src = Workout::Store::Memory->new;
  while( $chunk = $src->next ){
  	...
  }

=head1 DESCRIPTION

Workout::Store::Memory was merged into Workout::Store. This is an empty
class to help migration.

This is obsolete and will get removed. Don't use it.

=cut

package Workout::Store::Memory;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
