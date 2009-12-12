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

__PACKAGE__->mk_accessors(qw(
	cap_block
	cap_note
	recint

	note
));


=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

Creates an empty Store.

In addition the the Workout::Base the following arguments are recognized.
Please see the matching method's description:

=over 4

=item recint

=item cap_block

=item cap_note

=item note

=item fields_essential

=item fields_supported

=item fields_io

=back

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new({
		cap_block	=> 1,
		cap_note	=> 1,
		fields_essential	=> {},
		fields_supported	=> {
			%fields_supported,
		},
		fields_io	=> {},
		%$a,
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

	if( $self->{debug} ){
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
				." ". ($mark->note||'')
			);
		}
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

	$self->note( $store->note );
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



=head2 recint

recording intervall (fixed). undef when variable intervalls are allowed.

=head2 cap_block

block capability. true when gaps between chunks are allowed.

=head2 cap_note

note capability. true when store supports a per-workout note/comment.

=head2 note

note. A per-workout comment.

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

	} else {
		keys %{$self->{fields_io}};
	}
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

	foreach my $f ( keys %{ $self->{fields_essential} } ){
		if( $f eq 'dur' ){
			$c->dur or croak "missing duration";

		} elsif( $f eq 'time' ){
			$c->time or croak "missing time";

		} else {
			defined $c->$f or croak "missing field: $f";

		}
	}

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
		note	=> undef,
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
				.'): '. ($lap->note||'') );
		}
	}

	wantarray ? @laps : \@laps;
}

=head2 mark_new_laps( \@laps )

converts a list with lap end timestamps and note to marker and adds them
to this store. When possible overlapping marker are guessed from the lap
note. See Workout::Lap on how this such a lap note should look like.

 $store->mark_new_laps([{
 	end	=> $lap_end_time1,
	note	=> '1',
 }, {
 	end	=> $lap_end_time2,
	note	=> '2',
 });


=cut

sub mark_new_laps {
	my( $self, $laps ) = @_;

	# step1: guess overlapping marker from lap name
	my %mark;
	my $id = 0;
	my $mname;
	my $ltime = $self->time_start;
	foreach my $lap ( @$laps ){
		$mark{$mname}{end} ||= $lap->{end} if $mname;
		$mname = undef;

		my $lnote = $lap->{note} || '';

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
				."): ". ($lnote||'') );

		}

		foreach my $part ( split(/\s*;\s*/, $lnote ) ){
			if( my( $se, $note ) = $part =~ /^(start|end):\s*(.+)\s*$/ ){
				$mname = lc $note;
				$mname =~ s/\s+/./g;
				#$self->debug( "lap-part: $mname $se:$note" );

				$mark{$mname}{note} ||= $note;
				$mark{$mname}{start} ||= $ltime;
				$mark{$mname}{$se} = $lap->{end};
			}
		}

		if( ! $mname ){
			$mark{$id++} = {
				note	=> $lnote,
				start	=> $ltime,
				end	=> $lap->{end},
			};
		}

		$ltime = $lap->{end};
	}

	# step2: add marker
	foreach my $mid ( sort { $mark{$a}{start} <=> $mark{$b}{start} } keys %mark){
		$self->mark_new( $mark{$mid} );
	}
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
	my $i = Workout::Filter::Info->new( $self, @_ );
	$i->finish;
	$i;
}





1;
__END__

=head1 SEE ALSO

Workout::Base, Workout::Chunk, Workout::Marker, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut



