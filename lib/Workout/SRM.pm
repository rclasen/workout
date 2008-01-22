package Workout::SRM;

=head1 NAME

Workout::SRM - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Workout::SRM;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Workout::SRM, created by h2xs. It looks like the
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

# http://www.stephanmantler.com/?page_id=86

our $VERSION = '0.01';

my %magic_tag = (
	OK19	=> 1,
	SRM2	=> 2,
	SRM3	=> 3,
	SRM4	=> 4,
	SRM5	=> 5,
	SRM6	=> 6,
);

=head2 init( $a )

=cut

sub init {
	my( $self, $a ) = @_;

	foreach my $f ( qw( hr spd cad pwr )){
		$self->{fields}{$f}{supported} = 1;
	}

	$self->SUPER::init( $a );
}


=head2 read( $fh )

initialize data object from file

=cut

sub read {
	my( $class, $fh ) = @_;

	my $self = $class->new;
	my $buf;

	############################################################
	# file header
	CORE::read( $fh, $buf, 86 ) == 86
		or croak "failed to read file header";
	@_ = unpack( "A4vvCCvvxxA70", $buf );
		
	exists $magic_tag{$_[0]}
		or croak "unrecognized file format";
	my $version = $magic_tag{$_[0]};
	my $clen = 255;
	if( $version < 6 ){
		$clen = 3;
	}
	
	my $day = DateTime->new( 
		year => 1880, 
		month => 1, 
		day => 1
	)->add( days => $_[1] )->epoch;
	#$circum = $_[2];
	$self->{recint} = $_[3] / $_[4];
	my $blockcnt = $_[5];
	my $markcnt = $_[6];
	$self->{note} = $_[7];

	############################################################
	# TODO: marker
#	my @marker;
	while( $markcnt-- >= 0 ){
		CORE::read( $fh, $buf, $clen + 15 ) == $clen + 15
			or croak "failed to read marker";
#		@_ = unpack( "A[$clen]Cvvvvvvv", $buf );
#		push @marker, {
#			comment	=> $_[0],
#			active	=> $_[1],
#			ckstart	=> $_[2], # 1..
#			ckend	=> $_[3], # 1..
#			apwr	=> $_[4] / 8,
#			ahr	=> $_[5] / 64,
#			hcad	=> $_[6] / 32,
#			aspd	=> $_[7] / 2500 * 9,
#			pwc	=> $_[8],
#		};
	}

	############################################################
	# data blocks

	my $blockcks = 0;
	my @blocks;
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( "Vv", $buf );
		push @blocks, {
			tstamp	=> $_[0] / 100, # sec since 0:00
			ckcnt	=> $_[1],
			ckstart => $blockcks +1, # 1..
		};
		$blockcks += $_[1];
	}

	############################################################
	# calibration data, ff

	CORE::read( $fh, $buf, 7 ) == 7
		or croak "failed to read calibration data";
	@_ = unpack( "vvvx", $buf );
	#$self->{zeropos} = $_[0];
	#$self->{gradient} = $_[1];
	my $ckcnt = $_[2];

	$blockcks == $ckcnt
		or warn "inconsistent file: data block chunk count too large";

	############################################################
	# data chunks
	foreach my $blk ( @blocks ){
		my $cnt = $blk->{ckcnt};
		my $stime = $day + $blk->{tstamp};

		$self->block_add;

		my $etime = $stime + ($cnt +1) * $self->recint;
		print "reading block data: ", $stime, " to ", $etime, " chunks: ", $blk->{ckcnt}, "\n";

		# read block's chunks
		while( $cnt-- > 0 ){
			CORE::read( $fh, $buf, 5 ) == 5
				or croak "failed to read data chunk";
			@_ = unpack( "CCCCC", $buf );
			my $kph = ( (( $_[1] & 0xf0) << 3) | ( $_[0] & 0x7f)) 
				* 3.0 / 26;
			$self->chunk_add( {
				time	=> $stime += $self->recint,
				dur	=> $self->recint,
				pwr	=> ( $_[1] & 0x0f) | ( $_[2] << 4 ),
				spd	=> $kph / 3.6,
				cad	=> $_[3],
				hr	=> $_[4],
			});
		}
	}

	CORE::read( $fh, $buf, 1 )
		and warn "found unrecognized data at file end";
		
	return $self;
}

# TODO write


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
