package Workout::Join;

=head1 NAME

Workout::Join - Join blocks within Workout data

=head1 SYNOPSIS

# TODO

=head1 DESCRIPTION

Stub documentation for Workout::Join, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=cut

use 5.008008;
use strict;
use warnings;
use base 'Workout::Iterator';
use Carp;

our $VERSION = '0.01';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new( @_ );
	$self->{queued} = undef;
	$self->{last} = undef;
	$self;
}

sub next {
	my( $self ) = @_;

	my $t = $self->{queued} || $self->src->next
		or return;
	$self->{queued} = undef;

	my $l = $self->{last};
	if( $l && abs($t->{time} - $t->{dur} - $l->{time}) > 0.1){
		my $o = $self->{queued} = $t;
		$t = {
			time    => $o->{time},
			dur     => $o->{time} - $l->{time},
		}
	}

	$self->{last} = $t;
	return $t;
}


1;
__END__

=head1 SEE ALSO

Workout::Iterator

=head1 AUTHOR

Rainer Clasen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Rainer Clasen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
