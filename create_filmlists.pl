#!/bin/env perl
# nbt, 8.11.2019

# create lists of films from filmdata/*.json

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

my $film_web_root = path('../web/film');
my $filmdata_root = path('../data/filmdata');
my $img_file      = $filmdata_root->child('img_count.json');
my $ip_hints =
  path('../web/templates/fragments/ip_hints.de.md.frag')->slurp;

my %page = (
  h => {
    name       => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    column_ids => [
      qw/ film_id start_sig start_date end_sig end_date img_count online comment /
    ],
    info =>
'Das Material der Filme mit den [hellgrün unterlegten Links]{.is-online} ist in der [Pressemappe 20. Jahrhundert](http://webopac.hwwa.de/pressemappe20) erschlossen und online auf Mappen- und Dokumentebene zugreifbar, soweit rechtlich möglich auch im Web.',
    head =>
'Filmnummer|Signatur des jeweils ersten Bildes|Datum des jeweils ersten Bilder|Signatur des jeweils letzten Bildes|Datum des jeweils letzten Bildes|Anzahl Doppelseiten|Online gestellt|Bemerkungen',
    delim => '-|---|-|---|-|-|-|-',
    list  => {
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
    name       => 'Wirtschaftsarchiv des Instituts für Weltwirtschaft (WiA)',
    column_ids => [
      qw/ film_id img_id country geo_sig topic_sig from to no_material comment /
    ],
    info => 'Vorläufige Übersicht',
    head =>
'Film|Aufnahme|Land|Ländersign.|Sachsignatur|Von|Bis|Kein Material|Bemerkungen',
    delim => '--|--|---|--|--|-|-|-|---',
    list  => {
      k1_sh => {
        title => 'Sacharchiv 1. Verfilmung',
      },
      k2_sh => {
        title => 'Sacharchiv 2. Verfilmung',
      },
    },
  },
);

# TEMPORARY: remove path
my $img_count = decode_json( $img_file->slurp_raw );
my %img_cnt;
foreach my $key ( keys %{$img_count} ) {
  my $shortkey = substr( $key, 18 );
  $img_cnt{$shortkey} = $img_count->{$key};
}

foreach my $prov ( keys %page ) {
  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {
    print "$page_name\n";

    my $title = $page{$prov}{list}{$page_name}{title};
    my $coll  = substr( $page_name, 3, 2 );
    my $set   = substr( $page_name, 0, 2 );

    my $zotero_file = $filmdata_root->child("zotero.$page_name.json");
    my %zotero_film;
    if ( -f $zotero_file ) {
      %zotero_film = %{ decode_json( $zotero_file->slurp_raw ) };
    }

    # some header information for the page
    my @lines;
    push( @lines,
      '---',
      "title: \"$page_name: $title\"",
      "backlink: ./about.de.html",
      "backlink-title: Film-Überblick",
      "robots: noindex",
      '---', '' );
    push( @lines, "### $page{$prov}{name}",                  '' );
    push( @lines, "# $page{$prov}{list}{$page_name}{title}", '' );
    push( @lines,
'Aus urheberrechtlichen Gründen sind die digitalisierten Filme nur im ZBW-Lesesaal (und für das HWWA-Material bis 1949 auch aus dem EU-Raum) zugänglich. *Bitte überprüfen Sie eigenverantwortlich vor einer Vervielfältigung oder Veröffentlichung einzelner Artikel deren urheberrechtlichen Status* ([Hinweise](#urheberrecht)) und holen Sie ggf. die Rechte bei den Rechteinhabern ein.',
      '' );
    if ( $page{$prov}{info} ) {
      push( @lines, $page{$prov}{info}, '' );
    }
    push( @lines, '::: {.wikitable}', '' );
    push( @lines, $page{$prov}{head}, $page{$prov}{delim} );

    # read json input
    my $filmfile = $filmdata_root->child( $page_name . '.expanded.json' );
    if (not $filmfile->exists) {
      $filmfile = $filmdata_root->child( $page_name . '.json' );
    }
    my @film_sections =
      @{ decode_json( $filmfile->slurp_raw ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      my @columns;

      # add count via lookup
      my $film = "$set/$coll/$film_section->{film_id}";
      $film_section->{img_count} = $img_cnt{$film};

      foreach my $column_id ( @{ $page{$prov}->{column_ids} } ) {
        my $cell = $film_section->{$column_id} || '';

        # gray out films which are already online
        if (  $film_section->{online}
          and $column_id ne 'online'
          and $column_id ne 'film_id' )
        {
          $cell = "[$cell]{.gray}";
        }

        # add film id anchor
        # (don't use film_id column, otherwise linking fails)
        if ( $column_id eq 'start_sig' ) {
          $cell = "<a name='" . $film_section->{film_id} . "'></a>$cell";
        }

        if ( $column_id eq 'online' ) {
          ## add class and link to "online" cell
          if ( $cell ne '' ) {
            $cell = "[[$cell]{.is-online}](https://pm20.zbw.eu/folder/$coll)";
            ## add indicator for zotero films
          } elsif ( $zotero_film{ $film_section->{film_id} } ) {
            $cell = '-';
          }
        }
        push( @columns, $cell );
      }
      push( @lines, join( '|', @columns ) );

      if ( $#columns ne $#{ $page{$prov}->{column_ids} } ) {
        warn "Number of columns: $#columns\n$columns[$#columns]\n";
      }
    }

    # close table div
    push( @lines, '', ':::', '' );
    push( @lines, $ip_hints );

    # write output to public
    my $out = $film_web_root->child( 'public.' . $page_name . '.de.md' );
    $out->spew_utf8( join( "\n", @lines ) );

    # insert links into @lines
    my $lines_intern_ref = insert_links( $page_name, \@lines );

    # write output to intern
    $out = $film_web_root->child( 'intern.' . $page_name . '.de.md' );
    $out->spew_utf8( join( "\n", @{$lines_intern_ref} ) );
  }
}

#######################

sub insert_links {
  my $page_name = shift or die "param missing";
  my $lines_ref = shift or die "param missing";

  my $prov = substr( $page_name, 0, 1 );
  my @lines_intern;
  my $prev_film_id = '';
  foreach my $line ( @{$lines_ref} ) {

    # only for table lines which include some number(s)
    # (skip head and delim)
    if ( $line =~ m/\d\d/ and $line =~ m/^(.+?)\|(.*?)\|(.*)$/ ) {
      my $film_id      = $1;
      my $second_match = $2;
      my $rest         = $3;

      # for film ids from Kiel
      if ( $film_id =~ m/^[0-9]+$/ ) {
        $film_id = sprintf( "%04d", $film_id );
      }

      my $dir = join( '/', split( /_/, $page_name ) );

      # link only if there's content for the cell with the first image
      # and the according film directory exists
      my $film_link;
      if ( $second_match ne '' and -d "$film_web_root/$dir/$film_id" ) {
        $film_link = "[$film_id]($dir/$film_id)";

        # gray out filmlink if film is already online
        if ( $line =~ m/{\.is-online}/ ) {
          $film_link =~ s/(\[$film_id\])/\[$1\{.gray\}\]/;
        }
      } else {
        $film_link = $film_id;
      }

      # Kiel entries have an image link, Hamburg entries don't
      if ( $prov eq 'k' ) {
        my $img_id = $second_match;

        # enhance number (if valid) from file_id and construct file name
        if ( looks_like_number($img_id) ) {
          $img_id = sprintf( "%04d", $img_id );
        }
        my $img_file = "$film_web_root/$dir/$film_id/S$film_id${img_id}K.jpg";

        # check if according file exists
        my $img_link;
        if ( -f $img_file ) {
          $img_link = "[$img_id]($dir/$film_id/$img_id)";
        } else {
          print "    No img: $film_id $img_id\n";
          $img_link = $img_id;
        }

        # for every new film, create a link to the first image
        if ( $film_id ne $prev_film_id ) {
          push( @lines_intern, "$film_link|$img_link|$rest" );
        } else {
          push( @lines_intern, "\" |$img_link|$rest" );
        }
      } else {
        push( @lines_intern, "$film_link|$second_match|$rest" );
      }
      $prev_film_id = $film_id;
    } else {
      push( @lines_intern, $line );
    }
  }
  return \@lines_intern;
}
