package Workout::Chart;
use strict;
use warnings;
use base 'MyChart';
use Carp;
use MyChart::Source::Workout;

our %color = (
	ele	=> [qw/ 1 1 0 /], # yellow
	spd	=> [qw/ 0 1 1 /], # cyan
	hr	=> [qw/ 1 0 0 /], # red
	cad	=> [qw/ 0 0 1 /], # blue
	pwr	=> [qw/ 0 1 0 /], # green
);

# TODO: marker

sub new {
	my( $proto, $a ) = @_;

	my $self = $proto->SUPER::new({
		margin_t	=> 8, # for testing
		margin_l	=> 8, # for testing
		margin_b	=> 8, # for testing
		margin_r	=> 8, # for testing
		plot_box	=> 0,

		( $a ? %$a : ()),

		source		=> [],		# workouts
		color		=> { %color },	# plot colors
		line_style	=> 0,		# per workout line_style
	});

	# TODO: make tics configurable
	# TODO: make default min/max configurable

	my @orient = (0,1); # for testing
	#@orient = reverse @orient; # for testing
	$self->add_scale(

		# bottom axis
		time	=> {
			# bind to axis:
			orientation	=> $orient[0],
			position	=> 1, # 0, 1, 2, undef

			# scaling
			min		=> undef,
			max		=> undef,

			# tics, labels
			label_fmt	=> sub { 
				DateTime->from_epoch(
					epoch		=> $_[0],
					time_zone	=> 'local',
				)->strftime( '%H:%M' );
			},
			scale_label	=> 'Time (hh:mm)',

			#invert		=> 1, # for testing
			#label_rotate	=> 1, # for testing
			#grid		=> 1, # for testing
		},

		# left axis
		pwr	=> {
			position	=> 1,
			min		=> 0,
			max		=> 600,
			#tic_step	=> 25,
			label_fmt	=> '%d',
			label_fg	=> $self->{color}{pwr},
			scale_label_fg	=> $self->{color}{pwr},
			scale_label	=> 'Power (W)',

			#grid		=> 1, # for testing
		},
		spd	=> {
			position	=> 1,
			min		=> 0,
			max		=> 60,
			tic_step	=> 5,
			label_fmt	=> '%d',
			label_fg	=> $self->{color}{spd},
			scale_label_fg	=> $self->{color}{spd},
			scale_label	=> 'Speed (km/h)',
		},

		# right axis
		hr	=> {
			#invert		=> 1, # for testing
			orientation	=> $orient[1], # for testing
			position	=> 2,
			min		=> 40,
			max		=> 200,
			#tic_at		=> [    0,  120,  135, 145, 165, 180, 220 ],
			#label_fmt	=> [qw/ low rekom ga1  ga2  eb   sb   hai/],
			#tic_step	=> 10,
			label_fmt	=> '%d',
			label_fg	=> $self->{color}{hr},
			scale_label_fg	=> $self->{color}{hr},
			scale_label	=> 'Heartrate (1/min)',
		},
		cad	=> {
			position	=> 2,
			min		=> 40,
			max		=> 200,
			tic_step	=> 10,
			label_fmt	=> '%d',
			label_fg	=> $self->{color}{cad},
			scale_label_fg	=> $self->{color}{cad},
			scale_label	=> 'Cadence (1/min)',

			#label_rotate	=> 1, # for testing
		},

		# hidden vertical axis
		ele	=> {
			position	=> undef,
			label_fmt	=> '%.1f',
			label_fg	=> $self->{color}{ele},
			scale_label_fg	=> $self->{color}{ele},
			scale_label	=> 'Elevation (m)',
		},
	);

	$self;
}

sub add_workout {
	my( $self, $wk, $fields ) = @_;

	my $s = MyChart::Source::Workout->new( $wk );
	$fields ||= [qw/ ele spd cad hr pwr /];

	my $sourcecount = @{$self->{source}};
	my $suffix = $sourcecount ? " $sourcecount" : '';

	# ele
	$self->add_plot({
		legend	=> 'Elevation'. $suffix,
		xscale	=> 'time',
		yscale	=> 'ele',
		type	=> 'Area',
		source	=> $s,
		xcol	=> 'time',
		ycol	=> 'ele',
		color	=> $self->{color}{ele},
	}) if grep { /^ele$/ } @$fields;

	# spd
	$self->add_plot({
		legend	=> 'Speed'. $suffix,
		ycol	=> 'spd',
		source	=> $s,
		color	=> $self->{color}{spd},
		line_style	=> $self->{line_style},
	}) if grep { /^spd$/ } @$fields;

	# cad
	$self->add_plot({
		legend	=> 'Cadence'. $suffix,
		ycol	=> 'cad',
		source	=> $s,
		color	=> $self->{color}{cad},
		line_style	=> $self->{line_style},
	}) if grep { /^cad$/ } @$fields;

	# hr
	$self->add_plot({
		legend	=> 'Heartrate'. $suffix,
		xcol	=> 'time',
		ycol	=> 'hr',
		source	=> $s,
		color	=> $self->{color}{hr},
		line_style	=> $self->{line_style},
	}) if grep { /^hr$/ } @$fields;

	# pwr
	$self->add_plot({
		legend	=> 'Power'. $suffix,
		ycol	=> 'pwr',
		source	=> $s,
		color	=> $self->{color}{pwr},
		line_style	=> $self->{line_style},
	}) if grep { /^pwr$/ } @$fields;

	++ $self->{line_style};

	push @{$self->{source}}, $s;
	$self->flush_bounds_all;
}

sub set_delta {
	my( $self, $srcid, $delta ) = @_;
	$self->{source}[$srcid]->set_delta( 'time', $delta );
	$self->flush_bounds('time');
}

sub draw_chart_bg {
	my( $self ) = @_;

	# TODO: draw hr or pwr based trainigs zones as background
	$self->SUPER::draw_chart_bg;
}

1;
