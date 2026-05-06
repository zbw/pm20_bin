#!/bin/env perl
# nbt, 8.11.2019

# create lists of films from filmdata/*.json

use strict;
use warnings;
use utf8;

use Carp;
use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

# filmdata publicly available now
my $filmdata_root    = path('../data/filmdata');
my $klassdata_root   = path('../data/klassdata');
##my $filmdata_root    = $film_public_root;
my $img_file = $filmdata_root->child('img_count.json');
my $ip_hints =
  path('../web/templates/fragments/ip_hints.de.md.frag')->slurp_utf8;

my %page = (
  h => {
    column_ids => [
      qw/ film_id start_sig start_date end_sig end_date img_count online comment /
    ],
    list => {
      'h1_sh' => {
        title => 'Länder-Sacharchiv 1. Verfilmung',
      },
      'h2_sh' => {
        title => 'Länder-Sacharchiv 2. Verfilmung',
      },
      'h1_co' => {
        title => 'Firmen- und Institutionenarchiv 1. Verfilmung',
      },
      'h2_co' => {
        title => 'Firmen- und Institutionenarchiv 2. Verfilmung',
      },
      'h1_wa' => {
        title => 'Warenarchiv 1. Verfilmung',
      },
      'h2_wa' => {
        title => 'Warenarchiv 2. Verfilmung',
      },
    },
  },
  k => {
    column_ids => [
      qw/ film_id img_id country geo_sig topic_sig from to no_material comment /
    ],
    list => {
      k1_sh => {
        title => 'Sacharchiv 1. Verfilmung',
      },
      k2_sh => {
        title => 'Sacharchiv 2. Verfilmung',
      },
    },
  },
);

# notation regex
# (this is a variation of the notation regex in check_ifis_notation.pl)
my %nta_regex = (
  ge => {
    title   => 'Historische Länderklassifikation',
    pattern => qr/ ^ [A-Z]    # Continent
        ( \d{0,3}             # optional numerical code for country
          [a-z]?              # optional extension of country code
          ( (              # optional subdivision in brackets
            ( \(\d\d?\) )     # either numerical
            | \((alt|Wn|Bln)\)# or special codes (old|Wien|Berlin)
          ) ){0,1}
        )? $ /x,
    lookup => decode_json( $klassdata_root->child('ag_lookup.json')->slurp ),
  },
  sh => {
    title   => 'Alte Hamburger Systematik',
    pattern => qr/ ^
      [A-Z] |                 # ignore for now
      [a-z]                   # main class
        ( \s \d\d             # optional subclass
          [a-z]?              # optional subclass extension
        ){0,1}
        (                     # optional special folder
          \s SM \s .+
        ){0,1} $ /x,
    lookup => decode_json( $klassdata_root->child('je_lookup.json')->slurp ),
  },
);

my %sequence = (
  sh => [qw/ ge sh /],
  wa => [qw/ wa ge /],
  co => [qw/ ge co /],
);

## TODO extend to Kiel
##foreach my $prov ( keys %page ) {
foreach my $prov ('h') {
## TODO include companies and wares
##  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {
  foreach my $page_name ( 'h1_sh', 'h2_sh', 'h1_co', 'h2_co' ) {
    print "$page_name\n";

    my $coll = substr( $page_name, 3, 2 );
    my $set  = substr( $page_name, 0, 2 );

    # read json input
    my @film_sections =
      @{ decode_json( $filmdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      ##print Dumper $film_section;
      foreach my $sig ( 'start_sig', 'end_sig' ) {
        next unless $film_section->{$sig};

        # skip if special signature indicates empty film
        next if $film_section->{$sig} eq 'x';

        # remove the text part, reduce to notation
        my $nta;
        if ( $film_section->{$sig} =~ m/^.+? \[(.+)\]$/ ) {
          $nta = $1;
        } else {
          $nta = $film_section->{$sig};
        }
        warn( "  Missing signature in ", Dumper $film_section) unless $nta;

        # split notation at the first blank (second part may have been omitted)
        my @nta_parts = $nta =~ m/^(\S+)(?:\s(.+))?$/;

        # check the parts of the notation
        for ( my $i = 0 ; $i < scalar(@nta_parts) ; $i++ ) {
          my $nta_type = $sequence{$coll}->[$i];
          my $nta_part = $nta_parts[$i] || '';

          # skip empty notation parts
          next if $nta_part eq '';

          # TODO check also sh and co
          next unless $nta_type eq 'ge';

          check_nta( $film_section, $sig, $nta_type, $nta_part );

          ##print Dumper $nta, $nta_type, $nta_part, $film_section; exit;
        }

      }
    }
  }
}

#######################

sub check_nta {
  my $film_section = shift or die "Param missing";
  my $sig          = shift or die "Param missing";
  my $nta_type     = shift or die "Param missing";
  my $nta_part     = shift or confess "Param missing";

  # check the notation formally
  if ( not $nta_part =~ m/$nta_regex{$nta_type}{pattern}/x ) {
    warn sprintf(
      "  %-8s: [%s] %s - format error (%s)",
      $film_section->{film_id},
      $nta_part, $nta_type, $sig
      ),
      "\n";
    return;
  }

  # check if the notation is known
  if ( not exists $nta_regex{$nta_type}{lookup}->{$nta_part} ) {
    warn sprintf(
      "  %-8s: [%s] %s - not found (%s)",
      $film_section->{film_id},
      $nta_part, $nta_type, $sig
      ),
      "\n";
  }
}

