=head1 NAME

Workout::Store - Base Class for Sport Workout data Stores

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->new( "input.srm" ); 
  # read Gpx file for elevation
  $ele = Workout::Store::Gpx->new( "iele.gpx );

  # join, resample and merge input files into a memory copy
  $join = Workout::Filter::Join->new( $src );
  # aggregate/split chunks
  $res = Workout::Filter::Resample->new( $join, { recint => 5 } ); 
  # add ele info
  $merge = Workout::Filter::Merge->new( $res, $ele ); 
  # tmp copy for demonstration purpose
  $mem = Workout::Store::Memory->new;
  $mem->from( $merge );

  # write to file, calculating missing fields where necessary
  $conv = Workout::Filter::CalcMissing->new( $mem );
  # write to HRM file (one block) and different recint
  $dst = Workout::Store::HRM->new( "out.hrm", { write => 1, recint => 5 } );
  $dst->from( $conv );
  $dst->flush;


=head1 DESCRIPTION

Base Class Container for Sport Workout recordings taken from Heart rate
monitors, Power meters GPS receivers and so on.

=cut

package Workout::Store;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Carp;

our $VERSION = '0.01';

# TODO: move field definition to Workout::Chunk

=pod

sampling interval data fields:

field	span	calc from	description

dur	chunk	time,p:time	duration (sec)
time	abs	p:time,dur	end date (sec. since epoch 1970-1-1)

hr	chunkv	-		heartrate, avg (1/min)
cad	chunkv	-		cadence, avg (1/min)

ele 	geo	-		elevation at end of interval (m)
climb	chunk	p:ele,ele	elevation change, abs (m)
incline	trip	p:incline,climb	cumulated positive climb, abs (m)

lon,lat	geo	-		GPS coordinates
xdist	chunk	geo,p:geo	2dimensional distance, abs (m)
		dist,climb
dist	chunk	dur,spd		distance, abs (m)
		xdist,climb
		p:odo,odo
odo	trip	p:odo,dist	cumulated distance, abs, (m)

grad	chunk	xdist,climb	gradient, avg (%)

spd 	chunkv	dur,dist	speed, avg (m/sec)

work	chunk	pwr,dur		total, (Joule)
		angle,speed,..(guess)
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


=cut

our %fspan;
our %fields = (
	time	=> 'abs',
	dur	=> 'chunk',
	hr	=> 'chunkv',
	cad	=> 'chunkv',
	ele 	=> 'geo',
	climb	=> 'chunk',
	lon	=> 'geo',
	lat	=> 'geo',
	xdist	=> 'chunk',
	dist	=> 'chunk',
	grad	=> 'chunk',
	spd 	=> 'chunkv',
	work	=> 'chunk',
	pwr 	=> 'chunkv',
);

while( my($f, $span) = each %fields ){
	push @{$fspan{$span}}, $f;
}


sub filetypes {
	my( $class ) = @_;
	return;
}

=head2 new( $arg )

create empty Workout.

=cut

sub new {
	my( $class, $a ) = @_;

	my $self = $class->SUPER::new( $a );

	$self->{fields} = \%fields;
	$self->{fspan} = \%fspan;
	$self->{fsupported} = [qw( time dur )];
	$self->{frequired} = [qw( time dur )];

	$self->{recint} = $a->{recint} ||0;

	# athlete data
	$self->{maxhr} = $a->{maxhr} ||225; # max heartrate
	$self->{resthr} = $a->{resthr} ||30; # rest "
	$self->{vo2max} = $a->{vo2max} ||50;
	$self->{weight} = $a->{weight} ||80;

	# workout data
	$self->{note} = $a->{note} ||"";
	$self->{temp} = $a->{temp} ||20; # temperature
	return $self;
}

=head2 from( $iter )

copy workout data from specified source (other Workout::Store or
Workout::Iterator).

=cut

sub from { # TODO: make this a constructor
	my( $self, $iter ) = @_;

	# TODO: copy marker/laps/athlete/workout-/trip data

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	my $last;
	while( defined( my $chunk = $iter->next )){
		if( $last && $chunk->{time} - $chunk->{dur} - $last->{time} > 0.01 ){
			$self->block_add;
		}
		$self->chunk_add( $chunk );
		$last = $chunk;
	}
}

=head2 iterate

return iterator to retrieve all chunks.

=cut

sub iterate { croak "not implemented"; }; 


=head2 fields

returns a list with all fieldnames

=cut

sub fields {
	my( $self ) = @_;
	keys %{$self->{fields}};
}

=head2 fields_supported

returns a list of field names that are required for each data chunk.

=cut

sub fields_supported {
	my( $self ) = @_;

	@{$self->{fsupported}};
}

=head2 fields_required

returns a list of field names that are required for each data chunk.

=cut

sub fields_required {
	my( $self ) = @_;

	@{$self->{frequired}};
}

=head2 fields_span( @span )

returns a list of field names for the specified span

=cut

sub fields_span {
	my( $self, @span ) = @_;

	my @fields;
	foreach my $sp ( @span ){
		next unless exists $self->{fspan}{$sp};
		push @fields, @{$self->{fspan}{$sp}};
	}
	@fields;
}

=head2 recint

returns the recording interval in seconds.

=cut

sub recint {
	my( $self ) = @_;
	return $self->{recint};
}


=head2 note

return comment string for this workout

=cut

sub note {
	my( $self ) = @_;
	return $self->{note};
}


=head2 temperature

return comment string for this workout

=cut

sub temperature {
	my( $self ) = @_;
	return $self->{temp};
}


# TODO accessors for athlete data

# TODO: marker / lap data


=head2 block_add

open new data block.

=cut

sub block_add {
	my( $self ) = @_;
	croak "not implemented";
}


=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $chunk ) = @_;

	croak "not implemented";
}

=head2 chunk_check( $chunk )

check chunk data validity. For use in chunk_add().

=cut

sub chunk_check {
	my( $self, $c, $l  ) = @_;

	$c->{dur}
		or croak "missing duration";
	$c->{time}
		or croak "missing time";

	if( $self->recint && abs($self->recint - $c->{dur}) > 0.1 ){
		croak "duration doesn't match recint";
	}

	my $ltime = $c->{time} - $c->{dur};
	if( $l && ( $l->{time} > $ltime )){
		croak "no/negativ time step";
	}
	if( $l && abs($ltime - $l->{time}) > 0.1){
		croak "found time gap since last chunk";
	}

	foreach my $f ( $self->fields_required ){
		defined $c->{$f}
			or croak "missing field '$f'";
	}
}

1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
