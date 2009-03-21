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

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->read( "input.srm" ); 
  $it = Workout::Filter::FTP->new( $src->iterate, { ftp => 320 } );
  Workout::Store::Null->new->from( $it );
  print $it->tss;

=head1 DESCRIPTION

Base Class for modifying and filtering the Chunks of a Workout.

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

=head2 new( $iter, $arg )

create empty Iterator.

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

sub dur {
	my( $self ) = @_;
	$self->{dur};
}

sub apwr {
	my( $self ) = @_;

	$self->{dur} 
		or return;
	$self->{work} / $self->{dur};
}

sub npwr {
	my( $self ) = @_;

	$self->{dur} 
		or return;
	( $self->{npwr_sum} / $self->{dur} ) ** 0.25;
}

sub vi {
	my( $self ) = @_;

	my $apwr = $self->apwr
		or return;
	my $npwr = $self->npwr
		or return;
	$npwr / $apwr;
}

sub if {
	my( $self ) = @_;

	my $ftp = $self->ftp
		or return;
	$self->npwr / $ftp;
}

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

