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

sub next {
	my( $self ) = @_;

	my $dat = $self->store->{data};
	while( $self->{cblk} < @$dat ){
		my $blk = $dat->[$self->{cblk}];
		if( $self->{cchk} < @$blk ){
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

	$a->{recint} ||= 0;
	my $self = $class->SUPER::new( $a );
	$self->{data} = [[]];
	$self->{supplied} = {};

	$self->{dur_mov} = 0;
	$self->{dist} = 0;
	$self->{spd_max} = 0;
	$self->{ele_min} = undef;
	$self->{ele_max} = 0;
	$self->{incline} = 0;
	$self->{work} = 0;

	$self;
}

sub iterate {
	my( $self ) = @_;
	Workout::Store::Memory::Iterator->new( $self );
}

sub chunk_count {
	my( $self ) = @_;

	my $cnt;
	foreach my $blk ( $self->blocks ){
		$cnt += @$blk;
	}
	$cnt;
}

sub fields_seen {
	my( $self ) = @_;
	keys %{$self->{supplied}};
}

sub fields_allchunks {
	my( $self ) = @_;
	my $cnt = $self->chunk_count;
	grep {
		$self->{supplied}{$_} == $cnt;
	} $self->fields_seen;
}

=head2 block_add

open new data block.

=cut

sub block_add {
	my( $self ) = @_;
	return unless @{$self->{data}};
	push @{$self->{data}}, [];
}


sub block {
	my( $self, $block ) = @_;

	if( defined $block ){
		$block >= 0 && $block <= $#{$self->{data}}
			or croak "no such block";
	} else {
		$block = -1;
	}

	return $self->{data}[-1];
}

=head2 blocks

return list of nonempty blocks.

=cut

sub blocks {
	my( $self ) = @_;
	return grep { @$_ } @{$self->{data}};
}

sub chunk_first {
	my( $self ) = @_;
	return unless @{$self->{data}};
	return unless @{$self->{data}[0]};
	$self->{data}[0][0];
}

sub chunk_last {
	my( $self ) = @_;
	foreach my $blk ( reverse $self->blocks ){
		return $blk->[-1] if @$blk;
	}
	return;
}


=head2 chunk_add( $chunk )

add data chunk to last data block.

=cut

sub chunk_add {
	my( $self, $d ) = @_;

	my $last = $self->{data}[-1][-1];
	$self->chunk_check( $d, $last );

	# identify fields that were supplied for all chunks
	foreach my $f ( keys %$d ){
		$self->{supplied}{$f}++;
	}

	$self->calc->set( $d, $last );
	push @{$self->block}, $d;

	$self->{dist} += $d->{dist} ||0;

	if( ($d->{climb} || 0) > 0 ){
		$self->{incline} += $d->{climb};
	}

	$self->{work} += $d->{work} ||0;

	if( $d->{pwr} ||($d->{spd} || 0) > $self->calc->creep ){
		$self->{dur_mov} += $d->{dur};
	}

	if( ($d->{spd} || 0) > $self->{spd_max} ){
		$self->{spd_max} = $d->{spd};
	}

	if( ! defined $self->{ele_min}
		or ($self->{ele_min} > $d->{ele}) ){
		
		$self->{ele_min} = $d->{ele};
	}

	if( ($d->{ele} || 0)  > $self->{ele_max} ){
		$self->{ele_max} = $d->{ele};
	}

}

sub time_start {
	my( $self ) = @_;

	my $c = $self->chunk_first
		or return;
	$c->{time} - $c->{dur};
}

sub time_end {
	my( $self ) = @_;

	my $c = $self->chunk_last
		or return;
	$c->{time};
}

sub dur {
	my( $self ) = @_;

	my $s = $self->time_start
		or return;
	my $e = $self->time_end
		or return;

	$e - $s;
}

sub dur_mov {
	my( $self ) = @_;
	$self->{dur_mov};
}

sub dur_creep {
	my( $self ) = @_;

	my $t = $self->dur
		or return;

	$t - $self->dur_mov;
}

sub ele_start {
	my( $self ) = @_;

	my $s = $self->chunk_first
		or return;
	$s->{ele};
}

sub ele_min {
	my( $self ) = @_;
	$self->{ele_min};
}

sub ele_max {
	my( $self ) = @_;
	$self->{ele_max};
}

sub incline {
	my( $self ) = @_;
	$self->{incline};
}

sub dist {
	my( $self ) = @_;
	$self->{dist};
}

sub spd_max {
	my( $self ) = @_;
	$self->{spd_max};
}

sub spd_avg {
	my( $self ) = @_;
	my $d = $self->dur_mov
		or return;
	$self->dist / $d;
}

sub work {
	my( $self ) = @_;
	$self->{work};
}

sub pwr_avg {
	my( $self ) = @_;

	my $dur = $self->dur
		or return;

	$self->work / $dur;
}

# TODO: move calculations to something else


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
