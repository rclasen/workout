#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Chunk - Workout Data Chunk

=head1 SYNOPSIS

  $mem = Workout::Store::Memory->new;
  $mem->chunk_add( Workout::Chunk->new( 
  	time	=> now,
	dur	=> 5,
  ));

=head1 DESCRIPTION

Container for data of a short period of time during a Workout.

=cut

package Workout::Chunk;

use 5.008008;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Carp;


our $VERSION = '0.01';

=pod

core data fields:

field	span	calc from	description

time	abs	p:time,dur	end date (sec. since epoch 1970-1-1)

ele 	geo	-		elevation at end of interval (m)

lon,lat	geo	-		GPS coordinates

dur	chunk	time,p:time	duration (sec)

dist	chunk	dur,spd		distance, abs (m)
		xdist,climb
		p:odo,odo

cad	chunkv	-		cadence, avg (1/min)
hr	chunkv	-		heartrate, avg (1/min)

work	chunk	pwr,dur		total, (Joule)
		angle,speed,..(guess)

temp	abs	-		temperature °C

=cut

our @core_fields = qw( 
	time
	dur
	ele
	lon
	lat
	dist
	cad
	hr
	work
	temp
);
__PACKAGE__->mk_accessors('prev', @core_fields);


=head2 new( { <args> } )

create new Athlete object

=cut

# copy this chunk
sub clone {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Chunk->new( { 
		%$self,
		%$a,
	});
}

sub core_fields {
	@core_fields;
}

# caluclate data for time between two chunks
sub _intersect {
	my( $self, $next, $a ) = @_;

	my $new = Workout::Chunk->new( $a );

	my $dur = $new->time - $self->time;
	my $ma = $dur / ($next->time - $self->time);

	if( defined($self->temp) && defined($next->temp) ){ 
		$new->{temp} = $self->temp + ($next->temp - $self->temp) * $ma;
	} else {
		$new->{temp} = $next->temp;
	}

	if( defined($self->ele) && defined($next->ele) ){ 
		$new->{ele} = $self->ele + ($next->ele - $self->ele) * $ma;
	} else {
		$new->{ele} = $next->ele;
	}

	if( defined($self->lon) && defined($self->lat) &&
		defined($next->lon) && defined($next->lat) ){

		$new->{lon} = $self->lon + ($next->lon - $self->lon) * $ma;
		$new->{lat} = $self->lat + ($next->lat - $self->lat) * $ma;
	}

	$new;
}

# generate chunk that follows the current and lasts at most to the next
sub synthesize {
	my( $self, $time, $next ) = @_;

	croak "invalid synthesize time ".$time." for ".$self->time
		unless $time > $self->time;
	croak "invalid synthesize time ".$time." before ".$next->time
		if $next && $time > $next->stime;
	my $dur = $time - $self->time;

	my %a = (
		time	=> $time,
		dur	=> $time - $self->time,
		prev	=> $self,
	);

	return Workout::Chunk->new( \%a )
		unless $next;

	$self->_intersect( $next, \%a );
}

# split current chunk at specified time
sub split {
	my( $self, $time ) = @_;

	my $remain = $self->time - $time;
	croak "invalid split time ". $time ." for ". $self->time
		if $remain < 0;

	return $self->clone # , undef
		if $remain < 0.1;

	my $dur = $self->dur - $remain;
	my $ma = $dur / $self->dur;
	my $p = $self->prev;

	my %aa = (
		prev	=> $p,
		'time'	=> $time,
		dur	=> $dur,
		dist	=> ($self->dist||0) * $ma,
		work	=> ($self->work||0) * $ma,
		cad	=> $self->cad,
		hr	=> $self->hr,
	);
	my $a = $p 
		? $p->_intersect( $self, \%aa )
		: Workout::Chunk->new( \%aa );

	my $mb = $remain / $self->dur;
	return $a, Workout::Chunk->new({ 
		prev	=> $a,
		'time'	=> $self->time,
		dur	=> $remain,
		dist	=> ($self->dist||0) * $mb,
		work	=> ($self->work||0) * $mb,
		temp	=> $self->temp,
		ele	=> $self->ele,
		lon	=> $self->lon,
		lat	=> $self->lat,
		cad	=> $self->cad,
		hr	=> $self->hr,
	});
}

our @fields_avg = qw( cad hr );

sub merge {
	my %a;

	return $_[0]->clone if @_ < 2;

	$a{prev} = $_[0]->prev;

	foreach my $c(@_){
		foreach my $f ( qw( dur work dist )){
			if( defined( my $v = $c->$f )){
				$a{$f} += $v;
			}
		}

		foreach my $f ( @fields_avg ){
			if( defined( my $v = $c->$f )){
				$a{$f} += $v * $c->dur;
			}
		}
	}
	$a{dur} or croak "merged chunk is too short";


	foreach my $f (qw( time temp ele lon lat )){
		if( defined( my $v = $_[-1]->$f )){
			$a{$f} = $v;
		}
	}

	foreach my $f ( @fields_avg ){
		if( defined($a{$f})){
			$a{$f} /= $a{dur};
		}
	}

	return Workout::Chunk->new( \%a );
}

=pod

calculated data fields:

field	span	calc from	description

climb	chunk	p:ele,ele	elevation change, abs (m)
incline	trip	p:incline,climb	cumulated positive climb, abs (m)

xdist	chunk	geo,p:geo	2dimensional distance, abs (m)
		dist,climb
odo	trip	p:odo,dist	cumulated distance, abs, (m)

grad	chunk	xdist,climb	gradient, avg (%)
angle	chunk	xdist,climb	angle, avg (RAD PI)

spd 	chunkv	dur,dist	speed, avg (m/sec)
accel	chunk	p:spd,spd	acceleration (m/sec²)

pwr 	chunkv	dur,work	power, avg (watt)

pbal		-		pedal balance (?,polar)
pidx		-		pedal index (?,polar)
apres		-		air pressure, avg (?,polar)


span:
- abs		momentary snapshot of value at chunks' end
- geo		momentary snapshot of geographic position at chunks' end
- chunk		delta during chunk
- chunkv	average of chunk's period
- trip		cumulated value for whole trip

abs+geo require two data sets

geo based fields
 time	-> dur
 lon	-
 lat	|
 ele	+> dist, xdist, odo, climb, incline, grad, spd

chunk based fields
 dur
 dist	-> spd
 climb	-> xdist, incline, grad
 pwr	-> work
 cad
 hr

=cut

# TODO: use vertmax=elef, elefuz=climb, accelmax,ravg=spd, spdmin=moving

sub isfirst {
	my $self = shift;
	return ! $self->prev;
}

sub stime {
	my $self = shift;
	$self->time - $self->dur;
}

sub gap {
	my $self = shift;
	my $p = shift || $self->prev or return;
	$self->stime - $p->time;
}

sub isblockfirst {
	my $self = shift;
	my $p = shift || $self->prev or return;
	abs($self->gap($p) ||0) > 0.1;
}

sub climb {
	my $self = shift;
	my $p = $self->prev or return;
	($self->ele||0) - ($p->ele||0);
}

sub vspd {
	my $self = shift;
	my $c = $self->climb or return;
	my $d = $self->dur or return;
	$c / $d;
}

	
sub xdist {
	my $self = shift;

	my $arg = ($self->dist||0)**2 - ($self->climb||0)**2; 
	return if $arg <= 0;

	sqrt( $arg )
}

sub grad {
	my $self = shift;
	my $xd = $self->xdist or return;
	100 * ($self->climb||0) / $xd;
}

sub angle {
	my $self = shift;
	my $xd = $self->xdist or return;
	atan2( ($self->climb||0), $xd );
}

sub spd {
	my $self = shift;
	my $d = $self->dur or return;
	($self->dist||0)/$d;
}

sub accel {
	my $self = shift;
	my $d = $self->dur or return;
	my $p = $self->prev or return;
	( ($self->spd||0) - ($p->spd||0) ) / $d;
}


sub pwr {
	my $self = shift;
	my $d = $self->dur or return;
	($self->work||0)/$d;
}

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
