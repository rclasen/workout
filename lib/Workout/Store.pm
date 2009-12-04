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

=head2 new( $arg )

=cut

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

	$a ||= {};
	Workout::Store::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}

sub all { 
	my( $self ) = @_;

	my $iter = $self->iterate or return;
	$iter->all;
}

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

sub chunk_idx2time {
	my( $self, $idx ) = @_;
	if( $idx >= $self->chunk_count 
		|| $idx < 0 ){

		croak "index is out of range";
	}
	$self->{chunk}[$idx]->time;
}

sub chunks { $_[0]{chunk}; }
sub chunk_count { scalar @{$_[0]{chunk}}; }
sub chunk_first { $_[0]{chunk}[0]; }
sub chunk_last { $_[0]{chunk}[-1]; }

sub chunk_get_idx {
	my( $self, $idx1, $idx2 ) = @_;

	$idx2 ||= $idx1;
	$idx1 <= $idx2
		or croak "inverse index span";


	@{$self->{chunk}}[$idx1 .. $idx2];
}

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

sub chunk_del_idx {
	my( $self, $idx1, $idx2 ) = @_;

	$idx2 ||= $idx1;
	$idx1 <= $idx2
		or croak "inverse index span";

	# TODO: nuke marker outside the resulting time span
	splice @{$self->{chunk}}, $idx1, $idx2-$idx1;
}

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

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $i ) = @_;

	$self->_chunk_add( $i->clone({
		prev	=> $self->chunk_last,
	}));
}

sub _chunk_add {
	my( $self, $n ) = @_;

	$self->chunk_check( $n );
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



sub marks {
	my( $self ) = @_;
	$self->{mark};
}

sub mark_count {
	my( $self ) = @_;
	scalar @{$self->{mark}};
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
	push @{$self->{mark}}, Workout::Marker->new({
		%$a,
		store	=> $self,
	});
}

sub mark_del {
	my( $self, $idx ) = @_;
	splice @{$self->{mark}}, $idx, 1;
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
	my $self = shift;
	my $c = $self->chunk_first
		or return;
	$c->stime;
}

sub time_end {
	my $self = shift;
	my $c = $self->chunk_last
		or return;
	$c->time;
}

sub dur {
	my $self = shift;
	$self->time_end - $self->time_start;
}

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



