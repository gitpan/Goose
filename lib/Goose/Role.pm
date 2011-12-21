package Goose::Role;

use Goose;

$Goose::Role::Roles = {};

constructor sub {
    my ($self, $args) = @_;
    my $pkg = caller(0);
    if ($pkg->can('with')) {
        die "Cannot use a Goose::Role and Goose at the same time. Please choose one or the other\n";
    }
    exports 'list_roles' => ( into => $pkg );
    exports 'offers'     => ( into => $pkg );
    _add_new_role( $pkg );
};

sub list_roles {
    my $class = shift;
    return $Goose::Role::Roles->{$class}->{offers};
}

sub _add_new_role {
    my $pkg = shift;
    if (exists $Goose::Role::Roles->{$pkg}) {
        warn "$pkg already exists as a Role";
        return;
    }
    $Goose::Role::Roles->{$pkg} = { offers => [] };
}

sub offers {
    my $pkg = caller(0);
    my @offers = @_;
    for my $s (@offers) {
        if (! $pkg->can($s)) {
            warn "Can't offer a subroutine that does not exist ($s)";
            next;
        }
        push @{$Goose::Role::Roles->{$pkg}->{offers}}, $s;
    }
}

1;
