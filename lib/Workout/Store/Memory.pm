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

sub new {
	my( $class, $store, $a ) = @_;

	my $self = $class->SUPER::new( $store, $a );
	$self->{cblk} = 0;
	$self->{cchk} = 0;
	$self;
}

sub process {
	my( $self ) = @_;

	my $dat = $self->store->{data};
	while( $self->{cblk} < @$dat ){
		my $blk = $dat->[$self->{cblk}];
		if( $self->{cchk} < @$blk ){
			$self->{cntin}++;
			return $blk->[$self->{cchk}++];
		}
		$self->{cblk}++;
		$self->{cchk} = 0;
	};
	return;
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

	my $self = $class->SUPER::new( $a );
	$self->{data} = [[]];

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

=head2 block_add

open new data block.

=cut

sub block_add {
	my( $self ) = @_;
	return unless @{$self->{data}};
	push @{$self->{data}}, [];
}


=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $i ) = @_;

	my $last = $self->{data}[-1][-1];
	$self->chunk_check( $i, $last );

	my $o = $i->clone({
		prev	=> $last,
	});

	push @{$self->block}, $o;
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
