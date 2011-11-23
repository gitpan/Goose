#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Goose' ) || print "Bail out!\n";
}

diag( "Testing Goose $Goose::VERSION, Perl $], $^X" );
