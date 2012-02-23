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
	grad	=> [qw/ 1 0 1 /], # purple
);

our %default = (
	xfield	=> 'time',
	fields	=> { map { $_ => {} } [qw/ ele spd cad hr pwr /] },
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

	my $t = $self->fields;

	# TODO: marker
	# TODO: make tics configurable
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
		min		=> exists $t->{pwr}{min}
			? $t->{pwr}{min} : 0,
		max		=> exists $t->{pwr}{max}
			? $t->{pwr}{max} : 600,
		tic_step	=> exists $t->{pwr}{tic_step}
			? $t->{pwr}{tic_step} : 50,
		tic_num		=> exists $t->{pwr}{tic_num}
			? $t->{pwr}{tic_num} : undef,
		tic_at		=> exists $t->{pwr}{tic_at}
			? $t->{pwr}{tic_at} : undef,
		label_fmt	=> exists $t->{pwr}{label_fmt}
			? $t->{pwr}{label_fmt} : '%d',
		label_fg	=> $self->{color}{pwr},
		scale_label_fg	=> $self->{color}{pwr},
		scale_label	=> 'Power (W)',
	}) if $t->{pwr};

	$self->add_scale( spd	=> {
		position	=> 1,
		min		=> exists $t->{spd}{min}
			? $t->{spd}{min} : 0,
		max		=> exists $t->{spd}{max}
			? $t->{spd}{max} : 60,
		tic_step	=> exists $t->{spd}{tic_step}
			? $t->{spd}{tic_step} : 5,
		tic_num		=> exists $t->{spd}{tic_num}
			? $t->{spd}{tic_num} : undef,
		tic_at		=> exists $t->{spd}{tic_at}
			? $t->{spd}{tic_at} : undef,
		label_fmt	=> exists $t->{spd}{label_fmt}
			? $t->{spd}{label_fmt} : '%d',
		label_fg	=> $self->{color}{spd},
		scale_label_fg	=> $self->{color}{spd},
		scale_label	=> 'Speed (km/h)',
	}) if $t->{spd};

	$self->add_scale( grad	=> {
		position	=> 1,
		min		=> exists $t->{grad}{min}
			? $t->{grad}{min} : 0,
		max		=> exists $t->{grad}{max}
			? $t->{grad}{max} : 20,
		tic_step	=> exists $t->{grad}{tic_step}
			? $t->{grad}{tic_step} : 2,
		tic_num		=> exists $t->{grad}{tic_num}
			? $t->{grad}{tic_num} : undef,
		tic_at		=> exists $t->{grad}{tic_at}
			? $t->{grad}{tic_at} : undef,
		label_fmt	=> exists $t->{grad}{label_fmt}
			? $t->{grad}{label_fmt} : '%d',
		label_fg	=> $self->{color}{grad},
		scale_label_fg	=> $self->{color}{grad},
		scale_label	=> 'Gradient (%)',
	}) if $t->{grad};

	# right axis

	$self->add_scale( hr	=> {
		position	=> 2,
		min		=> exists $t->{hr}{min}
			? $t->{hr}{min} : 40,
		max		=> exists $t->{hr}{max}
			? $t->{hr}{max} : 200,
		tic_step	=> exists $t->{hr}{tic_step}
			? $t->{hr}{tic_step} : undef,
		tic_num		=> exists $t->{hr}{tic_num}
			? $t->{hr}{tic_num} : undef,
		tic_at		=> exists $t->{hr}{tic_at}
			? $t->{hr}{tic_at} : undef,
		label_fmt	=> exists $t->{hr}{label_fmt}
			? $t->{hr}{label_fmt} : '%d',
		#tic_at		=> [    0,  120,  135, 145, 165, 180, 220 ],
		#label_fmt	=> [qw/ low rekom ga1  ga2  eb   sb   hai/],
		label_fg	=> $self->{color}{hr},
		scale_label_fg	=> $self->{color}{hr},
		scale_label	=> 'Heartrate (1/min)',
	}) if $t->{hr};

	$self->add_scale( cad	=> {
		position	=> 2,
		min		=> exists $t->{cad}{min}
			? $t->{cad}{min} : 40,
		max		=> exists $t->{cad}{max}
			? $t->{cad}{max} : 200,
		tic_step	=> exists $t->{cad}{tic_step}
			? $t->{cad}{tic_step} : 10,
		tic_num		=> exists $t->{cad}{tic_num}
			? $t->{cad}{tic_num} : undef,
		tic_at		=> exists $t->{cad}{tic_at}
			? $t->{cad}{tic_at} : undef,
		label_fmt	=> exists $t->{cad}{label_fmt}
			? $t->{cad}{label_fmt} : '%d',
		label_fg	=> $self->{color}{cad},
		scale_label_fg	=> $self->{color}{cad},
		scale_label	=> 'Cadence (1/min)',
	}) if $t->{cad};

	# hidden vertical axis
	# TODO: change ele color based on slope in %
	$self->add_scale( ele	=> {
		position	=> undef,
		min		=> exists $t->{ele}{min}
			? $t->{ele}{min} : undef,
		max		=> exists $t->{ele}{max}
			? $t->{ele}{max} : undef,
		tic_step	=> exists $t->{ele}{tic_step}
			? $t->{ele}{tic_step} : undef,
		tic_num		=> exists $t->{ele}{tic_num}
			? $t->{ele}{tic_num} : undef,
		tic_at		=> exists $t->{ele}{tic_at}
			? $t->{ele}{tic_at} : undef,
		label_fmt	=> exists $t->{ele}{label_fmt}
			? $t->{ele}{label_fmt} : '%.1f',
		label_fg	=> $self->{color}{ele},
		scale_label_fg	=> $self->{color}{ele},
		scale_label	=> 'Elevation (m)',
	}) if $t->{ele};

	# TODO: fields: temp, torque, deconv, vspd, grad, accel
	foreach my $f ( keys %$t ){
		next if $f =~ /^(?:ele|spd|hr|cad|pwr|grad)$/;
		print STDERR "adding non-default scale: $f\n";

		$self->add_scale( $f	=> {
			scale_label	=> $f,
			min		=> exists $t->{$f}{min}
				? $t->{$f}{min} : undef,
			max		=> exists $t->{$f}{max}
				? $t->{$f}{max} : undef,
			tic_step	=> exists $t->{$f}{tic_step}
				? $t->{$f}{tic_step} : undef,
			tic_num		=> exists $t->{$f}{tic_num}
				? $t->{$f}{tic_num} : undef,
			tic_at		=> exists $t->{$f}{tic_at}
				? $t->{$f}{tic_at} : undef,
			label_fmt	=> exists $t->{$f}{label_fmt}
				? $t->{$f}{label_fmt} : undef,
		});
	};
	$self;
}

sub add_workout {
	my( $self, $wk, $fields ) = @_;

	my $t = $fields
		? { map { $_ => {} } @$fields }
		: $self->fields;
	my $s = Workout::Chart::Source->new( $wk, [ keys %$t ] );

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
	}) if $t->{ele};

	# spd
	$self->add_plot({
		legend	=> 'Speed'. $suffix,
		ycol	=> 'spd',
		source	=> $s,
		color	=> $self->{color}{spd},
		line_style	=> $self->{line_style},
	}) if $t->{spd};

	# grad
	$self->add_plot({
		legend	=> 'Gradient'. $suffix,
		ycol	=> 'grad',
		source	=> $s,
		color	=> $self->{color}{grad},
		line_style	=> $self->{line_style},
	}) if $t->{grad};

	# cad
	$self->add_plot({
		legend	=> 'Cadence'. $suffix,
		ycol	=> 'cad',
		source	=> $s,
		color	=> $self->{color}{cad},
		line_style	=> $self->{line_style},
	}) if $t->{cad};

	# hr
	$self->add_plot({
		legend	=> 'Heartrate'. $suffix,
		#xcol	=> 'time',
		ycol	=> 'hr',
		source	=> $s,
		color	=> $self->{color}{hr},
		line_style	=> $self->{line_style},
	}) if $t->{hr};

	# pwr
	$self->add_plot({
		legend	=> 'Power'. $suffix,
		ycol	=> 'pwr',
		source	=> $s,
		color	=> $self->{color}{pwr},
		line_style	=> $self->{line_style},
	}) if $t->{pwr};

	foreach my $f ( keys %$t  ){
		next if $f =~ /^(?:ele|spd|hr|cad|pwr|grad)$/;
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
