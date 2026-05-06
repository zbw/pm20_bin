# 

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

my $film_id = 'h1/sh/S0073H_1';
my $film = $class->new($film_id);

is($film->id, $film_id, 'id() works');

done_testing;
