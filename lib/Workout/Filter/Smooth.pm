package Workout::Filter::Smooth;

=head1 NAME

Workout::Filter::Smooth - Smoothen Workout data

=head1 SYNOPSIS

  $src = Workout::Store::SRM->new( "foo.srm" );
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
	$self->{ravg_num} = 3;
	$self->{ravg_hist} = [];
	$self->{ravg_keys} = [qw( spd )];
	$self->{last} = undef;
	$self->{lele} = undef;
	$self->{lspd} = undef;
	$self;
}

=head2 next

=cut

sub next {
	my( $self ) = @_;

	my $i = $self->src->next;
	defined $i or return;

	my $m = {%$i};
	$self->calc->set( $m, $self->{last} );
	$self->{last} = $m;

	# speed / accelmax
	if( defined $self->{lspd} && defined $m->{spd} ){
		my $accel = $m->{spd} - $self->{lspd};
		my $max = $m->{dur} * $self->calc->accelmax;

		if( abs($accel) > $max ){
			$m->{spd} = $self->{lspd} + $max * abs($accel)/$accel;
		}
	}
	$self->{lspd} = $m->{spd};

	# ele / vspdmax
	if( defined $self->{lele} && defined $m->{ele} ){
		my $climb = $m->{ele} - $self->{lele};
		my $max = $m->{dur} * $self->calc->vspdmax;

		if( abs($climb) > $max ){
			$m->{ele} = $self->{lele} + $max * abs($climb)/$climb;
		}
	}
	$self->{lele} = $m->{ele};

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

	$o;
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
