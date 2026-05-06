#!/bin/perl
# nbt, 31.1.2018

# create a IIIF manifest files for pm20 folders

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use HTML::Entities;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $IIIF_ROOT_URI   => 'https://pm20.zbw.eu/iiif/folder/';
Readonly my $PDF_ROOT_URI    => 'https://pm20.zbw.eu/pdf/folder/';
## manifest files exist in the web tree
Readonly my $IIIF_ROOT       => path('/pm20/iiif/folder');
Readonly my $IMAGEDATA_ROOT  => path('/pm20/data/imagedata');
Readonly my $DOCDATA_ROOT    => path('/pm20/data/docdata');
Readonly my $FOLDERDATA_ROOT => path('/pm20/data/folderdata');
Readonly my %RES_EXT         => (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);
Readonly my @LANGUAGES   => qw/ en de /;
Readonly my @COLLECTIONS => qw/ co pe sh wa /;

my $tmpl = HTML::Template->new(
  filename          => 'html_tmpl/static_manifest.json.tmpl',
  utf8              => 1,
  default_escape    => 'js',
  loop_context_vars => 1
);

my (
  $docdata_file, $imagedata_file, $imagesize_file, $folderdata_file,
  $docdata_ref,  $imagedata_ref,  $imagesize_ref,  $folderdata_ref
);

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa|sh)$: ) {
    my $collection = $1;
    mk_collection($collection);
  } elsif ( $ARGV[0] =~ m:^(co|pe)/(\d{6}): ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] =~ m:^(sh|wa)/(\d{6},\d{6})$: ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] eq 'ALL' ) {
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
    mk_collection($collection);
  }
}

sub mk_collection {
  my $collection = shift or die "param missing";

  # load input files
  load_files($collection);

  my $i = 0;
  foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
    $i++;
    ##next if ( $i < 2900);

    mk_folder( $collection, $folder_nk );

    # debug and progress info
    if ( $i % 100 == 0 ) {
      print "$i folders done (up to $collection/$folder_nk)\n";
    }
  }
}

sub mk_folder {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";

  my $folder         = ZBW::PM20x::Folder->new( $collection, $folder_nk );
  my $folderdata_raw = $folder->get_folderdata_raw;

  # check if folder dir exists
  my $rel_path  = $folder->get_folder_hashed_path();
  my $full_path = $ZBW::PM20x::Folder::FOLDER_ROOT->child($rel_path);
  if ( not -d $full_path ) {
    die "$full_path does not exist\n";
  }

  # check folder data exists
  if ( not $folderdata_raw ) {
    warn "No folder data for $collection/$folder_nk\n";
    return;
  }

  # open files if necessary
  # (check with arbitrary entry)
  if ( not defined $imagedata_ref ) {
    load_files($collection);
  }

  # TODO clearly wrong - change to public/intern pdfs?
  my $pdf_url = $PDF_ROOT_URI . "$rel_path/${folder_nk}.pdf";

  foreach my $type ( 'public', 'intern' ) {

    my $folder_uri = $folder->get_folder_uri;

    # get page and document structures
    my ( $main_loop_ref, $doc_loop_ref ) = build_canvases( $folder, $type );
    ## skip if empty
    next if scalar(@$main_loop_ref) < 1;

    my %tmpl_var = (
      manifest_uri => "${IIIF_ROOT_URI}$collection/$folder_nk/manifest.json",
      folder_uri   => $folder_uri,
      main_loop    => $main_loop_ref,
      doc_loop     => $doc_loop_ref,
    );
    if ( $folderdata_raw->{fromTo} ) {
      $tmpl_var{from_to} = $folderdata_raw->{fromTo};
    }
    if ( $folderdata_raw->{dateOfBirthAndDeath} ) {
      $tmpl_var{from_to} = $folderdata_raw->{dateOfBirthAndDeath};
    }

    foreach my $lang (@LANGUAGES) {

      # label
      my $label = decode_entities( $folder->get_folderlabel($lang) );
      $tmpl_var{"folder_label_$lang"} = $label;

      # feedback mailto
      my $mailto =
          "ma&#105;l&#116;o&#58;%69&#110;&#102;o%40zbw&#46;eu"
        . "?subject=Feedback%20zu%20PM20%20$label"
        . "&amp;body=%0D%0A%0D%0A%0D%0A---%0D%0A"
        . "https://pm20.zbw.eu/dfgview/$collection/$folder_nk";

      ##$tmpl_var{mailto} = $mailto;
    }

    $tmpl->param( \%tmpl_var );

    write_manifest( $type, $folder, $tmpl );
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $docdata_file    = $DOCDATA_ROOT->child("${collection}_docdata.json");
  $docdata_ref     = decode_json( $docdata_file->slurp_raw );
  $imagedata_file  = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref   = decode_json( $imagedata_file->slurp_raw );
  $imagesize_file  = $IMAGEDATA_ROOT->child("${collection}_size.json");
  $imagesize_ref   = decode_json( $imagesize_file->slurp_raw );
  $folderdata_file = $FOLDERDATA_ROOT->child("${collection}_label.json");
  $folderdata_ref  = decode_json( $folderdata_file->slurp_raw );
}

sub get_max_image_fn {
  my $folder_nk = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page      = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_nk} };

  return
      $imagedata{root} . '/'
    . $imagedata{docs}{$doc_id}{rp}
    . "/${page}_A.JPG";
}

sub get_doc_range_uri {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";

  return "${IIIF_ROOT_URI}$collection/${folder_nk}/${doc_id}";
}

sub get_document_uri {
  my $folder = shift || die "param missing";
  my $doc_id = shift || die "param missing";

  return $folder->get_folder_uri . "/$doc_id";
}

sub get_page_uri {
  my $folder  = shift || die "param missing";
  my $doc_id  = shift || die "param missing";
  my $page_no = shift || die "param missing";

  my $doc_uri = get_document_uri( $folder, $doc_id );
  $page_no = sprintf( "%04d", $page_no );
  return "$doc_uri/$page_no";
}

sub get_image_uri {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $page_no    = shift || die "param missing";

  my $doc_uri = get_doc_range_uri( $collection, $folder_nk, $doc_id );
  $page_no = sprintf( "%04d", $page_no );
  return "$doc_uri/${page_no}";
}

sub get_dim {
  my $max_image_fn = shift || die "param missing";
  my $res          = shift || die "param missing";

  my $width  = $imagesize_ref->{$max_image_fn}{$res}{w};
  my $height = $imagesize_ref->{$max_image_fn}{$res}{h};
  return ( $width, $height );
}

sub build_canvases {
  my $folder = shift || die "param missing";
  my $type   = shift || die "param missing";

  my $collection = $folder->{collection};
  my $folder_nk  = $folder->{folder_nk};

  my %imagedata = %{ $imagedata_ref->{$folder_nk} };

  my %doc_info;
  my @main_loop;
  my @doc_loop;
  my $doclist_ref = ( $folder->get_doclist($type) or [] );
  foreach my $doc_id ( sort @{$doclist_ref} ) {

    my @page_loop;
    my %doc_info  = %{ get_doc_info( $folder, $doc_id ) };
    my %doc_entry = (
      doc_range_uri => get_doc_range_uri( $collection, $folder_nk, $doc_id ) );

    # cannot be enumerated independently from file names, because in
    # create_iiif_img.pl only file names are available!
    ##my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      my $image_id = substr( $page, 24, 4 );
      ## file name is 0 based; start page numbers with 1
      my $page_no = $image_id + 1;

      # document uri on doc_loop/image_range structure is not displayed by
      # Universal viewer, therefore it is added here on the canvas level
      my $document_uri = $doc_entry{document_uri};
      my $page_uri     = get_page_uri( $folder, $doc_id, $page_no );
      my $image_uri =
        get_image_uri( $collection, $folder_nk, $doc_id, $page_no );
      my $max_url    = "$image_uri/full/max/0/default.jpg";
      my $canvas_uri = "$image_uri/canvas";
      ## w,h are here only used for aspect ratio
      my $max_image_fn = get_max_image_fn( $folder_nk, $doc_id, $page );
      my ( $width, $height ) = get_dim( $max_image_fn, 'A' );

      my %entry = (
        canvas_uri   => $canvas_uri,
        thumb_uri    => "$image_uri/thumbnail.jpg",
        document_uri => $doc_info{document_uri},
        page_uri     => $page_uri,
        img_uri      => $image_uri,
        max_url      => $max_url,
        width        => $width,
        height       => $height,

      );

      if ( $folder->get_document_locked_flag($doc_id) ) {
        $entry{is_locked} = 1;
      }

      foreach my $lang (@LANGUAGES) {
        my $label =
            ( $lang eq 'en' ? 'p. ' : 'S. ' )
          . $page_no
          . ( $lang eq 'en' ? ' of ' : ' von ' )
          . decode_entities( $doc_info{"doc_label_$lang"} );
        $entry{"canvas_label_$lang"} = $label;
      }

      push( @main_loop, { %entry, %doc_info } );
      push( @page_loop, { canvas_uri => $canvas_uri } );
    }
    $doc_entry{page_loop} = \@page_loop;
    push( @doc_loop, { %doc_entry, %doc_info } );
  }
  return \@main_loop, \@doc_loop;
}

sub get_manifest_dir {
  my $folder = shift || die "param missing";

  my $dir =
    $IIIF_ROOT->child( $folder->{collection} )->child( $folder->{folder_nk} );
  $dir->mkpath;

  return $dir;
}

sub get_doc_info {
  my $folder = shift || die "param missing";
  my $doc_id = shift || die "param missing";

  my %doc_info;
  $doc_info{document_uri} = get_document_uri( $folder, $doc_id );
  foreach my $lang (@LANGUAGES) {
    my $label = decode_entities( $folder->get_doclabel( $lang, $doc_id ) );
    $doc_info{"doc_label_$lang"} = $label;
  }

  # TODO additional document data as metadata fields
  # - is this necessary???
  ##my $docdata = $folder->get_docdata($doc_id);
  ##my @meta_fields = qw/ title author pub date /;
  ##my %config_meta = (
  ##  title => {
  ##    label => {
  ##      'de' => 'Titel',
  ##      'en' => 'Title',
  ##    },
  ##  },
  ##  author => {
  ##    label => {
  ##      'de' => 'Autor/in',
  ##      'en' => 'Auhtor',
  ##    },
  ##  },
  ##);
  ##my %meta;
  ##foreach my $field (@meta_fields) {
  ##}

  return \%doc_info;
}

sub write_manifest {
  my $type   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $manifest_file = get_manifest_dir($folder)->child("$type.manifest.json");

  # unescape single quotes, which should occur only within quoted strings
  my $output = $tmpl->output;
  $output =~ s/\\'/'/g;

  # validate json
  my $dummy = eval { decode_json($output) };
  if ($@) {
    ## skip UTF-8 errors
    if (  $type ne 'public'
      and not( $@ =~ m/malformed UTF-8 character in JSON string/ )
      and not( $@ =~ m/Wide character in subroutine entry/ ) )
    {
      print "decode_json for $folder->{collection}/$folder->{folder_nk} "
        . "failed, invalid json. error:$@\n";
    }
  }

  $manifest_file->spew_utf8($output);
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

