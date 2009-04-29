package Workout::Chart::Source;
use warnings;
use strict;
use base 'MyChart::Source';

# TODO: move to workout package

# setup data source
sub new {
	my( $proto, $wk, @ds ) = @_;

	my $self = $proto->SUPER::new;
	$self->set_workout( $wk, @ds ) if $wk;
	$self;
}

sub set_workout {
	my( $self, $wk, @ds ) = @_;

	@ds or @ds = qw/ ele spd hr cad pwr /;
	unshift @ds, 'time';

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
			if( $_ eq 'spd' && defined $r{$_} ) {
				$r{$_} *= 3.6;
			}

			next unless defined $r{$_};

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
