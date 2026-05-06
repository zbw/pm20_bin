# 10.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Vocab';

use_ok($class) or die "Could not load $class\n";

my ( $ware_id, $geo_id, $subject_id, $filming, @waresections, @geosections,
  @subjectsections );
my $ware_vocab    = $class->new('ware');
my $geo_vocab     = $class->new('geo');
my $subject_vocab = $class->new('subject');

# testcase film/h1/wa/W0087H/0002 (Eisenwaren : Österreich)
# film.jsonld comprises
#   - is arbitrary (beginning of new film, not beginning of geo
#     (as indicated by start date 1932))

$ware_id = 142275;
$geo_id  = 141731;
$filming = 1;

@waresections = $ware_vocab->filmsectionlist( $ware_id, $filming, 'geo' );
ok( @waresections, "ware $ware_id has geo sections in filming $filming" );

#diag Dumper \@waresections;

@geosections = $geo_vocab->filmsectionlist( $geo_id, $filming, 'ware' );
ok( @geosections, "geo $geo_id has ware sections in filming $filming" );

my @section_uris = map { $_->{'@id'} } @geosections;

#diag Dumper \@section_uris;

my @sorted_section_uris = sort @section_uris;
is_deeply \@section_uris, \@sorted_section_uris,
  "list is strictly sorted by section uri";

# create a lookup hash of ware ids for the geo (just for testing)
my %ware = map { $_->{ware}{'@id'} =~ m/\/(\d+)$/ => 1 } @geosections;

# TODO inverse logic, when sections with start date are excluded
ok( $ware{$ware_id}, "section for ware id $ware_id in result" );

#warn(Dumper \%ware_id);

# test case film/h1/sh/S0234H/0173/L (Polen : Seeschiffahrt)
$subject_id = 145567;
$geo_id     = 140962;

@geosections = $geo_vocab->filmsectionlist( $geo_id, $filming, 'subject' );
ok( @geosections, "geo $geo_id has subject sections in filming $filming" );

@subjectsections =
  $subject_vocab->filmsectionlist( $subject_id, $filming, 'geo' );
ok( @subjectsections,
  "subject $subject_id has geo sections in filming $filming" );

# create a lookup hash of geo ids for the subject (just for testing)
my %geo = map { $_->{country}{'@id'} =~ m/\/(\d+)$/ => 1 } @subjectsections;
ok( $geo{$geo_id}, "section for geo id $geo_id in result" );

#test case: Kautschuk : Brasilien

$ware_id = 143085;
$geo_id  = 141697;
$filming = 1;

@geosections = $geo_vocab->filmsectionlist( $geo_id, $filming, 'ware' );
ok( @geosections, "geo $geo_id has ware sections in filming $filming" );

#warn Dumper \@geosections;

done_testing;
