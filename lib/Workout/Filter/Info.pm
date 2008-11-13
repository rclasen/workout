=head1 NAME

Workout::Filter::Info - collect info about the workout

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = Workout::Filter::Info->new( $src->iterate );
  Workout::Store::Null->new->from( $it );
  print $it->dur;

=head1 DESCRIPTION

Base Class for modifying and filtering the Chunks of a Workout.

=cut

package Workout::Filter::Info;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

our %default = (
	vspdmax	=> 4,		# (m/s)		maximum vertical speed
	gradmax => 40,		# (%)           maximum gradient/slope
	accelmax => 6,		# (m/s²)	maximum acceleration
	elefuzz	=> 7,		# (m)		minimum elevatin change threshold
	spdmin	=> 1,		# (m/s)		minimum speed
	pwrmin	=> 40,		# (W)
);

our %init = (
	chunk_first	=> undef,
	chunk_last	=> undef,
	lele	=> undef,
	dur_mov	=> 0,
	dur_cad	=> 0,
	dur_hr	=> 0,
	dist	=> 0,
	spd_max	=> 0,
	spd_max_time	=> undef,
	accel_max	=> 0,
	accel_max_time	=> undef,
	ele_min	=> undef,
	ele_max	=> 0,
	ele_max_time	=> undef,
	grad_max	=> 0,
	grad_max_time	=> undef,
	incline	=> 0,
	work	=> 0,
	pwr_max	=> 0,
	pwr_max_time	=> undef,
	hr_sum	=> 0,
	hr_max	=> 0,
	hr_max_time	=> undef,
	cad_sum	=> 0,
	cad_max	=> 0,
	cad_max_time	=> undef,
);

__PACKAGE__->mk_accessors( keys %default );
__PACKAGE__->mk_ro_accessors( keys %init );



=head2 new( $iter, $arg )

create empty Iterator.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a||={};
	$class->SUPER::new( $iter, { 
		%default, 
		%$a, 
		%init,
	});
}

sub set_min {
	my( $self, $field, $ck ) = @_;

	my $val = $ck->$field;
	defined $val or return;

	my $fn = $field .'_min';
	if( ! defined $self->{$fn} || $self->{$fn} > $val ){
		$self->{$fn} = $val;
		$self->{"${fn}_time"} = $ck->time;
	}
}

sub set_max {
	my( $self, $field, $ck ) = @_;

	my $val = $ck->$field;
	defined $val or return;

	my $fn = $field .'_max';
	if( $self->{$fn} < $val ){
		$self->{$fn} = $val;
		$self->{"${fn}_time"} = $ck->time;
	}
}

sub process {
	my( $self ) = @_;

	my $d = $self->_fetch
		or return;

	$self->{chunk_first} ||= $d;
	$self->{chunk_last} = $d;

	$self->{dist} += $d->dist ||0;

	if( $d->ele ){
		if( defined $self->{lele} ){
			my $climb = $d->ele - $self->{lele};
			# TODO: better fix climb calculation in Calc.pm

			if( abs($climb) >= $self->elefuzz ){
				$self->{lele} = $d->ele;
				if( $climb > 0 ){
					$self->{incline} += $climb;
				}
			}

		} else {
			$self->{lele} = $d->ele;
		}
	}

	if( (my $work = $d->work||0) > 0 ){
		$self->{work} += $work;
	}

	$self->set_max( 'pwr', $d );

	if( ($d->pwr||0) > $self->pwrmin
		|| ($d->spd||0) > $self->spdmin ){

		$self->{dur_mov} += $d->dur;
		if( my $hr = $d->hr ){
			$self->{dur_hr} += $d->dur;
			$self->{hr_sum} += $hr * $d->dur;
		}
	}
	if( my $cad = $d->cad ){
		$self->{dur_cad} += $d->dur;
		$self->{cad_sum} += $cad * $d->dur;
	}

	$self->set_max( 'hr', $d );
	$self->set_max( 'cad', $d );
	$self->set_max( 'spd', $d );
	$self->set_max( 'accel', $d );
	$self->set_min( 'ele', $d );
	$self->set_max( 'ele', $d );
	$self->set_max( 'grad', $d );

	$d;
}

sub time_start {
	my( $self ) = @_;

	my $c = $self->chunk_first
		or return;
	$c->time - $c->dur;
}

sub time_end {
	my( $self ) = @_;

	my $c = $self->chunk_last
		or return;
	$c->time;
}

sub dur {
	my( $self ) = @_;

	my $s = $self->time_start
		or return;
	my $e = $self->time_end
		or return;

	$e - $s;
}

sub dur_creep {
	my( $self ) = @_;

	my $t = $self->dur
		or return;

	$t - $self->dur_mov;
}

sub hr_avg {
	my( $self ) = @_;
	my $d = $self->dur_hr ||$self->dur
		or return;
	$self->hr_sum / $d;
}

sub cad_avg {
	my( $self ) = @_;
	my $d = $self->dur_cad || $self->dur
		or return;
	$self->cad_sum / $d;
}

sub ele_start {
	my( $self ) = @_;

	my $s = $self->chunk_first
		or return;
	$s->ele;
}

sub spd_avg {
	my( $self ) = @_;
	my $d = $self->dur_mov
		or return;
	$self->dist / $d;
}

sub pwr_avg {
	my( $self ) = @_;

	my $dur = $self->dur_mov || $self->dur
		or return;

	$self->work / $dur;
}

1;

