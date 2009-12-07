#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store - Memory storage for Workout data

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
  $mem = Workout::Store->new;
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


package Workout::Store::Iterator;
use strict;
use warnings;
use Carp;
use base 'Workout::Iterator';

sub process {
	my( $self ) = @_;

	my $dat = $self->store->{chunk};
	return unless $self->{cntin} < @$dat;

	$dat->[$self->{cntin}++];
}




# TODO: move documentation to Workout;
# TODO: rewrite Store::* as input/output filter

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




=head2 new( \%args )

Constructor. Creates an empty Store.

=cut

# TODO: document new %args

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new({
		cap_block	=> 1,
		cap_note	=> 1,
		%$a,
		chunk		=> [],
		mark		=> [],
	});

	$self;
}



=head2 from( $source )

Copy chunks and store data from specified source (other Workout::Store or
Workout::Iterator).

=cut

sub from { # TODO: make this a constructor
	my( $self, $iter ) = @_;

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	while( defined( my $chunk = $iter->next )){
		$self->chunk_add( $chunk->clone );
	}

	my $store = $iter->store;
	$self->from_store( $store );
}



=head2 from_store( $store )

Copy store data (no chunks) from specified store.

=cut

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



=head2 do_read( $fh )

stub. Has to be implemented by individual stores according to their File
format.

=cut

sub do_read { croak "reading is not suported"; };



=head read( $fname, \%new )

Constructor. Create new store and read data from $fname. \%new is passed
to new().

=cut

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



=head2 do_write( $fh )

stub. Has to be implemented by individual stores according to their File
format.

=cut

sub do_write { croak "writing is not suported"; };



=head2 write( $fname )

write data to specified filename.

=cut

sub write {
	my( $self, $fname ) = @_;

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


=head2 cap_block

block capability. true when gaps between chunks are allowed.

=head2 cap_note

note capability. true when store supports a per-workout note/comment.

=head2 note

note. A per-workout comment.

=head2 recint

recording intervall (fixed). undef when variable intervalls are allowed.


=head2 iterate

returns a Workout::Iterator to retrieve chunks one by one.

=cut

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}



=head2 chunk_time2idx( $time )

finds index of chunk at specified time.

=cut

sub chunk_time2idx {
	my( $self, $time ) = @_;

	my $last = $#{$self->{chunk}};

	# no data
	return unless $last >= 0;

	# after data
	return $last if $time > $self->{chunk}[$last]->stime;

	# perform quicksearch
	$self->_chunk_time2idx( $time, 0, $last );
}

# quicksearch
sub _chunk_time2idx {
	my( $self, $time, $idx1, $idx2 ) = @_;

	return $idx1 if $time <= $self->{chunk}[$idx1]->time;
	return $idx2 if $idx1 + 1 == $idx2;

	my $split = int( ($idx1 + $idx2) / 2);
	#$self->debug( "qsrch $idx1 $split $idx2" );

	if( $time <= $self->{chunk}[$split]->time ){
		return $self->_chunk_time2idx( $time, $idx1, $split );
	}
	return $self->_chunk_time2idx( $time, $split, $idx2 );
}



=head2 chunk_idx2time( $idx )

shortcut to return (end-)time of chunk with specified index.

=cut

sub chunk_idx2time {
	my( $self, $idx ) = @_;
	if( $idx >= $self->chunk_count 
		|| $idx < 0 ){

		croak "index is out of range";
	}
	$self->{chunk}[$idx]->time;
}



=head2 chunks

return ref to internal array with all chunks.

=cut

sub chunks { $_[0]{chunk}; }



=head2 chunk_count

return number of chunks in store.

=cut

sub chunk_count { scalar @{$_[0]{chunk}}; }



=head2 chunk_first

returns first chunk in store.

=cut

sub chunk_first { $_[0]{chunk}[0]; }



=head2 chunk_last

returns last chunk in store.

=cut

sub chunk_last { $_[0]{chunk}[-1]; }



=head2 chunk_get_idx( $from, [ $to ] )

returns list of chunks in the specified index range.

=cut

sub chunk_get_idx {
	my( $self, $idx1, $idx2 ) = @_;

	$idx2 ||= $idx1;
	$idx1 <= $idx2
		or croak "inverse index span";


	@{$self->{chunk}}[$idx1 .. $idx2];
}



=head2 chunk_get_time( $from, [ $to ] )

returns list of chunks in the specified time range.

=cut

sub chunk_get_time {
	my( $self, $time1, $time2 ) = @_;

	$time2 ||= $time1;
	$time1 <= $time2
		or croak "inverse time span";

	$self->chunk_get_idx( 
		$self->chunk_idx( $time1 ),
		$self->chunk_idx( $time2 ),
	);

}



=head2 chunk_del_idx( $from, [ $to ] )

deletes chunks in the specified index range from store and returns them as
list.

=cut

sub chunk_del_idx {
	my( $self, $idx1, $idx2 ) = @_;

	$idx2 ||= $idx1;
	$idx1 <= $idx2
		or croak "inverse index span";

	# TODO: nuke marker outside the resulting time span
	# TODO: update ->prev
	splice @{$self->{chunk}}, $idx1, $idx2-$idx1;
}



=head2 chunk_del_time( $from, [ $to ] )

deletes chunks in the specified time range from store and returns them as
list.

=cut
sub chunk_del_time {
	my( $self, $time1, $time2 ) = @_;

	$time2 ||= $time1;
	$time1 <= $time2
		or croak "inverse time span";

	$self->chunk_del_idx( 
		$self->chunk_idx( $time1 ),
		$self->chunk_idx( $time2 ),
	);
}



=head2 chunk_add( $chunk )

add data chunk to store.

=cut

sub chunk_add {
	my( $self, $n ) = @_;

	$self->chunk_check( $n );

	$n->prev( $self->chunk_last );
	push @{$self->{chunk}}, $n;
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



=head2 marks

returns arrayref with Workout::Marker in this store.

=cut

sub marks {
	my( $self ) = @_;
	$self->{mark};
}



=head2 mark_count

returns number of marker in this store.

=cut

sub mark_count {
	my( $self ) = @_;
	scalar @{$self->{mark}};
}



=head2 mark_workout

returns a marker spaning the whole workout.

=cut

sub mark_workout {
	my( $self ) = @_;
	Workout::Marker->new( {
		store	=> $self, 
		start	=> $self->time_start, 
		end	=> $self->time_end,
		note	=> $self->note,
	});
}



=head2 mark_new( \%marker_data )

Creates a new marker with specified data and adds it to this Store.

=cut

sub mark_new {
	my( $self, $a ) = @_;
	# TODO: ensure that marker time span is within chunk timespan
	push @{$self->{mark}}, Workout::Marker->new({
		%$a,
		store	=> $self,
	});
}



=head2 mark_del( $idx )

deletes specified marker from Store and returns it.

=cut

sub mark_del {
	my( $self, $idx ) = @_;
	splice @{$self->{mark}}, $idx, 1;
}




=head2 time_add_delta( $delta )

adds $delta to all chunks and markers in this store. 

=cut

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



=head2 time_start

returns start time of first chunk in this store.

=cut

sub time_start {
	my $self = shift;
	my $c = $self->chunk_first
		or return;
	$c->stime;
}



=head2 time_end

returns end time of last chunk in this store.

=cut

sub time_end {
	my $self = shift;
	my $c = $self->chunk_last
		or return;
	$c->time;
}



=head2 dur

returns duration (in seconds) covered by chunks in this store.

=cut

sub dur {
	my $self = shift;
	$self->time_end - $self->time_start;
}



=head2 info

Collects overall Data from this story and returns it as a
finish()ed Workout::Filter::Info.

=cut

sub info {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self->iterate, @_ );
	$i->finish;
	$i;
}





1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut



