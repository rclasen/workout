package Workout::Store::File;

=head1 NAME

Workout::Store::File - Base Class to read/write Workout files

=head1 SYNOPSIS

  $src = Workout::Store::HRM->new( "foo.hrm" );
  while( $chunk = $src->next ){
  	...
  }


  $dst = Workout::Store::SRM->new( "foo.srm", { write => 1 } );
  $dst->chunk_add( $chunk );
  $dst->flush;

=head1 DESCRIPTION

Base class to add basic file handling for use in specific Store Classes:

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

=head2 fh

return an opened filehandle for the specified file and access

=cut

sub fh {
	my( $self ) = @_;
	
	return $self->{fh} if $self->{fh};
	return $self->{fh} = $self->{fname} if ref $self->{fname};

	open( my $fh, ($self->{write} ? ">" : ""). $self->{fname} )
		or croak "cannot open ". $self->{fname};
	$self->{fh} = $fh;
}

=head2

ensure data is written to disk, close filehandle.

=cut

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
