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

=head2 new( $src, $arg )

new iterator

=cut

sub new {
	my $class = shift;
	my $self = $class->SUPER::new( @_ );
	$self->{queued} = undef;
	$self;
}

=head2 next

get next data chunk

=cut

sub process {
	my( $self ) = @_;

	if( my $r = $self->{queued} ){
		$self->{queued} = undef;
		return $r;
	}

	my $i = $self->_fetch
		or return;

	my $o = $i->clone;
	my $last = $self->last;

	if( $last && $i->isfirst ){
		my $ltime = $i->time - $i->dur;
		my $dur = $ltime - $last->time;
		$self->debug( "inserting ". $dur ."sec at ". $ltime);

		$self->{queued} = $o;

		my $ma = $dur / ( $dur + $o->dur);
		# TODO: move ele,lon,lat calc to ::Chunk
		my %a = (
			time    => $ltime,
			dur     => $dur,
			ele => ($last->ele||0) + ($o->ele||0) * $ma,
			lon => ($last->lon||0) + (($o->lon||0) - ($last->lon||0)) * $ma,
			lat => ($last->lat||0) + (($o->lat||0) - ($last->lat||0)) * $ma,
		);

		$o = Workout::Chunk->new( \%a );
	}

	return $o;
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
