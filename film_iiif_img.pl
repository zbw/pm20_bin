#!/bin/perl
# nbt, 9.4.2022

# traverses film roots, creates (for each page)
# - info.json
# - .htaccess
# - TODO thumbnail

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use HTML::Entities;
use HTML::Template;
use Image::Size;
use Image::Thumbnail;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $PM20_ROOT_URI => 'https://pm20.zbw.eu/film/';
Readonly my $IIIF_ROOT_URI => 'https://pm20.zbw.eu/iiif/film/';
Readonly my $IIIF_ROOT     => path('/pm20/iiif/film/');
Readonly my $FILM_ROOT     => path('/pm20/film');

Readonly my $SUBSET_QR => qr/^[hk][12]_(co|sh|wa)$/;
Readonly my $FILM_QR   => qr/^S\d{4}H$/;

my $info_tmpl =
  HTML::Template->new( filename => 'html_tmpl/film.info.json.tmpl', );

my ( $imagedata_file, $imagesize_file, $imagedata_ref, $imagesize_ref, );

# check arguments
if ( scalar(@ARGV) == 2 ) {
  if ( $ARGV[0] =~ m/$SUBSET_QR/ and $ARGV[1] =~ m/$FILM_QR/ ) {
    my $subset = $ARGV[0];
    my $film   = $ARGV[1];
    mk_film( $subset, $film );
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
## TODO
}

sub mk_film {
  my $subset = shift || die "param missing";
  my $film   = shift || die "param missing";

  my ( $set, $collection ) = split( /_/, $subset );

  # get directory
  my $filmdir  = $FILM_ROOT->child($set)->child($collection)->child($film);
  my @pagelist = $filmdir->children(qr/\.jpg\z/);
  foreach my $image_fn (@pagelist) {
    my $image_id  = path($image_fn)->basename('.jpg');
    my $image_uri = get_image_uri( $subset, $film, $image_id );
    my $real_url  = $image_uri . '.jpg';
    my $image_dir = get_image_dir( $subset, $film, $image_id );

    my @rewrites;

    # create iiif info
    my %info_tmpl_var = ( image_uri => $image_uri, );
    my ( $width, $height ) = get_dim($image_fn);
    $info_tmpl_var{"width"}  = $width;
    $info_tmpl_var{"height"} = $height;

    # add rewrite for .htaccess
    push( @rewrites, { "max"            => $real_url } );
    push( @rewrites, { "$width,$height" => $real_url } );
    push( @rewrites, { "$width,"        => $real_url } );
    $info_tmpl->param( \%info_tmpl_var );
    write_info( $image_dir, $info_tmpl );

    # make thumbnail
    make_thumbnail( $image_fn, $image_dir )
      unless -f "$image_dir/thumbnail.jpg";

    # htaccess file
    write_htaccess( $image_dir, \@rewrites );
  }
}

sub get_image_dir {
  my $subset   = shift || die "param missing";
  my $film     = shift || die "param missing";
  my $image_id = shift || die "param missing";

  $subset =~ s:_:/:;
  my $image_dir =
    $IIIF_ROOT->child($subset)->child($film)->child($image_id);
  $image_dir->mkpath;
  return $image_dir;
}

sub get_image_uri {
  my $subset   = shift || die "param missing";
  my $film     = shift || die "param missing";
  my $image_id = shift || die "param missing";

  $subset =~ s:_:/:;
  return "$PM20_ROOT_URI$subset/${film}/${image_id}";
}

sub get_dim {
  my $image_fn = shift || die "param missing";

  my ( $w, $h ) = imgsize("$image_fn");
  return ( $w, $h );
}

sub write_info {
  my $image_dir = shift || die "param missing";
  my $info_tmpl = shift || die "param missing";

  my $json = $info_tmpl->output;

  my $info_file = $image_dir->child('info.json');
  $info_file->spew($json);
}

sub make_thumbnail {
  my $image_fn  = shift || die "param missing";
  my $image_dir = shift || die "param missing";

  # file is written
  my $t = new Image::Thumbnail(
    size       => "150",
    create     => 1,
    module     => 'Image::Magick',
    input      => "$image_fn",
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
      print $fh "RewriteRule \"full/$from/0/default.jpg\" \"$to\" [R=303,L]\n";
    }
  }
  close($fh);
}

sub usage {
  print "Usage: $0 {subset} {film-id} | ALL\n";
  exit 1;
}

