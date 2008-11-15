package Workout::Filter::Merge;

=head1 NAME

Workout::Filter::Merge - Merge Workout data

=head1 SYNOPSIS

  $src_from = Workout::Store::Gpx->read( "foo.gpx" );
  $src_to = Workout::Store::SRM->read( "foo.srm" );
  $merged = Workoute::Filter::Merge( $src_from, $src_to, {
  	master	=> $src_to,
  	fields	=> [ "ele" ],
  });
  while( $chunk = $merged->next ){
  	# do something
  }

=head1 DESCRIPTION

merge data from different Workout Stores into one stream. You may specify
whch fields to pick from the second, ... Store.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Resample';
use Carp;

our $VERSION = '0.01';

__PACKAGE__->mk_ro_accessors(qw(
	master
	fields
));

sub _fetch_master {
	my( $self ) = @_;

	my $r = $self->master->next 
		or return;

	$self->{cntin}++;
	$r;
}

sub process {
	my( $self ) = shift;

	# get master
	my $m = $self->_fetch_master
		or return;

	my $o = $m->clone({
		prev	=> $self->last,
	});

	#$self->debug( "merging chunk ". $m->stime ." to ". $m->time );
	my $s = $self->_fetch_time( $m->dur, $m->time )
		or return $o;

	foreach my $f (@{$self->fields}){
		$o->$f( $s->$f );
	}

	$o;
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
