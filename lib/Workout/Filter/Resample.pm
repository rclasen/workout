#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::Resample;

=head1 NAME

Workout::Filter::Resample - Resample Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );

  $new = Workout::Filter::Resample->new( $src, { recint => 10 } );

  while( $chunk = $new->next ){
  	# do smething
  }

=head1 DESCRIPTION

Resample Workout data chunks to match a differnet, fixed recording
interval or shift data to a different offset. Multiple (shorter) Chunks
are merged, longer Chunks are split into multiple parts.

=cut


use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::BaseQueue';
use Carp;

our $VERSION = '0.01';


our %default = (
	recint	=> 5,
);

__PACKAGE__->mk_accessors( keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	$class->SUPER::new( $src, {
		%default,
		%$a,
	});
}

=head2 recint

get/set recording/sampling interval in use

=cut


sub process {
	my( $self ) = @_;

	$self->_fetch_time( $self->recint );
}

sub _fetch_time {
	my( $self, $wdur, $wtime ) = @_;

	my @merge;
	my $dur = 0;
	my $next;

	# collect data
	#$self->debug( "collecting chunk: ".($wtime || 0) .", ". $wdur );
	while( $dur < $wdur ){

		$next = $self->_fetch_range( $wdur, $wtime )
			or last;

		#$self->debug( "next chunk: ".$next->time.", ". $next->dur 
		#	.", ". ($next->spd||0) );
		if( $wtime && ( $next->stime < ($wtime - $wdur)) ){
			$self->debug( "discarding chunk data between ".
				$next->stime." and ". ($wtime-$wdur) );
			$next = ($next->split( $wtime-$wdur ))[1];
		}

		# block terminated while collecting
		my $p = $merge[-1];
		if( $p && $next->isblockfirst( $p ) ){
			my $gap = $next->gap( $p );

			# gap is too small to complete $dur, fill with zero
			if( $dur + $gap < $wdur ){
				$self->debug( "filling small ". $gap 
					."sec block gap at ". $p->time );
				push @merge, $p->synthesize($next->stime, $next);
				$dur += $gap;

			# got enough data, exit
			} elsif( $dur > $wdur / 2 ){
				$self->_push( $next );
				last;

			# not enoug data, drop it and restart collecting
			} else {
				$self->debug( "block end at ". $p->time
				.", actually dropping ". $dur ."sec data");
				@merge = ();
				$dur = 0;
			}

		}

		push @merge, $next;
		$dur += $next->dur;
	}

	if( ! $dur ){
		return;

	} elsif( $dur < $wdur / 2 ){
		$self->debug( "dropping ". $dur ."sec data at workout end");
		return;

	} # else enough data present

	my $time = $merge[0]->stime + $wdur;
	my $last = $merge[-1];

	# ... fill end with zeros to complete recint
	if( $time - $last->time > 0.05 ){
		$self->debug( "extending workout/block end from ". $dur ."sec at ".
			$last->time );

		my $n = $last->synthesize($time);
		push @merge, $n;
		$dur += $n->dur;
	}

	# merge collected chunks
	my $agg = Workout::Chunk::merge( @merge );

	# split of recint and remember remainder
	my( $o, $q ) = $agg->split( $time );
	$self->_push( $q ) if $q;
	$o->prev( $self->last );

	return $o;
}

sub _fetch_range {
	my( $self, $wdur, $wtime ) = @_;

	while( my $i = $self->_fetch ){
		return $i unless $wtime;

		if( $i->time <= $wtime - $wdur ){
			$self->debug( "skipping chunk ". $i->stime 
				." to ". $i->time  );
			next;
		}
		return $i if $i->stime < $wtime;

		$self->debug( "delayed chunk ". $i->time );
		$self->_push( $i );
		last;
	}
	return;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::BaseQueue

=head1 AUTHOR

Rainer Clasen

=cut
