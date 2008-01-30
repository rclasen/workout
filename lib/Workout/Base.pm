=head1 NAME

Workout::Base - Base Class for Workout framework

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::Store::SRM->new( "input.srm" ); 
  $it = $src->iterate;
  while( defined(my $chunk = $it->next)){
  	print join(",",@$chunk{qw(time dur pwr)}),"\n";
  }

=head1 DESCRIPTION

Base Class to iterate through Workout Stores.

=cut

package Workout::Base;

use 5.008008;
use strict;
use warnings;
use Carp;
use Workout::Calc;

our $VERSION = '0.01';


=head2 new( $arg )

create empty class.

=cut

sub new {
	my( $class, $a ) = @_;

	my $self = bless {
		calc	=> $a->{calc},
		debug	=> $a->{debug} || 0,
	}, $class;

	return $self;
}

=head2 calc

returns the Workout::Calc object in use

=cut

sub calc {
	my( $self ) = @_;

	$self->{calc} ||= Workout::Calc->new;
}

=head2 athlete

returns the Workout::Athlete in use ( ... by Workout::Calc)

=cut

sub athlete {
	my $self = shift;
	$self->calc->athlete( @_ );
}

=head2 debug

log debug message when initialized with debug=>1

=cut

sub debug {
	my $self = shift;
	return unless $self->{debug};
	print STDERR @_, "\n";
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
