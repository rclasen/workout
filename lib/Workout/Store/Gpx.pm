#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

use 5.008008;
use warnings;
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

package Workout::Store::Gpx::Iterator;
use strict;
use base 'Workout::Iterator';
use Geo::Distance;
use Carp;

sub new {
	my( $class, $store, $a ) = @_;

	my $self = $class->SUPER::new( $store, $a );
	$self->{track} = $store->track;
	$self->{cseg} = 0;
	$self->{cpt} = 0;
	$self;
}

sub _geocalc {
	my( $self ) = @_;
	$self->{geocalc} ||= new Geo::Distance;
}

=head2 next

=cut

sub process {
	my( $self ) = @_;
	
	return unless $self->{track};

	my $segs = $self->{track}{segments};
	while( $self->{cseg} < @$segs ){
		my $seg = $segs->[$self->{cseg}];

		# next segment?
		if( defined $seg->{points} 
			&& @{$seg->{points}} <= $self->{cpt} ){

			$self->debug( "next segment" );
			$self->{cseg}++;
			$self->{cpt} = 0;
			next;
		}

		# next point!
		my $ck = Workout::Chunk->new( {
			%{$seg->{points}[$self->{cpt}++]},
			prev	=> $self->last,
		});
		$self->{cntin}++;

		# TODO: keep distance of time-less points? croak?
		next unless $ck->time;

		# remember first chunk for calculations
		my $last = $self->last;
		unless( $last ){
			$self->{last} = $ck;
			next;
		}

		$ck->dur( $ck->time - $last->time );
		$ck->dist( $self->_geocalc->distance( 'meter', 
			$last->lon, $last->lat,
			$ck->lon, $ck->lat 
		));

		return $ck;

	}
	return;
}



package Workout::Store::Gpx;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use Geo::Gpx;

our $VERSION = '0.01';

sub filetypes {
	return "gpx";
}

__PACKAGE__->mk_ro_accessors(qw( track gpx ));

# TODO: Geo::Gpx doesn't support subsecond timestamps
# TODO: use Store::Memory as base class

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new( {
		%$a,
		chunk_last	=> undef,	# last added chunk
		gpx	=> Geo::Gpx->new,
		track	=> {
			segments	=> [{
				points	=> [],
			}],
		},
		cap_block	=> 1,
		cap_note	=> 0,
	});
	$self->gpx->tracks( [ $self->track ] );

	$self;
}

sub do_read {
	my( $self, $fh ) = @_;

	$self->{gpx} = Geo::Gpx->new( input => $fh )
		or croak "cannot read file: $!";

	@{$self->{gpx}->tracks} <= 1
		or croak "cannot deal with multiple tracks per file";
	$self->{track} = $self->gpx->tracks->[0];
}


=head2 iterate

=cut

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::Gpx::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}

sub chunk_check {
	my( $self, $c ) = @_;

	unless( $c->lon && $c->lat ){
		croak "missing lon/lat at ". $c->time;
	}
	$self->SUPER::chunk_check( $c );
}

sub time_start { 
	my $p =$_[0]->track->{segments}[0]{points}[0]
		or return;
	$p->{time};
}

sub time_end { 
	my $p = $_[0]->track->{segments}[-1]{points}[-1]
		or return;
	$p->{time};
}

sub chunk_last { $_[0]{chunk_last}; }

sub _chunk_add {
	my( $self, $c ) = @_;

	$self->chunk_check( $c );

	if( $c->isblockfirst 
		&& @{$self->track->{segments}[-1]{points}} ){

		push @{$self->track->{segments}}, {
			points	=> [],
		}
	}

	push @{$self->track->{segments}[-1]{points}}, {
		lon	=> $c->lon,
		lat	=> $c->lat,
		ele	=> $c->ele,
		time	=> $c->time,
	};
}

sub do_write {
	my( $self, $fh ) = @_;

	@{$self->{track}{segments}} 
		or croak "no data";

	print $fh $self->gpx->xml;
}

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
