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

  use Workout::Store::Wkt;

  $src = Workout::Store::Wkt->read( "foo.wkt" );
  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.wkt" );


=head1 DESCRIPTION

Interface to read/write Wkt files.

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
our $re_mark = qr/^(\d*)\t(\d*)\t(.*)/;

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$class->SUPER::new({
		%$a,
		columns		=> [],
		cap_block	=> 1,
		cap_note	=> 1,
	});
}

sub do_read {
	my( $self, $fh ) = @_;

	my $parser;
	my $gotparams;
	my $gotchunks;

	my $re_empty = qr/^\s*$/;
	my $re_block = qr/^\[(\w+)\]/;

	binmode( $fh, ':encoding(utf8)' );
	while( defined(my $l = <$fh>) ){

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

	my( $k, $v ) = ($l =~ /^\s*(\S+)\s*=\s*(.*)\s*$/)
		or croak "misformed input: $l";

	$k = lc $k;

	if( $k eq 'version' ){
		($v == 1)
			or croak "unsupported version: $v";
	
	} elsif( $k eq 'note' ){
		$self->note( $v );

	} elsif( $k eq 'columns' ){
		my @cols = split( /\s*,\s*/, lc $v);
		grep { /^time$/ } @cols
			or croak "missing time column";
		grep { /^dur$/ } @cols
			or croak "missing duration column";
		$self->{columns} = \@cols;

	}
	
}

sub parse_chunks {
	my( $self, $l ) = @_;

	# TODO: be more paranoid about input
	my %a;
	@a{@{$self->{columns}}} = split( /$re_fieldsep/, $l );

	$self->chunk_add( Workout::Chunk->new( \%a ));
}

sub parse_markers {
	my( $self, $l ) = @_;

	$l =~ /$re_mark/
		or croak "invalid marker syntax: $l";
	# TODO: skip marker outside the chunk range
	$self->mark_new( {
		start	=> $1,
		end	=> $2,
		note	=> $3,
	});
}

=head2 write

write data to disk.

=cut

# TODO: specify what to write: hr, spd, cad, ele, pwr
sub do_write {
	my( $self, $fh ) = @_;

	$self->chunk_last or croak "no data";

	my @fields = &Workout::Chunk::core_fields();

	binmode( $fh, ':encoding(utf8)' );
	print $fh "[Params]\n";
	print $fh "Version=1\n";
	print $fh "Columns=", join(",", @fields), "\n";
	print $fh "Note=", $self->note, "\n" if $self->note;


	print $fh "[Chunks]\n";
	my $it = $self->iterate;
	while( my $ck = $it->next ){
		print $fh join( "\t", map { 
			$_ || 0;
		} @$ck{@fields}), "\n";
	}

	print $fh "[Markers]\n";
	foreach my $mk ( @{$self->marks} ){
		print $fh join( "\t", 
			$mk->start	|| 0,
			$mk->end	|| '',
			$mk->note	|| '',
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
