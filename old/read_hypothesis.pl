#!/bin/env perl
# nbt, 3.7.2020

# read all pm20 annotations from hypothes.is

# APPROACH ABORTED - hypothesis cannot be used with HAN server
# due to ever-switching domain URLs

use strict;
use warnings;
use utf8;

##use Hypothesis::API;
use Data::Dumper;
use JSON;
use Path::Tiny;
use REST::Client;
use Readonly;

Readonly my %DOMAIN => (
  intern => {
    root_uri => 'https://pm20.zbw.eu',
  },
  intern_old => {
    root_uri => 'http://pm20intern.zbw.eu',
  },
  han => {
    root_uri => 'https://pm20intern-1zbw-1eu-1j2a48iu10381.elic.zbw.eu',
  },
  han_michael1 => {
    root_uri => 'https://pm20-1zbw-1eu-1j2a48iu103ce.elic.zbw.eu',
  },
);
Readonly my $ENDPOINT => 'https://query.wikidata.org/sparql';

# Query for lookup of signatures
Readonly my $QUERY_TEMPLATE => <<'EOF';
PREFIX wikibase: <http://wikiba.se/ontology#>
PREFIX bd: <http://www.bigdata.com/rdf#>
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>

SELECT ?item ?itemLabel WHERE {
  ?item ?property ?signature .
  SERVICE wikibase:label { bd:serviceParam wikibase:language ?language }
}
EOF

$Data::Dumper::Sortkeys = 1;

my $client = REST::Client->new();

# collect from all domains to
# gloabal list of image annotations
my %img;
my @all_raw;
foreach my $dom ( keys %DOMAIN ) {

  # retrieves all entries for a certain domain
  my $domain  = $DOMAIN{$dom}{root_uri};
  my $api_url = "https://hypothes.is/api/search?wildcard_uri=$domain/*";
  $client->GET($api_url);
  my $res = decode_json( $client->responseContent() );
  push( @all_raw, @{ $res->{rows} } );

  foreach my $entry ( @{ $res->{rows} } ) {
    my $uri = $entry->{uri};

    # remove domain
    ( my $key = $uri ) =~ s/^$domain\/film//;

    # add to global list
    push( @{ $img{$key}{entries} }, $entry );
  }
}
path('/tmp/hypothesis.out')->spew( Dumper \@all_raw );

# evaluate collected annotations
my ( %lookup_subject, %lookup_geo, %lookup_ware );
foreach my $key ( sort keys %img ) {
  next unless $key =~ m;((?:h|k)(?:1|2))/(co|sh|wa)/(.*?)/(.*);;
  $img{$key}{parsed}{holding}    = $1;
  $img{$key}{parsed}{collection} = $2;
  $img{$key}{parsed}{film}       = $3;
  $img{$key}{parsed}{image}      = $4;

  # TODO deal wth multiple entries per key
  my $entry = $img{$key}{entries}[0];
  my $text  = $entry->{text};
  chomp $text;

  $img{$key}{parsed}{text} = $text;
  print
"$img{$key}{parsed}{holding}\t$img{$key}{parsed}{collection}\t$img{$key}{parsed}{film}\t$img{$key}{parsed}{image}\t$text\n";

  # parse text
  if ( $img{$key}{parsed}{collection} eq 'sh' ) {
    if ( $text =~
      m/(\$m\s+)?(\$s\s+)?([A-H][0-9]+(?:[a-z]?))\s+([a-q](?:[0-9]+)?)/ )
    {
      $img{$key}{parsed}{geo_code}     = $3;
      $lookup_geo{$3}                  = undef;
      $img{$key}{parsed}{subject_code} = $4;
      $lookup_subject{$4}              = undef;
    }
  }
}

# look up codes
foreach my $code ( keys %lookup_subject ) {

  # build query
  my $query = $QUERY_TEMPLATE;
  $query =~ s/\?property/wdt:P8484/;
  $query =~ s/\?signature/"$code"/;
  $query =~ s/\?language/"de"/;

  # execute the query
  $client->POST(
    $ENDPOINT,
    $query,
    {
      'Content-type' => 'application/sparql-query',
      'Accept'       => 'application/sparql-results+json'
    }
  );
  my $result_data;
  eval {
    my $json = $client->responseContent();
    $result_data = decode_json($json);
  };
  if ($@) {
    die "Error parsing response: ", $client->responseContent(), "\n";
  }
  print Dumper $result_data;
  exit;
}

# output
print "\n";
foreach my $key ( sort keys %img ) {
  my $parsed = $img{$key}{parsed};
  next unless $parsed->{collection} eq 'sh' and $parsed->{geo_code};
  print Dumper $parsed;
  ##print "$parsed->{holding}\t$parsed->{collection}\t$parsed->{film}\t$parsed->{image}\t$parsed->{geo_code}\t$parsed->{subject_code}\t($parsed->{text})\n";
}

print Dumper \%lookup_geo, \%lookup_subject;
