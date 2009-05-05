package Workout::Chart::Workout;
use strict;
use warnings;
use base 'MyChart', 'Class::Accessor::Fast';
use Carp;
use Workout::Chart::Source;

our %color = (
	ele	=> [qw/ 1 1 0 /], # yellow
	spd	=> [qw/ 0 1 1 /], # cyan
	hr	=> [qw/ 1 0 0 /], # red
	cad	=> [qw/ 0 0 1 /], # blue
	pwr	=> [qw/ 0 1 0 /], # green
);

our %default = (
	xfield	=> 'time',
	fields	=> [qw/ ele spd cad hr pwr /],
);

__PACKAGE__->mk_ro_accessors( keys %default );

sub new {
	my( $proto, $a ) = @_;

	my $self = $proto->SUPER::new({
		plot_box	=> 0,

		%default,
		( $a ? %$a : ()),

		source		=> [],		# workouts
		color		=> { %color },	# plot colors
		line_style	=> 0,		# per workout line_style
	});

	# TODO: marker
	# TODO: make tics configurable
	# TODO: make default min/max configurable
	# TODO: tooltips with values under mouse cursor
	# TODO: fields total/last n sec: npwr, spd_av, pwr_av
	# TODO: sum fields: odo, work

	# bottom axis
	# TODO: alternative x-scales: time, dur_mov, odo, work
	if( $self->xfield eq 'time' ){
		$self->add_scale( time	=> {
			# bind to axis:
			orientation	=> 0,
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
		});

	#} elsif( self->xfield eq 'dur' ){

	} else {
		croak "ivalid xfield: ". $self->xfield;
	}

	#print  STDERR "fields: ", join(', ', @{$self->fields}),"\n";

	# left axis

	$self->add_scale( pwr	=> {
		position	=> 1,
		min		=> 0,
		max		=> 600,
		#tic_step	=> 25,
		label_fmt	=> '%d',
		label_fg	=> $self->{color}{pwr},
		scale_label_fg	=> $self->{color}{pwr},
		scale_label	=> 'Power (W)',
	}) if grep { /^pwr$/ } @{$self->fields};

	$self->add_scale( spd	=> {
		position	=> 1,
		min		=> 0,
		max		=> 60,
		tic_step	=> 5,
		label_fmt	=> '%d',
		label_fg	=> $self->{color}{spd},
		scale_label_fg	=> $self->{color}{spd},
		scale_label	=> 'Speed (km/h)',
	}) if grep { /^spd$/ } @{$self->fields};

	# right axis

	$self->add_scale( hr	=> {
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
	}) if grep { /^hr$/ } @{$self->fields};

	$self->add_scale( cad	=> {
		position	=> 2,
		min		=> 40,
		max		=> 200,
		tic_step	=> 10,
		label_fmt	=> '%d',
		label_fg	=> $self->{color}{cad},
		scale_label_fg	=> $self->{color}{cad},
		scale_label	=> 'Cadence (1/min)',
	}) if grep { /^cad$/ } @{$self->fields};

	# hidden vertical axis
	# TODO: change ele color based on slope in %
	$self->add_scale( ele	=> {
		position	=> undef,
		label_fmt	=> '%.1f',
		label_fg	=> $self->{color}{ele},
		scale_label_fg	=> $self->{color}{ele},
		scale_label	=> 'Elevation (m)',
	}) if grep { /^ele$/ } @{$self->fields};

	# TODO: fields: temp, torque, deconv, vspd, grad, accel
	foreach my $f ( @{ $self->fields} ){
		next if $f =~ /^(?:ele|spd|hr|cad|pwr)$/;
		print STDERR "adding non-default scale: $f\n";

		$self->add_scale( $f	=> {
			scale_label	=> $f,
		});
	};
	$self;
}

sub add_workout {
	my( $self, $wk, $fields ) = @_;

	$fields ||= $self->fields;
	my $s = Workout::Chart::Source->new( $wk, $fields );

	my $sourcecount = @{$self->{source}};
	my $suffix = $sourcecount ? " $sourcecount" : '';

	# ele
	$self->add_plot({
		legend	=> 'Elevation'. $suffix,
		#xscale	=> 'time',
		yscale	=> 'ele',
		type	=> 'Area',
		source	=> $s,
		#xcol	=> 'time',
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
		#xcol	=> 'time',
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

	foreach my $f ( @{ $self->fields} ){
		next if $f =~ /^(?:ele|spd|hr|cad|pwr)$/;
		print STDERR "adding non-default plot: $f\n";

		$self->add_plot( {
			label	=> $f,
			ycol	=> $f,
			source	=> $s,
			line_style	=> $self->{line_style},
		});
	};

	++ $self->{line_style};

	push @{$self->{source}}, $s;
}

sub set_delta {
	my( $self, $srcid, $delta ) = @_;
	$self->{source}[$srcid]->set_delta( $self->xfield, $delta );
	$self->flush_bounds($self->xfield); # TODO: move to source
}

sub draw_chart_bg {
	my( $self ) = @_;

	# TODO: draw hr or pwr based trainigs zones as background
	$self->SUPER::draw_chart_bg;
}

1;
