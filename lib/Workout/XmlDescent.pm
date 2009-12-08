#
# Copyright (c) 2008 Rainer Clasen
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms described in the file LICENSE included in this
# distribution.
#

=head1 NAME

Workout::XmlDescent - adaptor for custom XML::SAX handler

=head1 SYNOPSIS


=head1 DESCRIPTION

recurses nested tags and disambiguates their name + position in the
hierarchie to a "node name". 

The node tree lists which tags are allowed in each level.

=cut

package Workout::XmlDescent;
use strict;
use warnings;
use Carp;

our %nodes = (
	top	=> {
		'*'	=> 'ignore',
	},

	ignore	=> {
		'*'	=> 'ignore',
	},
);

=head1 CONSTRUCTOR

=head2 new( \%arg )

Supported arguments:

=over 4

=item nodes

=back

=cut

sub new {
	my $proto = shift;
	my $a = shift || {};

	bless {
		nodes	=> \%nodes,
		%$a,
		stack		=> [{
			cdata	=> '',
			attr	=> {},
			node	=> 'top',
		}],
	}, ref $proto || $proto;
}

=head1 METHODS

=head2 start_element

called by XML::SAX for each <foo> tag. Starts collecting data that's
evaluated in end_element.

=cut

sub start_element {
	my( $self, $el )= @_;

	my $name = lc $el->{LocalName};

	my $node = $self->{stack}[0]{node};
	exists $self->{nodes}{$node}
		or croak "invalid node: $node/$name";

	my $children = $self->{nodes}{$node};

	if( ! defined $children ){
		croak "sub-element on leaf: $node/$name";

	} elsif( exists $children->{$name} ){
		# OK, do nothing

	} elsif( exists $children->{'*'} ){
		$name = '*';

	} else {
		croak "unsupported element: $node/$name";
	}

	my $next = $children->{$name};

	unshift @{$self->{stack}}, {
		cdata	=> '',
		attr	=> $el->{Attributes},
		node	=> $next,
	}
}


=head2 end_element

called by XML::SAX for each </foo> tag. Dispatches collected data to
end_leaf or end_node depending on the configured node-tree.

=cut

sub end_element {
	my( $self, $el )= @_;

	my $node = shift @{$self->{stack}};

	if( ! defined $self->{nodes}{$node->{node}} ){
		$self->end_leaf( $el, $node );
		
	} else {
		$self->end_node( $el, $node );
	}
}

=head2 end_leaf

called by end_element for leafs (i.e. no sub-tags). Should be overloaded
in derived classes.

=cut

sub end_leaf {
	my( $self, $el, $node ) = @_;
	# virtual
}

=head2 end_node

called by end_element for nodes (i.e. with nodes + leafs in them). Should
be overloaded in derived classes.

=cut

sub end_node {
	my( $self, $el, $node ) = @_;
	# virtual
}

=head2 characters

called by XML::SAX. Collects data within one <foo></foo> item.

=cut

sub characters {
	my( $self, $dat )= @_;

	$self->{stack}[0]{cdata} .= $dat->{Data};
}

1;
__END__

=head1 SEE ALSO

XML::SAX

=head1 AUTHOR

Rainer Clasen

=cut
