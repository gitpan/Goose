use inc::Module::Install;

name     'Goose';
all_from 'lib/Goose.pm';
author   q{Brad Haywood <brad@geeksware.net>};
license  'perl';

build_requires 'Test::Lite' => '0.007';

auto_install;

WriteAll;

