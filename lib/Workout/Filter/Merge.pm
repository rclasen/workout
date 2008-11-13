package Workout::Filter::Merge;

=head1 NAME

Workout::Filter::Merge - Merge Workout data

=head1 SYNOPSIS

  $src1 = Workout::Store::SRM->read( "foo.srm" );
  $src2 = Workout::Store::Gpx->read( "foo.gpx" );
  $merged = Workoute::Filter::Merge( $src1, $src2, [ "ele" ] );
  while( $chunk = $merged->next ){
  	# do something
  }

=head1 DESCRIPTION

merge data from different Workout Stores into one stream. You may specify
whch fields to pick from the second, ... Store.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Filter::Base';
use Carp;

our $VERSION = '0.01';

__PACKAGE__->mk_accessors(qw(
	src2
	fields
));

sub new {
	my( $class, $src, $src2, $fields, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new( $src, { 
		%$a,
		src2	=> $src2,
		fields	=> $fields,
	});
	$self->{prev} = undef;
	$self->{prev1} = undef;
	$self->{prev2} = undef;

	$self;
}

sub next {
	my( $self ) = shift;

	# get src1
	my $i = $self->src->next
		or return;
	$self->{cntin}++;

	my $stime = $i->time - $i->dur;

	# new src1 block?
	if( $self->{prev1} && abs($stime - $self->{prev1}->time) > 0.1 ){
		$self->{prev} = undef;
		$self->{prev1} = undef;
	}

	my $o = $i->clone;
	$o->prev( $self->{prev} );
	$self->{prev} = $o;
	$self->{cntout}++;

	# skip src2 chunks preluding src1
	while( ! $self->{agg} || $self->{agg}->time < $stime ){
		if( ! ( $self->{agg} = $self->src2->next )){
			return $o;
		}
		$self->{cntin}++;
	}

	# src1 preludes src2...
	my $stime2 = $self->{agg}->time - $self->{agg}->dur;
	if( $stime2 > $i->time ){
		return $o;
	}

	# throw part of src2 preluding src1 away.
	$self->{agg} = ($self->{agg}->split( $stime - $stime2 ))[1];

	# add more src2 to agg until long enough for src1->dur
	while( $self->{agg} && $self->{agg}->dur < $o->dur ){
		my $n = $self->src2->next;

		# end of src2
		if( ! $n ){
			$self->{agg} = undef;
			last;
		}
		$self->{cntin}++;

		# new block?
		my $stime3 = $n->time - $n->dur;
		if( $self->{prev2} && abs($stime3 - $n->time) > 0.1 ){
			$self->{agg} = $n;
			$self->{prev2} = undef;
			last;
		}
		
		$self->{agg} = $self->{agg}->merge( $n );
	}

	return $o unless $self->{agg};

	my $o2;
	( $o2, $self->{agg} ) = $self->{agg}->split( $o->dur );

	foreach my $f (@{$self->fields}){
		$o->$f( $o2->$f );
	}

	$o;
}


1;
__END__

=head1 SEE ALSO

Workout::Filter::Base 

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
