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
workout data that's recorded in frequent intervalls througout the whole
workout. It's written with heart rate monitors, bike computers and GPS in
mind. Admittedly it's a bit focused on cycling.

Each recorded data tuple is stored in a "Workout::Chunk" object.

All chunks of a workout are stored in a Workout::Store container. The
store also supports "Workout::Marker" to keep track of laps or intervals
in your workout. For now there's a bunch of stores to read and write
several files (srm, hrm, gpx, ...). Writing stores to integrate other file
types or direct device download should be quite easy.

Usually you retrieve chunks from a store using the store's own iterator.
This allows hiding the the store's internal details. 

These iterators are chainable (similar to a unix pipe) with further
filters (Workout::Filter). There are powerful filters for collecting some
infos, merging workouts and doing other processing.

=cut

# TODO: capabilities for auto plumb: blocking, variable recint, supported fields
# TODO: automatic plumbing of filters
# TODO: automagically pass $calc, $athlete, and other options to new instances
# TODO: find way to construct more complex pipelines more easily

package Workout;

use 5.008008;
use strict;
use warnings;
use Carp;
use Module::Pluggable
	search_path     => 'Workout::Store',
	sub_name        => 'stores';

our $VERSION = '0.14';

our %file_types;

foreach my $store ( __PACKAGE__->stores ){
	# ignore broken stores:
	eval "require $store"
		or next;

	next unless $store->isa('Workout::Store');
	next unless $store->can('filetypes');

	my @ftypes = $store->filetypes;
	push @{$file_types{''}}, $store if @ftypes;

	foreach my $ft ( @ftypes ){
		push @{$file_types{lc $ft}}, $store;
	}
}



=head1 FUNCTIONS

=head2 file_types

return mapping of file-extension to Workout::Store class as detected on
startup.

=cut

sub file_types {
	return \%file_types;
}

=head2 file_type_name( $file_name )

returns file type based on file extension

=cut

sub file_type_name {
	my( $fname ) = @_;

	$fname =~ /\.([^.]+)$/
		or return;

	return $1 if exists $file_types{lc $1};

	return;
}


=head2 file_read( $source, \%arg )

Instantiates a Workout::Store using it's read() constructor. The Store
class is guessed from the file extension unless specified manually. The
argument hash is passed to it's constructor.

=cut

sub file_read {
	my( $source, $a ) = @_;

	my $ftype = '';
	if( defined $a->{ftype} ){
		$ftype = $a->{ftype};

	} elsif( ! ref $source && $source =~ /\.([^.]+)$/ ){
		$ftype = $1 if exists $file_types{lc $1};

	}

	exists $file_types{lc $ftype}
		or croak "no such filetype: $ftype";

	my $classes = $file_types{lc $ftype};

	# exact filetype match found:
	if( @$classes == 1 ){
		my $class = $classes->[0];
		$a->{debug} && print STDERR "reading with store ", $class,"\n";
		return $class->read( $source, $a );
	}

	# multiple matches found, start guessing:
	ref $source
		and croak "filetype detection requires a filename";

	foreach my $class ( @$classes ){
		$a->{debug} && print STDERR "attempting read with store ", $class,"\n";

		my $store = eval {
			$class->read( $source, $a );
		};
		if( my $err = $@ ){
			$a->{debug} && print STDERR "store failed: ", $err;

		} else {
			return $store;
		}

	}

	croak "unsupported filetype";
	return;
}



=head2 file_new( \%arg )

Instantiates an empty Workout::Store of the specified type, The argument
hash is passed to it's constructor.

=cut

sub file_new {
	my( $a ) = @_;

	my $ftype = 'wkt';
	if( defined $a->{ftype} ){
		$ftype = $a->{ftype};
	}

	exists $file_types{lc $ftype}
		or croak "no such filetype: $ftype";

	my $classes = $file_types{lc $ftype};

	my $class = $classes->[0];
	$a->{debug} && print STDERR "new store: ", $class,"\n";

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
