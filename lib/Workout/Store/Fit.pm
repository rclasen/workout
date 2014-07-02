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

  $src->write( "out.fit" ); # TODO: not supported, yet

=head1 DESCRIPTION

Interface to read/write Garmin Fit Activity files. Inherits from
Workout::Store and implements do_read/_write methods.

Other Fit files (Course, Workout, ...) aren't supported, as they carry
information inapropriate for this framework.

=cut


package Workout::Store::Fit;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use Workout::Fit qw( :types );

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
	recint		=> undef,
);
__PACKAGE__->mk_accessors( keys %defaults );

our %meta = (
	sport		=> undef,
	manufacturer	=> 1, # Garmin
	device		=> 1169, # Edge800
	serial		=> undef,
	hard_version	=> undef,
	soft_version	=> undef,
	work_expended	=> undef, # energy guessed by heartrate
);

use constant {
	joule	=> 4186.8,
};

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

# TODO: meta sport

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

	my $info = $self->info; # TODO: meta use summary

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

	# TODO: meta lookup non-numeric manufacturer/device
	my $manu = $self->meta_field('manufacturer');
	$manu = $defaults{manufacturer} if $manu !~ /^\d+$/;

	my $dev = $self->meta_field('device');
	$dev = $defaults{device} if $dev !~ /^\d+$/;

	$fit->data( 0, FIT_FILE_ACTIVITY, $manu, $dev,
		$self->meta_field('serial') )
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
	$fit->data( 1, $self->meta_field('soft_version'),
		$self->meta_field('hard_version') )
		or return;



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

	# TODO meta summary data for laps
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
		defined $self->dur ? $self->dur * 1000 : undef,
		defined $info->dur_mov ? $info->dur_mov * 1000 : undef );

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
			defined $info->dist ? $info->dist * 100 : undef,
			defined $info->spd_avg ? $info->spd_avg * 1000 : undef,
			defined $info->spd_max ? $info->spd_max * 1000 : undef;
	}

	if( $io{ele} ){
		push @fields, {
			field	=> 22, # total_ascent
			base	=> FIT_UINT16,
		};
		push @data, $info->ascent;
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
			defined $info->work ? $info->work / 1000 : undef,
			$info->pwr_avg,
			$info->pwr_max;
	}

	if( $io{hr} ){
		push @fields, {
			field	=> 16, # avg_hr
			base	=> FIT_UINT8,
		}, {
			field	=> 17, # max_hr
			base	=> FIT_UINT8,
		};
		push @data, $info->hr_avg, $info->hr_max;
	}

	if( $io{cad} ){
		push @fields, {
			field	=> 18, # avg_cadence
			base	=> FIT_UINT8,
		}, {
			field	=> 19, # max_cadence
			base	=> FIT_UINT8,
		};
		push @data, $info->cad_avg, $info->cad_max;
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
		$self->time_end - FIT_TIME_OFFSET, 1, 0, 26, 1 );


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
	my $event_last_time;

	my $fit = Workout::Fit->new(
		from => $fh,
		#debug => $self->{debug},
	) or croak "initializing Fit failed";

	while( my $msg = $fit->get_next ){

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
					# TODO: l-r balance

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
					$self->debug("using first event $stime start time \@$ck->{time}" );

				} elsif( $ck->{spd} > 0 && $ck->{dist} > 0  ){
					$stime = $ck->{time}
						- $ck->{dist} / $ck->{spd};
					$self->debug("using speed as start time $stime \@$ck->{time}" );
				} else {
					$self->debug( "unknown sample duration, "
						."skipping record at ". $ck->{time} );
					next;
				}

			# first record after gap:
			} elsif( $event_last_time && $event_last_time > $rec_last_time ){
				$stime = $event_last_time;
				$self->debug("using event $stime as start time \@$ck->{time}" );
			# other records:
			} else {
				$stime = $rec_last_time;
			}

			if( defined $rec_last_time && $rec_last_time > $stime ){
				$self->debug( "backward time step, "
					."skipping record at ". $ck->{time} );

				next;
			}


			$rec_last_time = $ck->{time};
			$rec_last_dist = $dist if defined $dist;

			if( $stime >= $ck->{time} ){
				$self->debug( "short sample, skipping record at ". $ck->{time} );
				next;
			}

			$ck->{dur} = $ck->{time} - $stime;

			if( $ck->{pwr} ){
				$ck->{work} = $ck->{pwr} * $ck->{dur};
				++$self->{field_use}{work};
			}

			if( exists $ck->{dist} ){
				# delete($ck->{spd}); # unneeded

			} elsif( $ck->{spd} ){
				$ck->{dist} = $ck->{spd} * $ck->{dur};
				++$self->{field_use}{dist};

			# TODO: dist from geocalc
			#} elsif( defined($ck->{lon}) && defined($ck->{lat} ) ){

			}

			delete $ck->{pwr};
			delete $ck->{spd};

			my $chunk = Workout::Chunk->new( $ck );
			$self->chunk_add( $chunk );

		############################################################
		# event message

		} elsif( $msg->{message} == FIT_MSG_EVENT ){ # event
			my $end = $msg->{timestamp} + FIT_TIME_OFFSET;
			my( $event, $etype );

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){
					$event = $f->{val};

				} elsif( $f->{field} == 1 ){
					$etype = $f->{val};

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

					$self->debug( "found ".
						( $etype == 0  ? 'start' : 'stop' )
						." event @". $end
						.", last: ".  ($self->time_end||0) );

					$event_last_time = $end;

				} else {
					$self->debug( "found unhandled timer event $etype @"
							.($msg->{timestamp} + FIT_TIME_OFFSET));
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
				$self->debug( "found unhandled event $event/$etype @"
					.($msg->{timestamp} + FIT_TIME_OFFSET));
			}


		############################################################
		# lap message

		} elsif( $msg->{message} == FIT_MSG_LAP ){ # lap
			my( $event, $start, $elapsed, $timer, $trigger );
			my $end = $msg->{timestamp} + FIT_TIME_OFFSET;
			my %meta;

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){ # event
					$event = $f->{val};

				} elsif( $f->{field} == 2 ){ # start_time
					$start = $f->{val} + FIT_TIME_OFFSET;

				} elsif( $f->{field} == 7 ){ # total_elapsed_time
					$elapsed = $f->{val};

				} elsif( $f->{field} == 8 ){ # total_timer_time
					$timer = $f->{val};

				} elsif( $f->{field} == 24 ){ # total_timer_time
					$trigger = $f->{val};

				# TODO: trigger, ...
				# TODO: meta sport, summary ...
				} # else ignore
			}

			my $xend = $elapsed
				? $start + int( .5 + $elapsed/1000 )
				: $end;

			$self->debug( "found lap $start to $end/$xend: ".
				($end-$start) ." elapsed=$elapsed"
				.", timer=$timer, event=$event"
				.", trigger=$trigger" );

			push @laps, {
				start	=> $start,
				end	=> $xend,
				meta	=> \%meta,
			};

		############################################################
		# session message

		} elsif( $msg->{message} == FIT_MSG_SESSION ){ # TODO: session
			$self->debug( "found session @"
				.($msg->{timestamp} + FIT_TIME_OFFSET) );

			foreach my $f ( @{$msg->{fields}} ){

				if( ! defined $f->{val} ){
					# do nothing

				} elsif( $f->{field} == 11 ){
					$self->meta_field('work_expended',
						joule * $f->{val} );
				}
				# TODO: meta sport, summary ...
			}

		############################################################
		# activity message

		} elsif( $msg->{message} == FIT_MSG_ACTIVITY ){ # TODO: activity
			$self->debug( "found activity @"
				.($msg->{timestamp} + FIT_TIME_OFFSET) );

				# TODO: meta sport

		############################################################
		# file_id message

		} elsif( $msg->{message} == FIT_MSG_FILE_ID ){ # file_id
			my $ftype;

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){ # type
					$ftype = $f->{val};
					$ftype == FIT_FILE_ACTIVITY
						or warn "no activity file, unsupported";

					# TODO: support courses, aswell

				} elsif( $f->{field} == 1 ){ # manufacturer
					$self->meta_field('manufacturer', $f->{val} );

				} elsif( $f->{field} == 2 ){ # product
					$self->meta_field('device', $f->{val} );

				} elsif( $f->{field} == 3 ){ # serial
					$self->meta_field('serial', $f->{val} );

				}
			}

			# TODO: meta lookup manufacturer/device string

			$self->debug( "found file_id "
				."type=". ($ftype||'-'). ", "
				."manu=". ($self->meta_field('manufacturer')||'-'). ", "
				."prod=". ($self->meta_field('device')||'-'). ", "
				."seral=". ($self->meta_field('serial')||'-') );

		############################################################
		# file_creator message

		} elsif( $msg->{message} == FIT_MSG_FILE_CREATOR ){ # file_creator

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){ # soft version
					$self->meta_field('soft_version', $f->{val} );

				} elsif( $f->{field} == 1 ){ # hard version
					$self->meta_field('hard_version', $f->{val} );

				}

			}

			$self->debug( "found file_creator "
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
					if($i == 1){ $dev{type} .= '/antfs' }
					elsif($i == 11){ $dev{type} .= '/bike_power' }
					elsif($i == 12){ $dev{type} .= '/environment' }
					elsif($i == 120){ $dev{type} .= '/heart_rate' }
					elsif($i == 121){ $dev{type} .= '/bike_speed_cadence' }
					elsif($i == 122){ $dev{type} .= '/bike_cadence' }
					elsif($i == 123){ $dev{type} .= '/bike_speed' }

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
			$self->debug( "device idx=". ($dev{idx}||'')
				.", type=".  ($dev{type}||'')
				.", manu=". ($dev{manu}||'')
				.", serial=".  ($dev{serial}||'')
				.", device=". ($dev{device}||''));

		} elsif( $msg->{message} == 22
			|| $msg->{message} == 72 ){ # TODO: unknown messages

			# do nothing, calm down

		} else {
			$self->debug( "found unhandled message: "
				.$msg->{message} ." @"
				.($msg->{timestamp} + FIT_TIME_OFFSET) );
		}
	}
	$fit->close;

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
