#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Gpx - read/write GPS tracks in XML format

=head1 SYNOPSIS

  use Workout::Store::Gpx;

  $src = Workout::Store::Gpx->read( "foo.gpx" );
  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.gpx" );

=head1 DESCRIPTION

Interface to read/write GPS files

=cut

package Workout::Store::Gpx;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store::Memory';
use Carp;
use Geo::Gpx;
use Geo::Distance;

our $VERSION = '0.01';

sub filetypes {
	return "gpx";
}

# TODO: Geo::Gpx doesn't support subsecond timestamps - only matters when
# using something else but garmin as source: Garmin doesn't provide
# subsecond time resolution, too.

# TODO: use $pt->{extensions} = {} to store hr, cad, work, temp

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new( {
		%$a,
		cap_block	=> 1,
		cap_note	=> 1,
	});
	$self;
}

sub do_read {
	my( $self, $fh ) = @_;

	my $gpx = Geo::Gpx->new( input => $fh )
		or croak "cannot read file: $!";

	my $tracks = $gpx->tracks
		or croak "no tracks found";
	@$tracks <= 1
		or croak "cannot deal with multiple tracks per file";
	$self->note( $tracks->[0]{cmt} );

	my $gcalc = Geo::Distance->new;
	my $lck;
	foreach my $seg ( @{$tracks->[0]{segments}} ){
		my $lpt;
		foreach my $pt ( @{$seg->{points}} ){
			next unless $pt->{time};

			my $dur = 0.015;
			my $dist = 0;

			if( $lpt ){
				$dur = $pt->{time} - $lpt->{time};
				$dist = $gcalc->distance( 'meter',
					$lpt->{lon}, $lpt->{lat},
					$pt->{lon}, $pt->{lat},
				);
			}

			if( $dur < 0.01 ){
				$self->debug( "skipping zero time-step: ".  $pt->{time} );
				next;
			}

			my $ck = Workout::Chunk->new({
				%$pt,
				prev	=> $lck,
				dur	=> $dur,
				dist	=> $dist,
			});
			$self->_chunk_add( $ck );

			$lck = $ck;
			$lpt = $pt;
		}
	}
}


sub chunk_check {
	my( $self, $c ) = @_;

	unless( $c->lon && $c->lat ){
		croak "missing lon/lat at ". $c->time;
	}
	$self->SUPER::chunk_check( $c );
}



sub do_write {
	my( $self, $fh ) = @_;

	$self->chunk_count
		or croak "no data";

	my @segs = ( {
		points	=> [],
	});

	my $it = $self->iterate;
	while( my $c = $it->next ){
	
		if( $c->isblockfirst 
			&& @{$segs[-1]{points}} ){

			push @segs, {
				points	=> [],
			};
		}

		push @{$segs[-1]{points}}, {
			lon	=> $c->lon,
			lat	=> $c->lat,
			ele	=> $c->ele,
			time	=> $c->time,
		};
	}

	my $gpx = Geo::Gpx->new;
	$gpx->tracks( [ {
		segments	=> \@segs,
		( $self->note ? (cmt => $self->note) : () ),
	} ] );

	print $fh $gpx->xml;
}

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
