=head1 NAME

Workout - Fabric to easily create workout objects

=head1 SYNOPSIS

  # read SRM file with 1sec recint and multiple blocks
  $src = Workout::file_read( "input.srm" ); 
  $it = $src->iterate;
  while( defined(my $chunk = $it->next)){
  	print join(",",@$chunk{qw(time dur pwr)}),"\n";
  }

  $dst = Workout::file_new( "foo", { ftype => "hrm" });

=head1 DESCRIPTION

easily create workout objects

=cut

package Workout;

use 5.008008;
use strict;
use warnings;
use Carp;
use Module::Pluggable
	search_path     => 'Workout::Store',
	sub_name        => 'stores';

our $VERSION = '0.01';

our %ftype;

foreach my $store ( __PACKAGE__->stores ){
	eval "require $store";
	if( my $err = $@ ){
		croak $err;
	}
	next unless $store->can('filetypes');
	foreach my $ft ( $store->filetypes ){
		$ftype{$ft} = $store;
	}
}

# TODO: automagically pass $calc, $athlete, and other options to new instances

=head2 file_read( $fname, $a )

instanciate object according to specified ftype (or guess one).

=cut

sub file_type_class {
	my( $type ) = @_;

	exists $ftype{lc $type}
		or croak "unsupported filetype: $type";

	return $ftype{lc $type};
}

sub file_read {
	my( $fname, $a ) = @_;

	my $class = &file_type_class( $a->{ftype} 
		|| ($fname =~ /\.([^.]+)$/ )[0]
		|| "" );
	$class->read( $fname, $a );	
}

sub file_new {
	my( $a ) = @_;

	my $class = &file_type_class( $a->{ftype} 
		|| "" );
	$class->new( $a );	
}

=head2 filter( $type, <args> )

create new filter object, passing <args> to it's constructor

=cut

sub filter {
	my $type = shift;
	eval "require Workout::Filter::$type";
	if( my $err = $@ ){
		croak $err;
	}
	"Workout::Filter::$type"->new( @_ );
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
