# 15.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film::Section';

use_ok($class) or die "Could not load $class\n";

my $uri = 'https://pm20.zbw.eu/film/h1/sh/S0373H/1115';
ok( my $section1 = $class->init_from_uri($uri), "created from uri" );
##diag Dumper $section1;

ok( my $section2 = $class->init_from_id('h1/sh/S0373H/1115'),
  "created from id" );
##diag Dumper $section2;

is_deeply( $section1, $section2, "same result with init from uri and id" );

is( $section1->id, 'h1/sh/S0373H/1115', "id" );

is( $section1->collection, 'sh', "collection" );

is( $section1->filming, '1', "filming" );

done_testing;
