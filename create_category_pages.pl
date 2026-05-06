#!/bin/env perl
# nbt, 15.7.2020

# create overview and individual category pages

# TODO clean up mess
# - use check_missing_level for overview pages (needs tracking old id)
# - use master_detail_ids() for overview pages
# - all scope notes (add/prefer direct klassifikator fields)
# - for dedicated categories (B43), set "folders complete" if present
# POSTPONED
# - deeper hierarchies (too many forms beyond simple sub-Sm hierarchies)

use strict;
use warnings;
use autodie;
use utf8::all;

use Carp;
use Data::Dumper;
##use Devel::Size qw(size total_size);
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use Unicode::Collate;
use YAML;
use ZBW::PM20x::Folder;
use ZBW::PM20x::Vocab;

##Readonly my $WEB_ROOT        => path('/tmp/category');
Readonly my $WEB_ROOT        => path('../web/category');
Readonly my $KLASSDATA_ROOT  => path('../data/klassdata');
Readonly my $FOLDERDATA_ROOT => path('../data/folderdata');
Readonly my $FILMDATA_ROOT   => path('../data/filmdata');
Readonly my $TEMPLATE_ROOT   => path('html_tmpl');
Readonly my $TO_ROOT         => path('../../../..');

my %PROV = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

# TODO use prov as the first level?
my $definitions_ref = YAML::LoadFile('category_def.yaml');
my $filming_def_ref = YAML::LoadFile('filming_def.yaml');

my %linktitle = (
  about_hint => {
    de => 'über',
    en => 'about',
  },
  all_about_hint => {
    de => 'Alles über',
    en => 'All about',
  },
  folder => {
    de => 'Mappe',
    en => 'folder',
  },
  documents => {
    de => 'Dokumente',
    en => 'documents',
  },
  subject_cat => {
    de => '(in der ganzen Welt)',
    en => '(all over the world)',
  },
  geo_cat => {
    de => '(alle Mappen)',
    en => '(all folders)',
  },
  ware_cat => {
    de => '(XXX in der ganzen Welt)',
    en => '(XXX all over the world)',
  },
  subject_sys => {
    de => 'Sachsystematik',
    en => 'Subject category system',
  },
  ware_sys => {
    de => 'Warensystematik',
    en => 'Ware category system',
  },
  geo_sys => {
    de => 'Ländersystematik',
    en => 'Country category system',
  },
);

##########################
#
# category overview pages
#
##########################

print "\nCreate  overview pages\n\n";

my ( $master_voc, $detail_voc );

# loop over category types
foreach my $category_type ( sort keys %{$definitions_ref} ) {
  my $def_ref = $definitions_ref->{$category_type};

  # master vocabulary reference
  $master_voc = ZBW::PM20x::Vocab->new($category_type);

  # loop over detail types
  my ( %total_folder_count, %total_image_count );
  foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {

    # detail vocabulary reference
    $detail_voc = ZBW::PM20x::Vocab->new($detail_type);

    foreach my $lang (@LANGUAGES) {
      my @lines;
      my $title = $def_ref->{title}{$lang};
      my $provenance =
        $PROV{ $def_ref->{prov} }{name}{$lang};
      my $category_count = 0;

      # some header information for the page
      my $backlinktitle =
        $lang eq 'en'
        ? 'Folders by Category system'
        : 'Mappen nach Systematik';
      my %tmpl_var = (
        lang                => $lang,
        "is_$lang"          => 1,
        "is_$category_type" => 1,
        title               => $title,
        modified            => last_modified( $master_voc, $detail_voc ),
        backlink            => "../about.$lang.html",
        backlink_title      => $backlinktitle,
        provenance          => $provenance,
      );

      # main loop over sorted list of category ids
      my $firstletter     = '';
      my $firstletter_old = '';
      my @tabs;
      foreach my $category_id ( $master_voc->category_ids($lang) ) {

        # skip if top level "HWWA countries category system"
        next if $category_id eq '157538';

        # skip result if no folders or film sections exist
        next if ( $master_voc->has_material($category_id) == 0 );

        my $label = $master_voc->label( $lang, $category_id );

        my $signature    = $master_voc->signature($category_id);
        my $category_uri = $master_voc->category_uri($category_id);

        my %filmsections;
        foreach my $filming (qw/ 1 2/) {
          $filmsections{$filming} = [
            $master_voc->filmsectionlist(
              $category_id, $filming, $detail_type
            )
          ];
        }

        my $folder_count =
          $master_voc->folder_count( $category_id, $detail_type ) || 0;

        # control break?
        # (skip German Umlaut)
        $firstletter =
          $category_type eq 'ware'
          ? substr( $label,     0, 1 )
          : substr( $signature, 0, 1 );
        if (  $firstletter ne $firstletter_old
          and $firstletter ne 'Ä'
          and $firstletter ne 'Ö'
          and $firstletter ne 'Ü' )
        {
          my $subhead =
              $category_type eq 'ware'
            ? $firstletter
            : $master_voc->subheading( $lang, $firstletter );
          push( @lines, '', "#### $subhead <a name='id_$firstletter'></a>",
            '' );
          push( @tabs, { startchar => $firstletter } );
          $firstletter_old = $firstletter;
        }

        my $entry_body = '';
        if ( $folder_count > 0 ) {
          my $count_label =
            $category_type eq 'ware'
            ? ( $lang eq 'en' ? ' ware folders'    : ' Waren-Mappen' )
            : ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' );

          $entry_body = "$folder_count $count_label"
            . (
            ( $master_voc->folders_complete($category_id) )
            ? (
              $lang eq 'en' ? ' - complete unti 1949' : ' - bis 1949 komplett' )
            : ''
            );
        }

        # add note for film_only entries
        if ( $filmsections{1} or $filmsections{2} ) {
          my $grand_total = 0;
          foreach my $filming (qw/ 1 2 /) {
            next
              unless my $count =
              $master_voc->film_img_count( $category_id, $filming );

            $grand_total += $count;

            # total per category type, only add up in one language pass
            if ( $lang eq 'en' ) {
              $total_image_count{$category_type} += $count;
            }
          }

          if ( $grand_total > 0 ) {
            my $film_note =
              "$grand_total $filming_def_ref->{ALL}{film_note}{$lang}";
            if ($entry_body) {
              $entry_body .= " + $film_note";
            } else {
              $entry_body = $film_note;
            }
          }
        }

        # q&d extension for geo categories
        if ( $category_type eq 'geo' ) {
          $entry_body =
              ( $master_voc->folder_count( $category_id, 'subject' ) || 0 )
            . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' )
            . (
            ( $master_voc->folders_complete($category_id) )
            ? (
              $lang eq 'en'
              ? ' - complete until 1949'
              : ' - bis 1949 komplett'
              )
            : ''
            )
            . ', '
            . ( $master_voc->folder_count( $category_id, 'ware' ) || 0 )
            . ( $lang eq 'en' ? ' ware folders' : ' Waren-Mappen' );
        }

        my $entry_note = (
          ( $master_voc->geo_category_type($category_id) )
          ? $master_voc->geo_category_type($category_id) . ' '
          : ''
        );

        # don't output completely empty notes as "()"
        if ($entry_body) {
          $entry_note .= "[($entry_body)]{.hint}";
        }

        # main entry
        my $siglink = $master_voc->siglink($category_id)
          or print Dumper $category_id;
        my $entry_label =
          $category_type eq 'ware' ? $label : "$signature $label";
        my $line =
            "- [$entry_label](i/$category_id/about.$lang.html) $entry_note"
          . "<a name='$siglink'></a>";
        ## indent for Sondermappe
        if ( $signature =~ $SM_QR and $firstletter ne 'q' ) {

          # TODO check_missing_level
          $line = "  $line";
        }
        if ( $signature =~ $DEEP_SM_QR ) {

          # TODO check_missing_level
          $line = "  $line";
        }
        push( @lines, $line );
        $category_count++;
        if ( $lang eq 'en' ) {
          $total_folder_count{$detail_type} += $folder_count || 0;
        }
      }

      # for overview pages, which have only one level, we are done here
      my $tmpl = HTML::Template->new(
        filename => $TEMPLATE_ROOT->child('category_overview.md.tmpl'),
        utf8     => 1
      );
      $tmpl->param( \%tmpl_var );
      ## q & d: add lines as large variable
      $tmpl->param(
        tab_loop       => \@tabs,
        lines          => join( "\n", @lines ),
        category_count => $category_count,
      );

      foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {
        $tmpl->param( "${detail_type}_total_folder_count" =>
            $total_folder_count{$detail_type}, );
        $tmpl->param( "${detail_type}_total_image_count" =>
            $total_image_count{$category_type}, );
      }
      my $out = $WEB_ROOT->child($category_type)->child("about.$lang.md");
      $out->spew_utf8( $tmpl->output );

      $firstletter     = '';
      $firstletter_old = '';
    }
  }
}

###########################
#
# individual category pages
#
###########################

# data structure %category_data:

#   category_type
#     category_id       # defines page
#       detail_type
#         folder
#           lines
#             de|en
#         filming_loop
#           de|en
#             filming
#               filmsection_loop

my %category_data;

print "\nCollect data for folders\n";

foreach my $category_type ( sort keys %{$definitions_ref} ) {
  print "\ncategory_type: $category_type\n";

  # master vocabulary reference
  $master_voc = ZBW::PM20x::Vocab->new($category_type);

  foreach my $lang (@LANGUAGES) {
    print "  lang: $lang\n";

    my $count_ref;

    # loop over detail types
    my @detail_types =
      sort keys %{ $definitions_ref->{$category_type}{detail} };
    foreach my $detail_type (@detail_types) {
      print "    detail_type $detail_type\n";
      my $def_ref = $definitions_ref->{$category_type}->{detail}{$detail_type};
      my $detail_title = $def_ref->{title}{$lang};

      # detail vocabulary reference
      $detail_voc = ZBW::PM20x::Vocab->new($detail_type);

      my $detail_id_old = '';

      foreach my $category_id ( $master_voc->category_ids($lang) ) {

        # skip if top level "HWWA countries category system"
        next if $category_id eq '157538';

        # skip result if no folders or film sections exist
        next if ( $master_voc->has_material($category_id) == 0 );

        # collect everything for the category in lists of lines, keyed by
        # firstletter
        my $lines_ref;

        # loop over the folders for one category (for a certain detail type and
        # language)
        my @folderlist =
          $master_voc->folderlist( $lang, $category_id, $detail_voc );
        foreach my $folder (@folderlist) {

          my $folder_nk = $folder->{folder_nk};
          my ( $master_id, $detail_id ) =
            get_master_detail_ids( $category_type, $detail_type, $folder_nk );

          my $label     = $detail_voc->label( $lang, $detail_id );
          my $signature = $detail_voc->signature($detail_id);
          my $firstletter =
            $detail_type eq 'ware'
            ? substr( $label,     0, 1 )
            : substr( $signature, 0, 1 );

          ##print "      ", $folder->get_folderlabel($lang), "\n";

          # main entry
          my $line = '';
          my $relpath =
            $TO_ROOT->child('folder')->child( $folder->get_folder_hashed_path )
            ->child("about.$lang.html");
          my $syspage_link = "../../../$detail_type/about.$lang.html#"
            . $detail_voc->siglink($detail_id);
          my $catpage_link =
            "../../../$detail_type/i/$detail_id/about.$lang.html";
          my $entry_note =
              '(<a href="'
            . $folder->get_iiifview_url()
            . '" title="'
            . "$linktitle{about_hint}{$lang}: "
            . $folder->get_folderlabel($lang)
            . '" target="_blank">'
            . $folder->get_doc_count
            . " $linktitle{documents}{$lang}</a>) "
            . "([$linktitle{folder}{$lang}]($relpath))";

          # are additional indents necessary?
          # (only if there are lines already!)
          if ( $lines_ref->{$firstletter} ) {

            # additional indent for Sondermappen
            if ( $signature =~ $SM_QR and $firstletter ne 'q' ) {
              check_missing_level( $lang, $lines_ref->{$firstletter},
                $detail_voc, $detail_id, $detail_id_old, 1 );
              $line .= "  ";
            }

            # again, additional indent for subdivided Sondermappen
            if ( $signature =~ $DEEP_SM_QR ) {
              ## TODO fix with get_smsig and according broader
              check_missing_level( $lang, $lines_ref->{$firstletter},
                $detail_voc, $detail_id, $detail_id_old, 2 );
              $line .= "  ";
            }
          }

          my $syspage_title = $linktitle{"${detail_type}_sys"}{$lang};
          my $catpage_title =
            "$label " . $linktitle{"${detail_type}_cat"}{$lang};
          my $entry_label =
            $detail_type eq 'ware' ? $label : "$signature $label";
          $line .=
              "- $entry_label "
            . "[**&nearr;**]($catpage_link \"$catpage_title\") "
            . "[**&uarr;**]($syspage_link \"$syspage_title\") "
            . $entry_note;

          push( @{ $lines_ref->{$firstletter} }, $line );
          $detail_id_old = $detail_id;

          # statistics
          $count_ref->{folder_count_first}++;
          $count_ref->{document_count_first} += $folder->get_doc_count;
        }    # folder

        # save data for current category
        ## q & d: add lines as large variable
        if ( $lang eq 'en' ) {
          my %folder_data = (
            folder_count1   => $count_ref->{folder_count_first},
            document_count1 => $count_ref->{document_count_first},
          );
          if ( $master_voc->folders_complete($category_id) ) {
            $folder_data{complete} = 1;
          }
          $category_data{$category_type}{$category_id}{$detail_type}{folder} =
            \%folder_data;

          $count_ref->{folder_count_first}   = 0;
          $count_ref->{document_count_first} = 0;
        }

        # transform hash of lines by firstletter to flat text for
        # the complete category
        my $text;
        foreach my $firstletter ( sort keys %{$lines_ref} ) {

          # prepend subheading
          my $subheading =
            $detail_voc->subheading( $lang, $firstletter ) || $firstletter;
          $text .= "\n\n#### $subheading\n\n";

          # all text line for this subheading
          $text .= join( "\n", @{ $lines_ref->{$firstletter} } );
        }

        $category_data{$category_type}{$category_id}{$detail_type}{folder}
          {lines}{$lang} = $text;

      }    # category

      $count_ref = {};
      ##print "        ## size: ", total_size(\%category_data) / (1024*1024), "\n";
    }    # $detail_type
  }    # $lang
}    # $category_type

print "\n\nCollect data for film sections\n";

# now for all top level pages
foreach my $category_type (qw/ geo subject ware /) {
  print "\nfilm sections category_type: $category_type\n";

  # master vocabulary reference
  $master_voc = ZBW::PM20x::Vocab->new($category_type);
  my $master_type = $master_voc->vocab_name;

  foreach my $lang (@LANGUAGES) {
    print "  lang: $lang\n";

    # loop over detail types
    my @detail_types =
      sort keys %{ $definitions_ref->{$category_type}{detail} };
    foreach my $detail_type (@detail_types) {

      print "    detail_type: $detail_type\n";
      my $detail_voc = ZBW::PM20x::Vocab->new($detail_type);
      my $def_ref = $definitions_ref->{$category_type}->{detail}{$detail_type};
      my $detail_title = $def_ref->{title}{$lang};

      foreach my $category_id ( $master_voc->category_ids($lang) ) {
        ##print '      ', $master_voc->label( $lang, $category_id ), "\n"
        ##  if $lang eq 'de';

        my @filmings;
        foreach my $filming (qw/ 1 2 /) {
          my $filming_ref = $filming_def_ref->{$filming};

          # filmsections for the master / detail combination (works in either
          # normal or inversed hierarchical order)
          my @filmsectionlist =
            $master_voc->filmsectionlist( $category_id, $filming,
            $detail_type );

          # how to deal deal with missing information depends ...
          if ( not scalar(@filmsectionlist) > 0 ) {
            if (  $filming eq '1'
              and $category_data{$category_type}{$category_id}{$detail_type}
              {folder}{complete} )
            {
              ## is ok
            } else {
              ## in which cases should a warning be issued?
              ## warn "no film data for $category_id in filming $filming\n";
            }
            next;
          }

          my @filmsection_loop;
          foreach my $section (@filmsectionlist) {
            my $section_id = substr( $section->{'@id'}, 25 );

            my $section_label =
              $section->label( $lang, $detail_voc ) || $section->{title};

            my $entry = {
              "is_$lang"     => 1,
              filmviewer_url => $section->{'@id'},
              section_id     => $section_id,
              section_label  => $section_label,
              image_count    => $section->img_count,
            };
            if ( $section->is_filmstartonly ) {
              $entry->{is_filmstartonly} = 1;
            }
            push( @filmsection_loop, $entry );
          }

          # sort ware entries alphabetically
          if ( $detail_type eq 'ware' ) {
            my $uc = Unicode::Collate->new();
            @filmsection_loop =
              sort { $uc->cmp( $a->{'section_label'}, $b->{'section_label'} ) }
              @filmsection_loop;
          }

          my $total_number_of_images =
            $master_voc->film_img_count( $category_id, $filming );

          my %filming_data = (
            "is_$lang"             => 1,
            detail_title           => $detail_title,
            filming_title          => $filming_ref->{title}{$lang},
            legal                  => $filming_ref->{legal}{$lang},
            filmsection_loop       => \@filmsection_loop,
            total_number_of_images => $total_number_of_images,
          );

          # remove image count for ware section on geo pages
          # or geo sections on subject pages
          if ( ( $master_type eq 'geo' and $detail_type eq 'ware' )
            or ( $master_type eq 'subject' and $detail_type eq 'geo' ) )
          {
            delete $filming_data{total_number_of_images};
          }

          push( @filmings, \%filming_data );
        }    # $filming

        if ( scalar(@filmings) ) {
          $category_data{$category_type}{$category_id}{$detail_type}
            {filming_loop}{$lang} = \@filmings;
        }

        # add data for special text about secondary categories
        if ( is_secondary_category( $master_type, $detail_type ) ) {
          my $collection = $detail_type eq 'ware' ? 'wa' : 'sh';
          my %suppl      = (
            detail_title => $detail_title,
            ordered_by   => $def_ref->{ordered_by}{$lang},
            filmlist1    => "/film/h1_$collection.de.html",
            filmlist2    => "/film/h2_$collection.de.html",
          );
          $category_data{$category_type}{$category_id}{$detail_type}
            {secondary_category}{$lang} = \%suppl;
        }    # secondary_category
      }    # $category_id
    }    # $detail_type
  }    # $lang
}

###print "\n## size inc. film: ", total_size(\%category_data) / (1024*1024), "\n";
###path('/tmp/category.dat')->spew(Dumper \%category_data); exit;

print "\n\nOutput of individual category pages\n\n";

foreach my $lang (@LANGUAGES) {
  print "  $lang:\n";

  foreach my $category_type ( sort keys %category_data ) {
    print "    $category_type:\n";

    # master vocabulary reference
    $master_voc = ZBW::PM20x::Vocab->new($category_type);
    my $master_type = $master_voc->vocab_name;

    foreach my $category_id ( sort keys %{ $category_data{$category_type} } ) {

      my $category_ref = $category_data{$category_type}{$category_id};

      my @detail_data;
      foreach my $detail_type ( sort keys %{$category_ref} ) {
        my $def_ref =
          $definitions_ref->{$category_type}->{detail}{$detail_type};
        my $folder_ref = $category_ref->{$detail_type}{folder};
        my $filming_loop_ref =
          $category_ref->{$detail_type}{filming_loop}{$lang};
        my %data = (
          "is_$lang"               => 1,
          "detail_is_$detail_type" => 1,
          detail_title             => $def_ref->{title}{$lang},
          folder_count1            => $folder_ref->{folder_count1},
          document_count1          => $folder_ref->{document_count1},
          lines                    => $folder_ref->{lines}{$lang},
          complete                 => $folder_ref->{complete},
        );
        if ( defined $filming_loop_ref ) {
          $data{filming_loop} = $filming_loop_ref;
        }

        # supplemental data for secondary category
        ## TODO fix ugly construct
        if ( is_secondary_category( $master_type, $detail_type ) ) {
          $data{is_secondary_category} = 1;
          foreach
            my $key (qw[ ordered_by detail_title filmlist1 filmlist2 ])
          {
            $data{$key} =
              $category_ref->{$detail_type}{secondary_category}{$lang}{$key};
          }
        }
        push( @detail_data, \%data );
      }    # $detail_type

      # actual output
      output_category_page( $lang, $category_type, $category_id,
        \@detail_data );

    }    # $category_id
  }    # $category_type
}    # $lang

############

sub output_category_page {
  my $lang          = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $id            = shift or croak('param missing');
  my $data_ref      = shift or croak('param missing');

  my $provenance =
    $PROV{ $definitions_ref->{$category_type}{prov} }{name}{$lang};
  my $signature = $master_voc->signature($id);
  my $label     = $master_voc->label( $lang, $id );
  $label =~ s/"/\\"/g;
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  my $uri      = "https://pm20.zbw.eu/category/$category_type/i/$id";
  my %tmpl_var = (
    uri              => $uri,
    "is_$lang"       => 1,
    label            => $label,
    modified         => last_modified( $master_voc, $detail_voc ),
    backlink         => "../../about.$lang.html",
    backlink_title   => $backlinktitle,
    provenance       => $provenance,
    wdlink           => $master_voc->wdlink($id),
    wplink           => $master_voc->wplink( $lang, $id ),
    scope_note       => $master_voc->scope_note( $lang, $id ),
    detail_type_loop => $data_ref,
  );

  if ( $category_type ne 'ware' ) {
    $tmpl_var{signature} = $signature;
  }

  # navigation tabs for overview page?
  if ( $category_type eq 'geo'
    and scalar( @{$data_ref} ) > 1 )
  {
    $tmpl_var{show_tabs} = 1;
  }

  my $tmpl = HTML::Template->new(
    filename => $TEMPLATE_ROOT->child('category.md.tmpl'),
    utf8     => 1
  );
  $tmpl->param( \%tmpl_var );

  my $out_dir =
    $WEB_ROOT->child($category_type)->child('i')->child($id);
  $out_dir = path("$WEB_ROOT/$category_type/i/$id");
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( $tmpl->output );

  return;
}

sub get_master_detail_ids {
  my $category_type = shift or croak('param missing');
  my $detail_type   = shift or croak('param missing');
  my $folder_nk     = shift or croak('param missing');

  $folder_nk =~ m/^(\d{6}),(\d{6})$/
    or confess "irregular folder id $folder_nk";

  my ( $master_id, $detail_id );
  if ( $category_type eq 'geo' and $detail_type eq 'subject' ) {
    $master_id = $1;
    $detail_id = $2;
  } elsif ( $category_type eq 'geo' and $detail_type eq 'ware' ) {
    $master_id = $2;
    $detail_id = $1;
  } elsif ( $category_type eq 'subject' and $detail_type eq 'geo' ) {
    $master_id = $2;
    $detail_id = $1;
  } elsif ( $category_type eq 'ware' and $detail_type eq 'geo' ) {
    $master_id = $1;
    $detail_id = $2;
  } else {
    croak "combination of category: $category_type"
      . " and detail: $detail_type not defined";
  }
  return ( $master_id, $detail_id );
}

sub check_missing_level {
  my $lang      = shift or croak('param missing');
  my $lines_ref = shift or croak('param missing');
  my $voc       = shift or croak('param missing');
  my $id        = shift or croak('param missing');
  my $id_old    = shift or croak('param missing');
  my $level     = shift or croak('param missing');

  # skip special signatue
  return if ( $voc->signature($id) =~ m/^[a-z]0/ );

  # skip if first part of signature is same as in last entry
  return
    if ( $voc->start_sig( $id_old, $level ) eq $voc->start_sig( $id, $level ) );

  ## insert non-linked intermediate item
  my $id_broader = $voc->broader($id);
  my $label      = $voc->label( $lang, $id_broader );
  my $signature  = $voc->signature($id_broader);
  my $line       = "- [$signature $label]{.gray}";

  # additional indent on deeper level
  if ( $level == 2 ) {
    $line = "  $line";
  }
  push( @{$lines_ref}, $line );

  return;
}

sub last_modified {
  my $master_voc = shift or croak('param missing');
  my $detail_voc = shift or croak('param missing');

  my $last_modified =
      $master_voc->modified() gt $detail_voc->modified()
    ? $master_voc->modified()
    : $detail_voc->modified();

  return $last_modified;
}

sub get_canonical {
  my $category_type = shift or croak('param missing');
  my $signature     = shift or croak('param missing');

  ( my $sig = $signature ) =~ s/ /_/g;
  my $x_canonical = "https://pm20.zbw.eu/category/$category_type/s/$sig";

  return $x_canonical;
}

sub get_filmlist_link {
  my $category_type = shift or croak('param missing');
  my $filming       = shift or croak('param missing');

  # TODO does only work in certain settings
  my $filmlist_link;

  if ( $category_type eq 'ware' ) {
    $filmlist_link = "/film/h${filming}_wa.de.html";
  }

  return $filmlist_link;
}

sub is_secondary_category {
  my $master_type = shift or croak('param missing');
  my $detail_type = shift or croak('param missing');

  if ( ( $master_type eq 'geo' and $detail_type eq 'ware' )
    or ( $master_type eq 'subject' and $detail_type eq 'geo' ) )
  {
    return 1;
  } else {
    return;
  }
}
