#!/usr/bin/perl
# nbt, 22.2.2018

# Parse lists of PM20 image files

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use File::Basename;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

my $imagedata_root = path('../data/imagedata');

# iterate through all collections
foreach my $collection (qw/ co pe sh wa /) {

  my $lst   = $imagedata_root->child("${collection}_image.lst");
  my $files = $lst->slurp;

  my %img;
  foreach my $path ( sort split( /\n/, $files ) ) {

    # split the full path
    my @parts = split( /\//, $path );

    # assign elements
    my $holding_dir = join( '/', @parts[ 0 .. 3 ] );

    my $folder_number = $parts[5];

    my ( $relative_path, $doc_number, $basename );
    if ( $collection eq 'pe' or $collection eq 'co' ) {
      $relative_path = join( '/', @parts[ 4 .. 8 ] );
      $doc_number = $parts[7];

      # check formal correctness óf path
      if ( scalar(@parts) != 10 ) {
        warn "Irregular path: $collection/$relative_path, doc: $doc_number\n";
        next;
      }
      $basename = basename( $parts[9], '_A.JPG' );
    } else {

      # sh and wa filesystems are two more levels deep
      my $folder_number2 = $parts[7];
      $folder_number = "$folder_number,$folder_number2";
      $relative_path = join( '/', @parts[ 4 .. 10 ] );
      $doc_number    = $parts[9];
      if ( scalar(@parts) != 12 ) {
        warn "Irregular path: $collection/$relative_path, doc: $doc_number\n";
        next;
      }
      $basename = basename( $parts[11], '_A.JPG' );
    }

    # build data structure
    $img{$folder_number}{root} = $holding_dir;
    $img{$folder_number}{docs}{$doc_number}{rp} = $relative_path;
    push( @{ $img{$folder_number}{docs}{$doc_number}{pg} }, $basename );
  }

  # save as json
  my $out_file = $imagedata_root->child($collection . '_image.json');
  $out_file->spew( encode_json( \%img ) );
  print "$out_file saved\n";
}
