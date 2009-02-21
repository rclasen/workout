package Workout::GtkChartDelta;
use strict;
use warnings;
use Carp;
use Glib qw/ TRUE FALSE /;
use Gtk2;
use Workout;
use Workout::ChartDelta;
use MyChart::Gtk;


use Glib::Object::Subclass
	'MyChart::Gtk',
#	properties => [ # TODO
#		field	=>,
#	],
;

sub INIT_INSTANCE {
	my $self = shift;

	$self->{chart_class} = 'Workout::ChartDelta';
	# TODO: adjust chart_defaults 
}

sub set_delta {
	my $self = shift;

	# TODO: use GtkAdjustment?
	$self->chart->set_delta( @_ );

	$self->queue_redraw;
}

sub add_workout {
	my( $self, $wk, $fields ) = @_;

	$self->chart->add_workout( $wk, $fields );

	$self->queue_redraw;
}



1;
