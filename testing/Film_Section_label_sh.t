# 15.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;
use ZBW::PM20x::Vocab;

my $class = 'ZBW::PM20x::Film::Section';

my %vocab = (
  'geo' => ZBW::PM20x::Vocab->new('geo'),
  'subject' => ZBW::PM20x::Vocab->new('subject'),
  ##  'ware' => ZBW::PM20x::Vocab->new('ware'),
);

use_ok($class) or die "Could not load $class\n";

my $_ref = [
  {
    title            => '',
    id               => '',
    signature_string => '',
    vocab_name       => '',
    lang             => '',
    expected         => {
      label => '',
    },
    diag => 1,
  },
];

my @cases = (
  {
    title            => 'Polen : Seeschiffahrt',
    id               => 'h1/sh/S0234H/0173/L',
    signature_string => 'A12 n32',
    vocab_name       => 'geo',
    lang             => 'en',
    expected         => {
      label => 'Poland',
    },
    diag => 0,
  },
  {
    title            => 'Nyassaland',
    id               => 'h1/sh/S0824H/1180',
    signature_string => 'C99',
    vocab_name       => 'geo',
    lang             => 'en',
    expected         => {
      label => 'Nyasaland',
    },
    diag => 0,
  },
  {
    title            => 'Nyassaland',
    id               => 'h1/sh/S0824H/1180',
    signature_string => 'C99',
    vocab_name       => 'subject',
    lang             => 'en',
    expected         => {
      label => undef,
    },
    diag => 0,
  },
  {
    title => 'Nepal : Politische Beziehungen zu einzelnen Ländern - Tibet',
    id    => 'h1/sh/S0693H/1237/R',
    signature_string => 'B55 g1 - Tibet',
    vocab_name       => 'geo',
    lang             => 'de',
    expected         => {
      label => 'Nepal - Tibet',
    },
    diag => 0,
  },
  {
    title => 'Nepal : Politische Beziehungen zu einzelnen Ländern - Tibet',
    id    => 'h1/sh/S0693H/1237/R',
    signature_string => 'B55 g1 - Tibet',
    vocab_name       => 'subject',
    lang             => 'de',
    expected         => {
      label => 'Politische Beziehungen zu einzelnen Ländern - Tibet',
    },
    diag => 0,
  },
  {
    title =>
'Weichsel : Europa : Einzelne Binnenschiffahrtsstrassen u. Seekanäle, Verwaltung',
    id               => 'h1/sh/S0006H/0817/R',
    signature_string => 'A1 n33a Sm3 - Weichsel',
    vocab_name       => 'geo',
    lang             => 'en',
    expected         => {
      label => 'Europe - Weichsel',
    },
    diag => 0,
  },
  {
    title =>
'Weichsel : Europa : Einzelne Binnenschiffahrtsstrassen u. Seekanäle, Verwaltung',
    id               => 'h1/sh/S0006H/0817/R',
    signature_string => 'A1 n33a Sm3 - Weichsel',
    vocab_name       => 'subject',
    lang             => 'en',
    expected         => {
      label => 'Individual inland waterways and sea canals, administration - Weichsel',
    },
    diag => 0,
  },
);

foreach my $case_ref (@cases) {
  ok( my $section = ZBW::PM20x::Film::Section->init_from_id( $case_ref->{id} ),
    "init from id" );
  my $title      = $case_ref->{title};
  my $lang       = $case_ref->{lang};
  my $vocab_name = $case_ref->{vocab_name};
  my $vocab = $vocab{$vocab_name};
  $case_ref->{label} = $section->label( $lang, $vocab );
  foreach my $field ( keys %{ $case_ref->{expected} } ) {
    if ( my $expected = $case_ref->{expected}{$field} ) {
      is( $case_ref->{$field}, $expected, "$title {$lang, $vocab_name}" );
    }
  }
  if ( $case_ref->{diag} ) {
    diag Dumper $case_ref, $section;
    last;
  }
}

done_testing;
__DATA__
  $class->parse_sh($case_ref);
  (
    is( $case_ref->{subject_id}, $case_ref->{expected}{subject_id}, $title )
      && is( $case_ref->{geo_id}, $case_ref->{expected}{geo_id}, $title )
      && is(
      $case_ref->{keyword_string}, $case_ref->{expected}{keyword_string},
      $title
      )
  ) || diag Dumper $case_ref;

