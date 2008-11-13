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

=cut

our @core_fields = qw( 
	prev
	time
	dur
	ele
	lon
	lat
	dist
	cad
	hr
	work
);
__PACKAGE__->mk_accessors(@core_fields);


=head2 new( { <args> } )

create new Athlete object

=cut

sub clone {
	my( $self ) = @_;
	Workout::Chunk->new( { map {
		$_ => $self->$_;
	} @core_fields } );
}

sub split {
	my( $self, $at ) = @_;

	if( $at > $self->dur ){
		return;

	} elsif( $self->dur - $at < 0.1 ){
		return $self->clone; # , undef;

	} # else ...

	my $remain = $self->dur - $at;
	my $ma = $at / $self->dur;
	my $mb = $remain / $self->dur;

	my $a = {
		prev	=> $self->prev,
		'time'	=> $self->time - $remain,
		dur	=> $at,
		dist	=> ($self->dist||0) * $ma,
		work	=> ($self->work||0) * $ma,
		cad	=> $self->cad,
		hr	=> $self->hr,
	};

	my $p = $self->prev;

	# TODO: allow reuse of lon,lat,ele calc in Filter::Join
	# TODO: test ele, lon, lat
	if( $p && defined($p->ele) && defined($self->ele) ){ 
		$a->{ele} = $p->ele + ($self->ele - $p->ele) * $ma;
	} else {
		$a->{ele} = $self->ele;
	}
	if( $p && defined($p->lon) && defined($p->lat) &&
		defined($self->lon) && defined($self->lat) ){

		$a->{lon} = $p->lon + ($self->lon - $p->lon) * $ma;
		$a->{lat} = $p->lat + ($self->lat - $p->lat) * $ma;
	}

	my $aa = Workout::Chunk->new( $a );
	return $aa, Workout::Chunk->new({ 
		prev	=> $aa,
		'time'	=> $self->time,
		dur	=> $remain,
		dist	=> ($self->dist||0) * $mb,
		work	=> ($self->work||0) * $mb,
		ele	=> $self->ele,
		lon	=> $self->lon,
		lat	=> $self->lat,
		cad	=> $self->cad,
		hr	=> $self->hr,
	});

}

sub merge {
	my( $a, $b ) = @_;

	my $ndur = $a->dur + $b->dur;
	return Workout::Chunk->new({
		prev	=> $a->prev,
		cad	=> (($a->cad||0) * ($a->dur||0) 
			+ ($b->cad||0) * ($b->dur||0)) / $ndur,
		hr	=> (($a->hr||0)  * ($a->dur||0) 
			+ ($b->hr||0)  * ($b->dur||0)) / $ndur,
		ele	=> $b->ele,
		lon	=> $b->lon,
		lat	=> $b->lat,
		work	=> ($a->work||0) + ($b->work||0),
		dist	=> ($a->dist||0) + ($b->dist||0),
		dur	=> $ndur,
		'time'	=> $b->time,
	});
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
# TODO: calc vspd

sub climb {
	my $self = shift;
	my $p = $self->prev or return;
	($self->ele||0) - ($p->ele||0);
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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
