#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Filter::FTP - caculcate NP, IF, TSS based on your FTP

=head1 SYNOPSIS

  $src = Workout::Store::SRM->read( "input.srm" ); 

  $it = Workout::Filter::FTP->new( $src, { ftp => 320 } );
  $it->finish;

  print "tss: ", $it->tss, "\n";

=head1 DESCRIPTION

Calculates the metrics as defined by "Training and Racing with a power
meter". This requires to resample the data to 1sec intervall to build a
rolling average.

=cut

package Workout::Filter::FTP;

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Resample';
use Workout::Filter::Join;
use Carp;

our $VERSION = '0.01';

our %default = (
	ftp	=> 0,		# W		Function Threshold Power
);

__PACKAGE__->mk_accessors( keys %default );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a||={};
	# WKO+ ignores gaps, so do *not* join, too.
	#$iter = Workout::Filter::Join->new( $iter, $a );
	$class->SUPER::new( $iter, { 
		%default, 
		%$a, 
		recint		=> 1,

		chunks		=> [],
		dur		=> 0,
		work		=> 0,
		npwr_sum	=> 0,
	});
}

=head1 METHODS

=head2 dur

returns the total duration of all chunks we've seen so far. So this is the
total workout duration minus all gaps.

=cut

sub dur {
	my( $self ) = @_;
	$self->{dur};
}

=head2 apwr

returns the average power of all chunks.

=cut

sub apwr {
	my( $self ) = @_;

	$self->{dur} 
		or return;
	$self->{work} / $self->{dur};
}

=head2 npwr

returns the normalized power of all chunks

=cut

sub npwr {
	my( $self ) = @_;

	$self->{dur} 
		or return;
	( $self->{npwr_sum} / $self->{dur} ) ** 0.25;
}

=head2 vi

returns the variability index of all chunks

=cut

sub vi {
	my( $self ) = @_;

	my $apwr = $self->apwr
		or return;
	my $npwr = $self->npwr
		or return;
	$npwr / $apwr;
}

=head2 vi

returns the intensity factor of all chunks

=cut

sub if {
	my( $self ) = @_;

	my $ftp = $self->ftp
		or return;
	$self->npwr / $ftp;
}

=head2 vi

returns the trainig stress score of all chunks

=cut

sub tss {
	my( $self ) = @_;

	my $ftp = $self->ftp
		or return;
	my $if = $self->if
		or return;
	my $npwr = $self->npwr
		or return;

	$if * $self->dur * $npwr / ( $ftp * 36 )
}

sub process {
	my( $self ) = @_;

	my $c = $self->SUPER::process
		or return;

	$self->{dur} += $c->dur;
	$self->{work} += ($c->work)||0;

	unshift @{$self->{chunks}}, $c;
	splice @{$self->{chunks}}, 30 if @{$self->{chunks}} >= 30;

	my $work = 0;
	foreach my $ac ( @{$self->{chunks}} ){
		$work += ($ac->work||0);
	}
	$work /= @{$self->{chunks}};

	$self->{npwr_sum} += $work **4;

	$c;
}

1;
__END__

=head1 SEE ALSO

Workout::Filter::Resample

=head1 AUTHOR

Rainer Clasen

=cut

