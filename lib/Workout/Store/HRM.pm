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
use base 'Workout::Store';
use Carp;
use DateTime;


our $VERSION = '0.01';

our @fsupported = qw( hr spd cad ele pwr );

sub filetypes {
	return "hrm";
}

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $fname, $a ) = @_;

	my $self = $class->SUPER::new( $fname, $a );

	push @{$self->{fsupported}}, @fsupported;
	$self->{data} = [];
	$self->{recint} ||= 5; # different default
	$self->{tz} = $a->{tz} || 'local';

	# overall data (calc'd from chunks)
	$self->{dist} = 0; # trip odo
	$self->{climb} = 0, # sum of climb
	$self->{moving} = 0; # moving time
	$self->{elesum} = 0; # sum of ele
	$self->{elemax} = 0; # max of ele
	$self->{spdmax} = 0; # max of spd
	$self;
}

=head2 block_add

=cut

sub block_add {
	my( $self ) = @_;
	
	if( @{$self->{data}} ){
		croak "not supported";
	}
	# else: first block, no data -> do nothing;
}

=head2 chunk_add( $chunk )

=cut

sub chunk_add {
	my( $self, $c ) = @_;

	my $l = $self->{data}[-1] if @{$self->{data}};;

	$self->chunk_check( $c, $l );

	if( defined $c->{spd} ){
		my $dist = $self->calc->dist( $c, $l );

		$self->{spdmax} = $c->{spd} if $c->{spd} > $self->{spdmax};
		$self->{moving} += $c->{dur} if $c->{spd};
		$self->{dist} += $dist;
	}

	if( defined $c->{ele} ){
		my $climb = $self->calc->climb( $c, $l );

		$self->{climb} += $climb if defined $climb && $climb > 0;
		$self->{elesum} += $c->{ele};
		$self->{elemax} = $c->{ele} if $c->{ele} > $self->{elemax};
	}

	push @{$self->{data}}, $c;
}

# TODO: read / iterate

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

sub write {
	my( $self, $fname, $a ) = @_;

	open( my $fh, '>', $fname )
		or croak "open '$fname': $!";

	@{$self->{data}} 
		or croak "no data";
	my $last = $self->{data}[-1];
	my $first = $self->{data}[0];

	my $stime = $first->{time} - $self->recint;
	my $sdate = DateTime->from_epoch( 
		epoch		=> $stime,
		time_zone	=> $self->{tz},
	); 

	my $dur = $last->{time} - $stime;
	my $spdav = $self->{moving} ? $self->{dist} / $self->{moving} : 0;
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
MaxHr=", int($self->athlete->hrmax), "
RestHR=", int($self->athlete->hrrest), "
StartDelay=0
VO2max=", int($self->athlete->vo2max), "
Weight=", int($self->athlete->weight), "

[Note]
$self->{note}

[IntTimes]
", $self->fmtdur( $dur ), "	0	0	0	0
32	0	0	0	0	0
0	0	0	0	0
0	", int($self->{dist}), "	0	0	0	0
0	0	0	0	0	0
";
	# TODO: temperature
	# TODO: individual laps

	print $fh "
[IntNotes]

[ExtraData]

[Summary-123]
0	0	0	0	0	0
",$self->athlete->hrmax,"	0	0	",$self->athlete->hrrest,"
0	0	0	0	0	0
",$self->athlete->hrmax,"	0	0	",$self->athlete->hrrest,"
0	0	0	0	0	0
",$self->athlete->hrmax,"	0	0	",$self->athlete->hrrest,"
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

	foreach my $row ( @{$self->{data}} ){
		print $fh join( "\t", (
			int($row->{hr} || 0),
			int(($row->{spd} || 0) * 36),
			int($row->{cad} ||0),
			int($row->{ele} ||0),
			int($row->{pwr} ||0),
		) ), "\n";
	};

	close($fh);
	1;
}


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
