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

  $chunk = Workout::Chunk->new( 
  	time	=> scalar time(),
	dur	=> 5,
	work	=> 100,
	# ... other core fields
  );
  print join(' ', $chunk->stime, $chunk->dur, $chunk->time, $chunk->pwr ),"\n";

  $mem = Workout::Store->new;
  $mem->chunk_add( $chunk );

=head1 DESCRIPTION

Container for a data tuple within a workout store.

=cut

package Workout::Chunk;

use 5.008008;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Carp;
use Math::Trig;

# TODO: use vertmax=elef, elefuz=climb, accelmax,ravg=spd, spdmin=moving

our $VERSION = '0.01';

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

our @fields_avg = qw( cad hr );

__PACKAGE__->mk_accessors('prev', @core_fields);

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates new chunk. Fills in data from \%arg.

=head2 $copy = $chunk->clone( [ \%overrides ] )

copy current chunk.

=cut

sub clone {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Chunk->new( { 
		%$self,
		%$a,
	});
}

=head1 CLASS METHODS

=head2 core_fields

returns list with all core fields.

=cut

sub core_fields {
	@core_fields;
}


=head1 CORE FIELDS

These are the fields with actual data. Other fields in this chunk are
calculated from these fields. The accessor methods allow set/get of the
values. You can pass these fields to the constructor for initialization.

=head2 time	I<abs>

Chunk end date in seconds (sec) since epoch 1970-1-1. Essential: Must be non-null in
each chunk.

=head2 dur	I<relative>

Duration / length of chunk in seconds (sec). Essential: Must be non-null in each
chunk.

=head2 ele	I<geo>

Elevation at end of interval in meter (m)

=head2 lon,lat	I<geo>

GPS coordinates degrees of arc WGS84 (°).

=head2 dist	I<relative>

travelled distance during chunk in meters (m).

=head2 cad	I<avg>

Average Cadence during chunk (1/min)

=head2 hr	I<avg>

Average Heartrate during chunk (1/mi)n

=head2 work	I<relative>

work done during this chunk (Joule)

=head2 temp	I<abs>

Temperature at end of chunk in degrees centigrade (°C)

=head2 prev

Not really a core field. Points to the previous chunk. This is necessary
for several of the following calculations.


=head1 FIELDS

calculated data fields with read-only accessors:

=head2 isfirst

returns true when there's no previous chunk.

=cut

sub isfirst {
	my $self = shift;
	return ! $self->prev;
}

=head2 isblockfirst

returns true when there's a gap between the previous and this chunk

=cut

sub isblockfirst {
	my $self = shift;
	my $p = shift || $self->prev or return;
	abs($self->gap($p) ||0) > 0.1;
}

=head2 stime	I<abs>

start time of chunk.

=cut

sub stime {
	my $self = shift;
	$self->time - $self->dur;
}

=head2 gap	I<relative)

gap between previous and this chunk in seconds (sec).

=cut

sub gap {
	my $self = shift;
	my $p = shift || $self->prev or return;
	$self->stime - $p->time;
}

=head2 climb	I<relative>

elevation change (+-) since last chunk in meters (m).

=cut

sub climb {
	my $self = shift;
	my $e = $self->ele;
	defined $e or return;
	my $p = $self->prev or return;
	my $pe = $p->ele;
	defined $pe or return;
	$e - $pe;
}

=head2 vspd	I<avg>

average vertical speed during this chunk in meters/second (m/sec)

=cut

sub vspd {
	my $self = shift;
	my $c = $self->climb or return;
	my $d = $self->dur or return;
	$c / $d;
}

	
=head2 xdist	I<relative>

surface distance (2-dimensional) since last chunk in meters (m)

=cut

sub xdist {
	my $self = shift;

	defined( my $c = $self->climb ) or return;
	defined( my $d = $self->dist ) or return;
	my $arg = $d**2 - $c**2; 
	return if $arg <= 0;

	sqrt( $arg )
}

=head2 grad	I<relative>

gradient of elevation change since last chunk in percent (%)

=cut

sub grad {
	my $self = shift;
	defined( my $c = $self->climb ) or return;
	my $xd = $self->xdist or return;
	100 * $c / $xd;
}

=head2 angle	I<relative>

slope of elevation chane since last chunk in radians (rad pi)

=cut

sub angle {
	my $self = shift;
	defined( my $c = $self->climb ) or return;
	my $xd = $self->xdist or return;
	atan2( $c, $xd );
}

=head2 spd 	I<avg>

average speed during this chunk in meters/second (m/sec)

=cut

sub spd {
	my $self = shift;
	my $d = $self->dur or return;
	defined( my $i = $self->dist ) or return;
	$i/$d;
}

=head2 accel	I<relative>

acceleration since last chunk in meters/second² (m/sec²)

=cut

sub accel {
	my $self = shift;
	my $d = $self->dur or return;
	defined( my $s = $self->spd ) or return;
	my $p = $self->prev or return;
	defined( my $ps = $p->spd ) or return;
	( $s - $ps ) / $d;
}


=head2 pwr 	I<avg>

average power during this chunk in watt (W)

=cut

sub pwr {
	my $self = shift;
	my $d = $self->dur or return; # should be no-op
	defined(my $w = $self->work) or return;
	$w/$d;
}

=head2 torque	I<avg>

average torque during this chunk in Newton * meter (Nm)

=cut

sub torque {
	my $self = shift;
	my $cad = $self->cad or return;
	defined(my $pwr = $self->pwr) or return;

	$pwr / (2 * pi * $cad ) * 60;
}

=head2 deconv	I<avg>

average deconvolution during this chunk in meters (m). Might help you
identifying the gear you've been using.

=cut

sub deconv { # deconvolution / entfaltung
	my $self = shift;
	my $cad = $self->cad or return;
	defined(my $spd = $self->spd) or return;

	$spd / $cad * 60;
}


=head1 METHODS

=cut

# caluclate data for time between two chunks
sub _intersect {
	my( $self, $next, $a ) = @_;

	my $new = Workout::Chunk->new( $a );

	my $dur = $new->time - $self->time;
	my $ma = $dur / ($next->time - $self->time);

	if( defined($self->temp) && defined($next->temp) ){ 
		$new->temp( $self->temp + ($next->temp - $self->temp) * $ma );
	} else {
		$new->temp( $next->temp );
	}

	if( defined($self->ele) && defined($next->ele) ){ 
		$new->ele( $self->ele + ($next->ele - $self->ele) * $ma );
	} else {
		$new->ele( $next->ele );
	}

	if( defined($self->lon) && defined($self->lat) &&
		defined($next->lon) && defined($next->lat) ){

		$new->lon( $self->lon + ($next->lon - $self->lon) * $ma );
		$new->lat( $self->lat + ($next->lat - $self->lat) * $ma );
	}

	$new;
}


=head2 synthesize( $time [, $next_chunk ] )

generates an all-zero chunk that follows the current and lasts at most to the next

=cut

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

=head2 split( $time )

split current chunk at specified time and return the resulting two new
chunks.

=cut

sub split {
	my( $self, $time ) = @_;

	my $remain = $self->time - $time;

	return $self->clone # , undef
		if abs($remain) < 0.1;

	croak "invalid split time ". $time ." for ". $self->time
		if $remain < 0;

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

=head2 merge( @other_chunks )

returns new chunk with summarized data from this and all @other_chunks.

=cut

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

1;
__END__

=head1 SEE ALSO

Workout::Store, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
