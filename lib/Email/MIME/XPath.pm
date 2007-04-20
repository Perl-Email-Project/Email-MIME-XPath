use strict;
use warnings;

package Email::MIME::XPath;

use Tree::XPathEngine;
use Scalar::Util ();
use Carp ();

my (@EXTERNAL_AUTO, @EXTERNAL, @INTERNAL, @SPECIAL);
BEGIN {
  @EXTERNAL_AUTO = qw(findnodes findnodes_as_string findvalue exists find);
  @EXTERNAL      = qw(findnode matches);
  @INTERNAL = qw(get_name get_next_sibling get_previous_sibling get_root_node
    get_parent_node get_child_nodes
    is_element_node
    is_document_node
    is_attribute_node
    is_text_node
    cmp address
    get_attributes
    to_literal);
  @SPECIAL = qw(__xpath_engine __xpath_engine_options __build_parents
    __xpath_parent);
}

use Sub::Exporter -setup => {
  into    => 'Email::MIME',
  exports => [ @EXTERNAL, @SPECIAL, @INTERNAL ],
  groups => {
    external_auto => \&_build_external,
    external => [ @EXTERNAL ],
    internal => [ @INTERNAL ], 
    special  => [ @SPECIAL ],
    default => [
      -external_auto => { -prefix => 'xpath_' },
      -external      => { -prefix => 'xpath_' },
      -internal      => { -prefix => 'xpath_' },
      -internal      => { -prefix => '__xpath_' },
      -special,
    ],
  },
};
 
sub _build_external {
  my ($class, $group, $arg) = @_;
  return {
    map {
      my $method = $_;
      $method => sub {
        my $self = shift;
        $self->__build_parents;
        return $self->__xpath_engine->$method(@_, $self);
      }
    } @EXTERNAL_AUTO
  };
}

sub matches {
  my $self = shift;
  $self->__build_parents;
  my ($path, $context) = @_;
  $context ||= $self;
  return $self->__xpath_engine->matches($self, $path, $context);
};

sub findnode {
  my $self = shift;
  my (@nodes) = $self->__xpath_engine->findnodes(@_, $self);
  Carp::croak "findnode found more than one node" if @nodes > 1;
  return $nodes[0];
}

sub __xpath_engine_options { () }

sub __xpath_engine {
  return $_[0]->{__xpath_engine} ||= Tree::XPathEngine->new(
    $_[0]->__xpath_engine_options
  );
}

# this is a terrible, terrible hack.  something like this should be in
# Email::MIME instead.  try to future-proof it somewhat.  -- hdp, 2007-04-20
sub __is_multipart {
  return grep { $_ != $_[0] } $_[0]->parts;
}

# XXX a lot of trickery here is necessary because Email::MIME objects can be
# shared among multiple trees at once.  We keep track of parent/address
# information inside the XPathEngine object, which is (originally) only inside
# the top-level part.
sub __build_parents {
  my $self = shift;
  my $parent  = $self->__xpath_engine->{__parent}  = {};
  my $address = $self->__xpath_engine->{__address} = {};
  $self->__xpath_engine->{__root} = $self;
  Scalar::Util::weaken($self->__xpath_engine->{__root});
  my $id = 0;
  $address->{$self} = $id++;
  my @q = $self;
  while (@q) { 
    my $part = shift @q;
    my @subparts = $part->parts;
    for (@subparts) {
      $parent->{$_} = $part;
      Scalar::Util::weaken $parent->{$_};
      $address->{$_} = $id++;
      # XXX this will cause collisions if more than one Email::MIME::XPath
      # shares parts
      $_->{__xpath_engine} = $self->__xpath_engine;
      Scalar::Util::weaken $_->{__xpath_engine};
    }
    push @q, grep { __is_multipart($_) } @subparts;
  }
}

sub __xpath_parent {
  $_[0]->__xpath_engine->{__parent}->{$_[0]}
}

sub address {
  $_[0]->__xpath_engine->{__address}->{$_[0]}
}

sub get_name {
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  my $name = (split m!/!, (split /;/, $_[0]->content_type)[0])[1];
  #my $name = __is_multipart($_[0]) ? 'multi' : 'part';
  #warn "name = $name";
  return $name;
}
sub get_next_sibling {
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  return;
}
sub get_previous_sibling {
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  return;
}
sub get_root_node {
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  $_[0]->__xpath_engine->{__root}->__xpath_get_parent_node;
}
sub get_parent_node { 
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  my $node = shift;
  return $node->__xpath_parent || bless { root => $node }, 'Email::MIME::XPath::Root';
}
sub get_child_nodes {
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  my @kids = grep { $_ != $_[0] } $_[0]->parts;
  return @kids;
}
sub is_element_node { 1 }
sub is_document_node { 0 }
sub is_attribute_node { 0 }
sub is_text_node { }

sub get_attributes { 
  #my $subname = (caller(0))[3]; warn "$subname from " . $_[0]->__xpath_address;
  my $node = shift;
  my %attr = (
    content_type => (split /;/, $node->content_type)[0],
    address      => $node->__xpath_address,
    $node->header('Content-Disposition') ? (filename => $node->filename) : (),
    map {
      my $val = $node->header($_);
      defined $val ? (lc($_) => $val) : ()
    } qw(from to cc subject),
  );
  #use Data::Dumper; warn Dumper(\%attr);
  return map {
    bless {
      name  => $_,
      value => $attr{$_},
      node  => $node,
    } => 'Email::MIME::XPath::Attribute'
  } keys %attr;
}
sub cmp { 
  return $_[0]->__xpath_address <=> $_[1]->__xpath_address
}
sub to_literal { }

package Email::MIME::XPath::Root;

sub __xpath_address { -1 } # root is always first
sub xpath_get_child_nodes   { $_[0]->{root} }
sub xpath_get_attributes    { () }
sub xpath_is_document_node  { 1 }
sub xpath_is_element_node   { 0 }
sub xpath_is_attribute_node { 0 }

package Email::MIME::XPath::Attribute;

sub xpath_get_value    { return $_[0]->{value} }
sub xpath_get_name     { return $_[0]->{name} }
sub xpath_string_value { return $_[0]->{value} }
sub xpath_is_document_node  { 0 }
sub xpath_is_element_node   { 0 }
sub xpath_is_attribute_node { 1 }
sub to_string { return sprintf('%s="%s"', $_[0]->{name}, $_[0]->{value}) }
sub address { return join(":", $_[0]->{node}, $_[0]->{rank} || 0) }
sub xpath_cmp { $_[0]->address cmp $_[1]->address }

1;
