package Workout::Marker;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use Workout::Filter::Timespan;

__PACKAGE__->mk_accessors(qw/
	store
	note
	start
	end
/);

sub new {
	my( $proto, $a ) = @_;

	$proto->SUPER::new({
		( $a ? %$a : () ),
	});
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
