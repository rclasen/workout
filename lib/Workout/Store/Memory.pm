=head1 NAME

Workout::Store::Memory - Memory storage for Workout data

=head1 SYNOPSIS

  $src = Workout::Store::Memory->new;
  while( $chunk = $src->next ){
  	...
  }

=head1 DESCRIPTION

Interface to store Workout data in memory

=cut

package Workout::Store::Memory::Iterator;
use strict;
use warnings;
use Carp;
use base 'Workout::Iterator';

sub process {
	my( $self ) = @_;

	my $dat = $self->store->{data};
	return unless $self->{cntin} < @$dat;

	$dat->[$self->{cntin}++];
}


package Workout::Store::Memory;
use 5.008008;
use strict;
use warnings;
use Carp;
use base 'Workout::Store';

our $VERSION = '0.01';

=head2 new( $arg )

=cut

sub new {
	my( $class, $a ) = @_;

	$a ||= {};
	my $self = $class->SUPER::new({
		cap_block	=> 1,
		%$a,
	});
	$self->{data} = [];

	$self;
}

sub iterate {
	my( $self, $a ) = @_;

	$a ||= {};
	Workout::Store::Memory::Iterator->new( $self, {
		%$a,
		debug	=> $self->{debug},
	});
}

sub time_start {
	my $self = shift;
	my $c = $self->chunk_first
		or return;
	$c->stime;
}

sub time_end {
	my $self = shift;
	my $c = $self->chunk_last
		or return;
	$c->time;
}

sub chunk_first { $_[0]{data}[0]; }
sub chunk_last { $_[0]{data}[-1]; }

=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub _chunk_add {
	my( $self, $n ) = @_;

	$self->chunk_check( $n );
	push @{$self->{data}}, $n;
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
