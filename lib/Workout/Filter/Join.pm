package Workout::Filter::Join;

=head1 NAME

Workout::Filter::Join - Join blocks within Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );
  $join = Workout::Filter::Join->new( $src );
  while( my $chunk = $join->next ){
  	# do something
  }

=head1 DESCRIPTION

Iterator that automagically fills the gaps between individual data blocks
with fake chunks.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

our %default = (
	recint	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );

=head2 new( $src, $arg )

new Iterator

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( $src, {
		%default,
		%$a,
	});
	$self->{stime} = undef;
	$self;
}

=head2 next

get next data chunk

=cut

sub process {
	my( $self ) = @_;

	my $i = $self->_fetch
		or return;

	$self->{stime} ||= $i->stime;

	my $last = $self->last;

	if( $last && $i->isblockfirst( $last ) ){
		$self->_push( $i );

		if( $self->recint && $i->gap( $last) > $self->recint ){
			my $elapsed = $last->time - $self->{stime};
			my $time = $self->{stime} + $self->recint 
				* (1+int($elapsed/$self->recint));

			$self->debug( "insert join from ". $last->time ." to ". $time );
			return $last->synthesize( $time, $i );
		}

		$self->debug( "insert join from ". $last->time ." to ".  $i->stime );
		return $last->synthesize( $i->stime, $i );

	}

	return $i->clone({
		prev	=> $last,
	});
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
