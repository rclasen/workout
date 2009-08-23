#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

# based on http://www.polar.fi/files/Polar_HRM_file%20format.pdf 

=head1 NAME

Workout::Store::HRM - read/write polar HRM files

=head1 SYNOPSIS

  use Workout::Store::HRM;

  $src = Workout::Store::HRM->read( "foo.hrm" );
  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.hrm" );


=head1 DESCRIPTION

Interface to read/write Polar HRM files.

=cut

package Workout::Store::HRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store::Memory';
use Workout::Chunk;
use Workout::Athlete;
use Carp;
use DateTime;


our $VERSION = '0.01';

sub filetypes {
	return "hrm";
}

our %defaults = (
	athlete	=> undef,
	tz	=> 'local',
	recint	=> 5,
);

our $re_fieldsep = qr/\t/;

__PACKAGE__->mk_accessors( keys %defaults );

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$class->SUPER::new({
		%defaults,
		%$a,
		date	=> undef,	# tmp read
		time	=> 0,		# tmp read
		colfunc	=> [],		# tmp read
		cap_block	=> 0,
		cap_note	=> 1,
	});
}

sub do_read {
	my( $self, $fh ) = @_;

	my $parser;
	my $gotparams;

	$self->athlete( Workout::Athlete->new );

	# precompile pattern
	my $re_stripnl = qr/[\r\n]+$/;
	my $re_empty = qr/^\s*$/;
	my $re_block = qr/^\[(\w+)\]/;

	while( defined(my $l = <$fh>) ){
		$l =~ s/$re_stripnl//g;

		if( $l =~/$re_empty/ ){
			next;

		} elsif( $l =~ /$re_block/ ){
			my $blockname = lc $1;

			if( $blockname eq 'params' ){
				$parser = \&parse_params;
				$gotparams++;

			} elsif( $blockname eq 'hrdata' ){
				$gotparams or croak "missing parameter block";
				$self->{time} = $self->{date}->hires_epoch;
				$parser = \&parse_hrdata;

			# TODO: read laps / Marker

			} else {
				$parser = undef;
			}

		} elsif( $parser ){
			$parser->( $self, $l );

		} # else ignore input
	}
}

sub parse_params {
	my( $self, $l ) = @_;

	my( $k, $v ) = ($l =~ /^\s*(\S+)\s*=\s*(\S*)\s*$/)
		or croak "misformed input: $l";

	$k = lc $k;

	if( $k eq 'version' ){
		($v == 106 || $v == 107)
			or croak "unsupported version: $v";
	
	} elsif( $k eq 'interval' ){
		($v == 238 || $v == 204)
			and croak "unsupported data interval: $v";

		$self->{recint} = $v;
	
	} elsif( $k eq 'date' ){
		$v =~ /^(\d\d\d\d)(\d\d)(\d\d)$/
			or croak "invalid date";

		$self->{date} = DateTime->new(
			year	=> $1,
			month	=> $2,
			day	=> $3,
			time_zone	=> 'local',
		);

	} elsif( $k eq 'starttime' ){
		$v =~ /^(\d+):(\d+):([\d.]+)$/
			or croak "invalid starttime";

		$self->{date}->add(
			hours	=> $1,
			minutes	=> $2,
			seconds	=> $3,
		);

	} elsif( $k eq 'resthr' ){
		$self->athlete->hrrest( $v );

	} elsif( $k eq 'maxhr' ){
		$self->athlete->hrmax( $v );

	} elsif( $k eq 'weight' ){
		$self->athlete->weight( $v );

	} elsif( $k eq 'vo2max' ){
		$self->athlete->vo2max( $v );

	} elsif( $k eq 'smode' ){
		$v =~ /^(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)?$/
			or croak "invalid smode";

		# set unit conversion multiplieres
		my( $mdist, $mele );
		if( $8 ){ # uk
			# 0.1 mph -> m/s
			# ($x/10 * 1.609344)/3.6
			$mdist = 1.609344/10/3.6;
			# ft -> m
			$mele = 0.3048;
		} else { # metric
			# 0.1 km/h -> m/s
			# ($x/10)/3.6
			$mdist = 1 / 36;
			# m
			$mele = 1;
		}

		# add parser for each column
		my @colfunc = ( sub { 'hr'	=> $_[0] } );
		push @colfunc, sub { 'dist' => $_[0] * $mdist * $self->recint } if $1;
		push @colfunc, sub { 'cad' => $_[0] } if $2;
		push @colfunc, sub { 'ele' => $_[0] * $mele } if $3;
		push @colfunc, sub { 'work' => $_[0] * $self->recint } if $4;

		# not supported, ignore:
		#push @colfunc, sub { 'pbal' => $_[0] } if ($5||$6) && $9;
		#push @colfunc, sub { 'air' => $_[0] } if $9;

		$self->{colfunc} = \@colfunc;
	}
	
}

sub parse_hrdata {
	my( $self, $l ) = @_;

	my @row = split( /$re_fieldsep/, $l );

	$self->{time} += $self->recint;
	my %a = (
		prev	=> $self->{prev},
		time	=> $self->{time},
		dur	=> $self->recint,
		map {
			$_->( shift @row );
		} @{$self->{colfunc}},
	);
	$self->_chunk_add( Workout::Chunk->new( \%a ));
}


=head2 chunk_check( $chunk )

=cut

sub chunk_check {
	my( $self, $c ) = @_;

	$self->SUPER::chunk_check( $c );
}


=head2 fmtdur( $sec )

format duration as required in HRM files

=cut

sub fmtdur {
	my( $self, $sec ) = @_;

	# TODO: support fractional seconds ( %= doesn't )
	my $min = int($sec / 60 ); $sec %= 60;
	my $hrs = int($min / 60 ); $min %= 60;
	sprintf( '%02i:%02i:%02i.0', $hrs, $min, $sec );
}

=head2 write

write data to disk.

=cut

our $minlap = 5;

# TODO: specify what to write: hr, spd, cad, ele, pwr
sub do_write {
	my( $self, $fh ) = @_;

	$self->chunk_count
		or croak "no data";

	my $athlete = $self->athlete
		or croak "missing athlete info";

	# convert marker -> lap
	my @tics = sort { 
		$a->{time} <=> $b->{time}

	} map {
		{
			isend	=> 1,
			time	=> $_->start,
			note	=> $_->note,
		}, ( $_->end - $_->start >= $minlap ? {
			isend	=> 0,
			time	=> $_->end,
			note	=> $_->note,
		} : () ); 

	} @{ $self->marks || [] };

	if( ! @tics || $tics[0]->{time} > $self->time_start ){
		unshift @tics, {
			isend	=> 0,
			time	=> $self->time_start,
			note	=> '',
		};
	}
	if( ! @tics || $tics[-1]->{time} < $self->time_end ){
		push @tics, {
			isend	=> 1,
			time	=> $self->time_end,
			note	=> '',
		};
	}

	my @laps;
	my $last;
	foreach my $tic ( @tics ){
		if( $tic->{time} < $self->time_start ){
			$tic->{time} = $self->time_start;

		} elsif( $tic->{time} > $self->time_end ){
			$tic->{time} = $self->time_end;
		}

		if( $last ){
			if( $tic->{time} - $last->{time} <= $minlap ){
				# isend "overwrites" other entries
				if( @laps && ! $laps[-1]->{isend} 
					&& $tic->{isend} ){

					pop @laps;

				} else {
					next;
				}
			}

			$self->debug( 'lap: '. $last->{time}. '-'.
				$tic->{time}. ': '. $tic->{note} );
			push @laps, {
				start	=> $last->{time}, 
				end	=> $tic->{time},
				note	=> $tic->{note},
				isend	=> $tic->{isend},
			};
		}
		$last = $tic;
	}


	my $sdate = DateTime->from_epoch( 
		epoch		=> $self->time_start,
		time_zone	=> $self->tz,
	); 

	print $fh 
"[Params]
Version=106
Monitor=12
SMode=11111110
Date=", $sdate->strftime( '%Y%m%d' ), "
StartTime=", $sdate->strftime( '%H:%M:%S.%1N' ), "
Length=", $self->fmtdur( $self->dur ), "
Interval=", $self->recint, "
Upper1=0
Lower1=0
Upper2=0
Lower2=0
Upper3=0
Lower3=0
Timer1=0:00:00.0
Timer2=0:00:00.0
Timer3=0:00:00.0
ActiveLimit=0
MaxHR=", int($athlete->hrmax), "
RestHR=", int($athlete->hrrest), "
StartDelay=0
VO2max=", int($athlete->vo2max), "
Weight=", int($athlete->weight), "

[Note]
", $self->note||'' ,"\n\n";


	# write laps / Marker
	print $fh "[IntTimes]\n";
	foreach my $lap ( @laps ){
		my $info = Workout::Filter::Info->new(
			Workout::Filter::Timespan->new( $self->iterate, {
				start	=> $lap->{start},
				end	=> $lap->{end},
			} )
		);

		my $last_chunk;
		while( my $chunk = $info->next ){
			$last_chunk = $chunk;
		}
		$last_chunk or next;

		print $fh 
			# row 1
			join("\t", 
				$self->fmtdur( $info->time_end - $self->time_start ),
				int($last_chunk->hr||0),
				int($info->hr_min||0),
				int($info->hr_avg||0),
				int($info->hr_max||0),
				),"\n",
			# row 2
			join("\t",
				0,	# flags
				0,	# rectime
				0,	# rechr
				int( ($last_chunk->spd||0) * 3.6),
				int($last_chunk->cad||0),
				int($last_chunk->ele||0),
				),"\n",
			# row 3
			join("\t", 
				0,	# extra1
				0,	# extra2
				0,	# extra3
				int( ($info->incline||0) /10),	# ascend
				int( ($info->dist||0) /100),	# dist
				),"\n",
			# row 4
			join("\t", 
				0,	# lap type
				int($info->dist||0),
				int($last_chunk->pwr||0),
				int($last_chunk->temp||0),
				0,	# phase lap
				0,	# resrved
				),"\n",
			# row 5
			join("\t", 
				0,	# reserved
				0,	# reserved
				0,	# reserved
				0,	# reserved
				0,	# reserved
				0,	# reserved
				),"\n";
	}
	print $fh "\n";

	print $fh "[IntNotes]\n";
	foreach my $l ( 0 .. $#laps ){
		print $fh $l+1, "\t", $laps[$l]->{note}, "\n" if $laps[$l]->{note};
	}
	print $fh "\n";

	print $fh "[HRData]\n";
	my $it = $self->iterate;
	while( my $row = $it->next ){
		print $fh join( "\t", (
			int(($row->hr || 0)+0.5),
			int(($row->spd || 0) * 36+0.5),
			int(($row->cad ||0)+0.5),
			int(($row->ele ||0)+0.5),
			int(($row->pwr ||0)+0.5),
		) ), "\n";
	};
}


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
