#!/bin/env perl
# nbt, 28.5.2018

# Create a PM20 folder PDF from METS und JPEGs
# to be called with the PDF url and a log file name for ipc communication

# based on https://github.com/myollie/img2pdf

# all created files and directories have to be world r/w in order to
# allow for manual cleanup

# data strcuture extracted from METS: list of articles
#   [ { id => $id, label => $label, jpg_list => \@jpg_list }, ... ]

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use File::Temp;
use HTTP::Tiny;
use IO::Handle;
use Path::Tiny;
use Readonly;
use XML::LibXML;

Readonly my $PDF_ROOT      => path('/pm20/cache/pdf');
Readonly my $METS_ROOT     => path('/pm20/web/folder');
Readonly my $METS_URL_ROOT => 'https://pm20.zbw.eu/folder/';
Readonly my $PDF_URL_ROOT  => 'https://pm20.zbw.eu/pdf/';

# read param
my $pdf_url  = $ARGV[0];
my $log_file = $ARGV[1] or die "usage: $0 pdf_url log\n";

# compute mets url
my $mets_file = compute_mets_file($pdf_url);
my $pdf_path  = compute_pdf_path($pdf_url);

open( my $log, ">$log_file" ) or die "cannot open $log_file: $!\n";
$log->autoflush;

# create pdf
print $log "Get list of documents and pages from METS file\n";
my $document_list_ref = parse_mets($mets_file);
if ( not $document_list_ref or $document_list_ref eq {} ) {
  print $log "Error: METS file $mets_file not found or empty\n";
  exit;
}
build_pdf( $document_list_ref, $pdf_path );

print $log "Done\n";
close($log);

####################

sub url_ok {
  my $pdf_url = shift or die "param missing\n";

  if ( $pdf_url =~ m/^PDF_URL_ROOT[a-z0-9\/\.]+$/ ) {
    return 1;
  } else {
    return 0;
  }
}

sub compute_mets_file {
  my $pdf_url = shift or die "param missing\n";

  ( my $dir = $pdf_url ) =~ s/^$PDF_URL_ROOT//;
  $dir =~ s;(.*)/[^/]+$;$1;;
  my $mets_file = $METS_ROOT->child($dir)->child('public.mets.en.xml');

  return $mets_file;
}

sub compute_pdf_path {
  my $pdf_url = shift or die "param missing\n";

  ( my $pdf_path = $pdf_url ) =~ s/^$PDF_URL_ROOT//;
  $pdf_path = $PDF_ROOT->child($pdf_path);

  return $pdf_path;
}

sub parse_mets {
  my $mets_url = shift or die "param missing\n";

  # Parse mets file
  my $dom = eval { XML::LibXML->load_xml( location => $mets_url ); };
  if ($@) {
    print "$mets_url xxx\n";
    return undef;
  }

  # get file urls
  my %file;
  for my $node (
    $dom->findnodes(
      '/mets:mets/mets:fileSec/mets:fileGrp[@USE="MAX"]/mets:file')
    )
  {
    my $id   = $node->getAttribute('ID');
    my $floc = ( $node->findnodes('mets:FLocat') )[0];
    $file{$id} = $floc->getAttribute('xlink:href');
  }

  # get pages
  my %page;
  for my $node (
    $dom->findnodes(
      '/mets:mets/mets:structMap[@TYPE="PHYSICAL"]/mets:div/mets:div')
    )
  {
    my $id = $node->getAttribute('ID');
    for my $fptr ( $node->findnodes('mets:fptr') ) {
      my $file_id = $fptr->getAttribute('FILEID');
      if ( exists $file{$file_id} ) {
        $page{$id} = $file{$file_id};
      }
    }
  }

  # get documents to pages links
  my %docpagelink;
  for my $node ( $dom->findnodes('/mets:mets/mets:structLink/mets:smLink') ) {
    my $document_id = $node->getAttribute('xlink:from');
    my $page_id     = $node->getAttribute('xlink:to');
    $docpagelink{$document_id} = []
      if ( not exists $docpagelink{$document_id} );

    push( @{ $docpagelink{$document_id} }, $page{$page_id} );
  }

  # get the documents
  my @document_list;
  for my $node (
    $dom->findnodes(
      '/mets:mets/mets:structMap[@TYPE="LOGICAL"]/mets:div/mets:div')
    )
  {
    my $id    = $node->getAttribute('ID');
    my %entry = (
      id    => $id,
      label => $node->getAttribute('LABEL'),
      pages => $docpagelink{$id},
    );
    push( @document_list, \%entry );
  }
  return \@document_list;
}

sub build_pdf {
  my $document_list_ref = shift or die "param missing\n";
  my $pdf_path          = shift or die "param missing\n";

  # message
  my $page_count;
  foreach my $doc ( @{$document_list_ref} ) {
    foreach my $page ( @{ $doc->{pages} } ) {
      $page_count++;
    }
  }
  print $log "Creating $pdf_path from $page_count files for ",
    scalar( @{$document_list_ref} ), " documents\n";

  my @files;
  foreach my $doc ( @{$document_list_ref} ) {

    # skip certan document type like business reports
    next if $doc->{label} =~ m/^Gesch/;

    foreach my $file ( @{ $doc->{pages} } ) {
      ## transform URL to file name
      $file = $METS_ROOT->child( path($file)->relative($METS_URL_ROOT) );
      push( @files, $file );
    }
  }

  # create directory
  path($pdf_path)->parent->mkpath( { chmod => 0777 } );

  # concat temp files to pdf
  print $log "\nConcatenate pages to pdf file ...\n";
  my @args = ( 'img2pdf', '-o', $pdf_path, @files );
  system(@args) == 0
    or print $log "Error: system @args failed: $?";
  $pdf_path->chmod(0777);
}
