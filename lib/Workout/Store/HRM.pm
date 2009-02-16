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
	dist	=> 0,
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
	});
}

sub do_read {
	my( $self, $fh ) = @_;

	my $parser;
	my $gotparams;

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
		);

	} elsif( $k eq 'starttime' ){
		$v =~ /^(\d+):(\d+):([\d.]+)$/
			or croak "invalid starttime";

		$self->{date}->add(
			hours	=> $1,
			minutes	=> $2,
			seconds	=> $3,
		);

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

	$self->{dist} += $c->dist||0;
}


=head2 fmtdur( $sec )

format duration as required in HRM files

=cut

sub fmtdur {
	my( $self, $sec ) = @_;

	my $min = int($sec / 60 ); $sec %= 60;
	my $hrs = int($min / 60 ); $min %= 60;
	sprintf( '%02i:%02i:%02.1f', $hrs, $min, $sec );
}

=head2 write

write data to disk.

=cut

# TODO: specify what to write: hr, spd, cad, ele, pwr
sub do_write {
	my( $self, $fh ) = @_;

	my $data = $self->{data};
	@$data or croak "no data";

	my $athlete = $self->athlete
		or croak "missing athlete info";

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
MaxHr=", int($athlete->hrmax), "
RestHR=", int($athlete->hrrest), "
StartDelay=0
VO2max=", int($athlete->vo2max), "
Weight=", int($athlete->weight), "

";

	print $fh 
"[Note]
", $self->note ,"

" if $self->note;

	print $fh "[HRData]\n";
	foreach my $row ( @$data ){
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
