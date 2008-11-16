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

=cut

package Workout::Store::Wkt;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store::Memory';
use Workout::Chunk;
use Carp;
use DateTime;


our $VERSION = '0.01';

sub filetypes {
	return "wkt";
}

=head2 new( $file, $args )

constructor

=cut

sub new {
	my( $class, $a ) = @_;

	$a||={};
	$class->SUPER::new({
		%$a,
		columns	=> [],
	});
}

sub do_read {
	my( $self, $fh ) = @_;

	my $parser;
	my $gotparams;

	while( defined(my $l = <$fh>) ){

		if( $l =~/^\s*$/ ){
			next;

		} elsif( $l =~ /^\[(\w+)\]/ ){
			my $blockname = lc $1;

			if( $blockname eq 'params' ){
				$parser = \&parse_params;
				$gotparams++;

			} elsif( $blockname eq 'chunks' ){
				$gotparams or croak "missing parameter block";
				$parser = \&parse_chunks;

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

	my @row = split( /\t/, $l );
	# TODO: be more paranoid about input

	my %a = (
		prev	=> $self->{last},
		map {
			$_ => shift @row;
		} @{$self->{columns}},
	);
	my $ck = Workout::Chunk->new( \%a );

	if( $self->{last} && $self->{last}->time > $ck->stime ){
		croak "backward timestep not allowed";
	}

	if( $ck->isblockfirst ){
		$self->block_add;
		$self->debug( "block end at ". $ck->time );
	}
	$self->_chunk_add( $ck );
}

=head2 write

write data to disk.

=cut

# TODO: specify what to write: hr, spd, cad, ele, pwr
sub do_write {
	my( $self, $fh ) = @_;

	$self->{last} or croak "no data";

	my @fields = &Workout::Chunk::core_fields();

	print $fh "[Params]\n";
	print $fh "Version=1\n";
	print $fh "Columns=", join(",", @fields), "\n";


	print $fh "[Chunks]\n";
	foreach my $block ( @{$self->{data}} ){
		foreach my $ck ( @$block ){
			print $fh join( "\t", map { 
				$_ || 0;
			} @$ck{@fields}), "\n";
		}
	}
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
