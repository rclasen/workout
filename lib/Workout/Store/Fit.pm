#
# Copyright (c) 2011 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#


=head1 NAME

Workout::Store::Fit - Perl extension to read/write Garmin Fit Activity files

=head1 SYNOPSIS

  $src = Workout::Store::Fit->read( "foo.fit" );

  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.fit" );

=head1 DESCRIPTION

Interface to read/write Garmin Fit Activity files. Inherits from
Workout::Store and implements do_read/_write methods.

Other Fit files (Course, Workout, ...) aren't supported, as they carry
information inapropriate for this framework.

=cut

# TODO: support multiple activities, don't merge them silently

package Workout::Store::Fit;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use Workout::Constant qw/KCAL/;
use Workout::Fit qw( :types );
use Workout::Fit::Enum;

our $VERSION = '0.01';

sub filetypes {
	return "fit";
}

our %fields_supported = map { $_ => 1; } qw{
	dist
	lon
	lat
	work
	hr
	cad
	temp
	ele
};

our %defaults = (
	read_spd	=> 1,
	recint		=> undef,
);
__PACKAGE__->mk_accessors( keys %defaults );

our %meta = (
	sport		=> undef,
	manufacturer	=> 'garmin',
	device		=> 'edge800',
	serial		=> undef,
	hard_version	=> undef,
	soft_version	=> undef,
	work_expended	=> undef, # energy guessed by heartrate
);

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut


sub new {
	my( $class,$a ) = @_;

	$a||={};
	$a->{meta}||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		meta	=> {
			%meta,
			%{$a->{meta}},
		},
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,

		field_use	=> {},
	});

	$self;
}

=head1 METHODS

=cut

sub do_write {
	my( $self, $fh, $fname ) = @_;

	my $fit = Workout::Fit->new(
		to	=> $fh,
		debug	=> $self->{debug},
	) or croak "initializing Fit failed";

	# TODO: notes??

	my $info = $self->info_meta;

	# header

	defined $fit->define_raw(
		id	=> 0,
		message	=> FIT_MSG_FILE_ID,
		fields	=> [{
			field	=> 0, # file_type
			base	=> FIT_ENUM,
		}, {
			field	=> 1, # manufacturer
			base	=> FIT_UINT16,
		}, {
			field	=> 2, # product
			base	=> FIT_UINT16,
		}, {
			field	=> 3, # serial
			base	=> FIT_UINT32Z,
		}],
	) or return;

	my( $manu, $dev );
	if( ! defined $info->{device} ){
		# undef
	} elsif( $info->{device}=~ /^\d+$/ ){
		$dev = $info->{device}

	} elsif( $info->{device} =~ /^(\S+)\s+(\S+)$/ ){
		$info->{manufacturer} = $1
			unless defined $info->{manufacturer};
		$dev = FIT_garmin_product( lc($2) );

	} else {
		$dev = FIT_garmin_product( lc($info->{device}) );
	}

	if( ! defined $info->{manufacturer} ){
		# undef
	} elsif( $info->{manufacturer} =~ /^\d+$/ ){
		$manu = $info->{manufacturer};
	} else {
		$manu = FIT_manufacturer( lc($info->{manufacturer}) )
	}


	$fit->data( 0, FIT_FILE_ACTIVITY, $manu, $dev, $info->{serial} )
		or return;

	# TODO: support writing FIT courses, aswell

	defined $fit->define_raw(
		id	=> 1,
		message	=> FIT_MSG_FILE_CREATOR,
		fields	=> [{
			field	=> 0, # sw version
			base	=> FIT_UINT16,
		}, {
			field	=> 1, # hw version
			base	=> FIT_UINT8,
		}],
	) or return;
	$fit->data( 1, $info->{soft_version},
		$info->{hard_version} )
		or return;


	# TODO: write meta sport

	# timer events

	defined $fit->define_raw(
		id	=> 3,
		message	=> FIT_MSG_EVENT,
		fields	=> [{
			field	=> 253, # end timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 0, # event -> 0 timer
			base	=> FIT_ENUM,
		}, {
			field	=> 1, # event_type -> 0 start / 4 stop
			base	=> FIT_ENUM,
		}],
	) or return;
	$fit->data( 3, $self->time_start - FIT_TIME_OFFSET, 0, 0 );


	# Data

	my %io = map {
		$_ => 1,
	} $self->fields_io;

	my $dist = 0;

	my @fields = ({
		field	=> 253, # timestamp
		base	=> FIT_UINT32,
	});
	my @data = ( sub { $_[0]->time - FIT_TIME_OFFSET} );

	if( $io{lon} || $io{lat} ){
		push @fields, {
			field	=> 1, # lon
			base	=> FIT_SINT32,
		}, {
			field	=> 0, # lat
			base	=> FIT_SINT32,
		};

		push @data,
			sub { defined $_[0]->lon ? $_[0]->lon * FIT_SEMI_DEG : undef },
			sub { defined $_[0]->lat ? $_[0]->lat * FIT_SEMI_DEG : undef };
	}

	if( $io{dist} ){
		push @fields, {
			field	=> 5, # dist
			base	=> FIT_UINT32,
		}, {
			field	=> 6, # spd
			base	=> FIT_UINT16,
		};

		push @data,
			sub { $dist * 100 },
			sub { defined $_[0]->spd ? $_[0]->spd * 1000 : undef };
	}

	if( $io{ele} ){
		push @fields, {
			field	=> 2, # altitude
			base	=> FIT_UINT16,
		};

		push @data, sub { defined $_[0]->ele ? ( $_[0]->ele + 500) * 5 : undef };
	}

	if( $io{work} ){
		push @fields, {
			field	=> 7, # pwr
			base	=> FIT_UINT16,
		};

		push @data, sub { $_[0]->pwr };
	}

	if( $io{hr} ){
		push @fields, {
			field	=> 3, # hr
			base	=> FIT_UINT8,
		};

		push @data, sub { $_[0]->hr };
	}

	if( $io{cad} ){
		push @fields, {
			field	=> 4, # cad
			base	=> FIT_UINT8,
		};

		push @data, sub { $_[0]->cad };
	}

	if( $io{temp} ){
		push @fields, {
			field	=> 13, # temp
			base	=> FIT_SINT8,
		};

		push @data, sub { $_[0]->temp };
	}

	defined $fit->define_raw(
		id	=> 2,
		message	=> FIT_MSG_RECORD,
		fields	=> \@fields,
	) or return;

	my $it = $self->iterate;
	while( my $row = $it->next ){

		if( $row->isblockfirst ){
			$fit->data( 3, $row->prev->time, 0, 4 );
			$fit->data( 3, $row->stime, 0, 0 );
		}

		$dist += $row->dist || 0;
		$fit->data( 2, map { $_->( $row ) } @data );
	}

	$fit->data( 3, $self->time_end - FIT_TIME_OFFSET, 0, 4 );

	# laps

	# TODO write meta summary data for laps
	defined $fit->define_raw(
		id	=> 4,
		message	=> FIT_MSG_LAP,
		fields	=> [{
			field	=> 254, # lap number 
			base	=> FIT_UINT16,
		}, {
			field	=> 253, # end timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 2, # start timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 0, # event -> 9 lap
			base	=> FIT_ENUM,
		}, {
			field	=> 1, # event_type -> 1 stop
			base	=> FIT_ENUM,
		}, {
			field	=> 24, # lap_trigger -> 1 manual
			base	=> FIT_ENUM,
		}, {
			field	=> 26, # event_group -> undef
			base	=> FIT_UINT8,
		}],
	) or return;

	my $laps = 0;
	foreach my $m ( sort { $a->end <=> $b->end } $self->marks ){
		$fit->data( 4, $laps++,
			$m->end - FIT_TIME_OFFSET, $m->start - FIT_TIME_OFFSET,
			9, 1, 1, undef );
	}


	# summary

	# session
	@fields = ({
			field	=> 254, # session number 
			base	=> FIT_UINT16,
		}, {
			field	=> 253, # end timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 2, # start timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 0, # event -> 8 session
			base	=> FIT_ENUM,
		}, {
			field	=> 1, # event_type -> 1 stop
			base	=> FIT_ENUM,
		}, {
			field	=> 25, # first lap idx -> 0
			base	=> FIT_UINT16,
		}, {
			field	=> 26, # lap count -> $laps
			base	=> FIT_UINT16,
		}, {
			field	=> 27, # event_group -> undef
			base	=> FIT_UINT8,
		}, {
			field	=> 28, # session_trigger -> 0 activity end
			base	=> FIT_ENUM,
		}, {
			field	=> 7, # total_elapsed_time
			base	=> FIT_UINT32,
		}, {
			field	=> 8, # total_timer_time
			base	=> FIT_UINT32,
		}
	);
	@data = ( 5,
		0, $self->time_end - FIT_TIME_OFFSET, $self->time_start - FIT_TIME_OFFSET,
		8, 1, 0, $laps, undef, 0,
		defined $info->{dur} ? $info->{dur} * 1000 : undef,
		defined $info->{dur_mov} ? $info->{dur_mov} * 1000 : undef );

	if( $io{lon} || $io{lat} ){
		# find first chunk with lon+lat
		my $iter = $self->iterate;
		my $c;
		while( defined( $c = $iter->next )
			&& ( ! defined $c->lon || !  defined $c->lat ) ){
			1;
		};

		if( $c ){
			$self->debug( "found chunk @". $c->time ." with lon/lat for start_position" );
			push @fields, {
				field	=> 4, # start_position_lon
				base	=> FIT_SINT32,
			}, {
				field	=> 3, # start_position_lat
				base	=> FIT_SINT32,
			};
			push @data,
				defined $c->lon ? $c->lon * FIT_SEMI_DEG : undef,
				defined $c->lat ? $c->lat * FIT_SEMI_DEG : undef;
		}
	}

	if( $io{dist} ){
		push @fields, {
			field	=> 9, # total_distance
			base	=> FIT_UINT32,
		}, {
			field	=> 14, # avg_speed
			base	=> FIT_UINT16,
		}, {
			field	=> 15, # max_speed
			base	=> FIT_UINT16,
		};
		push @data,
			defined $info->{dist} ? $info->{dist} * 100 : undef,
			defined $info->{spd_avg} ? $info->{spd_avg} * 1000 : undef,
			defined $info->{spd_max} ? $info->{spd_max} * 1000 : undef;
	}

	if( $io{ele} ){
		push @fields, {
			field	=> 22, # total_ascent
			base	=> FIT_UINT16,
		};
		push @data, $info->{ascent};
	}

	if( $io{work} ){
		push @fields, {
			field	=> 11, # total_kalories
			base	=> FIT_UINT16,
		}, {
			field	=> 20, # avg_pwr
			base	=> FIT_UINT16,
		}, {
			field	=> 21, # max_pwr
			base	=> FIT_UINT16,
		};
		push @data,
			defined $info->{work} ? $info->{work} / 1000 : undef,
			$info->{pwr_avg},
			$info->{pwr_max};
	}

	if( $io{hr} ){
		push @fields, {
			field	=> 16, # avg_hr
			base	=> FIT_UINT8,
		}, {
			field	=> 17, # max_hr
			base	=> FIT_UINT8,
		};
		push @data, $info->{hr_avg}, $info->{hr_max};
	}

	if( $io{cad} ){
		push @fields, {
			field	=> 18, # avg_cadence
			base	=> FIT_UINT8,
		}, {
			field	=> 19, # max_cadence
			base	=> FIT_UINT8,
		};
		push @data, $info->{cad_avg}, $info->{cad_max};
	}

	defined $fit->define_raw(
		id	=> 5,
		message	=> FIT_MSG_SESSION,
		fields	=> \@fields,
	) or return;
	$fit->data( @data );

	# activity
	defined $fit->define_raw(
		id	=> 6,
		message	=> FIT_MSG_ACTIVITY,
		fields	=> [{
			field	=> 253, # end timestamp
			base	=> FIT_UINT32,
		}, {
			field	=> 1, # num sessions
			base	=> FIT_UINT16,
		}, {
			field	=> 2, # activity type -> 0 manual
			base	=> FIT_ENUM,
		}, {
			field	=> 3, # event -> 26 activity
			base	=> FIT_ENUM,
		}, {
			field	=> 4, # event_type -> 1 stop
			base	=> FIT_ENUM,
		}],
	) or return;
	$fit->data( 6,
		$info->{time_end} - FIT_TIME_OFFSET, 1, 0, 26, 1 );


	$fit->close
		or return;

	return 1;
}

sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $buf;

	my @laps;
	my $rec_last_dist = 0;
	my $rec_last_time;
	my $store_last_time = 0;
	my $event_last_time;

	my $fit = Workout::Fit->new(
		from => $fh,
		debug => $self->{debug},
	) or croak "initializing Fit failed";

	my $m = 0;
	while( my $msg = $fit->get_next ){
		++$m;

		############################################################
		# record message

		if( $msg->{message} == FIT_MSG_RECORD ){ # record
			my $dist;
			my $ck = {
				time => $msg->{timestamp} + FIT_TIME_OFFSET,
			};

			foreach my $f ( @{$msg->{fields}} ){

				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){
					$ck->{lat} = $f->{val} / FIT_SEMI_DEG;
					++$self->{field_use}{lat};

				} elsif( $f->{field} == 1 ){
					$ck->{lon} = $f->{val} / FIT_SEMI_DEG;
					++$self->{field_use}{lon};

				} elsif( $f->{field} == 2 ){
					$ck->{ele} = $f->{val}/5 - 500;
					++$self->{field_use}{ele};

				} elsif( $f->{field} == 3 ){
					$ck->{hr} = $f->{val};
					++$self->{field_use}{hr};

				} elsif( $f->{field} == 4 ){
					$ck->{cad} = $f->{val};
					++$self->{field_use}{cad};

				} elsif( $f->{field} == 5 ){
					$dist = $f->{val} / 100;
					$ck->{dist} = $dist - $rec_last_dist;
					++$self->{field_use}{dist};

				} elsif( $f->{field} == 6 ){
					$ck->{spd} = $f->{val} / 1000; # tmp

				} elsif( $f->{field} == 7 ){
					$ck->{pwr} = $f->{val}; # tmp

				} elsif( $f->{field} == 8 ){
					if( ! exists $ck->{dist} ){
						my @b = unpack('CCC',$f->{val} );
						# TODO: verify compressed speed/dist
						my $spd = ($b[0]
							| ($b[1] & 0x0f) <<8 ) / 100;
						my $dst = ( $b[1] >>4
							| $b[2] <<4 ) / 16;
						$ck->{dist} ||= $dst;
						++$self->{field_use}{dist};
					}

				} elsif( $f->{field} == 13 ){
					$ck->{temp} = $f->{val};
					++$self->{field_use}{temp};

				} elsif( $f->{field} == 30 ){
					# TODO: chunk LR-balance

				} # else ignore
			}

			if( defined $ck->{lon} && abs($ck->{lon}) >= 180
				|| defined $ck->{lat} && abs($ck->{lat}) >= 90 ){

				warn "geo position is out of bounds, skipping";
				delete( $ck->{lon} );
				delete( $ck->{lat} );
			}

			my $stime;

			# first record:
			if( ! $rec_last_time ){
				if( $event_last_time && $event_last_time < $ck->{time} ){
					$stime = $event_last_time;
					$self->debug("$m: using first event $stime start time \@$ck->{time}" );

				} elsif(  defined $ck->{spd} && defined $ck->{dist}
					&& $ck->{spd} > 0 && $ck->{dist} > 0  ){

					my $speedtime = $ck->{dist} / $ck->{spd};
					if( $speedtime > 1 ){
						$stime = $ck->{time} - $speedtime;
						$self->debug("$m: using speed as start time $stime \@$ck->{time}" );
					} else {
						$self->debug("$m: dist/speed don't provide usable duration");
					}
				}

			# first record after gap:
			} elsif( $event_last_time && $event_last_time > $rec_last_time ){
				$stime = $event_last_time;
				$self->debug("$m: using event $stime as start time \@$ck->{time}" );

			# other records:
			} else {
				$stime = $rec_last_time;
			}

			$event_last_time = undef;
			$rec_last_time = $ck->{time};
			$rec_last_dist = $dist if defined $dist;

			if( ! $stime ){
				$self->debug( "$m: unknown sample duration, skipping record at ".
					$ck->{time} );
				next;

			} elsif( $store_last_time > $stime ){
				$self->debug( "$m: backward time step, "
					."skipping record at ". $ck->{time} );

				next;

			} elsif( $stime >= $ck->{time} ){
				$self->debug( "$m: short sample, skipping record at ". $ck->{time} );
				next;
			}

			$ck->{dur} = $ck->{time} - $stime;

			if( $ck->{pwr} ){
				$ck->{work} = $ck->{pwr} * $ck->{dur};
				++$self->{field_use}{work};
			}

			if( exists $ck->{spd} && (
				! exists $ck->{dist} || $self->{read_spd}
			) ){
				$ck->{dist} = $ck->{spd} * $ck->{dur};
				++$self->{field_use}{dist};
			}

			delete $ck->{pwr};
			delete $ck->{spd};
			$store_last_time = $ck->{time};

			my $chunk = Workout::Chunk->new( $ck );
			$self->chunk_add( $chunk );

		############################################################
		# event message

		} elsif( $msg->{message} == FIT_MSG_EVENT ){ # event
			my $end = $msg->{timestamp} + FIT_TIME_OFFSET;
			my( $event, $etype, $data16, $data32 );

			foreach my $f ( @{$msg->{fields}} ){
				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){
					$event = $f->{val};

				} elsif( $f->{field} == 1 ){
					$etype = $f->{val};

				} elsif( $f->{field} == 2 ){
					$data16 = $f->{val};

				} elsif( $f->{field} == 3 ){
					$data32 = $f->{val};

				}
			}

			if( ! defined $event ){
				# do nothing

			} elsif( $event == 0 ){ # timer events
				if( ! defined $etype ){
					# do nothing

				} elsif( $etype == 0 # start
					|| $etype == 1 # stop
					|| $etype == 4 ){ # stop_all

					$self->debug( "$m: found ".
						( $etype == 0  ? 'start' : 'stop' )
						." event @". $end
						.", d16=". ($data16||'-')
						.", d32=". ($data32||'-')
						.", last: ".  ($self->time_end||0) );

					$event_last_time = $end;

				} else {
					$self->debug( "$m: found unhandled timer event $etype @"
						.($msg->{timestamp} + FIT_TIME_OFFSET)
						.", d16=". ($data16||'-')
						.", d32=". ($data32||'-') );
				}

			} elsif( $event >= 12 && $event <= 21 ){
				# calm down high/low zone alerts

			} elsif( $event == 3 || $event == 4 # workout/-step
#				|| $event == 5 || $event == 6 # power_down/_up
				|| $event == 7  # off course
#				|| $event == 8  # session end
				|| $event == 10  # course_point
				) {
				# calm down

			} else {
				$self->debug( "$m: found unhandled event $event/$etype @"
					.($msg->{timestamp} + FIT_TIME_OFFSET)
					.", d16=". ($data16||'-')
					.", d32=". ($data32||'-') );
			}


		############################################################
		# lap message

		} elsif( $msg->{message} == FIT_MSG_LAP ){ # lap
			my( $event, $start );
			my $end = $msg->{timestamp} + FIT_TIME_OFFSET;
			my %meta;

			foreach my $f ( @{$msg->{fields}} ){
				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){ # event
					$event = $f->{val};

				} elsif( $f->{field} == 2 ){ # start_time
					$start = $f->{val} + FIT_TIME_OFFSET;

				} elsif( $f->{field} == 3 ){
					$meta{'lat_start'} =
						$f->{val} / FIT_SEMI_DEG;

				} elsif( $f->{field} == 4 ){
					$meta{'lon_start'} =
						$f->{val} / FIT_SEMI_DEG;

				} elsif( $f->{field} == 5 ){
					$meta{'lat_end'} =
						$f->{val} / FIT_SEMI_DEG;

				} elsif( $f->{field} == 6 ){
					$meta{'lon_end'} =
						$f->{val} / FIT_SEMI_DEG;

				} elsif( $f->{field} == 7 ){
					$meta{'dur'} = $f->{val} / 1000;

				} elsif( $f->{field} == 8 ){
					$meta{'dur_rec'} = $f->{val} / 1000;

				} elsif( $f->{field} == 9 ){
					$meta{'dist'} = $f->{val} / 100;

				} elsif( $f->{field} == 11 ){
					$meta{'work_expended'} =
						$f->{val} * KCAL;

				} elsif( $f->{field} == 13 ){
					$meta{'spd_avg'} = $f->{val} / 1000;

				} elsif( $f->{field} == 14 ){
					$meta{'spd_max'} = $f->{val} / 1000;

				} elsif( $f->{field} == 15 ){
					$meta{'hr_avg'} = $f->{val};

				} elsif( $f->{field} == 16 ){
					$meta{'hr_max'} = $f->{val};

				} elsif( $f->{field} == 17 ){
					$meta{'cad_avg'} = $f->{val};

				} elsif( $f->{field} == 18 ){
					$meta{'cad_max'} = $f->{val};

				} elsif( $f->{field} == 19 ){
					$meta{'pwr_avg'} = $f->{val};

				} elsif( $f->{field} == 20 ){
					$meta{'pwr_max'} = $f->{val};

				} elsif( $f->{field} == 21 ){
					$meta{'ascent'} = $f->{val};

				} elsif( $f->{field} == 22 ){
					$meta{'descent'} = $f->{val};

				} elsif( $f->{field} == 23 ){
					$meta{'if'} = $f->{val} / 1000;

				} elsif( $f->{field} == 24 ){
					if( my $t = FIT_lap_trigger_id($f->{val}) ){
						$meta{'trigger'} = $t;
					}

				} elsif( $f->{field} == 25 ){
					if( my $s = FIT_sport_id($f->{val}) ) {
						$meta{'sport'} = $s;
					}

				} elsif( $f->{field} == 33 ){
					$meta{'npwr'} = $f->{val};

				} elsif( $f->{field} == 34 ){
					# TODO: lap LR-balance

				} elsif( $f->{field} == 41 ){
					$meta{'work'} = $f->{val};

				} elsif( $f->{field} == 42 ){
					$meta{'ele_avg'} = $f->{val} / 5 - 500;

				} elsif( $f->{field} == 43 ){
					$meta{'ele_max'} = $f->{val} / 5 - 500;

				} elsif( $f->{field} == 45 ){
					$meta{'grad_avg'} = $f->{val} / 100;

				} elsif( $f->{field} == 48 ){
					$meta{'grad_max'} = $f->{val} / 100;

				} elsif( $f->{field} == 49 ){
					$meta{'grad_min'} = $f->{val} / -100;

				} elsif( $f->{field} == 50 ){
					$meta{'temp_avg'} = $f->{val};

				} elsif( $f->{field} == 51 ){
					$meta{'temp_max'} = $f->{val};

				} elsif( $f->{field} == 52 ){
					$meta{'dur_mov'} = $f->{val} / 1000;

				} elsif( $f->{field} == 53 ){
					$meta{'vspd_avg'} = $f->{val} / 1000;

				} elsif( $f->{field} == 55 ){
					$meta{'vspd_max'} = $f->{val} / 1000;

				} elsif( $f->{field} == 56 ){
					$meta{'vspd_min'} = $f->{val} / -1000;

				} elsif( $f->{field} == 57 ){
					$meta{'dur_zone_hr'} = $f->{val} / 1000;

				} elsif( $f->{field} == 58 ){
					$meta{'dur_zone_spd'} = $f->{val} / 1000;

				} elsif( $f->{field} == 59 ){
					$meta{'dur_zone_cad'} = $f->{val} / 1000;

				} elsif( $f->{field} == 60 ){
					$meta{'dur_zone_pwr'} = $f->{val} / 1000;

				} elsif( $f->{field} == 62 ){
					$meta{'ele_min'} = $f->{val} / 5 - 500;

				} elsif( $f->{field} == 63 ){
					$meta{'hr_min'} = $f->{val};

				} # else ignore
			}

			if( ! defined $start ){
				warn "found lap without start \@$end, skipping";
				next;
			}

			my $xend = $meta{'dur'}
				? $start + int( .5 + $meta{'dur'} )
				: $end;

			$self->debug( "$m: found lap $start to $end/$xend: ". ($end-$start)
				.", elapsed=".  ($meta{'dur'}||'')
				.", timer=". ($meta{'dur_rec'}||'')
				.", event=". ($event||'')
				.", trigger=". ($meta{'trigger'}||'') );

			push @laps, {
				start	=> $start,
				end	=> $xend,
				meta	=> \%meta,
			};

		############################################################
		# session message

		} elsif( $msg->{message} == FIT_MSG_SESSION ){
			my $end = $msg->{timestamp} + FIT_TIME_OFFSET;
			$self->debug( "$m: found session @" . $end );
			$self->meta_field('time_end', $end );

			foreach my $f ( @{$msg->{fields}} ){

				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 2 ){
					$self->meta_field('time_start',
						$f->{val} + FIT_TIME_OFFSET );

				} elsif( $f->{field} == 3 ){
					$self->meta_field('lat_start',
						$f->{val} / FIT_SEMI_DEG );

				} elsif( $f->{field} == 4 ){
					$self->meta_field('lon_start',
						$f->{val} / FIT_SEMI_DEG );

				} elsif( $f->{field} == 5 ){
					if( my $s = FIT_sport_id($f->{val}) ) {
						$self->meta_field('sport', $s );
					}

				} elsif( $f->{field} == 7 ){
					$self->meta_field('dur',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 8 ){
					$self->meta_field('dur_rec',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 9 ){
					$self->meta_field('dist',
						$f->{val} / 100 );

				} elsif( $f->{field} == 11 ){
					$self->meta_field('work_expended',
						$f->{val} * KCAL );

				} elsif( $f->{field} == 14 ){
					$self->meta_field('spd_avg',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 15 ){
					$self->meta_field('spd_max',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 16 ){
					$self->meta_field('hr_avg',
						$f->{val} );

				} elsif( $f->{field} == 17 ){
					$self->meta_field('hr_max',
						$f->{val} );

				} elsif( $f->{field} == 18 ){
					$self->meta_field('cad_avg',
						$f->{val} );

				} elsif( $f->{field} == 19 ){
					$self->meta_field('cad_max',
						$f->{val} );

				} elsif( $f->{field} == 20 ){
					$self->meta_field('pwr_avg',
						$f->{val} );

				} elsif( $f->{field} == 21 ){
					$self->meta_field('pwr_max',
						$f->{val} );

				} elsif( $f->{field} == 22 ){
					$self->meta_field('ascent',
						$f->{val} );

				} elsif( $f->{field} == 23 ){
					$self->meta_field('descent',
						$f->{val} );

				} elsif( $f->{field} == 34 ){
					$self->meta_field('npwr',
						$f->{val} );

				} elsif( $f->{field} == 35 ){
					$self->meta_field('tss',
						$f->{val} / 10 );

				} elsif( $f->{field} == 36 ){
					$self->meta_field('if',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 37 ){
					# TODO session LR-balance

				} elsif( $f->{field} == 48 ){
					$self->meta_field('work',
						$f->{val} );

				} elsif( $f->{field} == 49 ){
					$self->meta_field('ele_avg',
						$f->{val} / 5 - 500 );

				} elsif( $f->{field} == 50 ){
					$self->meta_field('ele_max',
						$f->{val} / 5 - 500 );

				} elsif( $f->{field} == 52 ){
					$self->meta_field('grad_avg',
						$f->{val} / 100 );

				} elsif( $f->{field} == 55 ){
					$self->meta_field('grad_max',
						$f->{val} / 100 );

				} elsif( $f->{field} == 56 ){
					$self->meta_field('grad_min',
						$f->{val} / -100 );

				} elsif( $f->{field} == 57 ){
					$self->meta_field('temp_avg',
						$f->{val} );

				} elsif( $f->{field} == 58 ){
					$self->meta_field('temp_max',
						$f->{val} );

				} elsif( $f->{field} == 59 ){
					$self->meta_field('dur_mov',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 60 ){
					$self->meta_field('vspd_avg',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 62 ){
					$self->meta_field('vspd_max',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 63 ){
					$self->meta_field('vspd_min',
						$f->{val} / -1000 );

				} elsif( $f->{field} == 64 ){
					$self->meta_field('hr_min',
						$f->{val} );

				} elsif( $f->{field} == 65 ){
					$self->meta_field('dur_zone_hr',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 66 ){
					$self->meta_field('dur_zone_spd',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 67 ){
					$self->meta_field('dur_zone_cad',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 68 ){
					$self->meta_field('dur_zone_pwr',
						$f->{val} / 1000 );

				} elsif( $f->{field} == 71 ){
					$self->meta_field('ele_min',
						$f->{val} / 5 - 500 );

				}
			}

		############################################################
		# activity message

		} elsif( $msg->{message} == FIT_MSG_ACTIVITY ){
			$self->debug( "$m: found activity @"
				.($msg->{timestamp} + FIT_TIME_OFFSET) );

			 # TODO: are there any meainingful activity fields?

		############################################################
		# file_id message

		} elsif( $msg->{message} == FIT_MSG_FILE_ID ){ # file_id
			my $ftype;
			my( $manu, $prod );

			foreach my $f ( @{$msg->{fields}} ){
				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){ # type
					$ftype = $f->{val};
					$ftype == FIT_FILE_ACTIVITY
						or warn "no activity file, unsupported";

					# TODO: support courses, aswell

				} elsif( $f->{field} == 1 ){ # manufacturer
					$manu = $f->{val};

				} elsif( $f->{field} == 2 ){ # product
					$prod = $f->{val};

				} elsif( $f->{field} == 3 ){ # serial
					$self->meta_field('serial', $f->{val} );

				}
			}

			if( ! defined $manu ){
				$self->meta_field('manufacturer', undef );
				$self->meta_field('device', undef );

			} elsif( $manu == 1 || $manu == 2 ){
				$self->meta_field('manufacturer', 'garmin' );
				$self->meta_field('device', 'garmin '.
					FIT_garmin_product_id($prod)||$prod );

			} else {
				my $m = FIT_manufacturer_id($manu)||$manu;
				$self->meta_field('manufacturer', $m );
				$self->meta_field('device', $m .($prod
					? " $prod" : '' ) );
			}

			$self->debug( "$m: found file_id "
				."type=". ($ftype||'-'). ", "
				."manu=". ($manu||'-'). ", "
				."prod=". ($prod||'-'). ", "
				."seral=".  ($self->meta_field('serial')||'-'). ", "
				."device=".  ($self->meta_field('device')||'-') );

		############################################################
		# file_creator message

		} elsif( $msg->{message} == FIT_MSG_FILE_CREATOR ){ # file_creator

			foreach my $f ( @{$msg->{fields}} ){
				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){ # soft version
					$self->meta_field('soft_version', $f->{val} );

				} elsif( $f->{field} == 1 ){ # hard version
					$self->meta_field('hard_version', $f->{val} );

				}

			}

			$self->debug( "$m: found file_creator "
				."sw=". ($self->meta_field('soft_version')||'-') .", "
				."hw=".  ($self->meta_field('hard_version')||'-') );

		} elsif( $msg->{message} == FIT_MSG_DEVICE_INFO  ){ # device_info
			my %dev;

			foreach my $f ( @{$msg->{fields}} ){

				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 0 ){
					$dev{idx}= $f->{val};

				} elsif( $f->{field} == 1 ){
					$dev{type} = $f->{val};

					my $i = $f->{val};
					if($i == 1){
						$dev{type} .= '/antfs';

					} elsif($i == 11){
						++$dev{bike};
						$dev{type} .= '/bike_power';
						$dev{stype} = 'pwr';

					} elsif($i == 12){
						$dev{type} .= '/environment';

					} elsif($i == 120){
						$dev{type} .= '/heart_rate';
						$dev{stype} = 'hr';

					} elsif($i == 121){
						++$dev{bike};
						$dev{type} .= '/bike_speed_cadence';
						$dev{stype} = 'spd';

					} elsif($i == 122){
						++$dev{bike};
						$dev{type} .= '/bike_cadence';
						$dev{stype} = 'cad';

					} elsif($i == 123){
						++$dev{bike};
						$dev{type} .= '/bike_speed';
						$dev{stype} = 'spd';
					}

				} elsif( $f->{field} == 2 ){
					$dev{manu}= $f->{val};

				} elsif( $f->{field} == 3 ){
					$dev{serial}= $f->{val};

				} elsif( $f->{field} == 4 ){
					$dev{device}= $f->{val};

				} elsif( $f->{field} == 5 ){
					$dev{soft_version}= $f->{val};

				} elsif( $f->{field} == 6 ){
					$dev{hard_version}= $f->{val};

				}
			}

			# TODO: use device message instead of session

			$self->meta_field( 'sport', 'Bike' ) if $dev{bike};
			if( $dev{serial} && $dev{stype} ){
				$self->meta_field( "serial_".$dev{stype}, $dev{serial} );
			}

			$self->debug( "$m: device idx=". ($dev{idx}||'')
				.", type=".  ($dev{type}||'')
				.", manu=". ($dev{manu}||'')
				.", serial=".  ($dev{serial}||'')
				.", device=". ($dev{device}||''));

		} elsif( $msg->{message} == 22
			|| $msg->{message} == 72 ){ # TODO: unknown messages

			# do nothing, calm down

		} else {
			my $t = $msg->{timestamp}
				? $msg->{timestamp} + FIT_TIME_OFFSET
				: '<no_time>';
			$self->debug( "$m: found unhandled message: "
				.$msg->{message} ." @"
				.$t );
		}
	}
	$fit->close;

	if( $self->{debug} ){
		my $layouts = $fit->{layout};
		foreach my $id ( sort keys %$layouts ){
			my $layout = $layouts->{$id};
			$self->debug( "layout $id messages: $layout->{count}");
		}
	}

	if( @laps == 1 ){
		my $lap = $laps[0];
		if( $self->chunk_count && (
			$lap->{start} > $self->chunk_first->time
			|| $lap->{end} < $self->time_end ) ){

			$self->debug( "adding lap $lap->{start} - $lap->{end}" );
			$self->mark_new( $lap );
		} else {
			$self->debug( "skipping all-exercise lap" );
		}
	} else {
		foreach my $lap ( @laps ){
			$self->debug( "adding lap $lap->{start} - $lap->{end}" );
			$self->mark_new( $lap );
		}
	}

	$self->fields_io( keys %{$self->{field_use}} );

	1;
}


1;
__END__

=head1 META INFO

=head2 manufacturer

manufacturer of recording device - for now as ID

=head2 device

recording device type - for now as ID

=head2 serial

serial number of recording device

=head2 hard_version

hardware version of recording device

=head2 soft_version

softwar version of recording device

=head2 work_expended

expended energy usually guessed by heartrate (Joule)

=head1 SEE ALSO

Workout::Store, Workout::Fit

=head1 AUTHOR

Rainer Clasen

=cut
