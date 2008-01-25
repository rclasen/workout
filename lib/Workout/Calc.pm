=head1 NAME

Workout::Calc - helper functions for calculating workout data fields

=head1 SYNOPSIS

  $calc = Workout::Calc->new;
  $src = Workout::Store::SRM->new( "foo.srm", { calc => $calc } );
  ...

=head1 DESCRIPTION

Common algorithms to calculate Chunk data from other fields, the
difference to the previous Chunk or some global parameters.

=cut

package Workout::Calc;

use 5.008008;
use strict;
use warnings;
use Carp;
use Geo::Distance;
use Workout::Athlete;

our $VERSION = '0.01';

=head2 new( $arg )

new Workout data calculator

=cut

sub new {
	my( $class, $a ) = @_;

	my $self = bless {
		athlete	=> $a->{athlete} || Workout::Athlete->new,
	}, $class;

	$self;
}

=head2 athlete

set/get the athlete handle to retrieve data for calculations from.

=cut

sub athlete {
	my $self = shift;
	
	if( @_ ){
		$self->{athlete} = $_[0];
		return $self;
	}
	return $self->{athlete};
}

=head2 data access

calculate the Chunk field named by the method.

=item dur( $this, $last )
=item time( $this, $last )
=item climb( $this, $last )
=item inline( $this, $last )
=item xdist( $this, $last )
=item dist( $this, $last )
=item odo( $this, $last )
=item grad( $this, $last )
=item angle( $this, $last )
=item spd( $this, $last )
=item work( $this, $last )
=item pwr( $this, $last )

=cut

sub dur {
	my( $self, $this, $last ) = @_;

	if( defined $this->{dur} ){
		return $this->{dur};

	} elsif( defined $this->{time} 
		&& defined $last 
		&& defined $last->{time} ){

		return $this->{time} - $last->{time};
	}
	return;
}

sub time {
	my( $self, $this, $last ) = @_;

	if( defined $this->{time} ){
		return $this->{time};

	} elsif( defined $this->{dur} 
		&& defined $last 
		&& defined $last->{time} ){

		return $last->{time} + $this->{dur};
	}
	return;
}

sub climb {
	my( $self, $this, $last ) = @_;

	if( defined $this->{climb} ){
		return $this->{climb};

	} elsif( defined $this->{ele} 
		&& defined $last 
		&& defined $last->{ele} ){

		return $this->{ele} - $last->{ele};
	}
	return;
}

sub inline {
	my( $self, $this, $last ) = @_;

	if( defined $this->{incline} ){
		return $this->{incline};

	} elsif( defined $this->{climb} 
		&& defined $last 
		&& defined $last->{incline} ){

		$this->{incline} = $last->{incline};
		$this->{incline} += $this->{climb} if $this->{climb} > 0;
	}
	return;
}

sub _geocalc {
	my( $self ) = @_;

	$self->{geocalc} ||= new Geo::Distance;
}

sub xdist {
	my( $self, $this, $last ) = @_;

	if( defined $this->{xdist} ){
		return $this->{xdist};

	} elsif( defined $this->{lon} 
		&& defined $this->{lat}
		&& defined $last 
		&& defined $last->{lon} 
		&& defined $last->{lat} ){

		return $self->_geocalc->distance( 'meter', 
			$last->{lon}, $last->{lat},
			$this->{lon}, $this->{lat} );

	} elsif( defined $this->{dist} 
		&& defined $this->{climb} ){
	
		return sqrt( $this->{dist}**2 
			- $this->{climb}**2 );

	}
	return;
}

sub dist {
	my( $self, $this, $last ) = @_;

	if( defined $this->{dist} ){
		return $this->{dist};

	} elsif( defined $this->{xdist} 
		&& defined $this->{climb} ){

		return sqrt( $this->{xdist}**2 
			+ $this->{climb}**2 );

	} elsif( defined $this->{dur} 
		&& defined $this->{spd} ){

		return $this->{spd} * $this->{dur};

	} elsif( defined $this->{odo} 
		&& defined $last 
		&& defined $last->{odo} ){

		return $this->{odo} - $last->{odo};
	}
	return;
}

sub odo {
	my( $self, $this, $last ) = @_;

	if( defined $this->{odo} ){
		return $this->{odo};

	} elsif( defined $this->{dist} 
		&& defined $last 
		&& defined $last->{odo} ){

		return $last->{odo} + $this->{dist};
	}
	return;
}

sub grad {
	my( $self, $this, $last ) = @_;

	if( defined $this->{grad} ){
		return $this->{grad};

	} elsif( defined $this->{climb}
		&& defined $this->{xdist} 
		&& $this->{xdist} ){

		return 100 * $this->{climb} / $this->{xdist};
	}
	return;
}

sub angle {
	my( $self, $this, $last ) = @_;

	if( defined $this->{angle} ){
		return $this->{angle};

	} elsif( defined $this->{xdist} 
		&& defined $this->{climb} ){

		return atan2($this->{climb},$this->{xdist});
	}
	return;
}

sub spd {
	my( $self, $this, $last ) = @_;

	if( defined $this->{spd} ){
		return $this->{spd};

	} elsif( defined $this->{dur} 
		&& $this->{dur}
		&& defined $this->{dist} ){

		return $this->{dist}/$this->{dur};
	}
	return;
}

sub work {
	my( $self, $this, $last ) = @_;

	if( defined $this->{work} ){
		return $this->{work};

	} elsif( defined $this->{pwr} 
		&& defined $this->{dur} ){
	
		return $this->{pwr} * $this->{dur};

	} elsif( defined $this->{angle} 
		&& defined $this->{spd} ){

		return; # TODO calc work
	}
	return;
}

sub pwr {
	my( $self, $this, $last ) = @_;

	if( defined $this->{pwr} ){
		return $this->{pwr};

	} elsif( defined $this->{work} 
		&& defined $this->{dur} 
		&& $this->{dur} ){
	
		return $this->{work} / $this->{dur};
	}
	return;
}

# sub set { # TODO
#	my( $self, $this, $last, @cols ) = @_;
#}

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
