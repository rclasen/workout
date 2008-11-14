package Workout::Filter::Pwr;

=head1 NAME

Workout::Filter::Pwr - Calculatate work/pwr from other data

=head1 SYNOPSIS

  $ath = Workout::Athlete->new;
  $src = Workout::Store::Gpx->read( "foo.gpx" );
  $pwr = Workout::Filter->new( $src, { athlete => $ath } );
  ...

=head1 DESCRIPTION


=cut


use strict;
use warnings;
use base 'Workout::Filter::Base';

our $VERSION = '0.01';

# constants:
my $e = 2.718281;	# ()		Eulersche Zahl
my $rho_0 = 1.293;	# (kg/m³)	Luftdichte auf Meereshöhe bei 0° Celsius
my $P_0 = 101325;	# (Pa = kg/(ms²)) Luftdruck auf Meereshöhe bei 0° Celsius
my $g = 9.81; 		# (m/s²)	Erdbeschleunigung
my $kelvin = 273.15;

my %defaults = (
	athlete	=> undef,
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


=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	$class->SUPER::new( $src, {
		%defaults,
		%$a,
	});
}

sub process {
	my $self = shift;

	my $i = $self->_fetch
		or return;

	my $o = $i->clone;
	$o->prev( $self->last );

	# check for available data
	return $o if defined $o->work;

	defined( my $angle = $o->angle )
		or return $o;
	defined( my $spd = $o->spd )
		or return $o;
	defined( my $dist = $o->dist )
		or return $o;
	my $ele = $o->ele ||0;


	# intermediate results for power
	my $rho = ($kelvin / ($kelvin +$self->atemp)) * $rho_0 * 
		$e^(($ele * $rho_0 * $g) / $P_0);
	my $Fstg = ($self->weight + $self->athlete->weight) * $g * ( 
		$self->Cr * cos($angle) + sin($angle));
	my $op1 = $self->CwA * $rho * ($spd + $self->wind)^2 / 2;

	# final result
	$o->work( $self->Cm * $dist * ($op1 + $Fstg) );

	$o;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
