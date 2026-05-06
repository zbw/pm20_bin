#!/bin/env perl
# nbt, 2021-10-26

# Create the folder tree for the web directory, and
# create symlinks for actual document directories

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

Readonly my $FOLDER_DOCROOT => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;

my ( $imagedata_file, $imagedata_ref );

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

  foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
    mk_folder( $collection, $folder_nk );
  }
}

sub mk_folder {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";

  my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

  # check if folder dir exists
  my $rel_path  = $folder->get_folder_hashed_path();
  my $full_path = $FOLDER_DOCROOT->child($rel_path);
  if ( not -d $full_path ) {
    die "$full_path does not exist\n";
  }

  # open files if necessary
  # (check with arbitrary entry)
  if ( not defined $imagedata_ref ) {
    load_files($collection);
  }

  # create folder dir (including hashed level)
  my $folder_dir = $FOLDER_WEBROOT->child($rel_path);
  $folder_dir->mkpath;

  # for all documents
  my $doc_ref = $imagedata_ref->{$folder_nk}{docs};
  foreach my $doc_id ( sort keys %{$doc_ref} ) {
    my $doc_new_path = $folder_dir->child($doc_id);

    # change structure of new path
    # - drop hash level for documents
    my $doc_stub  = substr( $doc_id, 0, 3 ) . 'xx';
    my $phys_path = $full_path->child($doc_stub)->child($doc_id);

    # remove exsting symlink
    if ( $doc_new_path->exists ) {
      unlink $doc_new_path
        or die "Cannot delete existing symlink $doc_new_path: $!\n";
    }
    symlink( $phys_path, $doc_new_path )
      or die "Cannot create $doc_new_path (from $phys_path): $!\n";
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp_raw );
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

