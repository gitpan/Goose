#!perl
package TestModifiers;

use Test::Lite ':strict';
plan tests => 4;

$Test::Lite::DieOnSyntaxError = 1;

my $CLASS = __PACKAGE__;

use_ok 'Goose';

can_ok 'Goose' => qw/
    override
    around
    before
    after
/;

sub test { "World"; }

subtest 'Test Override' => sub {
    $CLASS->override( test => sub {
        "Town";
    });

    is test(), "Town", { type => 'Str' }, 'Override succeeded';
};

subtest 'Test Restore' => sub {
    $CLASS->restore( 'test' );
    
    is test(), "World", { type => 'Str' }, 'Restore succeeded';
};
