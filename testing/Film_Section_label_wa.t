# 03.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;
use ZBW::PM20x::Vocab;

my %vocab = (
  'geo' => ZBW::PM20x::Vocab->new('geo'),
  ##'subject' => ZBW::PM20x::Vocab->new('subject'),
  'ware' => ZBW::PM20x::Vocab->new('ware'),
);

my $class = 'ZBW::PM20x::Film::Section';

use_ok($class) or die "Could not load $class\n";

my $struct = $class->get_grouping_properties('wa');

my $class2 = 'ZBW::PM20x::Vocab';
use_ok($class2) or die "Could not load $class2\n";

ok( $struct, 'get grouping wa' );

my ( $ware_id, $geo_id, $subject_id, $filming, @waresections, @geosections,
  @subjectsections );

# Tests for secondary sections

# testcase h1/wa/W0087H/0002 (Eisenwaren : Österreich)
# film.jsonld comprises
#   - is arbitrary (beginning of new film, not beginning of geo
#     (as indicated by start date 1932))

$ware_id = 142275;
$geo_id  = 141731;
$filming = 1;

@waresections = $class->categorysections( 'ware', $ware_id, $filming );
##diag Dumper \@waresections;
ok( @waresections, "ware $ware_id has sections in filming $filming" );
is( $waresections[1]->label( 'de', $vocab{geo} ), 'Österreich', "utf8 string" );
##diag Dumper $waresections[1];

foreach my $section (@waresections) {

  #diag $section->title, "\n";
  #diag $section->label( 'en', $vocab{geo} ), "\n";
}

##@geosections = $class2->filmsectionlist($geo_id, $filming, 'ware');
@geosections = $class->categorysections_inv( 'geo', $geo_id, $filming );
foreach my $section (@geosections) {
  ##diag $section->title, "\n";
  ##diag $section->id, "  ", $section->label( 'en', $ware_vocab ), "\n";
}

my $_ref = [
  {
    title            => '',
    id               => '',
    signature_string => '',
    vocab_name       => '',
    lang             => 'en',
    expected         => {
      label => '',
    },
    diag => 0,
  },
];

my @cases = (
  {
    title            => 'Eisenwaren : Österreich',
    id               => 'h1/wa/W0087H/0002',
    signature_string => '',
    vocab_name       => 'ware',
    lang             => 'en',
    expected         => {
      label => '',
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
  my $vocab      = $vocab{$vocab_name};
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

# Tests for secondary sections

# testcase film/h1/wa/W0087H/0002 (Eisenwaren : Österreich)
# film.jsonld comprises
#   - is arbitrary (beginning of new film, not beginning of geo
#     (as indicated by start date 1932))

$ware_id = 142275;
$geo_id  = 141731;
$filming = 1;

@waresections = $class->categorysections( 'ware', $ware_id, $filming );
##diag Dumper \@waresections;
ok( @waresections, "ware $ware_id has sections in filming $filming" );
is( $waresections[1]->label( 'de', $vocab{geo} ), 'Österreich', "utf8 string" );

#diag Dumper $waresections[1];

foreach my $section (@waresections) {
  ##diag $section->title, "\n";
  #diag $section->label( 'en', $geo_vocab ), "\n";
}
##@geosections = $class2->filmsectionlist($geo_id, $filming, 'ware');
@geosections = $class->categorysections_inv( 'geo', $geo_id, $filming );
foreach my $section (@geosections) {
  ##diag $section->title, "\n";
  ##diag $section->id, "  ", $section->label( 'en', $ware_vocab ), "\n";
}

@geosections = $class->categorysections_inv( 'geo', $geo_id, $filming );
ok( @geosections, "geo $geo_id has ware sections in filming $filming" );
##diag Dumper \@geosections;

# create a lookup hash of ware ids for the geo (just for testing)
my %ware = map { $_->{ware}{'@id'} =~ m/\/(\d+)$/ => 1 } @geosections;

# TODO inverse logic, when sections with start date are excluded
ok( $ware{$ware_id}, "section for ware id $ware_id in result" );

#warn(Dumper \%ware_id);

# test case film/h1/sh/S0234H/0173/L (Polen : Seeschiffahrt)
$subject_id = 145567;
$geo_id     = 140962;

@subjectsections =
  $class->categorysections_inv( 'subject', $subject_id, $filming );
ok( @subjectsections,
  "subject $subject_id has geo sections in filming $filming" );

# create a lookup hash of geo ids for the subject (just for testing)
my %geo = map { $_->{country}{'@id'} =~ m/\/(\d+)$/ => 1 } @subjectsections;
ok( $geo{$geo_id}, "section for geo id $geo_id in result" );

done_testing;
