package Workout::Marker;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Carp;
use Scalar::Util qw/ weaken /;
use Workout::Filter::Timespan;

__PACKAGE__->mk_ro_accessors(qw/
	store
/);

__PACKAGE__->mk_accessors(qw/
	note
	start
	end
/);

sub new {
	my( $proto, $a ) = @_;

	exists $a->{store}
		or croak "missing store";

	my $self = $proto->SUPER::new( $a );
	weaken( $self->{store} );
	$self;
}

sub iterate {
	my( $self ) = @_;

	Workout::Filter::Timespan->new( $self->store->iterate, {
		start	=> $self->start, 
		end	=> $self->end,
	});
}

sub info {
	my $self = shift;
	my $i = Workout::Filter::Info->new( $self->iterate, @_ );
	while( $i->next ){ 1; };
	$i;
}

sub time_add_delta {
	my( $self, $delta ) = @_;
	$self->{start} += $delta;
	$self->{end} += $delta;
}

1;
