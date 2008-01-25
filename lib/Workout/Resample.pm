package Workout::Resample;

=head1 NAME

Workout::Resample - Resample Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->new( "foo.srm" );
  $new = Workout::Resample->new( $src, { recint => 10 } );
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
use base 'Workout::Iterator';
use Carp;

our $VERSION = '0.01';


# TODO: allow to supply start time

=head2 new( $src, $arg )

new Iterator

=cut

sub new {
	my( $class, $src, $a ) = @_;
	my $self = $class->SUPER::new( $src, $a );
	$self->{recint} = $a->{recint} || 5;
	$self->{agg} = {};
	$self->{last} = undef;
	$self;
}

=head2 recint

return recording/sampling interval in use

=cut

sub recint {
	my( $self ) = @_;
	$self->{recint};
}

=head2 next

return next (resampled) data chunk

=cut

sub next {
	my( $self ) = @_;

	my $a = $self->{agg};

	# aggregate data
	while( ! $a || ! exists $a->{dur} || $a->{dur} < $self->recint ){
		my $r = $self->src->next or return;
		$a->{dur} ||= 0;

		#my $s = { %$a };
		#print "reading chunk ", ++$icnt, "\n";
		#print "-";

		my $ndur = $a->{dur} + $r->{dur};
		foreach my $f ($self->store->fields_span(qw(chunkv)) ){
			if( exists $r->{$f} ){
				$a->{$f} = ( ($a->{$f}||0) * $a->{dur} 
					+ $r->{$f} * $r->{dur}) / $ndur;
			} else {
				delete $a->{$f};
			}
		}

		foreach my $f ($self->store->fields_span(qw(chunk)) ){
			if( exists $r->{$f} ){
				$a->{$f} += $r->{$f};
			} else {
				delete $a->{$f};
			}
		}

		foreach my $f ($self->store->fields_span(qw( trip abs geo)) ){
			if( exists $r->{$f} ){
				$a->{$f} = $r->{$f};
			} else {
				delete $a->{$f};
			}
		}

		#print "aggregated: ", Data::Dumper->Dump( [$s, $r, $a],[qw(s r a)] );
	}


	my $o; # new outuput entry
	#print "writing chunk ", ++$ocnt, "\n";
	#print "+";

	#my $s = { %$a };

	foreach my $f ($self->store->fields_span(qw(chunkv)) ){
		next unless exists $a->{$f};
		$o->{$f} = $a->{$f};
	}

	my $opart = $self->recint / $a->{dur};
	foreach my $f ($self->store->fields_span(qw(chunk)) ){
		next unless exists $a->{$f};
		$o->{$f} = $opart * $a->{$f};
		$a->{$f} -= $o->{$f};
	}

	my $l = $self->{last};
	$l->{time} ||= $a->{time} - $a->{dur};
		
	foreach my $f ($self->store->fields_span(qw(trip abs)) ){
		next unless exists $a->{$f};
		$l->{$f} ||= $a->{$f};
		my $d = $a->{$f} - $l->{$f};
		$o->{$f} = $l->{$f} + $opart * $d;
	}

	# TODO: @f_geo

	#print "split: ", Data::Dumper->Dump( [$l, $s, $o, $a], [qw(l s o a)] );
	$self->{last} = $o;
	return $o;
}


1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
