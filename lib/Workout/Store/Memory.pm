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
			$self->{cntin}++;
			$self->{cntout}++;
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

	$self->{lele} = undef;
	$self->{dur_mov} = 0;
	$self->{dur_cad} = 0;
	$self->{dur_hr} = 0;
	$self->{dist} = 0;
	$self->{spd_max} = 0;
	$self->{spd_max_time} = undef;
	$self->{accel_max} = 0;
	$self->{accel_max_time} = undef;
	$self->{ele_min} = undef;
	$self->{ele_max} = 0;
	$self->{ele_max_time} = undef;
	$self->{grad_max} = 0;
	$self->{grad_max_time} = undef;
	$self->{incline} = 0;
	$self->{work} = 0;
	$self->{pwr_max} = 0;
	$self->{pwr_max_time} = undef;
	$self->{hr_sum} = 0;
	$self->{hr_max} = 0;
	$self->{hr_max_time} = undef;
	$self->{cad_sum} = 0;
	$self->{cad_max} = 0;
	$self->{cad_max_time} = undef;

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
	my( $self, $i ) = @_;

	my $last = $self->{data}[-1][-1];
	$self->chunk_check( $i, $last );

	# identify fields that were supplied for all chunks
	foreach my $f ( keys %$i ){
		$self->{supplied}{$f}++;
	}

	my $d = { %$i };
	$self->calc->set( $d, $last );
	push @{$self->block}, $d;

	$self->chunk_summarize( $d );
}

sub chunk_summarize {
	my( $self, $d ) = @_;

	$self->{dist} += $d->{dist} ||0;

	if( $d->{ele} ){
		if( defined $self->{lele} ){
			my $climb = $d->{ele} - $self->{lele};
			# TODO: better fix climb calculation in Calc.pm

			if( abs($climb) >= $self->calc->elefuzz ){
				$self->{lele} = $d->{ele};
				if( $climb > 0 ){
					$self->{incline} += $climb;
				}
			}

		} else {
			$self->{lele} = $d->{ele};
		}
	}

	if( ($d->{work}||0) > 0 ){
		$self->{work} += $d->{work};
	}

	if( ($d->{pwr} || 0)  > $self->{pwr_max} ){
		$self->{pwr_max} = $d->{pwr};
		$self->{pwr_max_time} = $d->{time};
	}

	if( ($d->{pwr} || 0) > $self->calc->pwrmin 
		|| ($d->{spd} || 0) > $self->calc->spdmin ){

		$self->{dur_mov} += $d->{dur};
		if( $d->{hr} ){
			$self->{dur_hr} += $d->{dur};
			$self->{hr_sum} += ($d->{hr}||0) * $d->{dur};
		}
	}
	if( $d->{cad} ){
		$self->{dur_cad} += $d->{dur};
		$self->{cad_sum} += ($d->{cad}||0) * $d->{dur};
	}

	if( ($d->{hr} || 0) > $self->{hr_max} ){
		$self->{hr_max} = $d->{hr};
		$self->{hr_max_time} = $d->{time};
	}

	if( ($d->{cad} || 0) > $self->{cad_max} ){
		$self->{cad_max} = $d->{cad};
		$self->{cad_max_time} = $d->{time};
	}

	if( ($d->{spd} || 0) > $self->{spd_max} ){
		$self->{spd_max} = $d->{spd};
		$self->{spd_max_time} = $d->{time};
	}

	if( ($d->{accel} || 0) > $self->{accel_max} ){
		$self->{accel_max} = $d->{accel};
		$self->{accel_max_time} = $d->{time};
	}

	if( ! defined $self->{ele_min}
		or ($self->{ele_min} > $d->{ele}) ){
		
		$self->{ele_min} = $d->{ele};
	}

	if( ($d->{ele} || 0)  > $self->{ele_max} ){
		$self->{ele_max} = $d->{ele};
		$self->{ele_max_time} = $d->{time};
	}

	if( ($d->{grad} || 0)  > $self->{grad_max} ){
		$self->{grad_max} = $d->{grad};
		$self->{grad_max_time} = $d->{time};
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

sub dur_hr {
	my( $self ) = @_;
	$self->{dur_hr};
}

sub dur_cad {
	my( $self ) = @_;
	$self->{dur_cad};
}

sub dur_creep {
	my( $self ) = @_;

	my $t = $self->dur
		or return;

	$t - $self->dur_mov;
}

sub hr_avg {
	my( $self ) = @_;
	my $d = $self->dur_hr ||$self->dur
		or return;
	int($self->{hr_sum} / $d + 0.5);
}

sub hr_max {
	my( $self ) = @_;
	int($self->{hr_max}+0.5);
}

sub hr_max_time {
	my( $self ) = @_;
	$self->{hr_max_time};
}

sub cad_avg {
	my( $self ) = @_;
	my $d = $self->dur_cad || $self->dur
		or return;
	int($self->{cad_sum} / $d + 0.5);
}

sub cad_max {
	my( $self ) = @_;
	int(($self->{cad_max}||0)+0.5);
}

sub cad_max_time {
	my( $self ) = @_;
	$self->{cad_max_time};
}

sub ele_start {
	my( $self ) = @_;

	my $s = $self->chunk_first
		or return;
	int($s->{ele}||0 +0.5);
}

sub ele_min {
	my( $self ) = @_;
	int($self->{ele_min}||0 +0.5);
}

sub ele_max {
	my( $self ) = @_;
	int($self->{ele_max}+0.5);
}

sub ele_max_time {
	my( $self ) = @_;
	$self->{ele_max_time};
}

sub grad_max {
	my( $self ) = @_;
	$self->{grad_max};
}

sub grad_max_time {
	my( $self ) = @_;
	$self->{grad_max_time};
}

sub incline {
	my( $self ) = @_;
	int($self->{incline}+0.5);
}

sub dist {
	my( $self ) = @_;
	$self->{dist};
}

sub spd_max {
	my( $self ) = @_;
	$self->{spd_max};
}

sub spd_max_time {
	my( $self ) = @_;
	$self->{spd_max_time};
}

sub accel_max {
	my( $self ) = @_;
	$self->{accel_max};
}

sub accel_max_time {
	my( $self ) = @_;
	$self->{accel_max_time};
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

sub pwr_max {
	my( $self ) = @_;
	$self->{pwr_max};
}

sub pwr_max_time {
	my( $self ) = @_;
	$self->{pwr_max_time};
}

sub pwr_avg {
	my( $self ) = @_;

	my $dur = $self->dur_mov || $self->dur
		or return;

	int( $self->work / $dur +0.5);
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
