#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Pwx - read/write Trainingpeaks device agent XML files

=head1 SYNOPSIS

  use Workout::Store::Pwx;

  $src = Workout::Store::Pwx->read( "foo.pwx" );

  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.pwx" );

=head1 DESCRIPTION

Interface to read/write Trainingpeaks device agent files. Inherits from
Workout::Store and implements do_read/_write methods.

=cut

package Workout::Store::Pwx::Read;
use base 'Workout::XmlDescent';
use strict;
use warnings;
use DateTime;
use Geo::Distance;
use Workout::Chunk;
use Carp;


our %nodes = (
	top	=> {
		pwx	=> 'pwx'
	},

	pwx	=> {
		workout	=> 'workout',
		'*'	=> 'ignore',
	},

	workout	=> {
		sporttype	=> 'wksport',
		cmt	=> 'wkcmt',
		time	=> 'wktime',
		athlete	=> 'wkathlete',
		device	=> 'wkdevice',
		segment	=> 'wksegment',
		sample	=> 'wksample',
		'*'	=> 'ignore',
	},
	wksport	=> undef,
	wkcmt	=> undef,
	wktime	=> undef,

	wkathlete	=> {
		name	=> 'athlete',
	},
	athlete	=> undef,

	wkdevice	=> {
		'*'	=> 'ignore',
	},

	wksegment	=> {
		'name'	=> 'segname',
		'summarydata'	=> 'segsummary',
		'*'	=> 'ignore',
	},
	segname	=> undef,
	segsummary	=> {
		beginning	=> 'segstart',
		duration	=> 'segdur',
		'*'	=> 'ignore',
	},
	segstart => undef,
	segdur	=> undef,

	wksample	=> {
		timeoffset	=> 'ctime',
		pwr	=> 'cpwr',
		spd	=> 'cspd',
		dist	=> 'cdist',
		lon	=> 'clon',
		lat	=> 'clat',
		hr	=> 'chr',
		cad	=> 'ccad',
		alt	=> 'calt',
		'*'	=> 'ignore',
	},
	ctime	=> undef,
	cpwr	=> undef,
	cspd	=> undef,
	cdist	=> undef,
	clon	=> undef,
	clat	=> undef,
	chr	=> undef,
	ccad	=> undef,
	calt	=> undef,

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
		start	=> undef, # start time / epoch
		dist	=> 0, # total distance
		time	=> 0, # elapsed seconds
		sam	=> {}, # current sample / chunk
		seg	=> {}, # current segment / marker
		segs	=> [], # finished segments / marker
		io	=> {}, # seen data fields
		nodes	=> \%nodes,
	});
}

sub end_leaf {
	my( $self, $el, $node ) = @_;

	my $name = $node->{node};

	# sample / chunk
	if( $name eq 'ctime' ){
		$self->{sam}{time} = $node->{cdata};

	} elsif( $name eq 'cpwr' ){
		$self->{sam}{pwr} = $node->{cdata};

	} elsif( $name eq 'cspd' ){
		$self->{sam}{spd} = $node->{cdata};

	} elsif( $name eq 'cdist' ){
		$self->{sam}{dist} = $node->{cdata};

	} elsif( $name eq 'clon' ){
		$self->{sam}{lon} = $node->{cdata};

	} elsif( $name eq 'clat' ){
		$self->{sam}{lat} = $node->{cdata};

	} elsif( $name eq 'chr' ){
		$self->{sam}{hr} = $node->{cdata};

	} elsif( $name eq 'ccad' ){
		$self->{sam}{cad} = $node->{cdata};

	} elsif( $name eq 'calt' ){
		$self->{sam}{alt} = $node->{cdata};


	# segment / marker
	} elsif( $name eq 'segname' ){
		$self->{seg}{name} = $node->{cdata};

	} elsif( $name eq 'segstart' ){
		$self->{seg}{start} = $node->{cdata};

	} elsif( $name eq 'segdur' ){
		$self->{seg}{dur} = $node->{cdata};


	# workout

	} elsif( $name eq 'wktime' ){
		$self->{start} = _str2time( $node->{cdata} );
		$self->{Store}->debug( "start: ". $self->{start} );

	} elsif( $name eq 'wksport' ){
		$self->{Store}->sporttype( $node->{cdata} );

	} elsif( $name eq 'wkcmt' ){
		$self->{Store}->note( $node->{cdata} );

	} elsif( $name eq 'athlete' ){
		$self->{Store}->athletename( $node->{cdata} );

	}
}

sub end_node {
	my( $self, $el, $node ) = @_;

	my $name = $node->{node};
	if( $name eq 'wksample' ){
		my $start = $self->{start}
			or return;

		my $sam = $self->{sam};

		my $dur;
		if( ! $self->{Store}->chunk_count ){
			$dur = $sam->{time} - $self->{time};
			$self->{Store}->recint( $dur );
		} else {
			$dur = $self->{Store}->recint;
		}

		my %c = (
			time	=> $start + $sam->{time},
			dur	=> $dur,
		);

		if( exists $sam->{dist} && defined $sam->{dist} ){
			$self->{io}{dist}++;
			$c{dist} = $sam->{dist} - $self->{dist};
			$self->{dist} = $sam->{dist};

		} elsif( exists $sam->{spd} && defined $sam->{spd} ){
			$self->{io}{dist}++;
			$c{dist} = $sam->{spd} * $c{dur};
		}

		if( exists $sam->{pwr} && defined $sam->{pwr} ){
			$self->{io}{work}++;
			$c{work} = $sam->{pwr} * $c{dur};
		}

		if( (exists $sam->{lon} && defined $sam->{lon})
			|| (exists $sam->{lat} && defined $sam->{lat}) ){

			$self->{io}{lon}++;
			$self->{io}{lat}++;
			$c{lon} = $sam->{lon};
			$c{lat} = $sam->{lat};
		}

		if( exists $sam->{hr} && defined $sam->{hr} ){
			$self->{io}{hr}++;
			$c{hr} = $sam->{hr};
		}

		if( exists $sam->{cad} && defined $sam->{cad} ){
			$self->{io}{cad}++;
			$c{cad} = $sam->{cad};
		}

		if( exists $sam->{alt} && defined $sam->{alt} ){
			$self->{io}{ele}++;
			$c{ele} = $sam->{alt};
		}

		$self->{Store}->chunk_add( Workout::Chunk->new(\%c) );

		$self->{sam} = {};
		$self->{time} = $sam->{time};

	} elsif( $name eq 'wksegment' ){
		push @{$self->{segs}}, $self->{seg};
		$self->{seg} = {};

	} elsif( $name eq 'wkdevice' ){
		$self->{Store}->device( $node->{attr}{'{}id'}{Value} );

	}
}

sub end_document {
	my( $self ) = @_;

	# segment -> marker
	foreach my $seg ( @{ $self->{segs} } ){
		$self->{Store}->mark_new({
			start	=> $self->{start} + $seg->{start},
			end	=> $self->{start} + $seg->{start}
				+ $seg->{dur},
			note	=> $seg->{name},
		});
	}

	$self->{Store}->fields_io( keys %{ $self->{io} });

	1;
}


package Workout::Store::Pwx;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use XML::SAX;
use Carp;
use Workout::Filter::Info;

our $VERSION = '0.02';

sub filetypes {
	return "pwx";
}

our %fields_supported = map { $_ => 1; } qw{
	dist
	ele
	lon
	lat
	hr
	cad
	work
};

# TODO: other tags: slope, ...
our %defaults = (
	recint		=> 1,
	athletename	=> 'wkt',
	device		=> 'workout',
	sporttype	=> 'Bike',
);
__PACKAGE__->mk_accessors( keys %defaults );



=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,
		cap_note	=> 1,
	});
	$self;
}

sub from_store {
	my( $self, $store ) = @_;

	$self->SUPER::from_store( $store );

	foreach my $f (qw( athletename device sporttype )){
		$self->$f( $store->$f ) if $store->can( $f );
	}
}


sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $parser = XML::SAX::ParserFactory->parser(
		Handler	=> Workout::Store::Pwx::Read->new({
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

	my $start = $self->time_start;
	my $start_time = _time2str( $start );
	my $note = $self->note || '';

	my $info = Workout::Filter::Info->new( $self->iterate, {
		debug	=> $self->{debug},
	});
	$info->finish;

	my %io = map {
		$_ => 1;
	} $self->fields_io;

	$self->debug( "writing fields: ", join(",", keys %io ) );

	print $fh <<EOHEAD;
<?xml version="1.0" encoding="utf-8"?>
<pwx xmlns="http://www.peaksware.com/PWX/1/0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.peaksware.com/PWX/1/0 http://www.peaksware.com/PWX/1/0/pwx.xsd" xmlns:xsd="http://www.w3.org/2001/XMLSchema" creator="Workout">
<workout>
EOHEAD
	print $fh
		" <athlete>\n",
		"  <name>", &protect($self->athletename) ,"</name>\n",
		" </athlete>\n",
		" <sportType>", &protect($self->sporttype) ,"</sportType>\n",
		" <cmt>", &protect($note), "</cmt>\n",
		" <device id=\"", &protect($self->device), "\">\n",
		"  <make>", &protect($self->device) ,"</make>\n",
		" </device>\n",
		" <time>$start_time</time>\n";

	print $fh " <summarydata>\n",
		"  <beginning>1</beginning>\n",
		"  <duration>", $self->dur, "</duration>\n",
		"  <hr min=\"0\" max=\"0\" avg=\"0\"/>\n",
		"  <spd min=\"0\" max=\"0\" avg=\"0\"/>\n",
		"  <pwr min=\"0\" max=\"0\" avg=\"0\"/>\n",
		"  <cad min=\"0\" max=\"0\" avg=\"0\"/>\n",
		"  <dist>", int($info->dist + 0.5), "</dist>\n",
		"  <alt min=\"0\" max=\"0\" avg=\"0\"/>\n",
		" </summarydata>\n";

	foreach my $m ( $self->marks ){
		print $fh " <segment>\n",
			"  <name>", &protect($m->note), "</name>\n",
			"  <summarydata>\n",
			"   <beginning>", $m->start - $start, "</beginning>\n",
			"   <duration>", $m->end - $m->start, "</duration>\n",
			"  </summarydata>\n",
			" </segment>\n",
	}

	my $dist = 0;
	my $it = $self->iterate;
	while( my $c = $it->next ){

		print $fh " <sample>\n",
			"  <timeoffset>", $c->time - $start,"</timeoffset>\n";

		if( $io{hr} && defined $c->hr ){
			print $fh "  <hr>", $c->hr, "</hr>\n";
		}

		if( $io{dist} ){
			if( $c->dist ){
				$dist += $c->dist;
				print $fh "  <spd>", $c->spd, "</spd>\n";
			}
		}

		if( $io{work} && defined $c->work && $c->work ){
			print $fh "  <pwr>", $c->pwr, "</pwr>\n";
		}

		if( $io{cad} && defined $c->cad ){
			print $fh "  <cad>", $c->cad, "</cad>\n";
		}

		if( $io{dist} ){
			print $fh "  <dist>$dist</dist>\n";
		}

		if( ($io{lon} || $io{lat})
			&& defined $c->lon && defined $c->lat ){

			print $fh "  <lat>", $c->lat, "</lat>\n",
				"  <lon>", $c->lon, "</lon>\n";
		}

		if( $io{ele} && defined $c->ele ){
			print $fh "  <alt>", $c->ele, "</alt>\n",
		}

		print $fh " </sample>\n",
	}

	print $fh <<EOTAIL;
</workout>
</pwx>
EOTAIL
}

1;
__END__

=head1 SEE ALSO

Workout::Store, Workout::XmlDescent, XML::SAX

=head1 AUTHOR

Rainer Clasen

=cut
