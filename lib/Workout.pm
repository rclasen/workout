#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout - Fabric for creating workout objects easily

=head1 SYNOPSIS

  # read SRM file with power, hr, cad, speed, but no elevation. Data has
  # small gaps from stops at traffic lights. 1-sec recording intervall.
  $srm = Workout::file_read( "input.srm" ); 

  # read GPX file with elevaton. "Auto"-recording -> variable recording
  # intervall. Data has gaps from bad signal reception.
  $gpx = Workout::file_read( "iele.gpx, { ftype => 'gpx' });

  # new empty store for Polar HRM file. Polar files have a fixed
  # recording. According to the spec 5sec is the minimum fixed recording
  # intervall.
  $hrm = Workout::file_new( { ftype => "hrm", recint => 5 });

  # join, resample and merge input files into the destination store:

  # close gaps
  $join = Workout::filter( 'Join', $srm );

  # aggregate/split chunks
  $res = Workout::filter( 'Resample', $join, { recint => 5 } ); 

  # add ele info
  $merge = Workout::filter( 'Merge', $ele, {
  	master	=> $res, 
	fields	=> [ 'ele' ],
  }); 

  # run the above filter pipelin to convert and copy data to 
  # the HRM store:
  $hrm->from( $merge );

  # write the resulting HRM data to file
  $hrm->write( "out.hrm" );

=head1 DESCRIPTION

The Workout framework offers a common api to access all kinds of sport
workout data. It focuses on data from bike computers, heart rate monitors
and GPS that collect data throughout your workout in frequent intervalls.
Admittedly it's a bit focused on cycling.

Each recorded data tuple is stored in a "Workout::Chunk" object.

All chunks of a workout are stored in a Workout::Store container. The
store also supports "Workout::Marker" to keep track of laps or intervals
in your workout.

Usually you retrieve chunks from a store using the store's own iterator.
This allows hiding the the store's internal details. 

These iterators are chainable (similar to a unix pipe) with further
filters (Workout::Filter). There are powerful filters for collecting some
infos, merging workouts and doing other processing.

=cut

# TODO: capabilities for auto plumb: blocking, variable recint, supported fields
# TODO: automatic plumbing of filters
# TODO: automagically pass $calc, $athlete, and other options to new instances

package Workout;

use 5.008008;
use strict;
use warnings;
use Carp;
use Module::Pluggable
	search_path     => 'Workout::Store',
	sub_name        => 'stores';

our $VERSION = '0.12';

our %ftype;

foreach my $store ( __PACKAGE__->stores ){
	eval "require $store";
	if( my $err = $@ ){
		croak $err;
	}
	next unless $store->can('filetypes');
	foreach my $ft ( $store->filetypes ){
		$ftype{$ft} = $store;
	}
}



=head1 FUNCTIONS

=head2 file_types()

return mapping of file-extension to Workout::Store class as detected on
startup.

=cut

sub file_types {
	return \%ftype;
}

sub file_type_class {
	my( $type ) = @_;

	exists $ftype{lc $type}
		or croak "unsupported filetype: $type";

	return $ftype{lc $type};
}



=head2 file_read( $fname, \%arg )

Instantiates a Workout::Store using it's read() constructor. The Store
class is guessed from the file extension unless specified manually. The
argument hash is passed to it's constructor.

=cut

sub file_read {
	my( $fname, $a ) = @_;

	my $class = &file_type_class( $a->{ftype} 
		|| ($fname =~ /\.([^.]+)$/ )[0]
		|| "" );
	$class->read( $fname, $a );	
}



=head2 file_new( \%arg )

Instantiates an empty Workout::Store of the specified type, The argument
hash is passed to it's constructor.

=cut

sub file_new {
	my( $a ) = @_;

	my $class = &file_type_class( $a->{ftype} 
		|| "" );
	$class->new( $a );	
}



=head2 filter( $type, \%arg )

create new Workout::Filter::$type filter object, passing the argument hash
to it's constructor.

=cut

sub filter {
	my $type = shift;
	eval "require Workout::Filter::$type";
	if( my $err = $@ ){
		croak $err;
	}
	"Workout::Filter::$type"->new( @_ );
}


1;
__END__

=head1 SEE ALSO

Workout::Store, Workout::Chunk, Workout::Marker, Workout::Iterator,
Workout::Filter::*, wkdump, wkinfo, wkconv, wkmerge

=head1 AUTHOR

Rainer Clasen

=cut
