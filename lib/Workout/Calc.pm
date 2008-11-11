=head1 NAME

Workout::Calc - helper functions for calculating workout data fields

=head1 SYNOPSIS

  $calc = Workout::Calc->new;
  $src = Workout::Store::SRM->read( "foo.srm", { calc => $calc } );
  ...

=head1 DESCRIPTION

Common algorithms to calculate Chunk data from other fields, the
difference to the previous Chunk or some global parameters.

=cut

package Workout::Calc;

use 5.008008;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Carp;
use Geo::Distance;
use Workout::Athlete;

our $VERSION = '0.01';

my $e = 2.718281;	# ()		Eulersche Zahl
my $rho_0 = 1.293;	# (kg/m³)	Luftdichte auf Meereshöhe bei 0° Celsius
my $P_0 = 101325;	# (Pa = kg/(ms²)) Luftdruck auf Meereshöhe bei 0° Celsius
my $g = 9.81; 		# (m/s²)	Erdbeschleunigung
my $kelvin = 273.15;

# TODO: use vertmax=elef, elefuz=climb, accelmax,ravg=spd, spdmin=moving
# TODO: calc vspd

my %defaults = (
	vspdmax	=> 4,		# (m/s)		maximum vertical speed
	gradmax => 40,		# (%)           maximum gradient/slope
	accelmax => 6,		# (m/s²)	maximum acceleration
	elefuzz	=> 7,		# (m)		minimum elevatin change threshold
	spdmin	=> 1,		# (m/s)		minimum speed
	pwrmin	=> 40,		# (W)
	#A 	 		# (m²)		Gesamt-Stirnfläche (Rad + Fahrer)
	#Cw 	 		# ()		Luftwiderstandsbeiwert
	#CwA	=> 0.3207;	# (m²)		$Cw * $A für unterlenker
	CwA	=> 0.4764,	# (m²)		$Cw * $A für oberlenker
	Cr	=> 0.006,	# ()		.005 - .009 Rollwiderstandsbeiwert
	Cm	=> 1.06, 	# ()		1.03 - 1.09 Mechanische Verluste
	weight	=> 11, 		# (kg)		Equipment weight 
	atemp	=> 19,		# (°C)		Temperatur
	wind	=> 0,		# (m/s)		Windgeschwindigkeit
);

__PACKAGE__->mk_accessors( keys %defaults );

=head2 new( $arg )

new Workout data calculator

=cut

sub new {
	my( $class, $a ) = @_;

	my $self = bless {
		%defaults,
		athlete	=> $a->{athlete} || Workout::Athlete->new,
	}, $class;

        foreach my $f ( keys %$a ){
		$self->$f( $a->{$f} ) if $self->can($f);
	}

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
=item xdist( $this, $last )
=item dist( $this, $last )
=item grad( $this, $last )
=item angle( $this, $last )
=item spd( $this, $last )
=item accel( $this, $last )
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

	# TODO: use elefuzz
	} elsif( defined $this->{ele} 
		&& defined $last 
		&& defined $last->{ele} ){

		return $this->{ele} - $last->{ele};
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

sub accel {
	my( $self, $this, $last ) = @_;

	if( defined $this->{accel} ){
		return $this->{accel};

	} elsif( defined $this->{spd} 
		&& $this->{dur}
		&& defined $last->{spd} ){

		return ($this->{spd}-$last->{spd}) / $this->{dur};
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
		&& defined $this->{spd} 
		&& defined $this->{dist} ){

		my $ele = $this->{ele} ||0;

		# intermediate results for power
		my $rho = ($kelvin / ($kelvin +$self->atemp)) * $rho_0 * 
			$e^(($ele * $rho_0 * $g) / $P_0);
		my $Fstg = ($self->weight + $self->athlete->weight) * $g * ( 
			$self->Cr * cos($this->{angle}) + sin($this->{angle}));
		my $op1 = $self->CwA * $rho * ($this->{spd} + $self->wind)^2 / 2;

		# final result
		return $self->Cm * $this->{dist} * ($op1 + $Fstg);
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

=head2 set( $this, $last, @fields )

calculate specified fields and set their value in $this

=cut

my @fields = qw( 
	climb
	xdist
	dist
	grad
	angle
	spd
	accel
	work
	pwr
);
sub set {
	my( $self, $this, $last, @want ) = @_;

	# TODO: respect calc. dependencies when differnet fields are available
	foreach my $f ( @fields ){
		#next unless @want # TODO
		next unless $self->can( $f );
		my $v = $self->$f( $this, $last );
		next unless defined $v;
		$this->{$f} = $v;
	}
}

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
