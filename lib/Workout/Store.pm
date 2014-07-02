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

  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = $src->iterate;
  while( $c = $it->next ){
	print join(",",$c->time, $c->dur, $c->pwr ),"\n";
  }


=head1 DESCRIPTION

Container class with data chunks of sport workout recordings. This is
supposed to be subclassed for reading/writing specific workout file types
or downloading data direcly from a device.

=cut


package Workout::Store::Iterator;
use strict;
use warnings;
use Carp;
use base 'Workout::Iterator';

sub process {
	my( $self ) = @_;

	my $dat = $self->src->{chunk};
	return unless $self->{cntin} < @$dat;

	$dat->[$self->{cntin}++];
}

sub stores { $_[0]->src; }
sub recint { $_[0]->recint; }
sub cap_block { $_[0]->cap_block; }


# TODO: rewrite individual Workout::Store::* as input/output filters

package Workout::Store;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Workout::Chunk;
use Workout::Marker;
use Workout::Lap;
use Workout::Filter::Info;
use Carp;

our $VERSION = '0.01';

our %fields_essential = map { $_ => 1; } qw{
	time
	dur
};

our %fields_supported = map { $_ => 1; } 
	Workout::Chunk::core_fields;



sub filetypes {
	my( $class ) = @_;
	return;
}

our %default = (
	tz		=> 'local',
	cap_block	=> 0,
	recint		=> undef,
);
__PACKAGE__->mk_accessors( keys %default, qw(
	meta
));

our %meta = (
	sport		=> '',
	note		=> '',
);

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

Creates an empty Store.

In addition the the Workout::Base the following arguments are recognized.
Please see the matching method's description:

=over 4

=item tz

=item recint

=item cap_block

=item fields_essential

=item fields_supported

=item fields_io

=item meta

=back

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	$a->{meta}||={};
	my $self = $class->SUPER::new({
		%default,
		fields_essential	=> {},
		fields_supported	=> {
			%fields_supported,
		},
		fields_io	=> {},
		%$a,
		meta	=> {
			%meta,
			%{$a->{meta}},
		},
		chunk		=> [],
		mark		=> [],
	});
	$self->{fields_essential} = {
		%{$self->{fields_essential}},
		%fields_essential,
	},
	$self->{fields_supported} = {
		%{$self->{fields_supported}},
		%{$self->{fields_essential}},
	},
	$self->{fields_io} ||= { %{ $self->{fields_supported} } };
	$self;
}


=head2 read( $source [, \%arg ] )

Create new store and read data from $source. When source is a filename,
it's opened. Otherwise it's assumed to be an IO::Handle. \%arg is passed
to new().

=cut

sub read {
	my( $class, $source, $a ) = @_;
	my $self = $class->new( $a );

	my( $fh, $fname );
	if( ref $source ){
		$fh = $source;
	} else {
		$fname = $source;
		open( $fh, '<', $fname )
			or croak "open '$fname': $!";
	}

	$self->do_read( $fh, $fname );
	close($fh) if $fname;

	if( ! $self->{debug} ){
		# do nothing

	} elsif( $self->chunk_count ){
		my $sdate = DateTime->from_epoch(
			epoch		=> $self->time_start,
			time_zone	=> 'local',
		);
		my $edate = DateTime->from_epoch(
			epoch		=> $self->time_end,
			time_zone	=> 'local',
		);
		$self->debug( "read from ". $sdate->hms
			. " (".  $self->time_start
			.") to ". $edate->hms
			. " (".  $self->time_end
			."): ". $self->chunk_count
			." chunks, ".  $self->mark_count
			." marker");

		my $num = 0;
		foreach my $mark ( $self->marks ){
			$sdate = DateTime->from_epoch(
				epoch		=> $mark->start,
				time_zone	=> 'local',
			);
			$edate = DateTime->from_epoch(
				epoch		=> $mark->end,
				time_zone	=> 'local',
			);

			$self->debug( "mark ". $num++
				.": ".  $sdate->hms . " (".  $mark->start .")"
				." to ". $edate->hms . " (".  $mark->end .")"
				." ". ($mark->meta_field('note')||'')
			);
		}

	} else {
		$self->debug( "read no chunks" );

	}

	$self;
}



=head1 METHODS

=head2 from( $source )

Copy chunks and store data from specified source (other Workout::Store or
Workout::Iterator).

This will turn into a constructor in a future release.

=cut

sub from { # TODO: make this a constructor
	my( $self, $iter ) = @_;

	$iter->isa( 'Workout::Iterator' )
		or $iter = $iter->iterate;

	while( my $chunk = $iter->next ){
		$self->chunk_add( $chunk->clone );
	}

	foreach my $store ( $iter->stores ){
		$self->from_store( $store );
	}

	$self->fields_io( $self->fields_supported( $iter->fields_io ));
}



=head2 from_store( $store )

Copy store data (no chunks) from specified store. Used by from()

=cut

sub from_store {
	my( $self, $store ) = @_;

	my $marks = $store->marks;
	if( $marks ){
		foreach my $mark ( @{$store->marks} ){
			$self->mark_new( $mark );
		}
	}

	my $meta = $store->meta;
	foreach my $k ( keys %$meta ){
		defined $meta->{$k} or next;
		$self->meta_field( $k, $meta->{$k} );
	}
}



=head2 do_read( $fh, $fname )

stub. Has to be implemented by individual stores according to their File
format. $fname might be undefined when reading from a pipe, a scalar or
similar.

=cut

sub do_read { croak "reading is not suported"; };



=head2 do_write( $fh, $fname )

stub. Has to be implemented by individual stores according to their File
format. 

=cut

sub do_write { croak "writing is not suported"; };



=head2 write( $destination )

write data to specified destination. If destination is a filename, it's
opened. Otherwise it's assumed to be an IO::Handle.

=cut

sub write {
	my( $self, $source ) = @_;

	$self->chunk_count
		or return;

	my( $fh, $fname );
	if( ref $source ){
		$fh = $source;
	} else {
		$fname = $source;
		open( $fh, '>', $fname )
			or croak "open '$fname': $!";
	}

	$self->do_write( $fh, $fname );

	if( $fname ){
		close($fh) or return;
	}

	1;
}


=head2 tz

set/get timezone for reading/writing local timestamps in file types that
don't use UTC and don't specify their timezone. See DateTime.

=head2 recint

recording intervall (fixed). undef when variable intervalls are allowed.

=head2 recint_chunks

fixed recording intervall as used by chunks. undef, if chunk duration
varies.

=cut

sub recint_chunks {
	my( $self ) = @_;

	$self->chunk_count
		or return;

	my $recint = $self->chunk_first->dur;

	foreach my $c ( @{$self->{chunk}} ){
		return if $c->dur != $recint;
	}

	return $recint;
}


=head2 cap_block

block capability. true when gaps between chunks are allowed.

=cut

=head2 fields_essential

return list of fields essential for this store. Essential fields must have
a (non-null) value.

=cut

sub fields_essential {
	my $self = shift;
	keys %{$self->{fields_essential}};
}



=head2 fields_supported( [ <fields>, ...] )

return list of fields supported by this Store.

=cut

sub fields_supported {
	my $self = shift;
	if( @_ ){
		grep { exists $self->{fields_supported}{$_} } @_;
	} else {
		keys %{$self->{fields_supported}};
	}
}



=head2 fields_unsupported( <field> ... )

returns list of fields unsupported by this store.

=cut

sub fields_unsupported {
	my $self = shift;

	grep { ! exists $self->{fields_supported}{$_} } @_;
}



=head2 fields_io( [<field> ... ] )

set/get list of fields that were read / that are written.

=cut

sub fields_io {
	my $self = shift;

	if( @_ ){
		if( my @unsup = $self->fields_unsupported( @_ ) ){
			croak "fields are unsupported by this store: @unsup";
		}

		$self->{fields_io} = {
			map { $_ => 1 } @_, keys %{$self->{fields_essential}},
		};
		$self->debug( "fields_io set: ". join( " ", keys
			%{$self->{fields_io}}) );

	} else {
		keys %{$self->{fields_io}};
	}
}

=head2 have_fields_io( <field> ... )

returns subset of fields that were read / are written

=cut

sub have_fields_io {
	my $self = shift;

	grep {
		exists $self->{fields_io}{$_};
	} @_;
}



=head2 iterate

returns an iterator for the chunks in this store.

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

# TODO: convert from recursion -> loop

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

		croak "index $idx is out of range";
	}
	$self->{chunk}[$idx]->time;
}



=head2 chunks

return array/-ref to internal array with all chunks.

=cut

sub chunks {
	wantarray ? @{$_[0]{chunk}} : $_[0]{chunk};
}



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
		or croak "inverse index span $idx1-$idx2";


	@{$self->{chunk}}[$idx1 .. $idx2];
}



=head2 chunk_get_time( $from, [ $to ] )

returns list of chunks in the specified time range.

=cut

sub chunk_get_time {
	my( $self, $time1, $time2 ) = @_;

	$time2 ||= $time1;
	$time1 <= $time2
		or croak "inverse time span $time1-$time2";

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
		or croak "inverse index span $idx1-$idx2";

	$self->meta_prune_all;

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
		or croak "inverse time span $time1-$time2";

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

	foreach my $f ( keys %{ $self->{fields_essential} } ){
		if( $f eq 'dur' ){
			$c->dur or croak "missing duration";

		} elsif( $f eq 'time' ){
			$c->time or croak "missing time";

		} else {
			defined $c->$f or croak "missing field: $f";

		}
	}

	if( $c->dur <= 0 ){
		croak "duration <= 0 at ". $c->time;
	}

	if( $self->recint && abs($self->recint - $c->dur) > 0.1 ){
		croak "duration ". $c->dur ." doesn't match recint ".
			$self->recint ." at time ". $c->time;
	}

	my $l = $self->chunk_last
		or return;

	if( $c->stime - $l->time < -0.1 ){
		croak "nonlinear time step: l=".  $l->time 
			." c=". $c->time
			." d=". $c->dur;
	}
}



=head2 blocks

returns array/-ref of arrays with continous chunks. i.e. the chunks are
split into individual arrays at each gap.

=cut

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

	wantarray ? @blocks : \@blocks;
}



=head2 block_marks

returns array/-ref of Workout::Marker with continuous chunks. i.e. workout
is split at gaps / block boundaries.

=cut

sub block_marks {
	my( $self ) = @_;

	my @blocks;

	my $iter = $self->iterate;
	while( my $c = $iter->next ){
		if( $c->isfirst || $c->isblockfirst ){
			push @blocks, Workout::Marker->new({
				store	=> $self,
				start	=> $c->stime,
				end	=> $c->time,
			}),

		} else {
			$blocks[-1]->end( $c->time );
		}
	}

	wantarray ? @blocks : \@blocks;
}


=head2 marks

returns array/-ref (depending on context) with Workout::Marker in this store.

=cut

sub marks {
	wantarray ? @{$_[0]{mark}} : $_[0]{mark};
}



=head2 mark_count

returns number of marker in this store.

=cut

sub mark_count {
	my( $self ) = @_;
	scalar @{$self->{mark}};
}



=head2 mark_workout

returns a marker spanning the whole workout.

=cut

sub mark_workout {
	my( $self ) = @_;
	Workout::Marker->new( {
		store	=> $self, 
		start	=> $self->time_start, 
		end	=> $self->time_end,
	});
}



=head2 mark_new( \%marker_data )

Creates a new marker with specified data and adds it to this Store.

=cut

sub mark_new {
	my( $self, $a ) = @_;

	$a->{meta}||={};
	my %opt = (
		%$a,
		meta	=> {
			%{$a->{meta}},
		},
		store	=> $self,
	);

	my $start = $self->time_start // return;
	my $end = $self->time_end // return;

	# ensure that marker time span is within chunk timespan
	if( $opt{end} > $end ){
		$opt{end} = $end;
	}
	if( $opt{start} < $start ){
		$opt{start} = $start;
	}
	if( $opt{end} <= $opt{start} ){
		return;
	}

	push @{$self->{mark}}, Workout::Marker->new(\%opt);
}



=head2 mark_del( $idx )

deletes specified marker from Store and returns it.

=cut

sub mark_del {
	my( $self, $idx ) = @_;
	splice @{$self->{mark}}, $idx, 1;
}

=head2 laps( [$minlap] )

converts the marker to "laps". In contrast to markers, laps don't overlap.
Each workout has at least one lap: The whole workout.  Returns array-/ref
with Workout::Lap.

=cut

# TODO: document $minlaps

sub laps {
	my( $self, $minlap ) = @_;

	# step1: find marker, that refer to the same time

	$minlap ||= $self->recint || 1;

	my %tics;
	foreach my $mark ( sort { $a->start <=> $b->start } $self->marks ){

		push @{$tics{int(100 * $mark->start / $minlap)}{mark_start}}, $mark;
		push @{$tics{int(100 * $mark->end / $minlap)}{mark_end}}, $mark;
	};

	my $mark = $self->mark_workout;
	push @{$tics{int(100 * $mark->end / $minlap)}{mark_end}}, $mark;

	# step2: build laps

	my @laps;
	my $ltime = $self->time_start;
	foreach my $tictime ( sort { $a <=> $b } keys %tics ){
		my $tic = $tics{$tictime};

		my $lap = Workout::Lap->new({
			%$tic,
			start	=> $ltime,
			store	=> $self,
		});
		my $end = $lap->end;

		# skip empty lap at start of workout:
		next if ! @laps && ( $end - $ltime < $minlap );

		push @laps, $lap;
		$ltime = $end;

		if( $self->{debug} ){
			my $s = DateTime->from_epoch(
				epoch	=> $lap->start,
				time_zone	=> 'local',
			);
			my $e = DateTime->from_epoch(
				epoch	=> $end,
				time_zone	=> 'local',
			);

			$self->debug( 'lap '. @laps
				.': '. $s->hms
				.' ('. $lap->start
				.') to '. $e->hms
				.' ('.  $end
				.'): '. ($lap->meta_field('note')||'') );
		}
	}

	wantarray ? @laps : \@laps;
}

=head2 mark_new_laps( \@laps )

converts a list with lap end timestamps and meta info to marker and adds
them to this store.

 $store->mark_new_laps([{
 	end	=> $lap_end_time1,
	meta	=> {
		note	=> '1',
	}
 }, {
 	end	=> $lap_end_time2,
	meta	=> {
		note	=> '2',
	}
 });


=cut

sub mark_new_laps {
	my( $self, $laps ) = @_;

	my $ltime = $self->time_start;
	foreach my $lap ( sort { $a->{end} <=> $b->{end} } @$laps ){

		$lap->{meta} ||= {};
		if( $self->{debug} ){
			my $sdate = DateTime->from_epoch(
				epoch	=> $ltime,
				time_zone	=> 'local',
			);
			my $edate = DateTime->from_epoch(
				epoch	=> $lap->{end},
				time_zone	=> 'local',
			);

			$self->debug( "lap: ". $sdate->hms
				. " (".  $ltime
				.") to ". $edate->hms
				. " (".  $lap->{end}
				."): ". ($lap->{meta}{note}||'') );

		}

		$self->mark_new( {
			start	=> $ltime,
			end	=> $lap->{end},
			meta	=> $lap->{meta},
		} );

		$ltime = $lap->{end};
	}
}

=head2 time_add_delta( $delta )

adds $delta to all chunks and markers in this store.

=cut

sub time_add_delta {
	my( $self, $delta, $start, $end ) = @_;

	$start ||= $self->time_start;
	$end ||= $self->time_end;

	# check/ensure time consistency
	my $idxstart = $self->chunk_time2idx( $start );
	my $ckprev = $idxstart == 0 ? undef
		: $self->chunk_get_idx( $idxstart -1 );
	my $ckstart = $self->chunk_get_idx( $idxstart );

	my $idxend = $self->chunk_time2idx( $end );
	my( $ckend, $cknext ) = $self->chunk_get_idx( $idxend, $idxend + 1 );

	if( $delta > 0 ){
		if( $cknext && $ckend->time + $delta > $cknext->stime ){
			croak "invalid delta, causing overlap";
		}

		if( $ckprev && ! $self->cap_block ){
			croak "Store doesn't support gaps";
		}

	} else {
		if( $ckprev && $ckstart->stime + $delta < $ckprev->time ){
			croak "invalid delta, causing overlap";
		}

		if( $cknext && ! $self->cap_block ){
			croak "Store doesn't support gaps";
		}
	}

	my $iter = $self->iterate;
	while( my $c = $iter->next ){
		if( $start < $c->time  && $c->time <= $end ){
			$c->time( $c->time + $delta );
		}
	}

	foreach my $m ( @{ $self->marks } ){
		$m->time_add_delta( $delta, $start, $end );
	}

	$self->meta_prune_all;
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



=head2 info( [info_args] )

Collects overall Data from this store and returns it as a
finish()ed Workout::Filter::Info.

=cut

sub info {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self, @_ );
	$i->finish;
	$i;
}


=head2 info_meta( [info_args] )

returns a copy of the meta hash where missing bits are automatically
populated by calculated values of Workout::Filter::Info.

=cut

sub info_meta {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self, @_ );
	$i->finish;
	return $i->meta( $self->meta );
}

=head2 meta_prune

remove all keys from this store's meta that can ba calculated by
Workout::Filter::Info. As a result info_meta() will recompute all values
on next invocation.

=cut

sub meta_prune {
	my( $self ) = @_;

	foreach my $k ( &Workout::Filter::Info::meta_fields ){
		delete $self->{meta}{$k};
	}
}

=head2 meta_prune_all

prune recalculateable metadata from store and marker

=cut

sub meta_prune_all {
	my( $self ) = @_;

	$self->meta_prune;
	foreach my $m ( $self->marks ){
		$m->meta_prune;
	}
}

=head2 meta

returns hashref with metadata. See META INFO for details.

=head2 meta_field( $key [,$val] )

set/get a field of the meta hash

=cut

sub meta_field {
	my( $self, $k, @v ) = @_;

	return unless defined $k;

	my $m = $self->{meta};
	if( ! @v ){
		return unless exists $m->{$k};
		return $m->{$k};
	}
	$m->{$k} = $v[0]
}

1;
__END__

=head1 META INFO

Some files support precalculated summary information and metadata like
Athlete names and device information. This information is stored in the
"meta hash".

For pre-calculated summary information, please check the method names of
Workout::Filter::Info regarding their meaning.

Check the individual Stores' Documentation on additional fields they
support.

Well known meta fields are:

=head2 sport

Sport type. String, common values are 'Bike', 'Run', 'Swim', 'Other'

=head2 note

name/descrition of the workout. Supported length varies by Store.

=head2 device

recording device type (string)

=head2 circum

wheel circumference in millimeters (mm)

=head2 zeropos

power meter zero offset in Hertz (HZ)

=head2 slope

power meter slope as known from srmwin and PowerControl

=cut

# TODO: unit for slope

=head2 athletename

name of athlete. Supported length varies by Store.

=head2 hr_rest

Resting heartrate of athlete (1/min)

=head2 hr_capacity

maximum heartrate of athlete (1/min)

=head2 vo2max

maximum oxygen intake of athlete ( mL/(kg*min) )

=head2 weight

athlete weight (kg)

=head1 SEE ALSO

Workout::Base, Workout::Chunk, Workout::Marker, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut



