package Workout::Filter::Smooth;

=head1 NAME

Workout::Filter::Smooth - Smoothen Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "foo.srm" );
  $join = Workout::Filter::Smooth->new( $src );
  while( my $chunk = $join->next ){
  	# do something
  }

=head1 DESCRIPTION

Smoothens workout data while iterating.

=over 4

=item elevation 

limit changes by maximum vspeed.

=item speed

limit change by accelmax, rolling average.

=back

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

=head2 new( $src, $arg )

new iterator

=cut

sub new {
	my $class = shift;
	my $self = $class->SUPER::new( @_ );
	# TODO: split rolling average out into seperate filter
	$self->{ravg_num} = 3;
	$self->{ravg_hist} = [];
	$self->{ravg_keys} = [qw( spd )];
	$self->{last} = undef;
	$self->{cntspd} = 0;
	$self->{cntele} = 0;
	$self;
}

=head2 next

=cut

sub process {
	my( $self ) = @_;

	my $i = $self->_fetch
		or return;

	my $m = $i->clone;

die; # TODO: use ::Chunk
# TODO: block ends?

	# ele / vspdmax / gradmax
	if( defined $l && defined $l->{ele} && defined $m->{ele} ){
		my $max = $m->{dur} * $self->calc->vspdmax;
		if( defined $m->{xdist} ){
			my $gmax = $m->{xdist} * $self->calc->gradmax / 100;
			$max = $gmax if $gmax < $max;
		}

		if( abs($m->{climb}) > $max ){
			$self->{cntele}++;
			$m->{climb} = $max * abs($m->{climb})/$m->{climb};
			$m->{ele} = $l->{ele} + $m->{climb};
			$m->{grad} = $self->calc->grad( $m );
			$m->{angle} = $self->calc->angle( $m );
			if( exists $m->{lon} ){ # TODO: hack
				delete @$m{qw( spd dist )};
				$m->{dist} = $self->calc->dist( $m, $l );
			} else {
				delete @$m{qw( xdist )};
				$m->{xdist} = $self->calc->xdist( $m, $l );
			}
		}
	}

	$m->{dist} = $self->calc->dist( $m, $l );
	$m->{spd} ||= $self->calc->spd( $m, $l );
	$m->{accel} = $self->calc->accel( $m, $l );

	# speed / accelmax
	if( defined $l && defined $l->{spd} && defined $m->{spd} ){
		my $max = $self->calc->accelmax;

		if( abs($m->{accel}) > $max ){
			$self->{cntspd}++;
			$m->{accel} = $max * abs($m->{accel})/$m->{accel};
			$m->{spd} = $l->{spd} + $m->{accel} * $m->{dur};
		}
	}

	# rolling averages
	if( @{$self->{ravg_hist}} >= $self->{ravg_num} ){
		splice @{$self->{ravg_hist}}, $self->{ravg_num};
	}

	my $o = {%$m};
	foreach my $hist ( @{$self->{ravg_hist}} ){
		foreach my $k ( @{$self->{ravg_keys}} ){
			$o->{$k} += $hist->{$k} || 0;
		}
	};

	my $hnum = @{$self->{ravg_hist}} +1;
	foreach my $k ( @{$self->{ravg_keys}} ){
		$o->{$k} ||= 0;
		$o->{$k} /= $hnum;
	}

	unshift @{$self->{ravg_hist}}, $m;
	delete @$o{qw( accel )};
	$o->{accel} = $self->calc->accel( $m, $l );

	$self->{last} = $o;
	$o;
}

=head2 cntele

number of chunks where elevation was adjusted due to change limits

=cut

sub cntele {
	$_[0]->{cntele};
}

=head2 cntspd

number of chunks where speed was cut/limited

=cut

sub cntspd {
	$_[0]->{cntspd};
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
