#!/bin/env perl
# nbt, 2022-03-24
#
# create PHP include for previous/next function for film navigation

use strict;
use warnings;
use autodie;
use utf8::all;

use Path::Tiny;

my ( $set, $collection );
if ( scalar(@ARGV) == 2 ) {
  $set        = $ARGV[0];
  $collection = $ARGV[1];
} else {
  print "Usage: $0 {set} {collection}\n";
  exit 1;
}

my $filmdir  = path("/pm20/web/film/$set/$collection");
my @filmlist = $filmdir->children(qr/^([A-Z0-9_])+$/);

my $film_string;
foreach my $dir ( sort @filmlist ) {
  next unless $dir->is_dir;

  $film_string .= "','" . $dir->basename;
}
$film_string = substr( $film_string, 2 ) . "'";

my $output = <<'EOF';
<?php function prev_next_film ($film_id) {
$filmlist = 
[
@film_string@
];
$index = array_search($film_id, $filmlist);
if ($index != 0) { $prev = $filmlist[$index-1]; }
if ($index != array_slice($filmlist, -1)) { $next = $filmlist[$index+1]; }
return [ $prev, $next ];
}
EOF
$output =~ s/\@film_string\@/$film_string/ms;

my $output_path = path("/pm20/web/film/prev_next_film.${set}_$collection.inc");
$output_path->spew($output);

