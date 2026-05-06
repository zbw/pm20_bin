# 2025-12-09

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

my @cases = (
  {
    id    => 'h1/sh/S0001H',
    valid => undef,
  },
  {
    id    => 'h1/sh/S0006H',
    valid => 1,
  },
  {
    id    => 'h1/sh/S0370H',
    valid => 1,
  },
  {
    id    => 'h1/sh/S0374H_1',
    valid => 1,
  },
  {
    id    => 'h1/sh/S0220H_1',
    valid => undef,
  },
  {
    id    => 'h1/sh/S0220H_2',
    valid => 1,
  },
);

foreach my $case_ref (@cases) {
  my $id = $case_ref->{id};
  is( ZBW::PM20x::Film->valid($id),
    $case_ref->{valid}, "Film $id -> " . ( $case_ref->{valid} || "0" ) );
}

done_testing;
