#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::SkipUndef;

=head1 NAME

Workout::Filter::SkipUndef - Skip chunks when some fields are undef

=head1 SYNOPSIS

  $ath = Workout::Athlete->new;
  $src = Workout::Store::Wkt->read( "foo.gpx" );

  $dst = Workout::Store::Gpx->new;
  $iter = Workout::Filter->new( $src, {
  	fields => [ $dst->fields_essential ],
  } );

  $dst->from( $iter );

=head1 DESCRIPTION

Skips chunks when some fields are undefined. This allows to filter out
chunks that lack fields you need further down the pipeline.

=cut


use strict;
use warnings;
use base 'Workout::Filter::Base';

our $VERSION = '0.01';

my %defaults = (
	fields	=> [],
);

__PACKAGE__->mk_accessors( keys %defaults );

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $src, $a ) = @_;

	$a||={};
	$class->SUPER::new( $src, {
		%defaults,
		%$a,
	});
}

=head1 METHODS

=head2 fields

get/set the list of fields that must be defined.

=cut

sub fields_io {
	my $self = shift;

	my %fields = map { $_ => 1 } $self->SUPER::fields_io;
	foreach my $f ( @{ $self->{fields} } ){
		delete $fields{$f};
	}

	keys %fields;
}

sub process {
	my $self = shift;

	my $i;

	INPUT: while( $i = $self->_fetch ){
		foreach my $f ( @{ $self->{fields} } ){
			defined $i->$f or next INPUT;
		}
		last INPUT;
	}

	$i or return;

	return $i->clone({ prev => $self->last })
}

1;
__END__

=head1 SEE ALSO

Workout::Filter::Base

=head1 AUTHOR

Rainer Clasen

=cut
