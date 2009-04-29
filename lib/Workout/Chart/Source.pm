package Workout::Chart::Source;
use warnings;
use strict;
use base 'MyChart::Source';

# TODO: move to workout package

# setup data source
sub new {
	my( $proto, $wk, $ds ) = @_;

	my $self = $proto->SUPER::new;
	$self->set_workout( $wk, $ds ) if $wk;
	$self;
}

sub set_workout {
	my( $self, $wk, $ds ) = @_;

	my @ds = $ds ? @$ds : qw/ ele spd hr cad pwr /;
	unshift @ds, 'time';
	print STDERR "Workout->chart: @ds\n";

	my @dat;
	my %min;
	my %max;

	my $iter = $wk->isa( 'Workout::Iterator' )
		? $wk
		: $wk->iterate;

	while( my $c = $iter->next ){
		my %r;
		foreach( @ds ){
			$r{$_} = $c->$_;
			next unless defined $r{$_};

			if( $_ eq 'spd' ) {
				$r{$_} *= 3.6;
			}


			if( ! defined $max{$_} || $r{$_} > $max{$_} ){
				$max{$_} = $r{$_};
			}

			if( ! defined $min{$_} || $r{$_} < $min{$_} ){
				$min{$_} = $r{$_};
			}
		}

		push @dat, \%r;
	}	

	foreach( @ds ){
		$min{$_} ||= 0;
		$max{$_} ||= 0;
	}

	$self->set_data( \@dat, \%min, \%max );
}


1;
