#!/bin/perl
# nbt, 31.1.2018

# traverses image share and folder roots, creates (for each page)
# - info.json
# - .htaccess
# - thumbnail

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use HTML::Entities;
use HTML::Template;
use Image::Thumbnail;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $IIIF_ROOT_URI  => 'https://pm20.zbw.eu/iiif/folder/';
Readonly my $IIIF_ROOT      => path('/pm20/iiif/folder/');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;
Readonly my %RES_EXT        => (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);

my $info_tmpl =
  HTML::Template->new( filename => 'html_tmpl/info.json.tmpl', );

my ( $imagedata_file, $imagesize_file, $imagedata_ref, $imagesize_ref, );

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
    ##next if ($i < 8100);

    mk_folder( $collection, $folder_nk );

    # debug and progress info
    if ( $i % 100 == 0 ) {
      print "$i folders done (up to $folder_nk)\n";
    }
  }
}

sub mk_folder {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";

  # open files if necessary
  # (check with arbitrary entry)
  if ( not defined $imagedata_ref ) {
    print "loading imagedata\n";
    load_files($collection);
  }

  my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

  foreach my $doc_id ( keys %{ $imagedata_ref->{$folder_nk}{docs} } ) {

    foreach my $page ( @{ $imagedata_ref->{$folder_nk}{docs}{$doc_id}{pg} } ) {
      my $max_image_fn = get_max_image_fn( $folder_nk, $doc_id, $page );
      my $image_id     = substr( $page, 24, 4 );
      ## file name is 0 based; start page numbers with 1
      my $page_no = sprintf( "%04d", $image_id + 1 );
      my $image_uri =
        get_image_uri( $collection, $folder_nk, $doc_id, $page_no );
      my $image_dir =
        get_image_dir( $collection, $folder_nk, $doc_id, $page_no );

      my @rewrites;

      # create iiif info
      my %info_tmpl_var = ( image_uri => $image_uri, );
      foreach my $res ( keys %RES_EXT ) {
        my ( $width, $height ) = get_dim( $max_image_fn, $res );
        unless ( length($width) and length($height) ) {
          warn "width or height missing: $max_image_fn\n";
          next;
        }
        my $real_url = get_image_real_url( $folder, $doc_id, $page, $res );
        $info_tmpl_var{"width_$res"}  = $width;
        $info_tmpl_var{"height_$res"} = $height;

        # add rewrite for .htaccess
        push( @rewrites, { "max"            => $real_url } ) if ( $res eq 'A' );
        push( @rewrites, { "$width,$height" => $real_url } );
        push( @rewrites, { "$width,"        => $real_url } );
      }
      $info_tmpl->param( \%info_tmpl_var );
      write_info( $image_dir, $info_tmpl );

      # make thumbnail
      make_thumbnail( $max_image_fn, $image_dir )
        unless -f "$image_dir/thumbnail.jpg";

      # htaccess file
      write_htaccess( $image_dir, \@rewrites );
    }
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp_raw );
  $imagesize_file = $IMAGEDATA_ROOT->child("${collection}_size.json");
  $imagesize_ref  = decode_json( $imagesize_file->slurp_raw );
}

sub get_max_image_fn {
  my $folder_nk = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page      = shift || die "param missing";

  return
      $imagedata_ref->{$folder_nk}{root} . '/'
    . $imagedata_ref->{$folder_nk}{docs}{$doc_id}{rp}
    . "/${page}_A.JPG";
}

sub get_image_dir {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $page_no    = shift || die "param missing";

  my $image_dir =
    $IIIF_ROOT->child($collection)->child($folder_nk)->child($doc_id)
    ->child($page_no);
  $image_dir->mkpath;
  return $image_dir;
}

sub get_image_uri {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $page_no    = shift || die "param missing";

  return "$IIIF_ROOT_URI$collection/${folder_nk}/${doc_id}/${page_no}";
}

sub get_image_real_url {
  my $folder = shift || die "param missing";
  my $doc_id = shift || die "param missing";
  my $page   = shift || die "param missing";
  my $res    = shift || die "param missing";

  # create url according to dir structure
  my $url =
    '/folder/'
    . $folder->get_document_hashed_path($doc_id)->child('PIC')
    ->child( $page . $RES_EXT{$res} );

  return $url;
}

sub get_dim {
  my $max_image_fn = shift || die "param missing";
  my $res          = shift || die "param missing";

  my $width  = $imagesize_ref->{$max_image_fn}{$res}{w};
  my $height = $imagesize_ref->{$max_image_fn}{$res}{h};
  return ( $width, $height );
}

sub write_info {
  my $image_dir = shift || die "param missing";
  my $info_tmpl = shift || die "param missing";

  my $json = $info_tmpl->output;

  my $info_file = $image_dir->child('info.json');
  $info_file->spew($json);
}

sub make_thumbnail {
  my $max_image_fn = shift || die "param missing";
  my $image_dir    = shift || die "param missing";

  # file is written
  my $t = new Image::Thumbnail(
    size       => "150",
    create     => 1,
    module     => 'Image::Magick',
    input      => "$max_image_fn",
    outputpath => "$image_dir/thumbnail.jpg",
  );
}

sub write_htaccess {
  my $image_dir    = shift || die "param missing";
  my $rewrites_ref = shift || die "param missing";

  my $fh = $image_dir->child('.htaccess')->openw;
  print $fh "RewriteEngine On\n";
  foreach my $rewrite_ref ( @{$rewrites_ref} ) {
    foreach my $from ( keys %{$rewrite_ref} ) {
      my $to = $rewrite_ref->{$from};
      print $fh "RewriteRule \"full/$from/0/default.jpg\" \"$to\" [PT]\n";
    }
  }
  close($fh);
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

