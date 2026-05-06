# 2025-12-14

# also tests $section->film()

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film::Section';

use_ok($class) or die "Could not load $class\n";

my $_ref = [
  {
    id       => '',
    expected => {
      film          => '',
      filmstartonly => undef,
    },
    diag => 0,
  },
];

my @cases = (
  {
    id       => 'h1/wa/W0087H/0002',
    expected => {
      film          => 'W0087H',
      filmstartonly => 1,
    },
    diag => 0,
  },
);

foreach my $case_ref (@cases) {
  ok( my $section = ZBW::PM20x::Film::Section->init_from_id( $case_ref->{id} ),
    "init from id" );
  is( $section->film->name, $case_ref->{expected}{film}, 'film from section' );
  is(
    $section->is_filmstartonly,
    $case_ref->{expected}{filmstartonly},
    $section->id . ' is filmstartonly: ' . $section->is_filmstartonly
  );
}

done_testing;
