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

__PACKAGE__->mk_accessors(qw(
	recint
));

=head2 new( $src, $arg )

new Iterator

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( $src, {
		recint	=> 5,
		%$a,
	});
	$self->{agg} = undef;
	$self->{prev} = undef;
	$self->{prev_in} = undef;
	$self;
}

=head2 recint

return recording/sampling interval in use

=cut

=head2 next

return next (resampled) data chunk

=cut

sub next {
	my( $self ) = @_;

	# aggregate data
	while( ! $self->{agg} 
		|| $self->{agg}->dur < $self->recint ){

		my $r = $self->src->next or return;
		$self->{cntin}++;

		my $l = $self->{prev_in};

		# new block? throw away collected data and restart
		my $ltime = $r->time - $r->dur;
		if( $l && abs($ltime - $l->time) > 0.1){
			$self->debug( "new block, resample reset" );
			$self->{agg} = $r;
			$self->{prev} = undef;
			$self->{prev_in} = undef;
			next;
		}

		#my $s = { %$a };
		#print "reading chunk ", ++$icnt, "\n";
		#print "-";

		if( ! $self->{agg} ){
			$self->{agg} = $r;

		} else {
			# TODO: if $r->dur + $agg->dur > recint, then
			# split before merge
			$self->{agg} = $self->{agg}->merge( $r );
		}
	}

	# TODO: fill with zeros when crossing inbound block boundaries
	# TODO: move to seperate moduule for reuse in Merge.pm

	my $o;
	( $o, $self->{agg} ) = $self->{agg}->split( $self->recint );
	$o->prev( $self->{prev} );

	#print "split: ", Data::Dumper->Dump( [$l, $s, $o, $a], [qw(l s o a)] );
	$self->{cntout}++;
	$self->{prev} = $o;
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
