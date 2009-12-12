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

Interface to read/write Polar HRM files. Inherits from Workout::Store and
implements do_read/_write methods.

HRM files are always written as DOS files with CRLF line endings and
windows-1252 encoding.

=cut

package Workout::Store::HRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Workout::Chunk;
use Workout::Athlete;
use Carp;
use DateTime;

# TODO: verify read values are numbers

our $VERSION = '0.01';

sub filetypes {
	return "hrm";
}

our %defaults = (
	athlete	=> undef,
	tz	=> 'local',
	recint	=> 5,
);

our %fields_supported = map { $_ => 1; } qw{
	hr
	cad
	dist
	ele
	work
};

# precompile pattern
our $re_fieldsep = qr/\t/;
our $re_stripnl = qr/[\r\n]+$/;
our $re_empty = qr/^\s*$/;
our $re_block = qr/^\[(\w+)\]/;
our $re_value = qr/^\s*(\S+)\s*=\s*(\S*)\s*$/;
our $re_date = qr/^(\d\d\d\d)(\d\d)(\d\d)$/;
our $re_time = qr/^(\d+):(\d+):((\d+)(\.\d+))?$/;
our $re_smode = qr/^(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)?$/;
our $re_lap0 = qr/^(\d+):(\d+):((\d+)(\.\d+))?\t/;
our $re_lapnote = qr/(\d+)\t(.*)/;

__PACKAGE__->mk_accessors( keys %defaults );

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$class->SUPER::new({
		%defaults,
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		date	=> undef,	# tmp read
		time	=> 0,		# tmp read
		colfunc	=> [],		# tmp read
		blockline	=> 0,	# tmp read
		laps		=> [],	# tmp read
		cap_block	=> 0,
		cap_note	=> 1,
	});
}


=head1 METHODS

=head2 athlete

set/get Workout::Athlete object for this Store. Most of it's data is part
of the HRM file header.

=head2 tz

set/get timezone for reading/writing timestamps as HRM files stores them
in local time without timezone. See DateTime.

=cut

sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $parser;
	my $gotparams;

	$self->athlete( Workout::Athlete->new );

	binmode( $fh, ':crlf:encoding(windows-1252)' );
	while( defined(my $l = <$fh>) ){
		$l =~ s/$re_stripnl//g;

		if( $l =~/$re_empty/ ){
			next;

		} elsif( $l =~ /$re_block/ ){
			my $blockname = lc $1;
			$self->{blockline} = 0;

			if( $blockname eq 'params' ){
				$parser = \&parse_params;
				$gotparams++;

			} elsif( $blockname eq 'hrdata' ){
				$gotparams or croak "missing parameter block";
				$self->{time} ||= $self->{date}->hires_epoch;
				$parser = \&parse_hrdata;

			} elsif( $blockname eq 'inttimes' ){
				$self->{time} ||= $self->{date}->hires_epoch;
				$parser = \&parse_inttime;

			} elsif( $blockname eq 'intnotes' ){
				$parser = \&parse_intnotes;

			} elsif( $blockname eq 'note' ){
				$parser = \&parse_note;

			} else {
				$parser = undef;
			}

		} elsif( $parser ){
			$parser->( $self, $l );
			++$self->{blockline};

		} # else ignore input
	}

	$self->mark_new_laps( $self->{laps} ) if @{$self->{laps}};
}

sub parse_params {
	my( $self, $l ) = @_;

	my( $k, $v ) = ($l =~ /$re_value/ )
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
		$v =~ /$re_date/
			or croak "invalid date";

		$self->{date} = DateTime->new(
			year	=> $1,
			month	=> $2,
			day	=> $3,
			time_zone	=> 'local',
		);

	} elsif( $k eq 'starttime' ){
		$v =~ /$re_time/
			or croak "invalid starttime";

		$self->{date}->add(
			hours	=> $1,
			minutes	=> $2,
			seconds	=> $4,
			nanoseconds	=> $5 * 1000000000,
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
		@_ = $v =~ /$re_smode/
			or croak "invalid smode";

		# set unit conversion multiplieres
		my( $mdist, $mele );
		if( $_[7] ){ # uk
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

		# add parser/fields for each column
		my @fields = qw/ time dur hr /;
		my @colfunc = ( sub { 'hr'	=> ($_[0] || undef) } );

		if( $_[0] ){
			push @fields, 'dist';
			push @colfunc, sub {
				'dist' => $_[0] * $mdist * $self->recint;
			};
		}

		if( $_[1] ){
			push @fields, 'cad';
			push @colfunc, sub {
				'cad' => $_[0];
			};
		}

		if( $_[2] ){
			push @fields, 'ele';
			push @colfunc, sub {
				'ele' => $_[0] * $mele;
			};
		}

		if( $_[3] ){
			push @fields, 'work';
			push @colfunc, sub {
				'work' => $_[0] * $self->recint;
			};
		}

		# not supported, ignore:
		#push @colfunc, sub { 'pbal' => $_[0] } if ($5||$6) && $9;
		#push @colfunc, sub { 'air' => $_[0] } if $9;

		$self->fields_io( @fields );
		$self->{colfunc} = \@colfunc;
	}
	
}

sub parse_inttime {
	my( $self, $l ) = @_;

	if( 0 == ($self->{blockline} % 5) ){
		if( $l !~ /$re_lap0/ ){
			warn "invalid lap time in line $.";
			return;
		}

		my $delta = $3 + 60 * ( $2 + 60 * $1 );
		push @{ $self->{laps} }, {
			end	=> $self->{time} + $delta,
			note	=> undef,
		};
	}
}

sub parse_intnotes {
	my( $self, $l ) = @_;

	if( $l !~ /$re_lapnote/ ){
		warn "skipping invalid lap note line $.";
		return;
	}

	my $lap = $1 -1;
	my $note = $2;

	if( ($lap < 0) || ($lap >= @{ $self->{laps} }) ){
		warn "skipping note for unknown lap $lap at line $.";
		return;
	}

	$note =~ s/\\n/\n/g;
	$self->{laps}[$lap]{note} = $note;
}

sub parse_note {
	my( $self, $l ) = @_;

	$self->{note} .= $l;
}

sub parse_hrdata {
	my( $self, $l ) = @_;

	my @row = split( /$re_fieldsep/, $l );

	$self->{time} += $self->recint;
	my %a = (
		time	=> $self->{time},
		dur	=> $self->recint,
		map {
			$_->( shift @row );
		} @{$self->{colfunc}},
	);
	$self->chunk_add( Workout::Chunk->new( \%a ));
}

sub fmtdur {
	my( $self, $sec ) = @_;

	my $xsec = ($sec - int($sec)) * 10;
	my $min = int($sec / 60 ); $sec %= 60;
	my $hrs = int($min / 60 ); $min %= 60;
	sprintf( '%02i:%02i:%02i.%1d', $hrs, $min, $sec, $xsec );
}

sub do_write {
	my( $self, $fh, $fname ) = @_;

	$self->chunk_count
		or croak "no data";

	my $athlete = $self->athlete
		or croak "missing athlete info";

	my $laps = $self->laps;

	my %fields = map {
		$_	=> 1,
	} $self->fields_io;

	my $smode = sprintf('%0d%0d%0d%0d1110',
		$fields{cad} || 0,
		$fields{dist} || 0,
		$fields{ele} || 0,
		$fields{work} || 0,
	);
	my @colfunc = ( sub { int($_[0]->hr||0) } );
	push @colfunc, sub { int( ($_[0]->spd||0) * 36 +0.5) } if $fields{dist};
	push @colfunc, sub { int( ($_[0]->cad||0) +0.5) } if $fields{cad};
	push @colfunc, sub { int( ($_[0]->ele||0) +0.5) } if $fields{ele};
	push @colfunc, sub { int( ($_[0]->pwr||0) +0.5) } if $fields{work};

	my $sdate = DateTime->from_epoch( 
		epoch		=> $self->time_start,
		time_zone	=> $self->tz,
	); 

	binmode( $fh, ':crlf:encoding(windows-1252)' );
	print $fh 
"[Params]
Version=106
Monitor=12
SMode=$smode
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
	foreach my $lap ( @$laps ){
		my $info = $lap->info;

		my $last_chunk = $info->chunk_last
			or next;

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
				int( ($last_chunk->spd||0) * 3.6), # TODO check
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
				int(10 * ($last_chunk->temp||0) ),
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
	foreach my $l ( 0 .. $#$laps ){
		my $note = $laps->[$l]->note or next;
		$note =~ s/\n/\\n/g;
		print $fh $l+1, "\t", $note, "\n";
	}
	print $fh "\n";

	print $fh "[HRData]\n";
	my $it = $self->iterate;
	while( my $row = $it->next ){
		print $fh join( "\t", map {
			$_->( $row );
		} @colfunc ), "\n";
	};
}


1;
__END__

=head1 SEE ALSO

Workout::Store, Workout::Athlete

=head1 AUTHOR

Rainer Clasen

=cut
