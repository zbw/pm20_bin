#!/bin/env perl
# nbt, 2020-04-20

# Create .htaccess files that *allow* access for listed film images
# plus an overview page
# (requires a checked.yaml file in the film directory)
# see https://pm20.zbw.eu/doc/tech/film_meta

# TODO
# - rename {image_name}.locked.txt {image_name}.access_locked.txt
# - implement separate procedure with
#   - evaluate {image_name}.access_locked.txt and meta.yaml with author_(name|id|qid), date, death_year
#   - (re-)create {image_name}.lock files based on both
# - check only the latter here
# - update meta.en.md

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Path::Tiny;
use YAML::Tiny;
use ZBW::PM20x::Vocab;

my $film_root      = path('/pm20/film/');
my $pub_film_root  = path('/pm20/web/film/');
my $klassdata_root = path('/pm20/data/klassdata/');

my ( $holding, $film_id, $dir );

# datastructure for overview page with links
#
# {country_signature}
#   {film_id}
#     title_de
#     title_en
#     link
#     page_count
#
my %pub_film_sect;

# arguments
if ( scalar(@ARGV) < 1 ) {
  &usage;
  exit;
} else {
  $holding = $ARGV[0];
  $film_id = $ARGV[1] || undef;
  if ( not $holding =~ m/h(1|2)\/(sh|wa|co)/ ) {
    &usage;
    exit;
  }
}

# vocabulary for signature lookup
my $voc = ZBW::PM20x::Vocab->new('geo');

if ( defined $film_id ) {

  # one single film directory
  $film_id =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id $film_id not valid\n";
  $dir = $film_root->child($holding)->child($film_id);
  link_film($dir);

} else {

  # all directories of the holding
  $film_root->child($holding)->visit( \&link_film );
  create_overview_page( $holding, \%pub_film_sect );
}

################

sub usage {
  print "usage: (h1|h2)/(sh|wa|co) {film-id}\n";
}

sub link_film {
  my $dir = shift or die "param missing";
  return unless -d $dir;

  my $htaccess = $dir->child('.htaccess');
  $htaccess->remove;

  # iterate over checked sections
  my @img_allowed;
  my $checked_fn = $dir->child('checked.yaml');
  return unless -f $checked_fn;

  my $checked = YAML::Tiny->read($checked_fn);
  foreach my $section ( @{$checked} ) {

    # skip empty "undef" section at the end
    next if not $section;

    parse_section( $checked_fn, $section );
    my $count = add_section( $dir, \@img_allowed, $section );

    # fill data structure for overview page
    $section->{count} = $count;
    my ( $holding, $film_id ) = parse_dirname( $checked_fn->parent );
    push( @{ $pub_film_sect{ $section->{country} }{$film_id} }, $section );
  }

  # create .htaccess file
  my $fh = $htaccess->openw_raw;
  foreach my $file (@img_allowed) {
    print $fh "SetEnvIf Request_URI \"$file\$\" allowedURL\n";
  }
  close $fh;
}

sub add_section {
  my $dir             = shift or die "param missing";
  my $img_allowed_ref = shift or die "param missing";
  my $section         = shift or die "param missing";

  # TODO extend for half films
  my $count = 0;
  for ( my $i = $section->{start} ; $i <= $section->{end} ; $i++ ) {

    $dir =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id in $dir not valid\n";
    my $start_chr = $1;
    my $film_no   = $2;
    my $end_chr   = $3;

    # build and check source file name
    my $img_fn =
      $start_chr . "$film_no" . sprintf( "%04d", $i ) . $end_chr . '.jpg';
    my $src = $dir->child($img_fn);
    die "File $src missing: $!\n" if not $src->is_file;

    # check if a the source file is locked
    next if is_locked($src);
    push( @{$img_allowed_ref}, $img_fn );
    $count++;

    printf "%04d: $src\n", $i;
  }
  return $count;
}

sub is_locked {
  my $src = shift or die "param missing";

  ( my $lock = $src ) =~ s/(.*?)\.jpg/$1.locked.txt/;

  # TODO extend with date/qid from file contents for moving wall

  if ( -f $lock ) {
    return 1;
  } else {
    return 0,;
  }
}

sub parse_section {
  my $checked_fn = shift or die "param missing";
  my $section    = shift or die "param missing";

  # verify section data structure
  my @required_fields =
    qw/ title_de title_en start end checked_by checked_date country /;

  foreach my $field (@required_fields) {
    if ( not defined $section->{$field} ) {
      die "missing $field field in $checked_fn\n";
    }
  }

  # amend with start link name
  my $link =
    $checked_fn->parent->relative($film_root)->child( $section->{start} );
  $section->{link} = "$link";
}

sub parse_dirname {
  my $dir = shift or die "param missing";

  $dir =~ m;film/(h(?:1|2)/(?:co|sh|wa))/((?:S|A|F|W)\d{4}(?:H|K}));
    or die "Could not parse dir name $dir\n";
  my $holding = $1;
  my $film_id = $2;

  return ( $holding, $film_id );
}

sub create_overview_page {
  my $holding       = shift or die "param missing";
  my $pub_film_sect = shift or die "param missing";

  ( my $holding_shortname = $holding ) =~ s/\//_/;
  my %page_title = (
    de => 'Veröffentlichte Abschnitte aus digitalisierten Rollfilmen',
    en => 'Published sections from digitized roll films',
  );
  my %note = (
    de =>
'In den Abschnitten können einzelne Artikel aus urheberrechtlichen Gründen ausgeblendet sein.',
    en =>
'Some articles within the sections may be left out due to intellectual property law.',
  );

  foreach my $lang (qw/ de en/) {
    my $head = <<"EOF";
---
title: $page_title{$lang}
fn-stub: public_section.$holding_shortname
robots: nofollow
---

# $page_title{$lang}

$note{$lang}

EOF

    my @page;
    foreach my $country ( sort keys %{$pub_film_sect} ) {
      my $term_id = $voc->lookup_signature($country);
      my $label   = $voc->label( $lang, $term_id );
      push( @page, "## $label" );
      foreach my $film_id ( sort keys %{ $pub_film_sect->{$country} } ) {
        push( @page, "### $film_id" );
        foreach my $section ( @{ $pub_film_sect->{$country}->{$film_id} } ) {
          my $line = '- ['
            . $section->{ 'title_' . $lang } . ']('
            . $section->{link} . ') ('
            . $section->{count} . ')';
          push( @page, $line );
        }
      }
    }
    ( my $holding_flat = $holding ) =~ s;/;_;;
    my $fn = $pub_film_root->child("public_section.$holding_flat.$lang.md");
    $fn->spew_utf8( $head . join( "\n\n", @page ) );
    print "\n$fn\n";
  }
}
