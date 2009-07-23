#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store - Base Class for Sports Workout data Stores

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
# TODO: merge with Store::Memory, change Store::* to be input/output filter

package Workout::Store;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Workout::Marker;
use Workout::Filter::Info;
use Carp;

our $VERSION = '0.01';

sub filetypes {
	my( $class ) = @_;
	return;
}

__PACKAGE__->mk_accessors(qw(
	cap_block
	cap_note
	recint

	note
));

=head2 from( $iter )

copy workout data from specified source (other Workout::Store or
Workout::Iterator).

=cut

sub from { # TODO: make this a constructor
	my( $self, $iter ) = @_;

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	while( defined( my $chunk = $iter->next )){
		$self->chunk_add( $chunk );
	}

	my $store = $iter->store;
	$self->from_store( $store );
}

sub from_store {
	my( $self, $store ) = @_;

	my $marks = $store->marks;
	if( $marks ){
		foreach my $mark ( @{$store->marks} ){
			$self->mark_new( $mark );
		}
	}

	$self->note( $store->note );
}

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

	if( $self->{debug} ){
		$self->debug( "read ". $self->chunk_count ." chunks ".
			$self->mark_count ." marker");
	}

	$self;
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

=head2 iterate

return iterator to retrieve all chunks.

=cut

sub iterate { 
	my( $self, $a ) = @_;
	return; # not implemented
}

sub all { 
	my( $self ) = @_;

	my $iter = $self->iterate or return;
	$iter->all;
}

sub chunk_first { 
	return; # "not implemented"; 
}

sub chunk_last { 
	return; # "not implemented"; 
}

sub chunk_count { 
	return 0; # "not implemented";
};

sub chunk_get_idx {
	my( $self, $idx1, $idx2 ) = @_;
	return; # "not implemented";
}

sub chunk_get_time {
	my( $self, $from, $to ) = @_;
	return; # "not implemented";
}

sub chunk_del_idx {
	my( $self, $from, $to ) = @_;
	return; # "not implemented";
}

sub chunk_del_time {
	my( $self, $from, $to ) = @_;
	return; # "not implemented";
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


sub blocks { 
	my( $self ) = @_;

	my @blocks;
	my $iter = $self->iterate;
	while( my $c = $iter->next ){
		if( $c->isfirst || $c->isblockfirst ){
			push @blocks, [];
		}
		push @{$blocks[-1]}, $c;
	}

	\@blocks;
}


sub marks { 
	return; # "not implemented";
}

sub mark_count {
	return; # "not implemented";
}

sub mark_workout {
	my( $self ) = @_;
	Workout::Marker->new( {
		store	=> $self, 
		start	=> $self->time_start, 
		end	=> $self->time_end,
		note	=> $self->note,
	});
}

sub mark_new {
	my( $self, $a ) = @_;
	# TODO: ensure that marker time span is within chunk timespan
	$self->_mark_add( Workout::Marker->new({
		%$a,
		store	=> $self,
	}) );	
}

sub _mark_add {
	my( $self, $mark ) = @_;
	croak "not implemented";
}

sub mark_del {
	my( $self, $idx ) = @_;
	return; # "not implemented";
}




sub time_add_delta {
	my( $self, $delta ) = @_;

	my $iter = $self->iterate;
	while( my $c = $iter->next ){
		$c->time( $c->time + $delta );
	}

	foreach my $m ( @{ $self->marks } ){
		$m->time_add_delta( $delta );
	}
}

sub time_start { 
	return; # "not implemented";
}

sub time_end { 
	return; # "not implemented";
}

sub dur {
	my $self = shift;
	$self->time_end - $self->time_start;
}

sub info {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self->iterate, @_ );
	while( $i->next ){ 1; };
	$i;
}

1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
