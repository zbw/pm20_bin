#!/bin/env perl
# nbt, 2021-11-29

# creates the .md files for folder lists
# (links to all folders of a collection on one page)

# intended for pe and co
# (for sh and wa, categories work much better)

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use Unicode::Collate;
use YAML;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_DATA    => path('/pm20/data/rdf/pm20.extended.jsonld');
Readonly my $FOLDER_ROOT    => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');
Readonly my %TITLE          => %{ YAML::LoadFile('archive_titles.yaml') };
Readonly my @COLLECTIONS    => qw/ co pe /;
Readonly my @LANGUAGES      => qw/ en de /;

my $filming_def_ref = YAML::LoadFile('filming_def.yaml');

my $tmpl = HTML::Template->new(
  filename => 'html_tmpl/folderlist.md.tmpl',
  utf8     => 1,
);

my %collection_ids;

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa)$: ) {
    load_ids( \%collection_ids );
    my $collection = $1;
    mk_collectionlist($collection);
  } elsif ( $ARGV[0] =~ m:^(co|pe)/(\d{6}): ) {
    load_ids( \%collection_ids );
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] =~ m:^(sh|wa)/(\d{6},\d{6})$: ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] eq 'ALL' ) {
    load_ids( \%collection_ids );
    mk_all();
  } else {
    &usage;
  }
} else {
  &usage;
}

####################

sub mk_all {

  foreach my $collection (@COLLECTIONS) {
    mk_collectionlist($collection);
  }
}

sub mk_collectionlist {
  my $collection = shift or die "param missing";

  # number of folders without any documents (only on paper)
  my %without_docs_count;

  # number of companies with claimed holdings, but without known location
  my %maybe_docs_count;

  # two types of lists are created for pe collection, three for co
  my @list_types = ( 'with_docs', 'without_docs' );
  if ( $collection eq 'co' ) {
    push( @list_types, 'maybe_docs' );
  }
  foreach my $list_type (@list_types) {
    foreach my $lang (@LANGUAGES) {

      # create a hash of folder lists keyed by start character
      my %abc;
      foreach my $folder_nk ( sort @{ $collection_ids{$collection} } ) {
        my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

        my $has_docs = (
               $folder->get_doc_count
            or $folder->get_film_img_counts
        );

        my $maybe_has_docs = (
          $collection eq 'co'
            and ( $folder->company_may_have_material('filming2')
            or $folder->company_may_have_material('microfiche') )
        );

        # increment folder counters
        if ( $maybe_has_docs and not $has_docs ) {
          $maybe_docs_count{$folder_nk}++;
        }
        if ( not( $has_docs or $maybe_has_docs ) ) {
          $without_docs_count{$folder_nk}++;
        }

        # skip in cases where not fitting for current $list_type
        next if ( $list_type eq 'with_docs' and not $has_docs );
        next
          if ( $list_type eq 'maybe_docs'
          and ( $has_docs or not $maybe_has_docs ) );
        next
          if ( $list_type eq 'without_docs'
          and ( $has_docs or $maybe_has_docs ) );

        # collect data for folder entry
        my $label = $folder->get_folderlabel($lang);
        ## skip undefined folders (warning in Folder.pm)
        next unless $label;

        $label =~ s/&quot;//g;
        my $startchar = uc( substr( $label, 0, 1 ) );
        push( @{ $abc{$startchar} }, $folder );
      }

      # iterate through list of start characters
      my $uc = Unicode::Collate->new();
      my ( @tabs, @startchar_entries, %total_count );
      foreach my $startchar ( sort { $uc->cmp( $a, $b ) } keys %abc ) {
        push( @tabs, { startchar => $startchar } );
        my @folders;
        my @folder_list =
          sort {
          $uc->cmp( $a->get_folderlabel($lang), $b->get_folderlabel($lang) )
          } @{ $abc{$startchar} };
        foreach my $folder (@folder_list) {
          my $label = $folder->get_folderlabel($lang);
          ## skip undefined folders (warning in Folder.pm)
          next unless $label;

          ##print $folder->get_folderlabel($lang), "\n";
          my $from_to = ( $folder->get_folderdata_raw )->{fromTo}
            || ( $folder->get_folderdata_raw )->{dateOfBirthAndDeath};
          my $path = $folder->get_folder_hashed_path->relative($collection)
            ->child("about.$lang.html");

          # note with doc and img counts
          my $note;
          my $doc_count  = $folder->get_doc_count;
          my $img_counts = $folder->get_film_img_counts;

          if ( $list_type eq 'with_docs' and ( $doc_count or $img_counts ) ) {
            if ($doc_count) {
              $note =
                ( $lang eq 'en' )
                ? "$doc_count documents"
                : "$doc_count Dokumente";
            }
            if ($img_counts) {
              $note .= ' + ' if $note;
              $note .= "$img_counts $filming_def_ref->{ALL}{film_note}{$lang}";
            }
          }
          my %entry = (
            label   => $label,
            path    => "$path",
            from_to => $from_to,
            note    => $note,
          );
          push( @folders, \%entry );

          # total counts for head of list
          if ( $doc_count or $img_counts ) {
            $total_count{folder}++;
          }
          if ($doc_count) {
            $total_count{document} += $doc_count;
          }
          if ($img_counts) {
            my @counts = split( ' / ', $img_counts );
            foreach my $cnt (@counts) {
              $total_count{image} += $cnt;
            }
          }
        }
        my %entry = (
          "is_$lang"  => 1,
          startchar   => $startchar,
          folder_loop => \@folders,
        );
        push( @startchar_entries, \%entry );
      }
      my $label = $TITLE{collection}{$collection}{$lang};
      $label .= $lang eq 'de' ? ' Mappen' : ' folders';
      my %tmpl_var = (
        lang           => $lang,
        "is_$lang"     => 1,
        provenance     => $TITLE{provenance}{hh}{$lang},
        collection     => $collection,
        label          => $label,
        backlink       => "../../about.$lang.html",
        backlink_title => 'Home',
        tab_loop       => \@tabs,
        startchar_loop => \@startchar_entries,
        fn_stub        => 'about',
      );
      $tmpl_var{"is_$list_type"} = 1;
      if ( $list_type eq 'with_docs' ) {
        $tmpl_var{robots}         = 'noindex';
        $tmpl_var{folder_count}   = $total_count{folder};
        $tmpl_var{document_count} = $total_count{document};
        if ( $total_count{image} ) {
          $tmpl_var{image_count} = $total_count{image};
        }
      }
      if ( $list_type eq 'maybe_docs' ) {
        $tmpl_var{label} .=
          $lang eq 'de'
          ? ' mit nicht erschlossenem Material'
          : ' with unindexed Material';
        $tmpl_var{backlink}       = "about.$lang.html";
        $tmpl_var{backlink_title} = $label;
        $tmpl_var{fn_stub}        = 'maybe_docs';
        $tmpl_var{robots}         = 'noindex,nofollow';
      }
      if ( $list_type eq 'without_docs' ) {
        $tmpl_var{label} .=
          $lang eq 'de'
          ? ' nur mit Metadaten'
          : ' with metadata only';
        $tmpl_var{backlink}       = "about.$lang.html";
        $tmpl_var{backlink_title} = $label;
        $tmpl_var{fn_stub}        = 'without_docs';
        $tmpl_var{robots}         = 'noindex,nofollow';
      }
      if ( $list_type eq 'without_docs' ) {
        $tmpl_var{without_docs_count} = scalar( keys %without_docs_count );
      } else {
        if ( my $additional_count = scalar( keys %maybe_docs_count ) ) {
          $tmpl_var{maybe_docs_count} = $additional_count;
        }
      }
      $tmpl->clear_params;
      $tmpl->param( \%tmpl_var );

      # write file
      my $name = $list_type eq 'with_docs' ? 'about' : $list_type;
      my $out  = $FOLDER_WEBROOT->child($collection)->child("$name.$lang.md");
      $out->spew_utf8( $tmpl->output );
    }
  }
}

sub load_ids {
  my $coll_id_ref = shift or die "param missing";

  # create a list of numerical keys for each collection
  my $data = decode_json( $FOLDER_DATA->slurp_raw );
  foreach my $entry ( @{ $data->{'@graph'} } ) {
    $entry->{identifier} =~ m/^(co|pe|sh|wa)\/(\d{6}(?:,\d{6})?)$/;
    push( @{ $coll_id_ref->{$1} }, $2 );
  }
}

sub usage {
  print "Usage: $0 {collection}|ALL\n";
  exit 1;
}

