#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Gpx - read/write GPS tracks in XML format

=head1 SYNOPSIS

  use Workout::Store::Gpx;

  $src = Workout::Store::Gpx->read( "foo.gpx" );

  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.gpx" );

=head1 DESCRIPTION

Interface to read/write GPS files. Inherits from Workout::Store and
implements do_read/_write methods.

=cut

package Workout::Store::Gpx::Read;
use base 'Workout::XmlDescent';
use strict;
use warnings;
use DateTime;
use Geo::Distance;
use Workout::Chunk;
use Carp;

our %nodes = (
	top	=> {
		gpx	=> 'gpx'
	},

	gpx	=> {
		trk	=> 'trk',
		'*'	=> 'ignore',
	},

	trk	=> {
		trkseg	=> 'trkseg',
		cmt	=> 'trkcmt',
		#name	=> 'trkname',
		'*'	=> 'ignore',
	},
	trkname		=> undef,
	trkcmt		=> undef,

	trkseg	=> {
		trkpt	=> 'trkpt',
		'*'	=> 'ignore',
	},

	trkpt	=> {
		ele	=> 'trkele',
		time	=> 'trktime',
		'*'	=> 'ignore',
	},
	trkele		=> undef,
	trktime		=> undef,

	ignore	=> {
		'*'	=> 'ignore',
	},
);

our $re_time = qr/^\s*(-?\d\d\d\d+)-(\d\d)-(\d\d)	# date
	T(\d\d):(\d\d):(\d\d)(\.\d+)?			# time
	(?:(Z)|(([+-]\d\d):(\d\d)))?\s*$/x;		# zone

sub _str2time {
	my( $time ) = @_;

	my( $year, $mon, $day, $hour, $min, $sec, $nsec, $z, $zhour, $zmin ) 
		= ( $time =~ /$re_time/ )
		or croak "invalid time format: $time";

	if( $z || !defined $zhour || ! defined $zmin ){
		$zhour = '+00';
		$zmin = '00';
	}
	$nsec ||= 0;

	DateTime->new(
		year	=> $year,
		month	=> $mon,
		day	=> $day,
		hour	=> $hour,
		minute	=> $min,
		second	=> $sec,
		nanosecond	=> $nsec * 1000000000,
		time_zone	=> $zhour.$zmin,
	)->hires_epoch;
}

sub new {
	my $proto = shift;
	my $a = shift || {};

	$proto->SUPER::new({
		Store	=> undef,
		%$a,
		gcalc	=> Geo::Distance->new,
		cmt	=> undef,
		pt	=> {}, # current point
		lpt	=> undef, # last point
		nodes	=> \%nodes,
	});
}

sub end_leaf {
	my( $self, $el, $node ) = @_;

	my $name = $node->{node};
	if( $name eq 'trktime' ){
		$self->{pt}{time} = _str2time( $node->{cdata} );

	} elsif( $name eq 'trkele' ){
		$self->{pt}{ele} = $node->{cdata};
		++$self->{has_ele};

	} elsif( $name eq 'trkcmt' ){
		$self->{cmt} ||= $node->{cdata};

	#} elsif( $name eq 'trkname' ){

	}
}

sub end_node {
	my( $self, $el, $node ) = @_;

	my $name = $node->{node};
	if( $name eq 'trkpt' ){
		$self->end_trkpt( $node->{attr} );

	} elsif( $name eq 'trkseg' ){
		$self->{lpt} = undef;

	} elsif( $name eq 'gpx' ){
		$self->{Store}->meta_field( 'note', $self->{cmt} );

	}
}

sub end_trkpt {
	my( $self, $attr ) = @_;

	my $pt = $self->{pt};
	$self->{pt} = {};

	# TODO: calculate time based on constant speed
	return unless $pt->{time};

	$pt->{lon} = $attr->{'{}lon'}{Value};
	$pt->{lat} = $attr->{'{}lat'}{Value};
	my $dur = 0.015;
	my $dist = 0;

	if( defined( my $lpt = $self->{lpt} ) ){
		$dur = $pt->{time} - $lpt->{time};
		$dist = $self->{gcalc}->distance( 'meter',
			$lpt->{lon}, $lpt->{lat},
			$pt->{lon}, $pt->{lat},
		);
	}

	return if $dur < 0.01;

	$self->{Store}->chunk_add( Workout::Chunk->new({
		%$pt,
		dur     => $dur,
		dist    => $dist,
	}) );

	$self->{lpt} = $pt;
}

sub end_document {
	my( $self ) = @_;

	my @fields = ( $self->{Store}->fields_essential, 'dist' );
	push @fields, 'ele' if $self->{has_ele};

	$self->{Store}->fields_io( @fields );

	$self->{has_ele} = 0;
	$self->{cmt} = undef;

	1;
}


package Workout::Store::Gpx;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use XML::SAX;
use Carp;

our $VERSION = '0.02';

sub filetypes {
	return "gpx";
}

our %defaults = (
);

our %meta = (
	sport	=> undef,
	device	=> 'Gpx',
);

our %fields_essential = map { $_ => 1; } qw{
	lon
	lat
};

our %fields_supported = map { $_ => 1; } qw{
	dist
	ele
};

# TODO: use $pt->{extensions} = {} to store hr, cad, work, temp
# TODO: verify read values are numbers

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	$a->{meta}||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		meta	=> {
			%meta,
			%{$a->{meta}},
		},
		fields_essential	=> {
			%fields_essential,
		},
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,
	});
	$self;
}

sub do_read {
	my( $self, $fh, $fname ) = @_;

	# TODO: allow filtering tracks by name/id
	# TODO: support reading routes
	my $parser = XML::SAX::ParserFactory->parser(
		Handler	=> Workout::Store::Gpx::Read->new({
			Store	=> $self,
		}),
	) or croak 'cannot start parser';

	$parser->parse_file( $fh )
		or croak "parse failed: $!";

}


sub _time2str {
	my( $time ) = @_;

	my $d = DateTime->from_epoch(
		epoch	=> $time,
		time_zone	=> 'UTC',
	);
	return $d->nanosecond
		? $d->strftime( '%Y-%m-%dT%H:%M:%S.%6NZ' )
		: $d->strftime( '%Y-%m-%dT%H:%M:%SZ' );
}

sub protect {
	my $s = shift;

	$s ||= '';

	$s =~ s/&/&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/"/&quot;/g;

	$s;
}

sub do_write {
	my( $self, $fh, $fname ) = @_;

	$self->chunk_count
		or croak "no data";

	binmode( $fh, ':encoding(utf8)' );

	my( $minlon, $minlat, $maxlon, $maxlat );
	my $it = $self->iterate;
	while( my $c = $it->next ){
		if( ! defined $minlon || $c->lon < $minlon ){
			$minlon = $c->lon;
		}

		if( ! defined $minlat || $c->lat < $minlat ){
			$minlat = $c->lat;
		}

		if( ! defined $maxlon || $c->lon > $maxlon ){
			$maxlon = $c->lon;
		}

		if( ! defined $maxlat || $c->lat > $maxlat ){
			$maxlat = $c->lat;
		}
	}

	my $now = _time2str( time );

	my %write = map {
		$_ => 1;
	} $self->fields_io;
	$self->debug( "writing fields: ", join(",", keys %write ) );

	print $fh <<EOHEAD;
<?xml version="1.0" encoding="utf-8"?>
<gpx xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" creator="Workout::Store::Gpx" xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd" xmlns="http://www.topografix.com/GPX/1/0">
<desc></desc>
<time>$now</time>
<bounds maxlat="$maxlat" maxlon="$maxlon" minlat="$minlat" minlon="$minlon" />
<trk>
EOHEAD
	print $fh "<cmt>", &protect( $self->meta_field('note') ), "</cmt>\n",
		"<trkseg>\n";

	$it = $self->iterate;
	while( my $c = $it->next ){
	
		if( $c->isblockfirst ){
			print $fh "</trkseg>\n<trkseg>\n";
		}

		print $fh '<trkpt lat="', $c->lat, '" lon="', $c->lon, '">', "\n";
		print $fh '<ele>', int($c->ele), '</ele>',"\n"
			if $write{ele} && defined $c->ele;
		print $fh '<time>', _time2str($c->time), '</time>',"\n",
			'</trkpt>',"\n";
	}

	print $fh <<EOTAIL;
</trkseg>
</trk>
</gpx>
EOTAIL
}

1;
__END__

=head1 SEE ALSO

Workout::Store, Workout::XmlDescent, XML::SAX

=head1 AUTHOR

Rainer Clasen

=cut
