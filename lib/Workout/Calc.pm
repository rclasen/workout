=head1 NAME

Workout::Calc - helper functions for calculating workout data fields

=head1 SYNOPSIS

# TODO synopsis

=head1 DESCRIPTION

Stub documentation for Workout::Calc, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=cut

package Workout::Calc;

use 5.008008;
use strict;
use warnings;
use Carp;
use Geo::Distance;

our $VERSION = '0.01';

sub new {
	my( $class, $a ) = @_;

	my $self = bless {
	}, $class;

	$self;
}

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
