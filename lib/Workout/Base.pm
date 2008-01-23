=head1 NAME

Workout::Base - Cycling Workout data

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::SRM->read( "input.srm" ); 
  # read Gpx file for elevation
  $ele = Workout::Gpx->read( "iele.gpx );
  # write to HRM file (one block) and different recint
  $dst = Workout::HRM->new( recint = 5 );

  $join = Workout::Join->src( $src );
  $res = Workout::Resample->src( $join, 
  	recint => $dst->recint ); # aggregate/split chunks
  $merge = Workout::Merge->src( $res, $ele ); # add ele info
  $conv = Workout::Recalc->src( $merge, 
  	fields => [ $dst->required ]  ); # calculate missing fields

  $dst->copy( $conv );

  # write
  open( F, "out.hrm" );
  $dst->write( \*F );


=head1 DESCRIPTION

Stub documentation for Workout::Resample, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=cut

package Workout::Base;

use 5.008008;
use strict;
use warnings;
use Carp;
use Geo::Distance;

our $VERSION = '0.01';

=pod

sampling interval data fields:

field	span	calc from	description

dur	chunk	time,p:time	duration (sec)
time	abs	p:time,dur	end date (sec. since epoch 1970-1-1)

hr	chunkv	-		heartrate, avg (1/min)
cad	chunkv	-		cadence, avg (1/min)

ele 	geo	-		elevation at end of interval (m)
climb	chunk	p:ele,ele	elevation change, abs (m)
incline	trip	p:incline,climb	cumulated positive climb, abs (m)

lon,lat	geo	-		GPS coordinates
xdist	chunk	geo,p:geo	2dimensional distance, abs (m)
		dist,climb
dist	chunk	dur,spd		distance, abs (m)
		xdist,climb
		p:odo,odo
odo	trip	p:odo,dist	cumulated distance, abs, (m)

grad	chunk	xdist,climb	gradient, avg (%)

spd 	chunkv	dur,dist	speed, avg (m/sec)

work	chunk	pwr,dur		total, (Joule)
		angle,speed,..(guess)
pwr 	chunkv	dur,work	power, avg (watt)

pbal		-		pedal balance (?,polar)
pidx		-		pedal index (?,polar)
apres		-		air pressure, avg (?,polar)



span:
- abs		momentary snapshot of value at chunks' end
- geo		momentary snapshot of geographic position at chunks' end
- chunk		delta during chunk
- chunkv	average of chunk's period
- trip		cumulated value for whole trip


=cut

# Not a method
sub _new_array_iterator {
    my $arr = shift || [];    # array ref

    unless ( defined( $arr ) ) {
        return sub {
            return;
        };
    }

    my $max = scalar( @{$arr} );
    my $pos = 0;
    return sub {
        return if $pos >= $max;
        return $arr->[ $pos++ ];
    };
}

# Not a method
sub _new_iter_iterator {
    my @its = @_;
    return sub {
        for ( ;; ) {
            return undef unless @its;
            my $next = $its[0]->();
            return $next if defined( $next );
            shift @its;
        }
      }
}


=head2 new( <arg> )

create empty Workout.

=cut

sub new {
	my $class = shift;

	my %a = @_;

	my $self = bless {
		fields	=> {
			time	=> {
				supported	=> 1,
				required	=> 1,
				span		=> 'abs',
			},
			dur	=> {
				supported	=> 1,
				required	=> 1,
				span		=> 'chunk',
			},
			hr	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunkv',
			},
			cad	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunkv',
			},
			ele 	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'geo',
			},
			climb	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunk',
			},
			incline	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'trip',
			},
			lon	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'geo',
			},
			lat	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'geo',
			},
			xdist	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunk',
			},
			dist	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunk',
			},
			odo	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'trip',
			},
			grad	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunk',
			},
			spd 	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunkv',
			},
			work	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunk',
			},
			pwr 	=> {
				supported	=> 0,
				required	=> 0,
				span	=> 'chunkv',
			},
		},
		fsupported => [], # filled by init()
		frequired => [], # filled by init()
		fspan => {}, # filled by init()
		supplied => {},

		data	=> [[]],
		recint	=> $a{recint} ||5,

		# athlete data
		maxhr	=> $a{maxhr} ||225, # max heartrate
		resthr	=> $a{resthr} ||30, # rest "
		vo2max	=> $a{vo2max} ||50,
		weight	=> $a{weight} ||80,

		# workout data
		note	=> $a{note} ||"",
		temp	=> $a{temp} ||20, # temperature

		# overall data (calc'd from chunks)
		dist	=> 0, # trip odo
		climb	=> 0, # sum of climb
		moving	=> 0, # moving time
		elesum	=> 0, # sum of ele
		elemax	=> 0, # max of ele
		spdmax	=> 0, # max of spd
	}, $class;

	$self->init( \%a );

	return $self;
}

=head2 init( $args )

hook for inherited classes. Called by new()

=cut

sub init {
	my( $self, $a ) = @_;

	while( my( $f, $fd ) = each %{$self->{fields}} ){
		push @{$self->{fsupported}}, $f if $fd->{supported};
		push @{$self->{frequired}}, $f if $fd->{requiured};
		push @{$self->{fspan}{$fd->{span}}}, $f;
	}
}

=head2 fields

returns a hash with information about fields supported

=cut

sub fields {
	my( $self ) = @_;
	$self->{fields};
}

=head2 fields_supported

returns a list of field names that are required for each data chunk.

=cut

sub fields_supported {
	my( $self ) = @_;

	@{$self->{fsupported}};
}

=head2 fields_required

returns a list of field names that are required for each data chunk.

=cut

sub fields_required {
	my( $self ) = @_;

	@{$self->{frequired}};
}

=head2 fields_span( $span )

returns a list of field names for the specified span

=cut

sub fields_span {
	my( $self, $span ) = @_;
	return unless exists $self->{fspan}{$span};
	@{$self->{fspan}{$span}};
}

=head2 fields_seen

returns a list of field names that were supplied for some data chunks

=cut

sub fields_seen {
	my( $self ) = @_;
	my $cnt = $self->chunk_cnt;
	keys %{$self->{supplied}};
}


=head2 fields_allchunks

returns a list of field names that were supplied for all data chunks

=cut

sub fields_allchunks {
	my( $self ) = @_;
	my $cnt = $self->chunk_cnt;
	grep {
		$self->{supplied}{$_} == $cnt;
	} keys %{$self->{supplied}}
}


=head2 recint

returns the recording interval in seconds.

=cut

sub recint {
	my( $self ) = @_;
	return $self->{recint};
}

# TODO accessors for trip/athlete data

# TODO: marker / lap data

=head2 copy( $src )

copy data from other workout

=cut

sub copy { # TODO: extra iterator
	my( $self, $src ) = @_;

	my $ib = $src->blocks_iter;
	while( defined( my $ic = $ib->() ) ){
		$self->block_add;
		while( defined( my $chunk = $ic->() ) ){
			$self->chunk_add( $chunk );
		}
	}
}

=head2 block_add

open new data block.

=cut

sub block_add {
	my( $self ) = @_;
	return unless @{$self->{data}};
	push @{$self->{data}}, [];
}


=head2 block( $num )

last/specified block

=cut

sub block {
	my( $self, $block ) = @_;

	if( defined $block ){
		$block >= 0 && $block <= $#{$self->{data}}
			or croak "no such block";
	} else {
		$block = -1;
	}

	return $self->{data}[-1];
}

=head2 blocks

return list of nonempty blocks.

=cut

sub blocks {
	my( $self ) = @_;
	return grep { @$_ } @{$self->{data}};
}

sub blocks_iter {
	my( $self ) = @_;
	_new_array_iterator( [ map {
		_new_array_iterator( $_ );
	} $self->blocks ] );
}

=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $d ) = @_;

	$d->{dur}
		or croak "missing duration";
	$d->{time}
		or croak "missing time";
	unless( $self->recint && abs($self->recint - $d->{dur}) < 0.1 ){
		croak "duration doesn't match recint";
	}

	# identify fields that were supplied for all chunks
	foreach my $f ( keys %$d ){
		$self->{supplied}{$f}++;
	}

	$self->chunk_calc( $d );

	foreach my $f ( $self->fields_required ){
		defined $d->{$f}
			or croak "missing field '$f'";
	}

	push @{$self->block}, $d;
}

=head2 chunk_calc( $chunk )

calculate trip summaries (and maybe some other chink fields)

=cut

sub chunk_calc {
	my( $self, $n ) = @_;

	my $dist = $n->{dist} || 0;
	if( defined $n->{spd} ){
		$dist ||= $self->dist_dur_spd( $n ) || 0;
		$self->{spdmax} = $n->{spd} if $n->{spd} > $self->{spdmax};
	}
	$self->{moving} += $n->{dur} if $dist;
	$self->{dist} += $dist;

	if( defined $n->{ele} ){
		my $o = $self->chunk_last;
		my $climb = $n->{climb} || $self->climb_ele_pele( $n, $o ) || 0;
		$self->{climb} += $climb if $climb && $climb > 0;
		$self->{elesum} += $n->{ele};
		$self->{elemax} = $n->{ele} if $n->{ele} > $self->{elemax};
	}
}


=head2 chunks

return list with all data chunks. Gaps are automagically filled with
chunks with according duration (i.e. != recint !!!)

=cut

sub chunks {
	my( $self ) = @_;

	my @dat;
	my $it = $self->chunks_iter;
	while( my $chunk = $it->() ){
		push @dat, $chunk;
	}
	return @dat;
}

sub chunks_iter {
	my( $self ) = @_;

	my @iter;
	my $l;
	foreach my $blk ( $self->blocks ){
		# synthesize fake chunk to fill gap between blocks
		if( $l ){
			my $t = $blk->[0];
			push @iter, _new_array_iterator( [{
				time	=> $t->{time},
				dur	=> $t->{time} - $l->{time},
			}]);
		}
		$l = $blk->[-1];

		push @iter, _new_array_iterator( $blk );
	}
	_new_iter_iterator( @iter );
}


=head2 chunk_cnt

return number of data chunks

=cut

sub chunk_cnt {
	my( $self ) = @_;

	my $sum;
	foreach my $blk ( $self->blocks ){
		$sum += @$blk;
	}
	return $sum;
}

=head2 chunk_first

returns the first data chunk of first block.

=cut

sub chunk_first {
	my( $self ) = @_;

	my $blk = $self->block(0)
		or return;
	@$blk or return;
	$blk->[0];
}


=head2 chunk_last

returns the last data chunk of last nonempty block.

=cut

sub chunk_last {
	my( $self ) = @_;

	foreach my $blk ( reverse $self->blocks ){
		return $blk->[-1];
	}
	return;
}


# TODO: calc methods

sub dur_time_ptime {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{time} 
		&& defined $last 
		&& defined $last->{time};
	$this->{time} - $last->{time};
}

sub time_dur_ptime {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{dur} 
		&& defined $last 
		&& defined $last->{time};
	$last->{time} + $this->{dur};
}

sub climb_ele_pele {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{ele} 
		&& defined $last 
		&& defined $last->{ele};
	$this->{ele} - $last->{ele};
}

sub incline_climb_pincline {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{climb} 
		&& defined $last 
		&& defined $last->{incline};
	$this->{incline} = $last->{incline};
	$this->{incline} += $this->{climb} if $this->{climb} > 0;
}

sub xdist_geo_pgeo {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{lon} 
		&& defined $this->{lat}
		&& defined $last 
		&& defined $last->{lon} 
		&& defined $last->{lat};

	$self->{geocalc} ||= new Geo::Distance;
	$self->{geocalc}->distance( 'meter', 
		$last->{lon}, $last->{lat},
		$this->{lon}, $this->{lat} );
}


sub xdist_dist_climb {
	my( $self, $this ) = @_;
	return unless defined $this->{dist} 
		&& defined $this->{climb};
	sqrt( $this->{dist}**2 - $this->{climb}**2 );
}

sub dist_xdist_climb {
	my( $self, $this ) = @_;
	return unless defined $this->{xdist} 
		&& defined $this->{climb};
	sqrt( $this->{xdist}**2 + $this->{climb}**2 );
}

sub dist_dur_spd {
	my( $self, $this ) = @_;
	return unless defined $this->{dur} 
		&& defined $this->{spd};
	$this->{spd} * $this->{dur};
}

sub dist_odo_podo {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{odo} 
		&& defined $last 
		&& defined $last->{odo};
	$this->{odo} - $last->{odo};
}

sub odo_podo_dist {
	my( $self, $this, $last ) = @_;
	return unless defined $this->{dist} 
		&& defined $last 
		&& defined $last->{odo};
	$last->{odo} + $this->{dist};
}

sub grad_xdist_climb {
	my( $self, $this ) = @_;
	return unless defined $this->{xdist} 
		&& defined $this->{climb};
	100 * $this->{climb} / $this->{xdist};
}

sub angle_xdist_climb {
	my( $self, $this ) = @_;
	return unless defined $this->{xdist} 
		&& defined $this->{climb};
	atan2($this->{climb},$this->{xdist});
}

sub spd_dur_dist {
	my( $self, $this ) = @_;
	return unless defined $this->{dur} 
		&& $this->{dist};
	$this->{dist}/$this->{dur};
}

sub work_pwr_dur {
	my( $self, $this ) = @_;
	return unless defined $this->{pwr} 
		&& defined $this->{dur};
	$this->{pwr} * $this->{dur};
}

sub work_angle_spd {
	my( $self, $this ) = @_;
	return unless defined $this->{angle} 
		&& defined $this->{spd};
	undef; # TODO
}

sub pwr_work_dur {
	my( $self, $this ) = @_;
	return unless defined $this->{work} 
		&& defined $this->{dur};
	$this->{work} / $this->{dur};
}

sub calc_data {
	my( $self, $this, $last ) = @_;

	# TODO: replace || with defined() as this overwrites 0-values

	# time
	$this->{dur} ||= $self->dur_time_ptime( $this, $last ) 
		|| $self->{recint};
	$this->{time} ||= $self->time_dur_ptime( $this, $last )
		or croak "cannot determin time";

	# elevation
	$this->{climb} ||= $self->climb_ele_pele( $this, $last );
	$this->{incline} ||= $self->incline_climb_pincline( $this, $last)
		|| 0;

	# distance
	$this->{xdist} ||= $self->xdist_geo_pgeo( $this, $last )
		|| $self->xdist_dist_climb( $this );
	$this->{dist} ||= $self->dist_xdist_climb( $this )
		|| $self->dist_dur_spd( $this )
		|| $self->dist_odo_podo( $this, $last );
	$this->{odo} ||= $self->odo_podo_dist( $this, $last )
		|| 0;

	# gradient
	$this->{grad} ||= $self->grad_xdist_climb( $this );
	$this->{angle} ||= $self->angle_xdist_climb( $this );

	# speed
	$this->{spd} ||= $self->spd_dur_dist( $this ) || 0;

	# power
	$this->{work} ||= $self->work_pwr_dur( $this )
		|| $self->work_angle_spd( $this )
		|| 0;
	$this->{pwr} ||= $self->pwr_work_dur( $this );
}

1;
