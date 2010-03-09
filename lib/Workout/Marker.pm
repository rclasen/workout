#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Marker - keeps track of workout parts to highlight.

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 

  $marks = $src->marks;
  foreach my $mark ( @$marks )){
  	print "marker from ", $mark->start, 
		" to ", $mark->end,
		": ", $mark->note, "\n";
	
	my $it = $mark->iterate;
	while( my $c = $it->next ){
		print join(",",$c->time, $c->dur, $c->pwr ),"\n";
	}
  }


=head1 DESCRIPTION

Marker keep track of parts of a workout. Think of laps or intervalls,
though marker may overlap.

=cut


package Workout::Marker;
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
	note
	start
	end
/);

=head1 CONSTRUCTOR

=head2 new( \%arg )

creates new marker. Ususally you're not using this directly. This is
called automagically when using the mark_add() method of a Workout::Store.

The arg hashref is used to initialize the data elements (store, note,
start, end ).

=cut

sub new {
	my( $proto, $a ) = @_;

	exists $a->{store}
		or croak "missing store";

	my $self = $proto->SUPER::new( $a );
	weaken( $self->{store} );
	$self;
}

=head1 METHODS

=head2 store

get the store this marker is referring to.

=head2 start

get/set start time of this marker (unix timestamp)

=head2 end

get/set end time of this marker (unix timestamp)

=head2 note

get/set the descriptional text of this marker.

=head2 dur

get duration of marker

=cut

sub dur {
	my( $self ) = @_;
	$self->end - $self->start;
}

=head2 iterate

returns an iterator for the chunks covered by this marker.

=cut

sub iterate {
	my( $self ) = @_;

	Workout::Filter::Timespan->new( $self->store, {
		start	=> $self->start, 
		end	=> $self->end,
	});
}

=head2 info

Collects overall data of chunks within this marker and returns it as a
finish()ed Workout::Filter::Info.

=cut

sub info {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self->iterate, @_ );
	$i->finish;
	$i;
}

=head2 time_add_delta( $delta )

adds $delta to this marker.

=cut


sub time_add_delta {
	my( $self, $delta ) = @_;
	$self->{start} += $delta;
	$self->{end} += $delta;
}

1;
__END__

=head1 SEE ALSO

Workout::Base, Workout::Chunk, Workout::Store, Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
