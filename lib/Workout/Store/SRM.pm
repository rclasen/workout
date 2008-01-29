
=head1 NAME

Workout::Store::SRM - Perl extension for blah blah blah

=head1 SYNOPSIS

  $src = Workout::Store::Gpx->new( "foo.gpx" );
  while( $chunk = $src->next ){
  	...
  }

=head1 DESCRIPTION

Interface to read/write SRM power meter files

=cut


package Workout::Store::SRM::Iterator;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Iterator';
use Carp;
use DateTime;


=head2 next

=cut

sub next {
	my( $self ) = @_;

	my $store = $self->store;
	return unless @{$store->{blocks}};

	my $blk = $store->{blocks}[0];

	# last chunk in block?
	my $cck = ++$self->{chunk};
	if( $cck >= $blk->{ckcnt} ){
		$store->{chunk} = 0;
		shift @{$store->{blocks}};
	}

	my $buf;
	CORE::read( $store->fh, $buf, 5 ) == 5
		or croak "failed to read data chunk";
	@_ = unpack( "CCCCC", $buf );
	my $kph = ( (( $_[1] & 0xf0) << 3) | ( $_[0] & 0x7f)) 
		* 3.0 / 26;
	return {
		time	=> $blk->{stime} + $cck * $store->recint,
		dur	=> $store->recint,
		pwr	=> ( $_[1] & 0x0f) | ( $_[2] << 4 ),
		spd	=> $kph / 3.6,
		cad	=> $_[3],
		hr	=> $_[4],
	};
}




package Workout::Store::SRM;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store::File';
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

our @fsupported = qw( hr spd cad pwr );

sub filetypes {
	return "srm";
}

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $fname, $a ) = @_;

	my $self = $class->SUPER::new( $fname, $a );

	push @{$self->{fsupported}}, @fsupported;
	$self->{blocks} = undef; # list with data block offsets
	$self->{chunk} = 0; # chunks read in current block
	$self;
}

# TODO: block_add
# TODO: chunk_add
# TODO: flush

=head2 iterate

read header (ie. non-chunk data) from file and return iterator

=cut

sub iterate {
	my( $self ) = @_;

	defined $self->{blocks}
		and croak "file already open";

	$self->{blocks} = [];

	my $fh = $self->fh;
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
	# TODO: read marker
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
	while( $blockcnt-- > 0 ){
		CORE::read( $fh, $buf, 6 ) == 6
			or croak "failed to read data block";

		@_ = unpack( "Vv", $buf );
		push @{$self->{blocks}}, {
			stime	=> $day + $_[0] / 100,
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
	# data chunks are read by next()

	Workout::Store::SRM::Iterator->new( $self );
}


1;
__END__


=head1 SEE ALSO

Workout::Store::File

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
