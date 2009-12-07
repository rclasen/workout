#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

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

sub new {
	my( $class, $iter, $a ) = @_;

	$a ||= {};

	my $master = $a->{master};
	$master->isa( 'Workout::Iterator' )
		or $master = $master->iterate( $a );

	$class->SUPER::new( $iter, {
		%$a,
		master	=> $master,
	});
}

sub stores {
	my( $self ) = @_;
	( $self->SUPER::stores, $self->master->stores );
}

sub fields_supported {
	my $self = shift;

	my %sup = map { $_ => 1 }
		$self->SUPER::fields_supported(  @{$self->{fields}} ),
		$self->master->fields_supported( @_ );
	
	keys %sup;
}

sub fields_io {
	my $self = shift;

	( $self->master->fields_io, @{$self->{fields}} );
}

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
	my $s = $self->_fetch_time( $o->dur, $o->time )
		or return $o;

	foreach my $f (@{$self->fields}){
		$o->$f( $s->$f );
	}
	#$self->debug( "merged chunk ". $o->time .", ".  $o->spd );

	$o;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base 

=head1 AUTHOR

Rainer Clasen

=cut
