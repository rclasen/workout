package Workout::ChartDelta;
use strict;
use warnings;
use base 'MyChart';
use Carp;
use MyChart::Source::Workout;

sub new {
	my( $proto, $a ) = @_;

	my $self = $proto->SUPER::new({
		plot_box	=> 0,
		field		=> 'spd',

		( $a ? %$a : ()),

		source		=> [],		# workouts
	});

	# TODO: make tics configurable
	# TODO: make default min/max configurable


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

	if( $self->{field} eq 'pwr' ){
		$self->add_scale( pwr	=> {
			position	=> 1,
			min		=> 0,
			max		=> 600,
			tic_step	=> 50,
			label_fmt	=> '%d',
			scale_label	=> 'Power (W)',
		});

	} elsif( $self->{field} eq 'spd' ){
		$self->add_scale( spd	=> {
			position	=> 1,
			min		=> 0,
			max		=> 60,
			tic_num		=> 6,
			label_fmt	=> '%d',
			scale_label	=> 'Speed (km/h)',
		});

	} elsif( $self->{field} eq 'hr' ){
		$self->add_scale( hr	=> {
			position	=> 1,
			min		=> 40,
			max		=> 200,
			tic_at		=> [    0,  120,  135, 145, 165, 180, 220 ],
			label_fmt	=> [qw/ low rekom ga1  ga2  eb   sb   hai/],
			scale_label	=> 'Heartrate (1/min)',
		});

	} elsif( $self->{field} eq 'cad' ){
		$self->add_scale( cad	=> {
			position	=> 1,
			min		=> 40,
			max		=> 200,
			label_fmt	=> '%d',
			scale_label	=> 'Cadence (1/min)',
		});

	} elsif( $self->{field} eq 'ele' ){
		$self->add_scale( ele	=> {
			position	=> 1,
			label_fmt	=> '%.1f',
			scale_label	=> 'Elevation (m)',
		});

	} else {
		croak "invalid field: $self->{field}";
	}


	$self;
}

sub add_workout {
	my( $self, $wk ) = @_;

	my $s = MyChart::Source::Workout->new( $wk );

	my $sourcecount = @{$self->{source}};

	if( $self->{field} eq 'ele' ){
		$self->add_plot({
			legend	=> 'Elevation '. $sourcecount,
			source	=> $s,
			ycol	=> 'ele',
		});

	} elsif( $self->{field} eq 'spd' ){
		$self->add_plot({
			legend	=> 'Speed '. $sourcecount,
			ycol	=> 'spd',
			source	=> $s,
		});

	} elsif( $self->{field} eq 'cad' ){
		$self->add_plot({
			legend	=> 'Cadence '. $sourcecount,
			ycol	=> 'cad',
			source	=> $s,
		});

	} elsif( $self->{field} eq 'hr' ){
		$self->add_plot({
			legend	=> 'Heartrate '. $sourcecount,
			ycol	=> 'hr',
			source	=> $s,
		});

	} elsif( $self->{field} eq 'pwr' ){
		$self->add_plot({
			legend	=> 'Power '. $sourcecount,
			ycol	=> 'pwr',
			source	=> $s,
		});
	}

	push @{$self->{source}}, $s;
	$self->flush_bounds_all;
}

sub set_delta {
	my( $self, $srcid, $delta ) = @_;
	$self->{source}[$srcid]->set_delta( 'time', $delta );
	$self->flush_bounds('time');
}


1;
