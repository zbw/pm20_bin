# 2025-12-05

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
    title    => '',
    id       => '',
    expected => {
      img_count => '',
    },
    diag => 1,
  },
];

my @cases = (
  {
    title    => 'Glutamat',
    id       => 'h2/wa/W2087H/0987/L',
    expected => {
      img_count => '15',
    },
    diag => 0,
  },
  {
    title =>
'Sachsen (Pr.) : Geschichtliche Vorgänge in einzelnen Staaten, Provinzen und Städten',
    id       => 'h1/sh/S0043H_1/0562/R',
    expected => {
      img_count => '59',
    },
    diag    => 0,
    comment => 'section spans S0043H_1 and S0043H_2',
  },
);

my ( $section, $img_count );

foreach my $case_ref (@cases) {
  ok( my $section = ZBW::PM20x::Film::Section->init_from_id( $case_ref->{id} ),
    'init ' . $case_ref->{title} );
  is(
    $section->img_count,
    $case_ref->{expected}{img_count},
    'img_count ' . $section->img_count
  );
  diag Dumper $case_ref, $section if $case_ref->{diag};
}

done_testing;
