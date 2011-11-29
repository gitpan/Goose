#!perl

package MyTest;
use Goose ':Antlers';
use Test::Lite;

use_ok 'Goose', [':Antlers'];
can_ok 'MyTest' => 'has';
has 'x' => ( is => 'ro', default => 7 );
is x(), 7, { type => 'Int' }; 

done_testing;




