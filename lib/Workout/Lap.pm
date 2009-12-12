#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Lap - Adapter interface for reading/writing lap based files

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "input.srm" ); 

  foreach my $lap ( $src->lap ){
  	print "lap from ", $lap->start, 
		" to ", $lap->end,
		": ", $lap->note, "\n";
	
	my $it = $lap->iterate;
	while( my $c = $it->next ){
		print join(",",$c->time, $c->dur, $c->pwr ),"\n";
	}
  }


=head1 DESCRIPTION

Laps are an alternative view of the Marker within a Store. While Marker
are allowed to overlap, Laps must follow each others from workout's start
to end.

This is mostly intended for reading/writing lap based file formats (HRM,
TCX, Powertap, ...).

=cut


package Workout::Lap;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Carp;
use Scalar::Util qw/ weaken /;
use Workout::Filter::Timespan;

__PACKAGE__->mk_ro_accessors(qw/
	store
/);

__PACKAGE__->mk_accessors(qw/
	start
/);

=head1 CONSTRUCTOR

=head2 new( \%arg )

creates new lap. Ususally you're not using this directly. This is
called automagically from Workout::Store::laps.

The arg hashref is used to initialize the data elements;

=cut

sub new {
	my( $proto, $a ) = @_;

	exists $a->{store}
		or croak "missing store";

	my $self = $proto->SUPER::new({
		store		=> undef,
		start		=> undef,
		end		=> undef,
		mark_start	=> [],
		mark_end	=> [],
		%$a,
	});
	weaken( $self->{store} );
	$self;
}

=head1 METHODS

=head2 store

get the store this lap is referring to.

=head2 start

get/set start time of this lap (unix timestamp)

=head2 end

get end time of this lap (unix timestamp)

=cut

sub end {
	my( $self ) = @_;

	foreach my $mark ( $self->mark_end ){
		return $mark->end;
	}

	foreach my $mark ( $self->mark_start ){
		return $mark->start;
	}

	return;
}

=head2 mark_start

get list of marker starting at this lap.

=cut

sub mark_start {
	my( $self ) = @_;

	wantarray
		? @{$self->{mark_start}}
		: $self->{mark_start};
}

=head2 mark_end

get list of marker ending at this lap.

=cut

sub mark_end {
	my( $self ) = @_;

	wantarray
		? @{$self->{mark_end}}
		: $self->{mark_end};
}

=head2 note

get the descriptional text for all Marker that caused this lap. Each
marker's note is prefixed with "start: " or "end: " - depending on which
timestamp of both timestamps relate to this Lap. All prefixed notes are
joined with ";".

=cut

sub note {
	my( $self ) = @_;

	my @note;
	foreach my $mark ( $self->mark_end ){
		push @note, 'end: '.$mark->note if $mark->note;
	}

	foreach my $mark ( $self->mark_start ){
		push @note, 'start: '.$mark->note if $mark->note;
	}

	return join('; ', @note );
}

=head2 iterate

returns an iterator for the chunks covered by this lap.

=cut

sub iterate {
	my( $self ) = @_;

	Workout::Filter::Timespan->new( $self->store, {
		start	=> $self->start, 
		end	=> $self->end,
	});
}

=head2 info

Collects overall data of chunks within this lap and returns it as a
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

Workout::Base, Workout::Chunk, Workout::Store, Workout::Marker, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
