#!/bin/env perl
# nbt, 2022-01-24

# creates html fragments with image links for filmviewer

# TODO extend to proper tags in English
# perhaps link to primary group or (company) folder

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Vocab;

$Data::Dumper::Sortkeys = 1;

# TODO fix dev dir
Readonly my $FILM_ROOT     => path('/pm20/web/film');
##Readonly my $FILM_ROOT     => path('/tmp/film');
Readonly my $FILMDATA_ROOT => path('/pm20/data/filmdata');
Readonly my @COLLECTIONS   => qw/ co sh wa /;
Readonly my @LANGUAGES     => qw/ en de /;
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co h1_wa h2_co h2_sh h2_wa /;
## films in film lists, but not on disk
Readonly my @MISSING_FILMS =>
  qw/ S0005H S0010H S0371H S0843H S1009H S1010H S9393 S9398 /;

my ( $provenance, $filming, $collection, $set, $subset, $subset_root );
if ( $ARGV[0] and $ARGV[0] =~ m/(h|k)(1|2)_(co|sh|wa)/ ) {
  $provenance = $1;
  $filming    = $2;
  $collection = $3;
  $set        = "$provenance$filming";
  $subset     = "${set}_$collection";
  if ( not grep( /^$subset$/, @VALID_SUBSETS ) ) {
    usage();
    exit 1;
  }
  $subset_root = $FILM_ROOT->child($set)->child($collection);
} else {
  usage();
  exit 1;
}

print "\nsubset $subset\n";

my %vocab;
$vocab{geo}     = ZBW::PM20x::Vocab->new('geo');
$vocab{subject} = ZBW::PM20x::Vocab->new('subject');
$vocab{ware}    = ZBW::PM20x::Vocab->new('ware');

# all start positions of sections, from zotero and film lists
my %position;

my $olditem_ref = {};
my @films       = ZBW::PM20x::Film->films($subset);

foreach my $film (@films) {

  # TODO fix dev restriction
  ##next
  ##  unless ( $film->name eq 'W2001H'
  ##  or $film->name eq 'S2806H'
  ##  or $film->name eq 'F2008H' );

  my $film_name = $film->name;
  my $film_dir  = $subset_root->child($film_name);

  # skip directories in test environment
  if ( -d "$film_dir" ) {
    print "  $film_name\n";
  } else {
    print "  $film_name missing\n";
    next;
  }

  # read file info from disk
  my %image;
  my @files    = $film_dir->children(qr/\.jpg\z/);
  foreach my $file (@files) {
    my $img_nr = $file->basename('.jpg');
    $img_nr =~ s/[SAFW]\d{4}(\d{4})[HK]/$1/;
    $image{$img_nr} =
      $file->relative('/pm20/web')->parent->child($img_nr)->absolute('/');
  }
  $image{'0000'} = undef;
  $image{'9999'} = undef;

  my %position;
  foreach my $section ( $film->sections ) {
    my $section_uri = $section->{'@id'};
    ( my $img_nr = $section_uri ) =~ s;^(?:.+)/$film_name/(\d{4})(?:/.+)?;$1;;

    # TODO workaround for first image from filmlist
    if ( $section_uri =~ m/$film_name\/1$/ ) {
      $img_nr = '0001';
    }
    $position{$img_nr} = $section;
  }

  # merge
  my $current_olditem_ref;
  foreach my $lang (@LANGUAGES) {
    $current_olditem_ref = $olditem_ref;
    my @links;
    foreach my $img_nr ( sort keys %image ) {
      if ( defined $position{$img_nr} ) {

        my %item = %{ $position{$img_nr} };
        ## skip items without identified geo (should not occur)
        ## often occurs within wa - TODO check
        ## next if not defined $item{geo};

        # TODO replace dumbed-down version of item tags (only based on title,
        # with optional geo enhancement)
        push( @links,
          '<br />',
          get_item_tag_dumb( $lang, $img_nr, \%item, $current_olditem_ref ) );

        $current_olditem_ref = \%item;
      }
      if ( defined $image{$img_nr} ) {
        push( @links,
          "<a id='img_$img_nr' href='$image{$img_nr}'>$img_nr</a> &#160;" );
      }
    }

    # save links
    $film_dir->child("links.$lang.html.frag")
      ->spew_utf8( join( "\n", @links ) );
  }
  $olditem_ref = $current_olditem_ref;
}

# count films which were not processed via Zotero
my $cnt_open = 0;

####################

sub get_item_tag_dumb {
  my $lang        = shift or die "param missing";
  my $img_nr      = shift or die "param missing";
  my $item_ref    = shift or die "param missing";
  my $olditem_ref = shift or die "param missing";

  my %item = %{$item_ref};

  # TODO extend film dataset to collection
  my $collection;
  if ( not $item{collection} ) {
    ( $collection = $item{'@id'} ) =~ s;^.+?/film/h[12]/(co|sh|wa)/.+$;$1;;
  }

  # TODO replace q&d signature lookup with proper geo in item
  my $geo_label;
  if ( $collection eq 'co' or $collection eq 'sh' ) {
    if ( $item{notation} ) {
      ( my $geo_sig ) = split( / /, $item{notation} );
      my $geo_id = $vocab{geo}->lookup_signature($geo_sig);
      $geo_label = $vocab{geo}->label( $lang, $geo_id );
      $item_ref->{geo}{'@id'} = $vocab{geo}->category_uri($geo_id);
    }
  }

  my $new_geo = 0;
  if (
    ## not relevant for ware!
    not defined $item_ref->{ware}
    and (
      not defined $olditem_ref->{geo}
      or (  $item_ref->{geo}{'@id'} ne $olditem_ref->{geo}{'@id'}
        and $img_nr ne '9999' )
    )
    )
  {
    $new_geo = 1;
  }

  # title is used to display the notation
  my ( $label, $linktitle );
  $label     = $item{title};
  $linktitle = $label;

  # extend with bold country for sh and co on first occurence
  if ($new_geo) {
    if ( $collection eq 'co' ) {
      if ($geo_label) {
        $label = "<b>$geo_label</b> $label";
      }

    } elsif ( $collection eq 'sh' ) {

      # label not necessarily represents a folder!
      if ( $label =~ m/^(.+)?( : .+)$/ ) {
        $label = "<b>$1</b>$2";
      } else {
        $label = "<b>$label</b>";
      }
    }
  }

  my $tag = "<a id='tag_$img_nr' title='$linktitle'>$label</a> &#160;";

  return $tag;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}

