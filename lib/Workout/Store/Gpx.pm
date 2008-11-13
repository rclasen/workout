use 5.008008;
use warnings;
=head1 NAME

Workout::Store::Gpx - read/write GPS tracks in XML format

=head1 SYNOPSIS

  use Workout::Store::Gpx;

  $src = Workout::Store::Gpx->read( "foo.gpx" );
  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.gpx" );

=head1 DESCRIPTION

Interface to read/write GPS files

=cut

package Workout::Store::Gpx::Iterator;
use strict;
use base 'Workout::Iterator';
use Geo::Distance;
use Carp;

sub new {
	my( $class, $store, $a ) = @_;

	my $self = $class->SUPER::new( $store, $a );
	$self->{track} = $store->{gpx}->tracks->[0];
	$self->{cseg} = 0;
	$self->{cpt} = 0;
	$self->{prev} = undef;
	$self;
}

sub _geocalc {
	my( $self ) = @_;
	$self->{geocalc} ||= new Geo::Distance;
}

=head2 next

=cut

sub next {
	my( $self ) = @_;
	
	return unless $self->{track};

	my $segs = $self->{track}{segments};
	while( $self->{cseg} < @$segs ){
		my $seg = $segs->[$self->{cseg}];

		# next segment?
		if( defined $seg->{points} 
			&& @{$seg->{points}} <= $self->{cpt} ){

			$self->debug( "next segment" );
			$self->{cseg}++;
			$self->{cpt} = 0;
			$self->{prev} = undef;
			next;
		}

		# next point!
		my $ck = Workout::Chunk->new(
			$seg->{points}[$self->{cpt}++] );
		$self->{cntin}++;

		# TODO: keep distance of time-less points? croak?
		next unless $ck->time;

		my $prev = $self->{prev};
		$self->{prev} = $ck;

		next unless $prev;

		$ck->dur( $ck->time - $prev->time );
		$ck->dist( $self->_geocalc->distance( 'meter', 
			$prev->lon, $prev->lat,
			$ck->lon, $ck->lat 
		));
		$ck->prev( $prev ) if $prev->dur;

		$self->{cntout}++;
		return $ck;

	}
	return;
}



package Workout::Store::Gpx;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use Geo::Gpx;

our $VERSION = '0.01';

sub filetypes {
	return "gpx";
}

sub new {
	my( $class, $a ) = @_;

	my $self = $class->SUPER::new( $a );
	$self;
}

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

	$self->{gpx} = Geo::Gpx->new( input => $fh )
		or croak "cannot read file: $!";

	close($fh);

	@{$self->{gpx}->tracks} <= 1
		or croak "cannot deal with multiple tracks per file";

	$self;
}


=head2 iterate

=cut

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::Gpx::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}

# TODO: block_add
# TODO: chunk_add
# TODO: write

1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
