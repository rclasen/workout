package Workout::Fit;
use warnings;
use strict;
use Carp;
use Exporter;

our( @ISA, @EXPORT_OK, %EXPORT_TAGS );
BEGIN {
	@ISA = qw( Exporter );
	%EXPORT_TAGS = (
		types	=> [ qw(
			FIT_ENUM
			FIT_SINT8
			FIT_UINT8
			FIT_SINT16
			FIT_UINT16
			FIT_SINT32
			FIT_UINT32
			FIT_STRING
			FIT_FLOAT32
			FIT_FLOAT64
			FIT_UINT8Z
			FIT_UINT16Z
			FIT_UINT32Z
			FIT_BYTE

			FIT_MSG_FILE_ID
			FIT_MSG_CAPABILITIES
			FIT_MSG_DEVICE_SETTINGS
			FIT_MSG_USER_PROFILE
			FIT_MSG_HRM_PROFILE
			FIT_MSG_SDM_PROFILE
			FIT_MSG_BIKE_PROFILE
			FIT_MSG_ZONES_TARGET
			FIT_MSG_HR_ZONE
			FIT_MSG_POWER_ZONE
			FIT_MSG_MET_ZONE
			FIT_MSG_SPORT
			FIT_MSG_TRAINING_GOALS
			FIT_MSG_SESSION
			FIT_MSG_LAP
			FIT_MSG_RECORD
			FIT_MSG_EVENT
			FIT_MSG_DEVICE_INFO
			FIT_MSG_WORKOUT
			FIT_MSG_WORKOUT_STEP
			FIT_MSG_WEIGHT_SCALE
			FIT_MSG_TOTALS
			FIT_MSG_ACTIVITY
			FIT_MSG_SOFTWARE
			FIT_MSG_FILE_CAPABILITIES
			FIT_MSG_MESG_CAPABILITIES
			FIT_MSG_FIELD_CAPABILITIES
			FIT_MSG_FILE_CREATOR
			FIT_MSG_BLOOD_PRESSURE

			FIT_FILE_DEVICE
			FIT_FILE_SETTINGS
			FIT_FILE_SPORT
			FIT_FILE_ACTIVITY
			FIT_FILE_WORKOUT
			FIT_FILE_WEIGHT
			FIT_FILE_TOTALS
			FIT_FILE_GOALS
			FIT_FILE_BLOOD_PRESSURE

		) ],
	);
	Exporter::export_ok_tags('types');
}

#########################################################
# defines / data structurs / constants

use constant {
	FIT_ENUM	=> 0,
	FIT_SINT8	=> 1,
	FIT_UINT8	=> 2,
	FIT_SINT16	=> 3,
	FIT_UINT16	=> 4,
	FIT_SINT32	=> 5,
	FIT_UINT32	=> 6,
	FIT_STRING	=> 7,
	FIT_FLOAT32	=> 8,
	FIT_FLOAT64	=> 9,
	FIT_UINT8Z	=> 10,
	FIT_UINT16Z	=> 11,
	FIT_UINT32Z	=> 12,
	FIT_BYTE	=> 13,

	FIT_MSG_FILE_ID			=> 0,
	FIT_MSG_CAPABILITIES		=> 1,
	FIT_MSG_DEVICE_SETTINGS		=> 2,
	FIT_MSG_USER_PROFILE		=> 3,
	FIT_MSG_HRM_PROFILE		=> 4,
	FIT_MSG_SDM_PROFILE		=> 5,
	FIT_MSG_BIKE_PROFILE		=> 6,
	FIT_MSG_ZONES_TARGET		=> 7,
	FIT_MSG_HR_ZONE			=> 8,
	FIT_MSG_POWER_ZONE		=> 9,
	FIT_MSG_MET_ZONE		=> 10,
	FIT_MSG_SPORT			=> 12,
	FIT_MSG_TRAINING_GOALS		=> 15,
	FIT_MSG_SESSION			=> 18,
	FIT_MSG_LAP			=> 19,
	FIT_MSG_RECORD			=> 20,
	FIT_MSG_EVENT			=> 21,
	FIT_MSG_DEVICE_INFO		=> 23,
	FIT_MSG_WORKOUT			=> 26,
	FIT_MSG_WORKOUT_STEP		=> 27,
	FIT_MSG_WEIGHT_SCALE		=> 30,
	FIT_MSG_TOTALS			=> 33,
	FIT_MSG_ACTIVITY		=> 34,
	FIT_MSG_SOFTWARE		=> 35,
	FIT_MSG_FILE_CAPABILITIES	=> 37,
	FIT_MSG_MESG_CAPABILITIES	=> 38,
	FIT_MSG_FIELD_CAPABILITIES	=> 39,
	FIT_MSG_FILE_CREATOR		=> 49,
	FIT_MSG_BLOOD_PRESSURE		=> 51,

	FIT_FILE_DEVICE		=> 1,
	FIT_FILE_SETTINGS	=> 2,
	FIT_FILE_SPORT		=> 3,
	FIT_FILE_ACTIVITY	=> 4,
	FIT_FILE_WORKOUT	=> 5,
	FIT_FILE_WEIGHT		=> 9,
	FIT_FILE_TOTALS		=> 10,
	FIT_FILE_GOALS		=> 11,
	FIT_FILE_BLOOD_PRESSURE	=> 14,

};

# decode( $buf, $bytes, $big )
our @base_type = ( { # 0, enum
		endian	=> 0,
		bytes	=> 1,
		decode	=> sub { $_[0] eq pack('C', 0xff)
			? undef : unpack('C',$_[0] ) },
	}, { # 1, sint8
		endian	=> 0,
		bytes	=> 1,
		decode	=> sub { $_[0] eq pack('C', 0x7f)
			? undef : unpack('c',$_[0] ) },
	}, { # 2, uint8
		endian	=> 0,
		bytes	=> 1,
		decode	=> sub { $_[0] eq pack('C', 0xff)
			? undef : unpack('C',$_[0] ) },
	}, { # 3, sint16
		endian	=> 1,
		bytes	=> 2,
		decode	=> sub { $_[0] eq pack( $_[2] ? 's>' : 's<', 0x7fff )
			? undef : unpack( $_[2] ? 's>' : 's<', $_[0] ) },
	}, { # 4, uint16
		endian	=> 1,
		bytes	=> 2,
		decode	=> sub { $_[0] eq pack( 'S', 0xffff )
			? undef : unpack( $_[2] ? 'S>' : 'S<', $_[0] ) },
	}, { # 5, sint32
		endian	=> 1,
		bytes	=> 4,
		decode	=> sub { $_[0] eq pack( $_[2] ? 'l>' : 'l<', 0x7fffffff )
			? undef : unpack( $_[2] ? 'S>' : 'S<', $_[0] ) },
	}, { # 6, uint32
		endian	=> 1,
		bytes	=> 4,
		decode	=> sub { $_[0] eq pack( 'L', 0xffffffff )
			? undef : unpack( $_[2] ? 'L>' : 'L<', $_[0] ) },
	}, { # 7, string
		endian	=> 0,
		bytes	=> 1,
		decode	=> sub { unpack('C', $_[0]) == 0x00
			? undef : unpack( 'U'.$_[1], $_[0] ) },
	}, { # 8, float32
		endian	=> 1,
		bytes	=> 4,
		decode	=> sub { $_[0] eq pack( 'L', 0xffffffff )
			? undef : unpack( $_[2] ? 'f>' : 'f<', $_[0] ) },
	}, { # 9, float64
		endian	=> 1,
		bytes	=> 8,
		decode	=> sub { $_[0] eq pack( 'L2', 0xffffffff, 0xffffffff )
			? undef : unpack( $_[2] ? 'd>' : 'd<', $_[0] ) },
	}, { # 10, uint8z
		endian	=> 0,
		bytes	=> 1,
		decode	=> sub { $_[0] eq pack('x')
			? undef : unpack('C',$_[0] ) },
	}, { # 11, uint16z
		endian	=> 1,
		bytes	=> 2,
		decode	=> sub { $_[0] eq pack( 'x2' )
			? undef : unpack( $_[2] ? 'S>' : 'S<', $_[0] ) },
	}, { # 12, uint32z
		endian	=> 1,
		bytes	=> 4,
		decode	=> sub { $_[0] eq pack( 'x4')
			? undef : unpack( $_[2] ? 'L>' : 'L<', $_[0] ) },
	}, { # 13, byte
		endian	=> 1,
		bytes	=> 1,
		decode	=> sub { $_[0] eq pack( 'C', 0xff) x $_[1]
			? undef : wantarray
				? unpack( 'C'.$_[1], $_[0] )
				: unpack( 'a'.$_[1], $_[0] ) },
	},
);


sub new {
	my( $proto, %a ) = @_;

	my $self = bless {
		debug	=> 0,

		protocol_version	=> 16,
		profile_version		=> 108,

		%a,

		layout_id	=> 0,
		layout	=> {},

		close	=> 0,
		fh	=> undef,
		fsize	=> 0,

		last_timestamp	=> 0,
		last_delta	=> 0,
	}, ref $proto || $proto;

	$self->_read( $a{from} )
		if exists $a{from} || defined $a{from};

	return $self;
}

sub protocol_version { $_[0]->{protocol_version} }
sub profile_version { $_[0]->{profile_version} }

sub debug {
	my $self = shift;

	$self->{debug} or return;

	print STDERR "@_\n";
}


sub close {
	my( $self ) = @_;
	close( $self->{fh} ) if $self->{close};
}

############################################################
# read

sub _read {
	my( $self, $from ) = @_;

	if( ref $from ){
		$self->{fh} = $from;

	} else {
		open( my $fh, '<', $from )
			or croak "open failed: $!";

		$self->{fh} = $fh;
		$self->{close} = 1;
	}

	binmode( $self->{fh} );

	$self->_check_header;
	# TODO: crc

	return $self;
}

sub _get {
	my( $self, $len ) = @_;

	my $buf;
	CORE::read( $self->{fh}, $buf, $len ) == $len
		or return;
	return $buf;
}

sub _unpack {
	my( $self, $len, $pat ) = @_;

	my $buf = $self->_get( $len );
	defined $buf
		or return;

	return unpack( $pat, $buf );
}

sub _check_header {
	my( $self ) = @_;

	my( $hsize, $proto, $profile, $dsize, $magic ) =
		$self->_unpack( 12, 'CCvVA4' )
		or croak "failed to read header: $!";

	$self->debug( "hsize=$hsize, proto=$proto, profile=$profile, magic=$magic, data=$dsize" );

	$hsize == 12
		or croak "invalid header length: $hsize";
#	$proto == 1
#		or carp "unknown proto version: $proto";
#	$profile == 1
#		or carp "unknown profile version: $profile";
	$magic eq '.FIT'
		or croak "no FIT signature found";

	$self->{protocol_version} = $proto;
	$self->{profile_version} = $profile;
	$self->{fsize} = $hsize + $dsize;

}

sub get_all {
	my( $self ) = @_;

	my @all;
	while( defined( my $ent = $self->get_next ) ){
		push @all, $ent;
	}

	@all;
}

sub get_next {
	my( $self ) = @_;

	# TODO: optionally ignore fsize
	while( $self->{fsize} > ( my $tell = tell( $self->{fh} )  ) ){;

		my( $rhead ) = $self->_unpack(1, 'C' )
			or return;
		#$self->debug( sprintf("next record 0x%x at %d", $rhead, $tell ));

		if( $rhead & 0x80 ){ # compressed timestamp data

			my $layout_id = ($rhead >> 5 ) & 0x3;
			my $delta = $rhead & 0x1f;
			return $self->_decode_data( $layout_id, $delta );

		} else { # normal header

			my $layout_id = $rhead & 0x0f;

			if( $rhead & 0x40 ){ # definitin
				$self->_decode_define( $layout_id )
					or return;

			} else { # data
				return $self->_decode_data( $layout_id );
			}
		}
	}

	# reached on EOF, only:
	return;
}

sub _decode_define {
	my( $self, $layout_id ) = @_;

	my( $big ) = $self->_unpack( 2, 'xC' )
		or return;
	my( $message, $fields ) = $self->_unpack( 3, $big ? 'nC' : 'vC' )
		or return;

	$self->debug( "defined layout $layout_id=$message, big=$big fields=$fields" );

	my @fields;

	foreach my $f ( 1..$fields ){
		my( $field, $bytes, $base ) = $self->_unpack( 3, 'CCC' )
			or return;

		my %dat = (
			field	=> $field,
			bytes	=> $bytes,
		);

		my $bnum = $base & 0x1f;
		if( $bnum < @base_type ){
			$dat{decode} = $base_type[$bnum]{decode};
		} else {
			croak "unknown base type: $bnum";
		}

		$self->debug( " $layout_id=$message/$field -> base=$bnum" );
		push @fields, \%dat;
	}

	$self->{layout}{$layout_id} = {
		message	=> $message,
		big	=> $big,
		fields	=> \@fields,
	};

	return 1;
}

sub _decode_data {
	my( $self, $layout_id, $delta ) = @_;

	exists $self->{layout}{$layout_id}
		or croak "undefined data layout: $layout_id";
	my $layout = $self->{layout}{$layout_id};

	my $tstamp;
	if( defined $delta ){
		my $d = 0x1f & ($delta - ($self->{last_delta} || 0) );

		if( $self->{last_timestamp} ){
			$tstamp = $self->{last_timestamp} += $d;
			$self->{last_delta} = $delta;
		} else {
			carp "delta timestamp without reference time...";
		}
	}

	my @fields;
	foreach my $fdat (@{$layout->{fields}} ){
		my $val;

		if( defined $delta && $fdat->{field} == 253 ){
			# insert decompressed timestamp
			$val = $tstamp;

		} else {
			my $buf = $self->_get( $fdat->{bytes} );
			defined $buf
				or return;

			$val = $fdat->{decode}( $buf, $fdat->{bytes},
				$layout->{big} );

			if( defined $val && $fdat->{field} == 253 ){
				# real timestamp

				$self->{last_timestamp} = $val;
				$self->{last_delta} = 0x1f & $val;
				$tstamp = $val;
			}

		}
		push @fields, {
			field	=> $fdat->{field},
			val	=> $val,
		}
	}

	$self->debug( "data $layout_id/$layout->{message}, len=$layout->{len}, delta=". ($delta||'-') .", time=".  ($tstamp||'-') );

	return {
		message	=> $layout->{message},
		timestamp	=> $tstamp,
		layout	=> $layout_id,
		fields	=> \@fields,
	};
}


1;

__END__

############################################################
# TODO: write

sub define {
	my( $self, %a ) = @_,

	my $id;
	if( defined $a{id} ){
		$id = $a{id};
		if( $self->{layout_id} < $a{id} ){
			$self->{layout_id} = $a{id};
		}

	} else {
		$id = $self->{layout_id}++;
	}

	# remember data layout
	$self->{layout}{$id} = {
		compress	=> $a{compress} || 0,
		message	=> $a{message},
		fields	=> $a{fields},
	};

	# TODO write + remember data message layout

	return $id;
}

sub data {
	my( $self, $id, @data ) = @_;
	# TODO write data according to previous definition
}

1;
