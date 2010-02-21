#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

package Workout::Filter::Concat;

=head1 NAME

Workout::Filter::Concat - Concatenate data of multiple sources

=head1 SYNOPSIS

  $first = Workout::Store::Gpx->read( "input1.srm" );
  $second = Workout::Store::SRM->read( "input2.srm" );

  $concat = Workoute::Filter::Concat( $first, {
  	sources	=> [ $second ],
  });

  while( $chunk = $concat->next ){
  	# do something
  }

=head1 DESCRIPTION

reads chunks from multiple sources in turn.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Iterator';
use Carp;

our $VERSION = '0.01';

__PACKAGE__->mk_ro_accessors(qw(
	sources
	srcidx
));

=head1 CONSTRUCTOR

=head2 new( $src, \%arg )

creates the filter.

=cut

sub new {
	my( $class, $iter, $a ) = @_;

	$a ||= {};

	my $sources = $a->{sources};

	$class->SUPER::new( $iter, {
		%$a,
		srcidx	=> 0,
		sources => [ map {
			$_->isa('Workout::Iterator')
			? $_ : $_->iterate;
		} $iter, @$sources ],
	});
}

=head1 METHODS

=head2 sources

returns the list of *all* source itarators.

=head2 srcidx

returns the index of the last used iterator.

=cut

sub stores {
	my( $self ) = @_;
	map {
		$_->stores;
	} @{ $self->{sources} };
}

sub fields_supported {
	my $self = shift;

	my %fields = map { $_ => 1 } map {
		$_->fields_supported( @_ );
	} @{ $self->{sources} };

	keys %fields;
}

sub fields_io {
	my $self = shift;

	my %fields = map { $_ => 1 } map {
		$_->fields_io( @_ );
	} @{ $self->{sources} };

	keys %fields;
}

sub process {
	my( $self ) = shift;

	my $n;
	while( $self->{srcidx} <= $#{$self->{sources}} ){
		$n = $self->{sources}[$self->{srcidx}]->next
			and last;

		$self->debug( "Concat: next store" );
		++$self->{srcidx};
	}

	return unless $n;
	++$self->{cntin};

	$n->clone({
		prev	=> $self->last,
	});
}


1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=cut
