package Workout::HRM;

=head1 NAME

Workout::HRM - read/write polar HRM files

=head1 SYNOPSIS

  use Workout::HRM;
  blah blah blah # TODO

=head1 DESCRIPTION

Stub documentation for Workout::HRM, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Base';
use Carp;
use DateTime;
use Geo::Distance;

our $VERSION = '0.01';

=head2 init( $a )

initialize HRM specific stuff.

=cut

sub init {
	my( $self, $a ) = @_;

	foreach my $f ( qw( hr spd cad ele pwr )){
		$self->{fields}{$f}{supported} = 1;
	}

	$self->SUPER::init( $a );
}

sub block_add {
	my( $self ) = @_;
	croak "HRM doesn't support data blocks";
}

# TODO: read

=head2 fmtdur( $sec )

format duration as required in HRM files

=cut

sub fmtdur {
	my( $self, $sec ) = @_;

	my $min = int($sec / 60 ); $sec %= 60;
	my $hrs = int($min / 60 ); $min %= 60;
	sprintf( '%02i:%02i:%02.1f', $hrs, $min, $sec );
}

=head2 write( $fh )

generate HRM file and write it to filehandle

=cut

sub write {
	my( $self, $fh ) = @_;

	my $last = $self->chunk_last
		or croak "no data";

	my $first = $self->chunk_first;

	my $stime = $first->{time} - $self->recint;
	my $sdate = DateTime->from_epoch( epoch => $stime ); 

	my $dur = $last->{time} - $stime;
	my $spdav = $self->{dist} / $self->{moving};
	my $eleav = $self->{elesum} * $self->{recint} / $dur;

	print $fh 
"[Params]
Version=107
Monitor=23
SMode=111111100
Date=", $sdate->strftime( '%Y%m%d' ), "
StartTime=", $sdate->strftime( '%H:%M:%S.%1N' ), "
Length=", $self->fmtdur( $dur ), "
Interval=", $self->recint, "
Upper1=0
Lower1=0
Upper2=0
Lower2=0
Upper3=0
Lower3=0
Timer1=00:00
Timer2=00:00
Timer3=00:00
ActiveLimit=0
MaxHr=", int($self->{maxhr}), "
RestHR=", int($self->{resthr}), "
StartDelay=0
VO2max=", int($self->{vo2max}), "
Weight=", int($self->{weight}), "

[Note]
$self->{note}

[IntTimes]
", $self->fmtdur( $dur ), "	0	0	0	0
32	0	0	0	0	0
0	0	0	0	0
0	", int($self->{dist}), "	0	0	0	0
0	0	0	0	0	0
";
	# TODO: individual laps

	print $fh "
[IntNotes]

[ExtraData]

[Summary-123]
0	0	0	0	0	0
$self->{maxhr}	0	0	$self->{resthr}
0	0	0	0	0	0
$self->{maxhr}	0	0	$self->{resthr}
0	0	0	0	0	0
$self->{maxhr}	0	0	$self->{resthr}
0	-1

[Summary-TH]
0	0	0	0	0	0
0	0	0	0
0	-1

[HRZones]
0
0
0
0
0
0
0
0
0
0
0

[SwapTimes]

[Trip]
", int($self->{dist} / 100 ), "
", int($self->{climb}), "
", int($self->{moving}), "
", int($eleav), "
", int($self->{elemax}), "
", int($spdav * 3.6 * 128 ), "
", int($self->{spdmax} * 3.6 * 128 ), "
", int($self->{dist} / 1000), "


[HRData]
";

	foreach my $row ( $self->chunks ){
		print $fh join( "\t", (
			int($row->{hr} || 0),
			int(($row->{spd} || 0) * 36),
			int($row->{cad} ||0),
			int($row->{ele} ||0),
			int($row->{pwr} ||0),
		) ), "\n";
	};
}


1;
__END__

=head1 SEE ALSO

Workout::Base

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
