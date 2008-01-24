package Workout::Store::File;

=head1 NAME

Workout::Store::File - Base Class to read/write Workout files

=head1 SYNOPSIS

  use Workout::Store::HRM;
  blah blah blah # TODO

=head1 DESCRIPTION

Stub documentation for Workout::Store::File, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use DateTime;

our $VERSION = '0.01';

=head2 new( $fname, $args )

Consructor

=cut

sub new {
	my( $class, $fname, $a ) = @_;

	my $self = $class->SUPER::new( $a );
	$self->{fname} = $fname;
	$self->{write} = $a->{write} ? 1 : 0;
	$self->{fh} = undef;
	$self;

}

sub fh {
	my( $self ) = @_;
	
	return $self->{fh} if $self->{fh};
	return $self->{fh} = $self->{fname} if ref $self->{fname};

	open( my $fh, ($self->{write} ? ">" : ""). $self->{fname} )
		or croak "cannot open ". $self->{fname};
	$self->{fh} = $fh;
}

sub flush {
	my( $self ) = @_;
	return if ref $self->{fname};
	close( $self->{fh} ) if $self->{fh};
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
