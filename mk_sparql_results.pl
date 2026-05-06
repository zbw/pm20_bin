#!/usr/bin/perl
# nbt, 16.7.2020
# based on /opt/thes/bin/generate_change_reports.pl

# Create SPARQL result files for reports

# Requires an SPARQL endpoint with all data available
# (+ plus the queries taking these as default).

# Query parsing and variable replacement is based on whitespace recognition,
# minimal:
#   values ( ... ) { ( ... ) }
# optional select extension (TBD):
#   select ... where

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Path::Tiny;
use Readonly;
use REST::Client;
##use String::Util qw/unquote/;
##use URI::file;
use URL::Encode qw/url_encode/;
use YAML;

Readonly my $DEFINITIONS_FILE => path('sparql_results.yaml');

my $definition_ref = YAML::LoadFile($DEFINITIONS_FILE);
my @languages      = qw/ en de /;

my $endpoint = "https://zbw.eu/beta/sparql/pm20/query";

# Main loop over all results of a dataset
foreach my $definition ( sort keys %{$definition_ref} ) {
  foreach my $lang (@languages) {
    get_result( $lang, $definition );
  }
}

#######################

sub get_result {
  my $lang       = shift or die "param missing";
  my $definition = shift or die "param missing";

  ##print "$definition $lang\n";

  my $resultdef_ref = $definition_ref->{$definition};

  # read query from file (by command line argument)
  my $query = path( $$resultdef_ref{query_file} )->slurp
    or die "Can't read $!";

  # replacements
  my %insert_value = (
    '?language'   => "\"$lang\"",
  );

  # parse VALUES clause
  my ( $variables_ref, $value_ref ) = parse_values($query);

  # replace values
  foreach my $variable ( keys %$value_ref ) {
    if ( defined( $insert_value{$variable} ) ) {
      $$value_ref{$variable} = $insert_value{$variable};
    }
  }
  $query = insert_modified_values( $query, $variables_ref, $value_ref );

  # prepare query
  my $query_encoded = "query=" . url_encode($query);

  # execute query
  my $client = REST::Client->new();
  $client->GET( "$endpoint?$query_encoded",
    { Accept => 'application/sparql-results+json' } );
  if ( $client->responseCode ne '200' ) {
    warn "Could not execute query for $definition: ", $client->responseCode, "\n";
    return;
  }
  my $result_data = $client->responseContent();

  # write output with a created file name
  write_output( $lang, $resultdef_ref, $result_data );
}

sub parse_values {
  my $query = shift or die "param missing";

  $query =~ m/ values \s+\(\s+ (.*?) \s+\)\s+\{ \s+\(\s+ (.*?) \s+\)\s+\} /ixms;

  my @variables  = split( /\s+/, $1 );
  my @values_tmp = split( /\s+/, $2 );
  my %value;
  for ( my $i = 0 ; $i < scalar(@variables) ; $i++ ) {
    $value{ $variables[$i] } = $values_tmp[$i];
  }
  return \@variables, \%value;
}

sub insert_modified_values {
  my $query         = shift or die "param missing";
  my $variables_ref = shift or die "param missing";
  my $value_ref     = shift or die "param missing";

  # create new values clause
  my @values;
  foreach my $variable (@$variables_ref) {
    push( @values, $$value_ref{$variable} );
  }
  my $values_clause =
      ' values ( '
    . join( ' ', @$variables_ref )
    . " ) {\n    ( "
    . join( ' ', @values )
    . " )\n  }";

  # insert into query
  $query =~ s/\svalues .*? \s+\)\s+\}/$values_clause/ixms;

  return $query;
}

sub write_output {
  my $lang          = shift or die "param missing";
  my $resultdef_ref = shift or die "param missing";
  my $result_data   = shift or die "param missing";

  # start with the last part of the query name
  $resultdef_ref->{query_file} =~ m|.*/(.+)\.rq$|;
  my $name = $1;

  my $fn = $resultdef_ref->{output_dir} . "/$name.$lang.json";

  path($fn)->spew($result_data);
}
