#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::Max - caculcate NP, IF, TSS based on your Max

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = Workout::Filter::Max->new( $src->iterate, { ftp => 320 } );
  Workout::Store::Null->new->from( $it );
  print $it->tss;

=head1 DESCRIPTION

Base Class for modifying and filtering the Chunks of a Workout.

=cut

package Workout::Filter::Max;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Resample';
use Workout::Filter::Join;
use Carp;
use DateTime;

our $VERSION = '0.01';

our %default = (
	dur	=> 1200,
	work	=> 0,
	time	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );

=head2 new( $iter, $arg )

create empty Iterator.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a||={};
	$iter = Workout::Filter::Join->new( $iter, $a );
	$class->SUPER::new( $iter, { 
		%default, 
		%$a, 
		recint		=> 1,
		chunks		=> [],
		sum		=> 0,
	});
}

sub pwr {
	my( $self ) = @_;

	my $d = $self->dur or return; # should be no-op
	defined(my $w = $self->work) or return;
	$w/$d;
}

sub stime {
	my( $self ) = @_;

	my $t = $self->time or return;
	$t - $self->dur;
}

sub process {
	my( $self ) = @_;

	my $c = $self->SUPER::process
		or return;

	unshift @{$self->{chunks}}, $c;
	$self->{sum} += ($c->work||0);

	if( @{$self->{chunks}} > $self->{dur} ){
		my $old = pop @{$self->{chunks}};
		$self->{sum} -= ($old->work||0);
	}

	if( $self->{sum} > $self->work ){
		$self->debug( "found new max work $self->{sum} at ".
			DateTime->from_epoch(
				epoch	=> $c->time,
				time_zone	=> 'local',
			)->hms );
		$self->work( $self->{sum} );
		$self->time( $c->time );
	}

	$c;
}


1;

