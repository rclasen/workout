#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Memory - Memory storage for Workout data

=head1 SYNOPSIS

  $src = Workout::Store::Memory->new;
  while( $chunk = $src->next ){
  	...
  }

=head1 DESCRIPTION

Interface to store Workout data in memory

=cut

package Workout::Store::Memory::Iterator;
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


package Workout::Store::Memory;
use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Workout::Store';

our $VERSION = '0.01';

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

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::Memory::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
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

sub _chunk_add {
	my( $self, $n ) = @_;

	$self->chunk_check( $n );
	push @{$self->{chunk}}, $n;
}

sub marks {
	my( $self ) = @_;
	$self->{mark};
}

sub mark_count {
	my( $self ) = @_;
	scalar @{$self->{mark}};
}

sub _mark_add {
	my( $self, $mark ) = @_;
	push @{$self->{mark}}, $mark;
}

sub mark_del {
	my( $self, $idx ) = @_;
	splice @{$self->{mark}}, $idx, 1;
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

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
