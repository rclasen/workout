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
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';


# TODO: allow to supply start time

our %default = (
	recint	=> 5,
);

__PACKAGE__->mk_accessors( keys %default );

=head2 new( $src, $arg )

new Iterator

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( $src, {
		%default,
		%$a,
	});
	$self->{queue} = ();
	$self;
}

=head2 recint

return recording/sampling interval in use

=cut

=head2 next

return next (resampled) data chunk

=cut

sub process {
	my( $self ) = @_;

	my @merge;
	my $dur = 0;

	if( my $q = pop @{$self->{queue}} ){
		$dur = $q->dur;
		push @merge, $q;
	}


	# collect data
	while( $dur < $self->recint ){

		# TODO: append zeros when @merge is too small?
		my $r = $self->_fetch
			or return;

		# new block?
		if( $r->isblockfirst ){
			my $p = $r->prev;
			my $gap = $r->gap;
			my $gdur = $dur + $gap;

			# fill small gaps with zeros
			if( $gdur < $self->recint ){
				$self->debug( "filling small ". $gap 
					."sec gap at ". $r->stime );
				push @merge, $p->synthesize($r->stime, $r);
				$dur = $gdur;

			} elsif( $dur > $self->recint / 2 ){
				$self->debug( "extending block end from ". $dur 
					."sec at ". $r->stime );
				push @merge, $p->synthesize($r->stime, $r);
				$dur = $gdur;

			} elsif( $gdur > $self->recint ){
				# TODO: append zeros when gap is too large?
				$self->debug( "block end at ". $r->stime 
					.", actually dropping ". $dur ."sec data");
				@merge = ();
				$dur = 0;
			}
		}

		push @merge, $r;
		$dur += $r->dur;
	}

	# merge
	my $agg = Workout::Chunk::merge( @merge );

	# split
	my( $o, $q ) = $agg->split( $agg->stime + $self->recint );
	push @{$self->{queue}}, $q;
	$o->prev( $self->last );

	return $o;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
