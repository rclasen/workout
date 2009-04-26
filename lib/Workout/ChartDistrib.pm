package Workout::ChartDistrib;
use strict;
use warnings;
use base 'MyChart';
use Carp;
use MyChart::Source;

our %color = (
	spd	=> [qw/ 0 1 1 /], # cyan
	hr	=> [qw/ 1 0 0 /], # red
	cad	=> [qw/ 0 0 1 /], # blue
	pwr	=> [qw/ 0 1 0 /], # green
);


sub new {
	my( $proto, $a ) = @_;

	my $self = $proto->SUPER::new({
		plot_box	=> 0,

		( $a ? %$a : ()),

		color		=> { %color },	# plot colors
		source		=> [],		# workouts
	});

	# TODO: make tics configurable
	# TODO: make default min/max configurable

	$self->add_scale( dur	=> {
		# bind to axis:
		orientation	=> 0,
		position	=> 1, # 0, 1, 2, undef

		# scaling
		min		=> undef,
		max		=> undef,

		# tics, labels
		label_fmt	=> sub { 
			sprintf( '%d:%02d:%02d', 
				$_[0]/3600, 
				($_[0] % 3600) / 60, 
				$_[0]%60 );
		},
		scale_label	=> 'Time (hh:mm::ss)',
	},

	# left axis
	pwr	=> {
		position	=> 1,
		min		=> 50,
		max		=> 300,
		#tic_step	=> 25,
		label_fmt	=> '%d',
		label_fg	=> $self->{color}{pwr},
		scale_label_fg	=> $self->{color}{pwr},
		scale_label	=> 'Power (W)',
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
		position	=> 2,
		min		=> 80,
		max		=> 170,
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
		max		=> 120,
		tic_step	=> 10,
		label_fmt	=> '%d',
		label_fg	=> $self->{color}{cad},
		scale_label_fg	=> $self->{color}{cad},
		scale_label	=> 'Cadence (1/min)',
	});

	$self;
}

sub add_workout {
	my( $self, $wk, $fields ) = @_;

	$fields ||= [qw/ spd cad hr pwr /];
	my @all = $wk->all;

	my %s;
	foreach my $f ( @$fields ){
		my( @list, $min, $max );

		my $dur = 0;
		foreach my $c ( sort {
				($b->$f || 0) <=> ($a->$f || 0);
		} @all ){

			my $v = $c->$f;
			next unless defined $v;
			if( $f eq 'spd' ){
				$v *= 3.6;
			}

			$dur += $c->dur;
			push @list, { 
				dur	=> $dur,
				$f	=> $v,
			};
			if( ! defined $min || $v < $min ){
				$min = $v;#
			}
			if( ! defined $max || $v > $max ){
				$max = $v;#
			}
		}

		$s{$f} = MyChart::Source->new({
			list	=> \@list,
			min	=> { 
				dur	=> 0,
				$f	=> $min,
			},
			max	=> {
				dur	=> $dur,
				$f	=> $max,
			},
		});
	};

	my $sourcecount = @{$self->{source}};

	if( grep { /^spd$/ } @$fields ){
		$self->add_plot({
			legend	=> 'Speed '. $sourcecount,
			ycol	=> 'spd',
			source	=> $s{spd},
			color	=> $self->{color}{spd},
		});
	}

	if( grep { /^cad$/ } @$fields ){
		$self->add_plot({
			legend	=> 'Cadence '. $sourcecount,
			ycol	=> 'cad',
			source	=> $s{cad},
			color	=> $self->{color}{cad},
		});
	}

	if( grep { /^hr$/ } @$fields ){
		$self->add_plot({
			legend	=> 'Heartrate '. $sourcecount,
			ycol	=> 'hr',
			source	=> $s{hr},
			color	=> $self->{color}{hr},
		});
	}

	if( grep { /^pwr$/ } @$fields ){
		$self->add_plot({
			legend	=> 'Power '. $sourcecount,
			ycol	=> 'pwr',
			source	=> $s{pwr},
			color	=> $self->{color}{pwr},
		});
	}

	push @{$self->{source}}, \%s;
	$self->flush_bounds_all;
}


1;
