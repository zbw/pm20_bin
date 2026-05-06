#!/bin/env perl
# nbt, 28.7.2020

# Copies sparql report files from ite-srv24 (with the
# most current query files) to Intares server

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Net::SCP;
use Readonly;
use YAML;

Readonly my $DEFINITIONS_FILE => 'sparql_results.yaml';
Readonly my $TARGET_ROOT      => 'nbt@pm20:/disc1/pm20/data/';

my %definition = %{ YAML::LoadFile($DEFINITIONS_FILE) };
my @languages  = qw/ en de /;
my $scp        = Net::SCP->new();

# Main loop over all results of a dataset
foreach my $def ( keys %definition ) {
  foreach my $lang (@languages) {

    # extract source and target names from YAML config file
    $definition{$def}{query_file} =~ m/.*\/(.*?)\.rq$/;
    my $fn = "$definition{$def}{output_dir}/$1.$lang.json";
    $definition{$def}{output_dir} =~ m/.*\/(.*?)$/;
    my $target = "${TARGET_ROOT}$1/";

    # copy via scp
    $scp->scp( $fn, $target ) or die $scp->{errstr};
  }
}
