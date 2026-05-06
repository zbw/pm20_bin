# 2025-12-09

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

ok( my @films = $class->films('h1_sh'), "load film list" );

#diag Dumper \@films;

ok(
  !( grep { $_->name() eq 'S0001H' } @films ),
  'does not contain S0001H (online with folder)'
);

done_testing;
