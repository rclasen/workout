#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::Store::Wkt - read/write Wkt files

=head1 SYNOPSIS

  $src = Workout::Store::Wkt->read( "foo.wkt" );

  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.wkt" );


=head1 DESCRIPTION

Interface to read/write Wkt files. Inherits from Workout::Store and
implements do_read/_write methods.

The Wkt file format is the "native" file format for the Workout library.
Wkt files are always encoded as UTF8.

=cut

package Workout::Store::Wkt;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Workout::Chunk;
use Carp;
use DateTime;


our $VERSION = '0.01';

sub filetypes {
	return "wkt";
}

our $re_fieldsep = qr/\t/;
our $re_stripnl = qr/[\r\n]+$/;
our $re_mark = qr/^(\d+(?:\.\d+)?)\t(\d+(?:\.\d+)?)\t(.*)/;
our $re_empty = qr/^\s*$/;
our $re_block = qr/^\[(\w+)\]/;
our $re_value = qr/^\s*(\S+)\s*=\s*(.*)\s*$/;
our $re_colsep = qr/\s*,\s*/;

our %defaults = (
);
__PACKAGE__->mk_accessors( keys %defaults );

our %meta = (
	sport		=> undef,
	bike		=> undef,
	circum		=> 2000,
	zeropos		=> 100,
	slope		=> 1,
	athletename	=> 'wkt',
);

=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$a->{meta}||={};
	$class->SUPER::new({
		%defaults,
		%$a,
		meta	=> {
			%meta,
			%{$a->{meta}},
		},
		columns		=> [],
		cap_block	=> 1,
	});
}

sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $parser;
	my $gotparams;
	my $gotchunks;

	binmode( $fh, ':encoding(utf8)' );
	while( defined(my $l = <$fh>) ){
		$l =~ s/$re_stripnl//g;

		if( $l =~/$re_empty/ ){
			next;

		} elsif( $l =~ /$re_block/ ){
			my $blockname = lc $1;

			if( $blockname eq 'params' ){
				$parser = \&parse_params;
				$gotparams++;

			} elsif( $blockname eq 'chunks' ){
				$gotparams or croak "missing parameter block";
				$parser = \&parse_chunks;
				$gotchunks++;

			} elsif( $blockname eq 'markers' ){
				$gotchunks or croak "missing chunk block";
				$parser = \&parse_markers;

			} else {
				$parser = undef;
			}

		} elsif( $parser ){
			$parser->( $self, $l );

		} # else ignore input
	}
}

sub parse_params {
	my( $self, $l ) = @_;

	my( $k, $v ) = ($l =~ /$re_value/)
		or croak "misformed input: $l";

	$k = lc $k;

	if( $k eq 'version' ){
		($v == 1)
			or croak "unsupported version: $v";
	
	} elsif( $k eq 'note' ){
		$v =~ s/\\n/\n/g;
		$self->meta_field('note', $v );

	} elsif( $k eq 'columns' ){
		my @cols = split( /$re_colsep/, lc $v);
		grep { $_ eq 'time' } @cols
			or croak "missing time column";
		grep { $_ eq 'dur' } @cols
			or croak "missing duration column";
		$self->fields_io( @cols );
		$self->{columns} = \@cols;

	} elsif( $k eq 'athlete' ){
		$self->meta_field('athletename', $v );

	} elsif( $k eq 'sport' ){
		$self->meta_field('sport', $v );

	} elsif( $k eq 'bike' ){
		$self->meta_field('bike', $v );

	} elsif( $k eq 'circum' ){
		$self->meta_field('circum', $v );

	} elsif( $k eq 'slope' ){
		$self->meta_field('slope', $v );

	} elsif( $k eq 'zeropos' ){
		$self->meta_field('zeropos', $v );

	} elsif( $self->{debug} ){
		$self->debug( "found unsupported field: $k" );
	}
}

sub parse_chunks {
	my( $self, $l ) = @_;

	# TODO: be more paranoid about input
	my %a;
	@a{@{$self->{columns}}} = map {
		$_ eq '' ? undef : $_;
	} split( /$re_fieldsep/, $l );

	$self->chunk_add( Workout::Chunk->new( \%a ));
}

sub parse_markers {
	my( $self, $l ) = @_;

	my( $start, $end, $note ) = $l =~ /$re_mark/
		or croak "invalid marker syntax: $l";

	$note =~ s/\\n/\n/g;

	# TODO: skip marker outside the chunk range
	$self->mark_new( {
		start	=> $1,
		end	=> $2,
		meta	=> {
			note	=> $3,
		},
	});
}

sub do_write {
	my( $self, $fh, $fname ) = @_;

	$self->chunk_last or croak "no data";

	my @fields = sort { $a cmp $b } $self->fields_io;
	$self->debug( "writing columns: ". join(",", @fields) );

	binmode( $fh, ':encoding(utf8)' );
	print $fh "[Params]\n";
	print $fh "Version=1\n";
	print $fh "Columns=", join(",", @fields), "\n";
	if( my $note = $self->meta_field('note') ){
		$note =~ s/\n/\\n/g;
		print $fh "Note=", $note, "\n"
	}
	if( my $a = $self->meta_field('athletename') ){
		print $fh "Athlete=$a\n";
	}
	if( my $a = $self->meta_field('sport') ){
		print $fh "Sport=$a\n";
	}
	if( my $a = $self->meta_field('bike') ){
		print $fh "Bike=$a\n";
	}
	if( my $a = $self->meta_field('circum') ){
		print $fh "Circum=$a\n";
	}
	if( my $a = $self->meta_field('slope') ){
		print $fh "Slope=$a\n";
	}
	if( my $a = $self->meta_field('zeropos') ){
		print $fh "Zeropos=$a\n";
	}

	print $fh "[Chunks]\n";
	my $it = $self->iterate;
	while( my $ck = $it->next ){
		print $fh join( "\t", map { 
			$_ || '';
		} @$ck{@fields}), "\n";
	}

	print $fh "[Markers]\n";
	foreach my $mk ( @{$self->marks} ){
		my $note = $mk->meta_field('note') || '';
		$note =~ s/\n/\\n/g;

		print $fh join( "\t", 
			$mk->start	|| 0,
			$mk->end	|| '',
			$note,
		), "\n";
	}
}


1;
__END__

=head1 SEE ALSO

Workout::Store

=head1 AUTHOR

Rainer Clasen

=cut
