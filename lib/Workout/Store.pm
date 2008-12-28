#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store - Base Class for Sport Workout data Stores

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  # read Gpx file for elevation
  $ele = Workout::Store::Gpx->read( "iele.gpx );

  # join, resample and merge input files into a memory copy
  $join = Workout::Filter::Join->new( $src );
  # aggregate/split chunks
  $res = Workout::Filter::Resample->new( $join, { recint => 5 } ); 
  # add ele info
  $merge = Workout::Filter::Merge->new( $ele, {
  	master	=> $res, 
	fields	=> [ 'ele' ],
  }); 
  # tmp copy for demonstration purpose
  $mem = Workout::Store::Memory->new;
  $mem->from( $merge );

  # write to file, resample to new interval
  $conv = Workout::Filter::Resample->new( $mem, { recint => 5 } );
  # write to HRM file (one block) and different recint
  $dst = Workout::Store::HRM->new( { recint => 5 } );
  $dst->from( $conv );
  $dst->write( "out.hrm" );


=head1 DESCRIPTION

Base Class Container for Sport Workout recordings taken from Heart rate
monitors, Power meters, GPS receivers and so on.

=cut

# TODO: move documentation to Workout;

package Workout::Store;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Carp;

our $VERSION = '0.01';

sub filetypes {
	my( $class ) = @_;
	return;
}

__PACKAGE__->mk_accessors(qw(
	cap_block
	fields
	recint
	temperature
	note
));

sub do_read { croak "reading is not suported"; };

sub read {
	my( $class, $fname, $a ) = @_;
	my $self = $class->new( $a );

	my $fh;
	if( ref $fname ){
		$fh = $fname;
	} else {
		open( $fh, '<', $fname )
			or croak "open '$fname': $!";
	}

	$self->do_read( $fh );

	close($fh);
	$self;
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

	while( defined( my $chunk = $iter->next )){
		$self->chunk_add( $chunk );
	}
}

=head2 iterate

return iterator to retrieve all chunks.

=cut

sub iterate { croak "not implemented"; }; 



# TODO: marker / lap data

sub chunk_last { croak "not implemented"; };

sub time_start { croak "not implemented"; };
sub time_end { croak "not implemented"; };

sub dur {
	my $self = shift;
	$self->time_end - $self->time_start;
}


=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $i ) = @_;

	$self->_chunk_add( $i->clone({
		prev	=> $self->chunk_last,
	}));
}

sub _chunk_add {
	my( $self, $chunk ) = @_;

	croak "not implemented";
	#$self->chunk_check( $chunk, 1 );
}

=head2 chunk_check( $chunk, $inblock )

check chunk data validity. For use in chunk_add().

=cut

sub chunk_check {
	my( $self, $c ) = @_;

	$c->dur
		or croak "missing duration";
	$c->time
		or croak "missing time";

	if( $self->recint && abs($self->recint - $c->dur) > 0.1 ){
		croak "duration doesn't match recint";
	}

	my $l = $self->chunk_last
		or return;

	if( $c->stime - $l->time < -0.1 ){
		croak "nonlinear time step: l=".  $l->time 
			." c=". $c->time
			." d=". $c->dur;
	}
}

sub do_write { croak "writing is not suported"; };

sub write {
	my( $self, $fname, $a ) = @_;

	my $fh;
	if( ref $fname ){
		$fh = $fname;
	} else {
		open( $fh, '>', $fname )
			or croak "open '$fname': $!";
	}

	$self->do_write( $fh );

	close($fh)
		or return;

	1;
}


1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
