package Workout::XmlDescent;
use strict;
use warnings;
use Carp;

# TODO: pod

our %nodes = (
	top	=> {
		'*'	=> 'ignore',
	},

	ignore	=> {
		'*'	=> 'ignore',
	},
);

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


sub start_element {
	my( $self, $el )= @_;

	my $node = $self->{stack}[0]{node};
	my $next = $self->dispatch( $node, $el );

	unshift @{$self->{stack}}, {
		cdata	=> '',
		attr	=> $el->{Attributes},
		node	=> $next,
	}
}

sub dispatch {
	my( $self, $node, $el )= @_;

	my $name = lc $el->{LocalName};
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

	$children->{$name};
}

sub end_element {
	my( $self, $el )= @_;

	my $node = shift @{$self->{stack}};

	if( ! defined $self->{nodes}{$node->{node}} ){
		$self->end_leaf( $el, $node );
		
	} else {
		$self->end_node( $el, $node );
	}
}

sub end_leaf {
	my( $self, $el, $node ) = @_;
	# virtual
}

sub end_node {
	my( $self, $el, $node ) = @_;
	# virtual
}

sub characters {
	my( $self, $dat )= @_;

	$self->{stack}[0]{cdata} .= $dat->{Data};
}

1;
