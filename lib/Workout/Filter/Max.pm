#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::Max - find peak power periods

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = Workout::Filter::Max->new( $src, { dur => 300 } );
  $it->finish;

  print "max 5min power: ", $it->pwr
  	"(at ", $it->tme ,")\n";

=head1 DESCRIPTION

calculates the average power for the duration throughout the whole workout
and finds the span where it peaks. Chunks are resampled to the duration.

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

# TODO: npwr
# TODO: split rolling average into seperate module

our %default = (
	dur	=> 1200,
	work	=> 0,
	time	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

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

=head1 METHODS

=head2 dur

duration in seconds to calculate average power for.

=head2 time

end time of peak period.

=head2 stime

start time of peak period.

=cut

sub stime {
	my( $self ) = @_;

	my $t = $self->time or return;
	$t - $self->dur;
}

=head2 work

work of the peak period.

=head2 pwr

average power during the peak period.

=cut

sub pwr {
	my( $self ) = @_;

	my $d = $self->dur or return; # should be no-op
	defined(my $w = $self->work) or return;
	$w/$d;
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
__END__

=head1 SEE ALSO

Workout::Filter::Resample

=head1 AUTHOR

Rainer Clasen

=cut

