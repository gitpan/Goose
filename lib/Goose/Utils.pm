package Goose::Utils;

use Goose;

$Goose::Utils::VERSION = '0.002';

my $CLASS = __PACKAGE__;

constructor sub {
    my ($self, $args) = @_;
    my $class = caller(0);
    exports 'ref_has'   => ( into => $class );
    exports 'count'     => ( into => $class );
    exports 'is_number' => ( into => $class );
    exports 'speak'     => ( into => $class );
};

sub deep_keys {
    my ($self, $hashref, $code, $args) = @_;
    my $keys = 0;
    while (my ($k, $v) = each(%$hashref)) {
        my @newargs = defined($args) ? @$args : ();
        push(@newargs, $k);
        $keys++;
        if (ref($v) eq 'HASH') {
            $keys++;
            $self->deep_keys($v, $code, \@newargs);
        }
        else {
            $code->(@newargs);
        }
    }
    return $keys;
}

sub ref_has {
    my ($refvar, $key) = @_;
    if (! ref($refvar)) {
        warn 'has_element(): Expecting a reference';
        return 0;
    }

    if (ref($refvar) eq 'HASH') {
        my $match = 0;
        $CLASS->deep_keys($refvar, sub {
            $match = 1
                if grep { $_ eq $key } @_;
        });

        if ($match) { return 1; }
        else { return 0; }
    }
    elsif (ref($refvar) eq 'ARRAY') {
        if ( grep { $_ eq $key } @$refvar ) {
            return 1;
        }
        else {
            return 0;
        }
    }
}

sub is_number {
    my $num = shift;
    $num =~ s/^\s+//g;
    $num =~ s/\s+$//g;
    return 'Integer' if $num =~ /^\d+$/;
    return 'Float' if $num =~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/;
    return 0;
}   

sub count {
    my ($refvar) = @_;
    if (! ref($refvar)) {
        warn "count(): Expecting a reference";
        return 0;
    }
    else {
        if (ref($refvar) eq 'ARRAY') {
            my $num = scalar @$refvar;
            return $num;
        }
        elsif (ref($refvar) eq 'HASH') {
            my $keys = $CLASS->deep_keys($refvar, sub { });
            return $keys;
        }
    }
}

sub speak {
    my ($txt, $to) = @_;
    $to = *STDOUT
        if ! $to;
    my ($pkg, $filename, $line) = caller;
    print $to "($pkg/$filename\[ln:$line]) $txt\n";
}

1;
