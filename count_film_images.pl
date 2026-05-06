#!/usr/bin/perl
# nbt, 2019-02-14

# Count film images and aggregate various numbers
# - grand total
# - images on film only
# - images from films starting with a certain notation

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
##use Data::Dumper::Names;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

my $film_root      = path('/pm20/film');
my $filmdata_root  = path('../data/filmdata');
my $img_count_file = $filmdata_root->child('img_count.json');
my $missing_file   = $filmdata_root->child('missing.json');

# regex for counting images with start_sig
my $special_qr = qr/(B42|B42a)/;    # Indien
##my $special_qr = qr/E86 /;    # Argentinien

my %img_count;
my %count;
my %missing;

my %conf = (
  h1 => [qw/ co sh wa /],
  h2 => [qw/ co sh wa /],
  k1 => [qw/ sh /],
  k2 => [qw/ sh /],
);

foreach my $set ( sort keys %conf ) {
  foreach my $collection ( @{ $conf{$set} } ) {
    print "$set $collection\n";

    my $special_count = 0;

    $count{total}{$set}{$collection}     = 0;
    $count{film_only}{$set}{$collection} = 0;

    # findbuch input
    my $findbuch_file =
      $filmdata_root->child( $set . '_' . $collection . '.json' );
    my $findbuch_data = decode_json( $findbuch_file->slurp_raw )
      || die "not found";

    my $last_film_id = 0;
    foreach my $entry ( @{$findbuch_data} ) {
      ##print Dumper $entry; exit;
      my $film_id = $entry->{film_id} || 'dummy';

      # for film ids from Kiel
      if ( $film_id =~ m/^[0-9]+$/ ) {
        $film_id = sprintf( "%04d", $film_id );
      }
      next if ( $film_id eq $last_film_id );
      $last_film_id = $film_id;

      my $filmpath =
        $film_root->child($set)->child($collection)->child($film_id);
      my $img_count = 0;
      if ( -d $filmpath ) {
        $img_count = scalar( $filmpath->children(qr/\.jpg/) );
      } elsif ( $entry->{online} ) {

        # skip, because images are in PM20
      } else {
        ##push(@{$missing{$set}}, $entry->{film_id});
        push( @{ $missing{$set} }, $filmpath->stringify );
      }
      $img_count{$filmpath} = $img_count;

      # Counts films with start_sig (Hamburg only)
      if ( $entry->{provenance} eq 'h' ) {
        if ( $entry->{start_sig} =~ m/$special_qr/ ) {
          $special_count = $special_count + $img_count;
        }
      }
      $count{total}{$set}{$collection} += $img_count;
      if ( !$entry->{online} ) {
        $count{film_only}{$set}{$collection} += $img_count;
      }
    }

    print "    Anzahl (Doppel-)Seiten aus $set/"
      . $collection
      . " zum Bereich $special_qr: $special_count\n";
  }
}

# save image counts
$img_count_file->spew( encode_json( \%img_count ) );
$missing_file->spew( encode_json( \%missing ) );

# statistics
my %grand_total;
foreach my $type ( keys %count ) {
  foreach my $set ( keys %{ $count{$type} } ) {
    foreach my $collection ( keys %{ $count{$type}{$set} } ) {
      $grand_total{$type} += $count{$type}{$set}{$collection};
    }
  }
}
print Dumper \%count, \%grand_total;
my $stats_file = $filmdata_root->child('stats.dat');
$stats_file->spew( Dumper \%count, \%grand_total );

