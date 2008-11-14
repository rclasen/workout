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
use Workout::Chunk;
use Carp;
use DateTime;


our $VERSION = '0.01';

sub filetypes {
	return "hrm";
}

__PACKAGE__->mk_accessors(qw(
	athlete
	tz
	dist
	climb
	moving
	elesum
	elemax
	spdmax
));

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( {
		recint	=> 5,
		tz	=> 'local',
		%$a,
	});

	$self->{data} = [];

	# overall data (calc'd from chunks)
	$self->dist( 0 ); # trip odo
	$self->climb( 0 ), # sum of climb
	$self->moving( 0 ); # moving time
	$self->elesum( 0 ); # sum of ele
	$self->elemax( 0 ); # max of ele
	$self->spdmax( 0 ); # max of spd
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
	my $n = $c->clone;
	$n->prev( $l );

	if( defined( my $spd = $n->spd )){
		$self->spdmax( $spd ) if $spd > $self->spdmax;
		$self->{moving} += $n->dur if $spd;
	}
	$self->{dist} += $n->dist||0;

	if( defined( my $ele = $n->ele )){
		my $climb = $n->climb;

		$self->{climb} += $climb if defined $climb && $climb > 0;
		$self->{elesum} += $ele;
		$self->elemax( $ele ) if $ele > $self->elemax;
	}

	push @{$self->{data}}, $n;
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

# TODO: specify what to write: hr, spd, cad, ele, pwr
sub do_write {
	my( $self, $fh ) = @_;

	@{$self->{data}} 
		or croak "no data";

	my $athlete = $self->athlete
		or croak "missing athlete info";

	my $last = $self->{data}[-1];
	my $first = $self->{data}[0];

	my $stime = $first->time - $self->recint;
	my $sdate = DateTime->from_epoch( 
		epoch		=> $stime,
		time_zone	=> $self->tz,
	); 

	my $dur = $last->time - $stime;
	my $spdav = $self->moving ? $self->dist / $self->moving : 0;
	my $eleav = $self->elesum * $self->recint / $dur;

	print $fh 
"[Params]
Version=106
Monitor=12
SMode=11111110
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

=pod
	print $fh
"[IntTimes]
", $self->fmtdur( $dur ), "	0	0	0	0
32	0	0	0	0	0
0	0	0	0	0
0	", int($self->dist), "	0	0	0	0
0	0	0	0	0	0
";
	# TODO: temperature
	# TODO: individual laps

	print $fh "
[IntNotes]

[ExtraData]

[Summary-123]
0	0	0	0	0	0
",$athlete->hrmax,"	0	0	",$athlete->hrrest,"
0	0	0	0	0	0
",$athlete->hrmax,"	0	0	",$athlete->hrrest,"
0	0	0	0	0	0
",$athlete->hrmax,"	0	0	",$athlete->hrrest,"
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
", int($self->dist / 100 ), "
", int($self->climb), "
", int($self->moving), "
", int($eleav), "
", int($self->elemax), "
", int($spdav * 3.6 * 128 ), "
", int($self->spdmax * 3.6 * 128 ), "
", int($self->dist / 1000), "

";

=cut

	print $fh "[HRData]\n";
	foreach my $row ( @{$self->{data}} ){
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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
