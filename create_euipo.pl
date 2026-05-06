#!/bin/env perl
# nbt, 26.6.2023

# create xml files from filmdata/*.json for bulk upload to EUIPO portal

# TODO validate output against records.xsd

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Path::Tiny;

my $filmdata_root = path('../data/filmdata');

my $type = 'INDIVIDUAL';

my %page = (
  h => {
    name      => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    desc_tmpl =>
'des ehemaligen Hamburgischen Welt-Wirtschafts-Archivs (HWWA). Themenbezogene Mappen mit Ausschnitten aus über 1500 Zeitungen und Zeitschriften des In- und Auslands (weltweit), Firmenschriften u.ä. aus der Zeit $covers$. Archiviert als digitalisierter Mikrofilm, hier:',
    list => {
      'h1_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_wa' => {
        title  => 'Warenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1946',
      },
      'h2_wa' => {
        title  => 'Warenarchiv',
        covers => 'von ca. 1947 bis ca. 1960',
      },
    },
  },
  k => {
    name => 'Wirtschaftsarchiv des Instituts für Weltwirtschaft (WiA)',
    list => {
      k1_sh => {
        title => 'Sacharchiv',
      },
      k2_sh => {
        title => 'Sacharchiv',
      },
    },
  },
);

my $header = << 'END_HEADER';
<?xml version="1.0"?>
<tns:collection xmlns:tns="http://euipo.europa.eu/out-of-commerce/schemas/qdc/records"
           xmlns:xml="http://www.w3.org/XML/1998/namespace"
           xmlns:dcterms="http://purl.org/dc/terms/"
		   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
END_HEADER
my $footer = << 'END_FOOTER';
</tns:collection>
END_FOOTER

my $film_cnt = 0;
foreach my $prov (qw/ h /) {

  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {

    my $out_txt;

    my $title = $page{$prov}{list}{$page_name}{title};
    my $coll  = substr( $page_name, 3, 2 );
    my $set   = substr( $page_name, 0, 2 );
    my $desc_stub =
      "$page{$prov}{list}{$page_name}{title} $page{$prov}{desc_tmpl}";
    $desc_stub =~ s/\$covers\$/$page{$prov}{list}{$page_name}{covers}/;

    # read json input
    my @film_sections = @{
      decode_json(
        $filmdata_root->child( $page_name . '.expanded.json' )->slurp
      )
    };

    # iterate through the list of film sections (from the excel file)
    my $i = 0;
    foreach my $film_section (@film_sections) {
      my $film_id = $film_section->{film_id};

      my $id   = "film/$set/$coll/$film_id";
      my $from = "$film_section->{start_sig}";
      my $to   = "$film_section->{end_sig}";

      # skip film if it has no metadata
      next unless $from and $from ne 'x';

      my $description = "$desc_stub $film_id, von: \"$from\" bis: \"$to\"";
      $description = cleanup($description);

      # if the film is already online as part of folders, add url
      my $folder_url_elem = '';
      if ( $film_section->{online} ) {
        $folder_url_elem =
          "<tns:webPage>https://pm20.zbw.eu/folder/$coll</tns:webPage>";
      }

      my $work_record = << "END_RECORD";
<tns:individualWorkRecord>
  <dcterms:identifier>$id</dcterms:identifier>
  <dcterms:type xsi:type="dcterms:DCMIType">Text</dcterms:type>
  <dcterms:description>$description</dcterms:description>
  <tns:useOfWork><tns:legalBasis>EXCEPTION_OR_LIMITATION</tns:legalBasis><tns:country>DE</tns:country><tns:additionalInformation>§61d UrhG; §1 Abs. 2 Nr. 4 NvWV</tns:additionalInformation>$folder_url_elem</tns:useOfWork>
</tns:individualWorkRecord>
END_RECORD
      $out_txt .= $work_record;

      $i++;
    }

    # write output to public
    my $out = $filmdata_root->child( 'euipo.' . $page_name . '.xml' );
    $out->spew_utf8( $header . $out_txt . $footer );

    print "$page_name: $i films written\n";
    $film_cnt += $i;
  }
}
print "total: $film_cnt\n";

########

sub cleanup {
  my $text = shift;

  # squeeze multiple blanks
  $text =~ s/\s+/ /g;

  # mask xml special chars
  $text =~ s/&/&amp;/g;
  $text =~ s/\</&lt;/g;
  $text =~ s/\>/&gt;/g;

  return $text;
}
