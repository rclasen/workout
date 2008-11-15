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
  $merge = Workout::Filter::Merge->new( $res, $ele, [ 'ele' ] ); 
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
	fields
	recint
	temperature
	note
));

sub do_read { croak "not suported"; };

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

	my $last;
	while( defined( my $chunk = $iter->next )){
		if( $chunk->isblockfirst ){
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

	$c->dur
		or croak "missing duration";
	$c->time
		or croak "missing time";

	if( $self->recint && abs($self->recint - $c->dur) > 0.1 ){
		croak "duration doesn't match recint";
	}

	return unless $l;

	if( $l->time > $c->stime ){
		croak "nolinear time step: l=".  $l->time 
			." c=". $c->time
			." d=". $c->dur;
	}
	if( $c->isblockfirst( $l ) ){
		croak "found unexpected gap without block start: l=". $l->time 
			." c=". $c->time
			." d=". $c->dur;
	}
}

sub do_write { croak "not suported"; };

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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
