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

To me its unclear if Pwx requires fixed recording intervals or if samples
may cover varying time. Header doesn't contain any recording interval and
the actual samples could be specified properly for varying intervals,
aswell. To extend the confusion a "stopdetectionsetting" was introdued -
which kind of supports the varying interval theory.

So, without further clarification this parser/writer assumes, it's varying
intervals. Unfortunatly this makes it quite picky about how samples need
to be written for recording gaps. As a result the first sample after a
recording gap tends to be wrong. Speed will be low, and the whole gap will
have the same average power - possibly distorting the averages.
If the "stopdetectionsetting" is provided, impact is lmited by this, but
it's also unclear how exactly this setting should be evaluated.

I couldn't find any reference on the timeoffset - I'd expect it to be the
time at the end of a sample... but I've seen many files having the first
timeoffset=0.

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
		summarydata	=> 'wksummarydata',
		sample	=> 'wksample',
		'*'	=> 'ignore',
	},
	wksport	=> undef,
	wkcmt	=> undef,
	wktime	=> undef,

	wkathlete	=> {
		name	=> 'athlete',
		'*'	=> 'ignore',
	},
	athlete	=> undef,

	wkdevice	=> {
		# TODO: look for device extensions
		make		=> 'devmake',
		model		=> 'devmodel',
		stopdetectionsetting	=> 'stopdetection',
		'*'	=> 'ignore',
	},
	devmake		=> undef,
	devmodel	=> undef,
	stopdetection	=> undef,

	wksummarydata	=> {
		beginning	=> 'sumstart',
		duration	=> 'sumdur',
		durationstopped	=> 'sumdurstop',
		work		=> 'sumwork',
		tss		=> 'sumtss',
		normalizedpower	=> 'sumnpwr',
		hr		=> 'sumhr',
		spd		=> 'sumspd',
		pwr		=> 'sumpwr',
		cad		=> 'sumcad',
		dist		=> 'sumdist',
		alt		=> 'sumalt',
		temp		 => 'sumtemp',
		variabilityindex	=> 'sumvi',
		climbingelevation	=> 'sumascent',
		descendingelevation	=> 'sumdescent',
		'*'	=> 'ignore',
	},
	sumstart	=> undef,
	sumdur		=> undef,
	sumdurstop	=> undef,
	sumwork		=> undef,
	sumtss		=> undef,
	sumnpwr		=> undef,
	sumhr		=> undef,
	sumspd		=> undef,
	sumpwr		=> undef,
	sumcad		=> undef,
	sumdist		=> undef,
	sumalt		=> undef,
	sumtemp		=> undef,
	sumvi		=> undef,
	sumascent	=> undef,
	sumdescent	=> undef,

	wksegment	=> {
		'name'	=> 'segname',
		'summarydata'	=> 'segsummary',
		'*'	=> 'ignore',
	},
	segname	=> undef,
	segsummary	=> {
		beginning	=> 'segstart',
		duration	=> 'segdur',
		durationstopped	=> 'segdurstop',
		work		=> 'segwork',
		tss		=> 'segtss',
		normalizedpower	=> 'segnpwr',
		hr		=> 'seghr',
		spd		=> 'segspd',
		pwr		=> 'segpwr',
		cad		=> 'segcad',
		dist		=> 'segdist',
		alt		=> 'segalt',
		temp		 => 'segtemp',
		variabilityindex	=> 'segvi',
		climbingelevation	=> 'segascent',
		descendingelevation	=> 'segdescent',
		'*'		=> 'ignore',
	},
	segstart	=> undef,
	segdur		=> undef,
	segdurstop	=> undef,
	segwork		=> undef,
	segtss		=> undef,
	segnpwr		=> undef,
	seghr		=> undef,
	segspd		=> undef,
	segpwr		=> undef,
	segcad		=> undef,
	segdist		=> undef,
	segalt		=> undef,
	segtemp		=> undef,
	segvi		=> undef,
	segascent	=> undef,
	segdescent	=> undef,

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
		temp	=> 'ctemp',
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
	ctemp	=> undef,

	ignore	=> {
		'*'	=> 'ignore',
	},
);

our $re_time = qr/^\s*(-?\d\d\d\d+)-(\d\d)-(\d\d)	# date
	T(\d\d):(\d\d):(\d\d)(\.\d+)?			# time
	(?:(Z)|(?:([+-]\d\d):(\d\d)))?\s*$/x;		# zone

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
		stopdetect	=> undef, # max gap before device pause
		dist	=> 0, # total distance
		ltime	=> 0, # last elapsed seconds
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

	} elsif( $name eq 'ctemp' ){
		$self->{sam}{temp} = $node->{cdata};


	# segment / marker
	} elsif( $name eq 'segname' ){
		$self->{seg}{name} = $node->{cdata};

	} elsif( $name eq 'segstart' ){
		$self->{seg}{dur_start} = $node->{cdata};

	} elsif( $name eq 'segdur' ){
		$self->{seg}{dur} = $node->{cdata};

	} elsif( $name eq 'segdurstop' ){
		$self->{seg}{dur_gap} = $node->{cdata};

	} elsif( $name eq 'segwork' ){
		$self->{seg}{work} = $node->{cdata};

	} elsif( $name eq 'segtss' ){
		$self->{seg}{tss} = $node->{cdata};

	} elsif( $name eq 'segnpwr' ){
		$self->{seg}{npwr} = $node->{cdata};

	} elsif( $name eq 'seghr' ){
		$self->{seg}{hr_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{hr_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{hr_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segspd' ){
		$self->{seg}{spd_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{spd_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{spd_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segpwr' ){
		$self->{seg}{spd_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{spd_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{spd_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segcad' ){
		$self->{seg}{spd_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{spd_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{spd_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segdist' ){
		$self->{seg}{dist} = $node->{cdata};

	} elsif( $name eq 'segalt' ){
		$self->{seg}{spd_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{spd_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{spd_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segtemp' ){
		$self->{seg}{spd_min} = $self->{stack}[1]{attr}{'{}min'}{Value};
		$self->{seg}{spd_max} = $self->{stack}[1]{attr}{'{}max'}{Value};
		$self->{seg}{spd_avg} = $self->{stack}[1]{attr}{'{}avg'}{Value};

	} elsif( $name eq 'segvi' ){
		$self->{seg}{vi} = $node->{cdata};

	} elsif( $name eq 'segascent' ){
		$self->{seg}{ascent} = $node->{cdata};

	} elsif( $name eq 'segdescent' ){
		$self->{seg}{descent} = $node->{cdata};


	# workout

	} elsif( $name eq 'stopdetection' ){
		$self->{stopdetect}	=> $node->{cdata};

	} elsif( $name eq 'devmake' ){
		$self->{Store}->meta_field('manufacturer', $node->{cdata} );

	} elsif( $name eq 'devmodel' ){
		$self->{Store}->meta_field('device', $node->{cdata} );

	} elsif( $name eq 'wktime' ){
		$self->{start} = _str2time( $node->{cdata} );
		$self->{Store}->debug( "start: ". $self->{start} );

	} elsif( $name eq 'wksport' ){
		$self->{Store}->meta_field('sport', $node->{cdata} );

	} elsif( $name eq 'wkcmt' ){
		$self->{Store}->meta_field('note', $node->{cdata} );

	} elsif( $name eq 'athlete' ){
		$self->{Store}->meta_field('athletename', $node->{cdata} );

	} elsif( $name eq 'sumstart' ){
		$self->{Store}->meta_field('dur_start', $node->{cdata} );

	} elsif( $name eq 'sumdur' ){
		$self->{Store}->meta_field('dur', $node->{cdata} );

	} elsif( $name eq 'sumdurstop' ){
		$self->{Store}->meta_field('dur_gap', $node->{cdata} );

	} elsif( $name eq 'sumwork' ){
		$self->{Store}->meta_field('work', $node->{cdata} );

	} elsif( $name eq 'segtss' ){
		$self->{Store}->meta_field('tss', $node->{cdata} );

	} elsif( $name eq 'segnpwr' ){
		$self->{Store}->meta_field('npwr', $node->{cdata} );

	} elsif( $name eq 'seghr' ){
		$self->{Store}->meta_field('hr_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('hr_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('hr_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segspd' ){
		$self->{Store}->meta_field('spd_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('spd_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('spd_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segpwr' ){
		$self->{Store}->meta_field('spd_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('spd_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('spd_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segcad' ){
		$self->{Store}->meta_field('spd_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('spd_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('spd_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segdist' ){
		$self->{Store}->meta_field('dist', $node->{cdata} );

	} elsif( $name eq 'segalt' ){
		$self->{Store}->meta_field('spd_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('spd_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('spd_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segtemp' ){
		$self->{Store}->meta_field('spd_min',
			$self->{stack}[1]{attr}{'{}min'}{Value} );
		$self->{Store}->meta_field('spd_max',
			$self->{stack}[1]{attr}{'{}max'}{Value} );
		$self->{Store}->meta_field('spd_avg',
			$self->{stack}[1]{attr}{'{}avg'}{Value} );

	} elsif( $name eq 'segvi' ){
		$self->{Store}->meta_field('vi', $node->{cdata} );

	} elsif( $name eq 'segascent' ){
		$self->{Store}->meta_field('ascent', $node->{cdata} );

	} elsif( $name eq 'segdescent' ){
		$self->{Store}->meta_field('descent', $node->{cdata} );

	}
}

sub end_node {
	my( $self, $el, $node ) = @_;

	my $name = $node->{node};
	if( $name eq 'wksample' ){
		my $start = $self->{start}
			or return;

		my $sam = $self->{sam};

		my $dur = $sam->{time} - $self->{ltime};
		$self->{ltime} = $sam->{time};

		if( $dur < 0.1 ){
			return;
		}

		# try to identify gaps by stopdetect: 
		my $stopdetect = $self->{stopdetect};
		if( defined $stopdetect && $dur > $stopdetect ){
			$dur = $stopdetect; # TODO: just guessing. Still wrong in 99%.
		}

		my %c = (
			time	=> $start + $sam->{time},
			dur	=> $dur,
		);

		if( exists $sam->{dist} && defined $sam->{dist} ){
			$self->{io}{dist}++;
			$c{dist} = $sam->{dist} - $self->{dist};
			$self->{dist} = $sam->{dist};

			# try to identify gaps by speed+distance:
			if( exists $sam->{spd} && $sam->{spd} > 0 ){
				my $sdur = $c{dist} / $sam->{spd};
				if( $dur > $sdur ){
					$dur = $sdur;
					$c{dur} = $sdur;
				}
			}

		} elsif( exists $sam->{spd} && defined $sam->{spd} ){
			$self->{io}{dist}++;
			$c{dist} = $sam->{spd} * $c{dur};
		}

		if( $dur < 0.1 ){
			return;
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

		if( exists $sam->{temp} && defined $sam->{temp} ){
			$self->{io}{temp}++;
			$c{temp} = $sam->{temp};
		}

		$self->{Store}->chunk_add( Workout::Chunk->new(\%c) );

		$self->{sam} = {};

	} elsif( $name eq 'wksegment' ){
		push @{$self->{segs}}, $self->{seg};
		$self->{seg} = {};

	} elsif( $name eq 'wkdevice' ){
		#$self->{Store}->meta_field('device', $node->{attr}{'{}id'}{Value} );

	}
}

sub end_document {
	my( $self ) = @_;

	# segment -> marker
	foreach my $seg ( @{ $self->{segs} } ){
		$self->{Store}->mark_new({
			start	=> $self->{start} + $seg->{dur_start},
			end	=> $self->{start} + $seg->{dur_start}
				+ $seg->{dur},
			meta	=> $seg,
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
	temp
};

our %defaults = (
);
__PACKAGE__->mk_accessors( keys %defaults );

our %meta = (
	sport		=> undef,
	athletename	=> 'wkt',
	device		=> 'Pwx',
);



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
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 0,
	});
	$self;
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

sub n { $_[0] || 0; }

sub round { int( $_[0] + 0.5 ); }

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

	my $info = $self->info_meta;

	my $start = $info->{time_start};
	my $start_time = _time2str( $start );
	my $note = $info->{note} || '';


	my %io = map {
		$_ => 1;
	} $self->fields_io;

	$self->debug( "writing fields: ", join(",", keys %io ) );

	my $stopdetect = 15; # TODO: hack
	if( $self->recint ){
		$stopdetect = 2* $self->recint;
	}
	$self->debug( "stopdetect: $stopdetect");

	my $device = $info->{device};
	my $manu = $info->{manufacturer};
	if( $device && $manu ){
		$device =~ s/^$manu\s+//i;
	}

	# TODO: write meta: map sport
	my $sport = $info->{sport};

	print $fh <<EOHEAD;
<?xml version="1.0" encoding="utf-8"?>
<pwx xmlns="http://www.peaksware.com/PWX/1/0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.peaksware.com/PWX/1/0 http://www.peaksware.com/PWX/1/0/pwx.xsd" xmlns:xsd="http://www.w3.org/2001/XMLSchema" creator="Workout">
<workout>
EOHEAD
	print $fh
		" <athlete>\n",
		"  <name>", &protect($info->{athletename}) ,"</name>\n",
		" </athlete>\n",
		" <sportType>", &protect($sport) ,"</sportType>\n",
		" <cmt>", &protect($note), "</cmt>\n",
		" <device id=\"", &protect($info->{device}), "\">\n",
		"  <make>", &protect($manu) ,"</make>\n",
		"  <model>", &protect($device) ,"</model>\n",
		#TODO:"  <stopdetectionsetting>", $stopdetect ,"</stopdetectionsetting>\n",
		# TODO: write device extensions
		" </device>\n",
		" <time>$start_time</time>\n";

	print $fh " <summarydata>\n",
		"  <beginning>1</beginning>\n",
		"  <duration>", &n($info->{dur}), "</duration>\n",
		"  <hr min=\"", &n($info->{hr_min}),
			"\" max=\"", &n($info->{hr_max}),
			"\" avg=\"", &n($info->{hr_avg}), "\"/>\n",
		"  <spd min=\"", &n($info->{spd_min}),
			"\" max=\"", &n($info->{spd_max}),
			"\" avg=\"", &n($info->{spd_avg}), "\"/>\n",
		"  <pwr min=\"", &n($info->{pwr_min}),
			"\" max=\"", &n($info->{pwr_max}),
			"\" avg=\"", &n($info->{pwr_avg}), "\"/>\n",
		"  <cad min=\"", &n($info->{cad_min}),
			"\" max=\"", &n($info->{cad_max}),
			"\" avg=\"", &n($info->{cad_avg}), "\"/>\n",
		"  <dist>", &round($info->{dist}), "</dist>\n",
		"  <alt min=\"", &n($info->{ele_min}),
			"\" max=\"", &n($info->{ele_max}),
			"\" avg=\"", &n($info->{ele_avg}), "\"/>\n",
		# TODO: write meta summary
		" </summarydata>\n";

	foreach my $m ( $self->marks ){
		print $fh " <segment>\n",
			"  <name>", &protect($m->meta_field('note')), "</name>\n",
			"  <summarydata>\n",
			"   <beginning>", $m->start - $start, "</beginning>\n",
			"   <duration>", $m->end - $m->start, "</duration>\n",
			# TODO: write meta summary marker
			"  </summarydata>\n",
			" </segment>\n",
	}

	my $dist = 0;
	my $it = $self->iterate;
	while( my $c = $it->next ){

		if( $c->isblockfirst ){
			print $fh " <sample>\n",
				"  <timeoffset>", $c->time - $c->dur - $start,"</timeoffset>\n",
				" </sample>\n";
		}

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

		if( $io{temp} && defined $c->temp ){
			print $fh "  <temp>", $c->temp, "</temp>\n",
		}

		# TODO: time

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
