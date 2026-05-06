# nbt, 2024-04-30

package ZBW::PM20x::Film;

use strict;
use warnings;
use autodie;
use utf8::all;

use Carp;
use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;

Readonly my $FILM_ROOT_URI => 'https://pm20.zbw.eu/film/';
Readonly my $RDF_ROOT      => path('../data/rdf');
Readonly my $IMG_COUNT     => _init_img_count();

# items in a collection are primarily grouped by $type, identified by zotero
# or filmlist properties
# CAUTION: for geo categories, subject, ware and company categories are related!
Readonly my %GROUPING_PROPERTY => (
  co => {
    ## ignore countries for now! (logically primary category for companies?)
    primary_group => {
      type       => 'company',
      zotero     => 'pm20Id',
      filmlist   => 'start_company_id',
      jsonld     => 'about',
      rdf_pred   => 'schema:about',
      rdf_prefix => 'pm20co',
    },
  },
  wa => {
    primary_group => {
      type       => 'ware',
      zotero     => 'ware_id',
      filmlist   => 'start_ware_id',
      jsonld     => 'ware',
      rdf_pred   => 'zbwext:ware',
      rdf_prefix => 'pm20ware',
    },
    secondary_group => {
      type       => 'geo',
      zotero     => 'geo_id',
      filmlist   => 'start_company_id',
      jsonld     => 'country',
      rdf_pred   => 'zbwext:country',
      rdf_prefix => 'pm20geo',
    },
  },
  sh => {
    primary_group => {
      type       => 'geo',
      zotero     => 'geo_id',
      filmlist   => 'start_geo_id',
      jsonld     => 'country',
      rdf_pred   => 'zbwext:country',
      rdf_prefix => 'pm20geo',
    },
    secondary_group => {
      type       => 'subject',
      zotero     => 'subject_id',
      jsonld     => 'subject',
      rdf_pred   => 'zbwext:subject',
      rdf_prefix => 'pm20subject',
    },
  },
);

# $FILM =     { $film_id => { total_image_count, ... }, sections => [ $section_uri, ... ] }
# $SECTION =  { $section_uri => { img_count, ...} }
# $FOLDER =   { $collection => { $folder_nk => { $filming => [ $section_uri, ... ] } } }
# $CATEGORY = { $category_type => { $category_id => { $filming => [ $section_uri ... ] } } }
# $CATEGORY_INV = { $type => { $secondary_category_id => { $filming => [ $section_uri ... ] } } }
# DOES NOT WORK WITH Readonly!
##Readonly my ( $FILM, $SECTION, $FOLDER, $CATEGORY ) => _load_filmdata();
my ( $FILM, $SECTION ) = _load_filmdata();

=encoding utf8

=head1 NAME

ZBW::PM20x::Film - Functions for PM20 microfilms


=head1 SYNOPSIS

  use ZBW::PM20x::Film;
  my $film = ZBW::PM20x::Film->new('h1/sh/S0073H_1');
  my @films = ZBW::PM20x::Film->films('h1_sh');

  my $film_name = $film->name();              # S0073H_1
  my $logical_name = $film->logigcal_name();  # S0073H
  my $number_of_images = $film->img_count();
  my @sections = $film->sections();

=head1 DESCRIPTION

The instances of this class represent digitized microfilms, as they are
physically organized on disk, e.g. S0073H_1. The superior unit (S0073H) is
called logical film.


=head1 Class methods

=over 2

=item new ($film_id)

Return a new film object for the film id (e.g., 'h1/wa/W0186H').

=cut

sub new {
  my $class   = shift or croak('param missing');
  my $film_id = shift or croak('param missing');

  if ( not $class->valid($film_id) ) {
    confess "Invalid film id $film_id";
  }

  $film_id =~ m;^(h[12])/(co|wa|sh)/([AFSW]\d{4}a?H(_[12])?$)$;;
  my $set        = $1;
  my $collection = $2;
  my $film_name  = $3;
  my $uri        = $FILM_ROOT_URI . $film_id;

  my $self = {
    film_id    => $film_id,
    set        => $set,
    collection => $collection,
    film_name  => $film_name,
    uri        => $uri,
    status     => $FILM->{$uri}{status},
  };
  bless $self, $class;

  return $self;
}

=item new_from_location ($location)

Return a new film object from a zotero location string.

=cut

sub new_from_location {
  my $class    = shift or croak('param missing');
  my $location = shift or croak('param missing');

  my $film_id;
  if ( $location =~ m/film\/(.+)?\/\d{4}(\/[RL])?$/ ) {
    $film_id = $1;
  } else {
    croak("Invalid location [$location]");
  }
  return $class->new($film_id);
}

=item films ($subset)

Return a list of films sorted by film id for a subset (e.g. "h1_sh"). (Films
which were already published as folders of documents are not part of the films
dataset.)

=cut

sub films {
  my $class  = shift or croak('param missing');
  my $subset = shift or croak('param missing');

  my @films;

  my $subset_path = $subset =~ s/_/\//r;

  foreach my $film_id ( sort keys %{$IMG_COUNT} ) {
    next unless $film_id =~ m/^$subset_path\//;

    # skip film image sets which are already online as folders
    # (and therefore not part of film dataset)
    next unless $FILM->{"$FILM_ROOT_URI$film_id"};

    # fix error with redundant _1/_2 and full films (e.g. A0023H)
    next
      if (defined $IMG_COUNT->{ ${film_id} . '_1' }
      and defined $IMG_COUNT->{ ${film_id} . '_2' } );

    # fix special case A0040H and A0040H_1 (no _2 exists)
    next if $film_id eq 'h1/co/A0040H';

    my $film = $class->new($film_id);

    next unless $film->img_count;

    push( @films, $film );
  }

  @films = sort { $a->{film_id} cmp $b->{film_id} } @films;

  return @films;
}

=item valid ($film_id)

Returns 1 if a $film_id is valid (id is formally valid and film is not empty or
already online), undef otherwise.

=cut

sub valid {
  my $class   = shift or croak('param missing');
  my $film_id = shift or croak('param missing');

  # formally valid film id
  my ( $set, $collection, $film_name, $uri );

  # TODO check/extend for Kiel films
  # NB a film named "S0901aH" exists!
  if ( $film_id =~ m;^(h[12])/(co|wa|sh)/([AFSW]\d{4}a?H(_[12])?$)$; ) {
    $set        = $1;
    $collection = $2;
    $film_name  = $3;
    $uri        = $FILM_ROOT_URI . $film_id;
  } else {
    carp("Invalid film id $film_id");
    return;
  }

  # TODO check with collection-specific regex

  # do not accept ids for films which are not in the film dataset
  # (may be non-existing or already online as folder)
  if ( not defined $FILM->{$uri} ) {
    return;
  }

  return 1;
}

=back

=head1 Instance methods

=over 2

=item id ()

Return the film identifier (e.g., h1/sh/S0073H_1).

=cut

sub id {
  my $self = shift or croak('param missing');

  my $id = $self->{film_id};

  return $id;
}

=item name ()

Return the actual name of the film (e.g., S0073H_1).

=cut

sub name {
  my $self = shift or croak('param missing');

  my $name = $self->{film_name};

  return $name;
}

=item logical_name ()

Return the name of the film (e.g., S0073H) - ignoring pysical splits.

=cut

sub logical_name {
  my $self = shift or croak('param missing');

  my $logical_name = $self->{film_name};
  $logical_name =~ s/^(.+)?_[12]$/$1/;

  return $logical_name;
}

=item sections ()

Return a list of film sections for a film.

=cut

sub sections {
  my $self = shift or croak('param missing');

  my @section_uris = ();
  if ( not defined $FILM->{ $self->{uri} }{sections} ) {
    carp "No sections for ", Dumper $self;
  } else {
    @section_uris = @{ $FILM->{ $self->{uri} }{sections} };
  }
  my @sectionlist = ();
  foreach my $section_uri (@section_uris) {
    push( @sectionlist, $SECTION->{$section_uri} );
  }
  return @sectionlist;
}

=item img_count ()

Return the numer of image files under the film directory.

=cut

sub img_count {
  my $self = shift or croak('param missing');

  my $img_count = $IMG_COUNT->{ $self->{film_id} };

  return $img_count;
}

=item status ()

Returns one of the following processing stati:

- indexed - film is completly indexed

- unindexed - film is not indexed (only country start entries for sh)

=cut

sub status {
  my $self = shift or croak('param missing');

  my $status = $self->{status};

  return $status;
}

=back

=cut

############ internal

sub _init_img_count {

  my %img_count;
  my $raw_ref =
    decode_json( path('/pm20/data/filmdata/img_count.json')->slurp() );
  foreach my $raw_id ( keys %{$raw_ref} ) {

    # skip misnamend (and empty) films
    next if $raw_id =~ m/F0549H_3$/;
    next if $raw_id =~ m/S9393$/;
    next if $raw_id =~ m/S9398$/;
    next if $raw_id =~ m/dummy$/;

    # strip filesystem prefix from film id
    $raw_id =~ m;^/pm20/film/(.+)$;;
    $img_count{$1} = $raw_ref->{$raw_id};
  }
  return \%img_count;
}

sub _load_filmdata {

  my ( $FILM, $SECTION );

  # opening _raw is necessary to avoid "Wide character ..." problem with
  # decode_json (slurp_utf8 does not work!)
  my $film_file = path('/pm20/data/rdf/film.jsonld');
  my @filmdata  = @{ decode_json( $film_file->slurp_raw )->{'@graph'} };

  foreach my $filmdata_ref (@filmdata) {
    my $type = $filmdata_ref->{'@type'};
    my $uri  = $filmdata_ref->{'@id'};
    if ( $type eq 'Pm20FilmItem' ) {
      $SECTION->{$uri} = $filmdata_ref;
    } elsif ( $type eq 'Pm20Film' ) {
      $FILM->{$uri} = $filmdata_ref;
    } else {
      ## subsets
      ##print Dumper $filmdata_ref;
    }
  }

  # add sections to films
  foreach my $section_uri ( sort keys %{$SECTION} ) {

    ( my $film_uri ) =
      $section_uri =~ m;^(.+?/film/[hk][12]/(?:co|sh|wa)/.+?)/.+$;;
    push( @{ $FILM->{$film_uri}{sections} }, $section_uri );
  }

  return $FILM, $SECTION;
}

# use only to transmit the pointer to Film::Section
sub _SECTION() {
  return $SECTION;
}

1;

