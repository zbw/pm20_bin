#!/bin/perl
# nbt, 22.2.2018

# Use data from PM20 image files to check .htaccess and parse file names.
# (.txt files are ignored) Produces docdata json file and beacon files as well
# as rdf/doc_count.ttl with number of free and total images, plus reportCount
# for the latter.

# Run after recreate_document_locks.pl!

# TODO
# - extended filename parsing
# - read meta.yaml files
# - check authors and publications

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Log::Log4perl::Level;
use Path::Tiny;
use Readonly;
use ZBW::Logutil;

# logging
my $log = ZBW::Logutil->get_logger('./log_conf/parse_docdata.conf');
$log->level($INFO);

$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_ROOT    => path('../folder');
Readonly my $IMAGEDATA_ROOT => path('../data/imagedata');
Readonly my $DOCDATA_ROOT   => path('../data/docdata');
Readonly my $DOC_COUNT_FILE => path('../data/rdf/doc_count.ttl');
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;
Readonly my $BEACON_ROOT    => path('../data/beacon');
Readonly my $BEACON_HEADER =>
  "#FORMAT: BEACON\n#PREFIX: https://pm20.zbw.eu/folder/\n\n";

# counter for total, free and report documents per folder
my %count;

$log->info('Start run');
foreach my $collection (@COLLECTIONS) {

  $log->info("Starting $collection");

  my %coll;
  $coll{cnt_doc_free} = 0;

  # read image data file
  my $img_ref =
    decode_json(
    $IMAGEDATA_ROOT->child("${collection}_image.json")->slurp_raw );

  # read doc attribute data file
  my $docattr_ref =
    decode_json(
    $DOCDATA_ROOT->child("${collection}_docattr.json")->slurp_raw );

  my %docdata;
  foreach my $folder ( sort keys %{$img_ref} ) {
    my $root = $FOLDER_ROOT->child($collection);
    $coll{cnt_folder}++;

    my %docs = %{ $img_ref->{$folder}{docs} };
    foreach my $doc ( sort keys %docs ) {

      $coll{cnt_doc_total}++;

      # check for document diretory
      my $doc_dir = path( $root . '/' . $docs{$doc}{rp} )->parent;
      if ( not -d $doc_dir ) {
        $log->warn("  directory $doc_dir is missing");
        $coll{cnt_doc_skipped}++;
        next;
      }

      # check if locked
      if ( is_free($doc_dir) ) {
        $docdata{$folder}{free}{$doc} = 1;
        $coll{cnt_doc_free}++;
      } else {
        $coll{cnt_doc_hidden}++;
      }

      # document information from .txt file
      my $txt_field_ref = parse_txt_file( $folder, $doc, $doc_dir );
      if ( scalar( %{$txt_field_ref} ) gt 0 ) {
        $docdata{$folder}{info}{$doc}{_txt} = $txt_field_ref;
      } else {
        $coll{cnt_bad_txt}++;
      }

      # add data from doc attribute
      $docdata{$folder}{info}{$doc}{_att} = $docattr_ref->{$folder}{$doc};

      # consolidated document information
      my $field_ref =
        consolidate_info( $folder, $doc, $docdata{$folder}{info}{$doc},
        $docs{$doc} );
      $docdata{$folder}{info}{$doc}{con} = $field_ref;

      ##if ($docdata{$folder}{info}{$doc}{_txt}{TIT}) {
      ##  print Dumper $docdata{$folder}{info}{$doc};
      ##}
    }

    # collect counter data
    $count{"$collection/$folder"} = {
      freeDoc  => scalar( keys %{ $docdata{$folder}{free} } ),
      totalDoc => scalar( keys %{ $docdata{$folder}{info} } ),
    };

    if ( $collection eq 'co' ) {
      my $report_count = 0;
      foreach my $doc ( keys %{ $docdata{$folder}{info} } ) {
        if (  $docdata{$folder}{info}{$doc}{con}{type}
          and $docdata{$folder}{info}{$doc}{con}{type} eq 'G' )
        {
          $report_count++;
        }
      }
      if ($report_count) {
        $count{"$collection/$folder"}{report} = $report_count;
      }
    }
  }

  # save data for collection
  $DOCDATA_ROOT->child("${collection}_docdata.json")
    ->spew( encode_json( \%docdata ) );

  my ( %beacon_total, %beacon_free );
  foreach my $folder ( keys %docdata ) {
    $beacon_free{"$collection/$folder"} =
      scalar( keys %{ $docdata{$folder}{free} } );
    $beacon_total{"$collection/$folder"} =
      scalar( keys %{ $docdata{$folder}{info} } );
  }

  # write beacon files
  foreach my $beacon_type (qw/ beacon_free beacon_total/) {
    my $fh = $BEACON_ROOT->child("${collection}_$beacon_type.txt")->openw;
    print $fh $BEACON_HEADER;
    my %beacon = eval( '%' . "$beacon_type" );
    foreach my $fid ( sort keys %beacon ) {
      print $fh "$fid | $beacon{$fid}\n";
    }
    close($fh);
  }

  # save stats data
  $DOCDATA_ROOT->child("${collection}_stats.json")
    ->spew( encode_json( \%coll ) );
}
write_doc_count( \%count );
$log->info('End run');

################

sub is_free {
  my $doc_dir = shift or die "param missing";

  my $free_status = path("$doc_dir/.htaccess")->is_file ? 0 : 1;

  return $free_status;
}

sub parse_filename {
  my $fn        = shift or die "param missing";
  my $field_ref = shift or die "param missing";

  # subtopic id
  $field_ref->{subtopic} = substr( $fn, 13, 5 );

  # provenance code
  $field_ref->{prov} = substr( $fn, 42, 1 );

  # type code
  $field_ref->{type} = substr( $fn, 43, 1 );
}

sub parse_txt_file {
  my $folder  = shift or die "param missing";
  my $doc     = shift or die "param missing";
  my $doc_dir = shift or die "param missing";

  my %txt_field;
  my @lines;
  my @txt_files = $doc_dir->children(qr/[AFPSW].*?\.txt$/);
  if ( scalar(@txt_files) lt 1 ) {
    ##$log->warn("  .txt file missing in $doc_dir");
  } elsif ( scalar(@txt_files) > 1 ) {
    ##$log->warn("  multiple .txt files in $doc_dir");
  } else {

    # parse the file
    @lines = $txt_files[0]->lines_raw;

    foreach my $line (@lines) {
      my ( $fieldname, $rest ) = split( /\t/, $line );
      if ( not $rest ) {
        $log->warn("  empty field $fieldname for folder $folder, doc $doc");
        next;
      }

      # remove line endings
      $rest =~ s/\r\n//g;

      # remove prepended field marks
      $rest =~ s/^[vtib]=(.*)$/$1/;

      $txt_field{$fieldname} = $rest;
    }
  }
  return \%txt_field;
}

sub consolidate_info {
  my $folder      = shift or die "param missing";
  my $doc         = shift or die "param missing";
  my $docdata_ref = shift or die "param missing";
  my $docs_ref    = shift or die "param missing";

  # priority document information
  my %field;

  # add  infos from file name of first page
  parse_filename( $docs_ref->{pg}->[0], \%field );

  # mapping of field names from old sources
  my %fieldname = (
    date => {
      _att => 'd',
      _txt => 'DATE',
    },
    title => {
      _att => 't',
      _txt => 'TITLE',
    },
    pub => {
      _att => 'q',
      _txt => 'NQUE',
    },
    author => {
      _att => 'v',
      _txt => 'AUT',
    },
  );

  # priority is
  # - meta.yaml
  # - doc_attributes
  # - txt file

  # TODO set pub and author from IDs, if given
  foreach my $name ( keys %fieldname ) {
    $field{$name} =
         $docdata_ref->{_meta}{$name}
      || $docdata_ref->{_att}{ $fieldname{$name}{_att} }
      || $docdata_ref->{_txt}{ $fieldname{$name}{_txt} };
  }

  # number of pages - only source is file system scan
  $field{pages} = scalar( @{ $docs_ref->{pg} } );

  return \%field;
}

sub write_doc_count {
  my $count_ref = shift or die "param missing";

  my @lines;
  foreach my $folder ( keys %{$count_ref} ) {
    my $uri = "<https://pm20.zbw.eu/folder/$folder>";
    foreach my $type (qw/ freeDoc totalDoc report /) {
      next unless $count_ref->{$folder}{$type};
      my $property = "<http://zbw.eu/namespaces/zbw-extensions/${type}Count>";
      push( @lines, "$uri $property $count_ref->{$folder}{$type} ." );
    }
  }
  $DOC_COUNT_FILE->spew( join( "\n", sort @lines ) );
}
