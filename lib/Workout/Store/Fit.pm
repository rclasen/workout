#
# Copyright (c) 2011 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#


=head1 NAME

Workout::Store::Fit - Perl extension to read/write Garmin Fit Activity files

=head1 SYNOPSIS

  $src = Workout::Store::Fit->read( "foo.fit" );

  $iter = $src->iterate;
  while( $chunk = $iter->next ){
  	...
  }

  $src->write( "out.fit" ); # TODO: not supported, yet

=head1 DESCRIPTION

Interface to read/write Garmin Fit Activity files. Inherits from
Workout::Store and implements do_read/_write methods.

Other Fit files (Course, Workout, ...) aren't supported, as they carry
information inapropriate for this framework.

=cut


package Workout::Store::Fit;
use 5.008008;
use strict;
use warnings;
use base 'Workout::Store';
use Carp;
use Workout::Fit qw( :types );

our $VERSION = '0.01';

sub filetypes {
	return "fit";
}

our %fields_supported = map { $_ => 1; } qw{
	dist
	lon
	lat
	work
	hr
	cad
	temp
	ele
};

our %defaults = (
	recint		=> undef,
	manufacturer	=> 1, # Garmin
	product		=> 1169, # Edge800
	serial		=> undef,
	hard_version	=> undef,
	soft_version	=> undef,
);
__PACKAGE__->mk_accessors( keys %defaults );

# conversion constants:
use constant {
	TIME_OFFSET	=> 631065600,	# timegm(0, 0, 0, 31, 11, 1989);
	SEMI_DEG	=> 2 ** 31 / 180,
};


=head1 CONSTRUCTOR

=head2 new( [ \%arg ] )

creates an empty Store.

=cut

sub new {
	my( $class,$a ) = @_;

	$a||={};
	my $self = $class->SUPER::new( {
		%defaults,
		%$a,
		fields_supported	=> {
			%fields_supported,
		},
		cap_block	=> 1,
		cap_note	=> 0,

		field_use	=> {},
	});

	$self;
}

=head1 METHODS

=cut

#sub from_store {
#	my( $self, $store ) = @_;
#
#	$self->SUPER::from_store( $store );
#
#	foreach my $f (qw( circum )){
#		$self->$f( $store->$f ) if $store->can( $f );
#	}
#}

sub do_write {
	my( $self, $fh, $fname ) = @_;

	my $fit = Workout::Fit->new(
		to	=> $fh,
		debug	=> $self->{debug},
	) or croak "initializing Fit failed";

	defined $fit->define_raw(
		id	=> 0,
		message	=> FIT_MSG_FILE_ID,
		fields	=> [{
			field	=> 0, # file_type
			base	=> FIT_ENUM,
		}, {
			field	=> 1, # manufacturer
			base	=> FIT_UINT16,
		}, {
			field	=> 2, # product
			base	=> FIT_UINT16,
		}, {
			field	=> 3, # serial
			base	=> FIT_UINT32Z,
		}],
	) or return;
	$fit->data( 0, FIT_FILE_ACTIVITY,
		$self->{manufacturer}, $self->{product}, $self->{serial} )
		or return;

	defined $fit->define_raw(
		id	=> 1,
		message	=> FIT_MSG_FILE_CREATOR,
		fields	=> [{
			field	=> 0, # sw version
			base	=> FIT_UINT16,
		}, {
			field	=> 1, # hw version
			base	=> FIT_UINT8,
		}],
	) or return;
	$fit->data( 1, $self->{soft_version}, $self->{hard_version} )
		or return;


	my %io = map {
		$_ => 1,
	} $self->fields_io;

	my $dist;

	my @fields = ({
		field	=> 253, # timestamp
		base	=> FIT_UINT32,
	});
	my @data = ( sub { $_[0]->time - TIME_OFFSET} );

	if( $io{lon} || $io{lat} ){
		push @fields, {
			field	=> 1, # lon
			base	=> FIT_SINT32,
		}, {
			field	=> 0, # lat
			base	=> FIT_SINT32,
		};

		push @data,
			sub { $_[0]->lon * SEMI_DEG},
			sub { $_[0]->lat * SEMI_DEG};
	}

	if( $io{dist} ){
		push @fields, {
			field	=> 5, # dist
			base	=> FIT_UINT32,
		}, {
			field	=> 6, # spd
			base	=> FIT_UINT16,
		};

		push @data,
			sub { $dist * 100 },
			sub { $_[0]->spd * 1000 };
	}

	if( $io{ele} ){
		push @fields, {
			field	=> 2, # altitude
			base	=> FIT_UINT16,
		};

		push @data, sub { ( $_[0]->ele + 500) * 5};
	}

	if( $io{work} ){
		push @fields, {
			field	=> 7, # pwr
			base	=> FIT_UINT16,
		};

		push @data, sub { $_[0]->pwr };
	}

	if( $io{hr} ){
		push @fields, {
			field	=> 3, # hr
			base	=> FIT_UINT8,
		};

		push @data, sub { $_[0]->hr };
	}

	if( $io{cad} ){
		push @fields, {
			field	=> 4, # cad
			base	=> FIT_UINT8,
		};

		push @data, sub { $_[0]->cad };
	}

	if( $io{temp} ){
		push @fields, {
			field	=> 13, # temp
			base	=> FIT_SINT8,
		};

		push @data, sub { $_[0]->temp };
	}

	defined $fit->define_raw(
		id	=> 2,
		message	=> FIT_MSG_RECORD,
		fields	=> \@fields,
	) or return;

	my $it = $self->iterate;
	while( my $row = $it->next ){
		$dist += $row->dist;
		$fit->data( 2, map { $_->( $row ) } @data );
	}

	# TODO: lap
	# TODO: session
	# TODO: activity

	$fit->close
		or return;
}


sub do_read {
	my( $self, $fh, $fname ) = @_;

	my $buf;

	my @laps;
	my $rec_last_dist = 0;
	my $rec_last_time;

	my $fit = Workout::Fit->new(
		from => $fh,
		debug => $self->{debug},
	) or croak "initializing Fit failed";

	while( my $msg = $fit->get_next ){

		############################################################
		# record message

		if( $msg->{message} == FIT_MSG_RECORD ){ # record
			my $dist;
			my $ck = {
				time => $msg->{timestamp} + TIME_OFFSET,
			};

			foreach my $f ( @{$msg->{fields}} ){

				if( $f->{field} == 0 ){
					$ck->{lat} = $f->{val} / SEMI_DEG;
					++$self->{field_use}{lat};

				} elsif( $f->{field} == 1 ){
					$ck->{lon} = $f->{val} / SEMI_DEG;
					++$self->{field_use}{lon};

				} elsif( $f->{field} == 2 ){
					$ck->{ele} = $f->{val}/5 - 500;
					++$self->{field_use}{ele};

				} elsif( $f->{field} == 3 ){
					$ck->{hr} = $f->{val};
					++$self->{field_use}{hr};

				} elsif( $f->{field} == 4 ){
					$ck->{cad} = $f->{val};
					++$self->{field_use}{cad};

				} elsif( $f->{field} == 5 ){
					$dist = $f->{val} / 100;
					$ck->{dist} = $dist - $rec_last_dist;
					++$self->{field_use}{dist};

				} elsif( $f->{field} == 6 ){
					$ck->{spd} = $f->{val} / 1000; # tmp

				} elsif( $f->{field} == 7 ){
					$ck->{pwr} = $f->{val}; # tmp

				} elsif( $f->{field} == 8 ){
					my @b = unpack('CCC',$f->{val} );
					# TODO: verify compressed speed/dist
					my $spd = ($b[0]
						| ($b[1] & 0x0f) <<8 ) / 100;
					my $dst = ( $b[1] >>4
						| $b[2] <<4 ) / 16;
					$ck->{dist} ||= $dst;
					++$self->{field_use}{dist};

				} elsif( $f->{field} == 13 ){
					$ck->{temp} = $f->{val};
					++$self->{field_use}{temp};

				} # else ignore
			}

			if( defined $ck->{lon} && abs($ck->{lon}) >= 180
				|| defined $ck->{lat} && abs($ck->{lat}) >= 90 ){

				warn "geo position is out of bounds, skipping";
				delete( $ck->{lon} );
				delete( $ck->{lat} );
			}

			if( ! $rec_last_time ){
				if( $ck->{spd} && $ck->{dist}  ){
					$rec_last_time = $ck->{time}
						- $ck->{dist} / $ck->{spd};
				}
			}

			if( $rec_last_time ){
				$ck->{dur} = $ck->{time} - $rec_last_time;

				if( $ck->{pwr} ){
					$ck->{work} = $ck->{pwr} * $ck->{dur};
					++$self->{field_use}{work};
					delete $ck->{pwr};
				}

				if( $ck->{dist} ){
					# delete($ck->{spd}); # unneeded

				} elsif( $ck->{spd} ){
					$ck->{dist} = $ck->{spd} * $ck->{dur};
					++$self->{field_use}{dist};

				# TODO: dist from geocalc
				#} elsif( defined($ck->{lon}) && defined($ck->{lat} ) ){

				}

				my $chunk = Workout::Chunk->new( $ck );
				$self->chunk_add( $chunk );

			}

			$rec_last_time = $ck->{time};
			$rec_last_dist = $dist;

		############################################################
		# lap message

		} elsif( $msg->{message} == FIT_MSG_LAP ){ # lap
			my $start;
			my $end = $msg->{timestamp} + TIME_OFFSET;

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 2 ){
					$start = $f->{val} + TIME_OFFSET;

				} # else ignore
			}

			$self->debug( "found lap $start - $end" );

			push @laps, {
				start	=> $start,
				end	=> $end,
			};

		############################################################
		# session message

		} elsif( $msg->{message} == FIT_MSG_SESSION ){ # TODO: session
			$self->debug( "found session" );

		############################################################
		# activity message

		} elsif( $msg->{message} == FIT_MSG_ACTIVITY ){ # TODO: activity
			$self->debug( "found activity" );

		############################################################
		# file_id message

		} elsif( $msg->{message} == FIT_MSG_FILE_ID ){ # file_id
			my $ftype;

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){ # type
					$ftype = $f->{val};
					$ftype == FIT_FILE_ACTIVITY
						or warn "no activity file, unsupported";

				} elsif( $f->{field} == 1 ){ # manufacturer
					$self->{manufacturer} = $f->{val};

				} elsif( $f->{field} == 2 ){ # product
					$self->{product} = $f->{val};

				} elsif( $f->{field} == 3 ){ # serial
					$self->{serial} = $f->{val};

				}
			}

			$self->debug( "found file_id "
				."type=". ($ftype||'-'). ", "
				."manu=". ($self->{manufacturer}||'-'). ", "
				."prod=". ($self->{product}||'-'). ", "
				."seral=". ($self->{serial}||'-') );

		############################################################
		# file_creator message

		} elsif( $msg->{message} == FIT_MSG_FILE_CREATOR ){ # file_creator

			foreach my $f ( @{$msg->{fields}} ){
				if( $f->{field} == 0 ){ # soft version
					$self->{soft_version} = $f->{val};

				} elsif( $f->{field} == 1 ){ # hard version
					$self->{hard_version} = $f->{val};

				}

			}

			$self->debug( "found file_creator "
				."sw=".  ($self->{soft_version}||'-') .", "
				."hw=".  ($self->{hard_version}||'-') );

		}
	}
	$fit->close;

	if( @laps == 1 ){
		my $lap = $laps[0];
		if( $self->chunk_count && (
			$lap->{start} > $self->chunk_first->time
			|| $lap->{end} < $self->time_end ) ){

			$self->debug( "adding lap $lap->{start} - $lap->{end}" );
			$self->mark_new( $lap );
		} else {
			$self->debug( "skipping all-exercise lap" );
		}
	} else {
		foreach my $lap ( @laps ){
			$self->debug( "adding lap $lap->{start} - $lap->{end}" );
			$self->mark_new( $lap );
		}
	}

	$self->fields_io( keys %{$self->{field_use}} );

	1;
}


1;
__END__


=head1 SEE ALSO

Workout::Store, Workout::Fit

=head1 AUTHOR

Rainer Clasen

=cut