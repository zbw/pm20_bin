#!/usr/bin/perl
# nbt, 10.5.2019

# Get sizes lists of PM20 image files

# Takes about 8 hours!!

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Devel::Size qw/ total_size /;
use Image::Size;
use JSON;
use Path::Tiny;
use Storable;

$Data::Dumper::Sortkeys = 1;

my $imagedata_root = path('/pm20/data/imagedata');

# iterate through all collections
foreach my $collection (qw/ co pe sh wa /) {

  my $lst      = $imagedata_root->child("${collection}_image.lst");
  my $file_lst = $lst->slurp;
  my @files    = sort split( /\n/, $file_lst );

  my %img;
  my $i = 1;
  foreach my $path (@files) {

    ##print "$path\n";

    # iterate over all resolutions
    foreach my $res (qw/ A B C /) {
      ( my $file = $path ) =~ s/_A\.JPG/_$res\.JPG/;
      my ( $w, $h ) = imgsize($file);
      $img{$path}{$res}{w} = $w;
      $img{$path}{$res}{h} = $h;
    }

    # debug and progress info
    if ( $i % 1000 == 0 ) {
      print 'Mem ', total_size( \%img ), " for $i images\n";
    }
    $i++;
  }

  # store as binary for debugging
  ##my $tmp_file = $imagedata_root->child( $collection . '_size.stored' );
  ##store \%img, $tmp_file;
  ##print "$tmp_file stored\n";

  # save as json
  my $out_fn = $collection . '_size.json';
  $imagedata_root->child($out_fn)->spew( encode_json( \%img ) );
  print "$out_fn saved\n\n";
}
