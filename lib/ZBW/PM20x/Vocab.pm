# nbt, 2020-08-06

package ZBW::PM20x::Vocab;

use strict;
use warnings;
use autodie;
use utf8::all;

use Carp qw/ cluck confess croak /;
use Data::Dumper;
use Exporter;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use Unicode::Collate;
use ZBW::PM20x::Film::Section;

# exported package constants
our @ISA    = qw/ Exporter /;
our @EXPORT = qw/ @LANGUAGES $SM_QR $DEEP_SM_QR /;

Readonly our @LANGUAGES => qw/ en de /;

# identifies "Sondermappen" on different levels
Readonly our $SM_QR => qr/ Sm\d+/;
##Readonly our $DEEP_SM_QR      => qr/ Sm\d+\.[IVX]+/;
Readonly our $DEEP_SM_QR => qr/ Sm\d+\.\d+/;

Readonly my $RDF_ROOT => path('../data/rdf');

Readonly my $URI_STUB => 'https://pm20.zbw.eu/category/';

# detail type -> relevant count property
Readonly my %COUNT_PROPERTY => (
  subject => {
    geo => 'folderCount',
  },
  geo => {
    subject => 'shFolderCount',
    ware    => 'waFolderCount',
  },
  ware => {
    geo => 'folderCount',
  },
);

=encoding utf8

=head1 NAME

ZBW::PM20x::Vocab - Functions for PM20 vocabularies


=head1 SYNOPSIS

  use ZBW::PM20x::Vocab;
  my $voc = ZBW::PM20x::Vocab->new('geo');

  my $last_modified = $voc->modified;
  my $label = $voc->label($lang, $id);
  my $signature = $voc->signature($id);
  my $term_id = $voc->lookup_signature('A10');
  my $term_id = $voc->lookup_geo_name('Andorra');
  my $term_id = $voc->lookup_ware_name('Kohle');
  my $subheading = $voc->subheading('A');
  my $folder_count = $voc->folder_count( 'subject', 'geo', $id );

=head1 DESCRIPTION

The instances of this class are vocabularies (geo, ware, subject), not
individual terms.

Read all vocabularies into a data structure, organized as:

  {$vocab}          e.g., 'geo'
    id              by identifier (main term entry)
      {$id}         hash with everything from database
    modified        last modification of the vocabulary
    nta             by signature
      {$signature}  points to id
    geo_name        by German lc geo name
      {$geo_name}   points to id
    ware_name       by German lc ware name
      {$ware_name}  points to id
    subhead         subheadings for lists
      {$first}      first letter of signature
    sorted_ids      list of ids (by long signature/name)
      {$lang}

  $id   term id (\d{6}, with leading zeros)

=cut

=head1 Class methods

=over 2

=item new ($vocab_name)

Return a new vocab object from the named vocabulary. (Names were previosly
lowercase ifis klass_code; now geo|suject|ware).  Read the according SKOS
vocabluary in JSONLD format into the object.

=cut

sub new {
  my $class      = shift or croak('param missing');
  my $vocab_name = shift or croak('param missing');

  my $self = { vocab_name => $vocab_name };
  bless $self, $class;

  # initialize with file
  my ( %cat, %lookup, $modified );
  my $file = path("$RDF_ROOT/$vocab_name.skos.extended.jsonld");
  foreach my $lang (qw/ en de /) {

    # opening _raw is necessary to avoid "Wide character ..." problem with
    # decode_json (slurp_utf8 does not work!)
    my @categories =
      @{ decode_json( $file->slurp_raw )->{'@graph'} };

    # read jsonld graph
    foreach my $category (@categories) {

      my $type = $category->{'@type'};
      next unless $type;
      if ( $type eq 'ConceptScheme' ) {
        $self->{modified} = $category->{modified};
      } elsif ( $type eq 'Concept' ) {

        my $id = $category->{identifier};

        # skip orphan entries for old vocab - do not require broader for new
        # entries (here only available via klassifikator id)
        if ( not exists $category->{broader} ) {
          if ( $id < 230701 ) {
            next;
          }
        }

        # map optional simple jsonld fields to hash entries
        my @fields = qw / notation notationLong foldersComplete geoCategoryType
          shFolderCount waFolderCount folderCount /;
        foreach my $field (@fields) {
          $cat{$id}{$field} = $category->{$field};
        }

        # map optional multivalued language-independent jsonld fields to hash
        # entries
        @fields = qw / exactMatch wikipediaArticle /;
        foreach my $field (@fields) {
          foreach my $entry ( _as_array( $category->{$field} ) ) {
            if ( $lang eq 'de' ) {
              push( @{ $cat{$id}{$field} }, $entry );
            }
          }
        }

        # map optional language-specifc jsonld fields to hash entries
        @fields = qw / prefLabel scopeNote /;
        foreach my $field (@fields) {
          foreach my $ref ( _as_array( $category->{$field} ) ) {
            $cat{$id}{$field}{ $ref->{'@language'} } = $ref->{'@value'};
          }
        }

        # add signature to lookup table
        $lookup{ $cat{$id}{notation} } = $id;
      } else {

        # with extended vocabs, lots of types are possible
        ##croak "Unexpectend type $type\n";
        next;
      }
    }

    # save state
    $self->{id}         = \%cat;
    $self->{nta}        = \%lookup;
    $self->{sorted_ids} = $self->_init_sorted_ids;

    # get the broader id for SM entries from first parts of the signature
    # TODO there are more types of hierarchies (below Sm and below ordinary
    # terms, so the second level should not be used before further analysis
    foreach my $id ( keys %cat ) {
      my $signature = $cat{$id}{notation};
      next if not $signature =~ m/ Sm\d/;

      my $start_sig;
      if ( $signature =~ $DEEP_SM_QR ) {
        $start_sig = $self->start_sig( $id, 2 );
      } elsif ( $signature =~ $SM_QR ) {
        $start_sig = $self->start_sig( $id, 1 );

        # special case with artificially introduced x0 level
        if ( $signature =~ m/^([a-z])0$/ ) {
          $start_sig = $1;
        }
      } else {
        cluck("Unknown Sm scheme: signature $signature");
      }
      $cat{$id}{broader} = $lookup{$start_sig}
        or confess("missing signature $start_sig");
    }

    $self->_add_subheadings();
  }
  ##print Dumper $self;
  return $self;
}

=back

=head1 Instance methods

=head2 Methods for the vocabulary

=over 4

=item modified ()

Returns the date of the last (manual) modification of the vocabulary (obtained from the term timestamps).

=cut

sub modified {
  my $self = shift or croak('param missing');

  # apparently, for some vocab, jsonld return a date value, for some a string
  my $modified;
  if ( ref( $self->{modified} ) ) {
    $modified = $self->{modified}{'@value'};
  } else {
    $modified = $self->{modified};
  }

  return $modified;
}

=item category_ids ( $lang )

Return a list of categories, sorted by signature or, in case of ware, by the language-specific label.

=cut

sub category_ids {
  my $self = shift or croak('param missing');
  my $lang = shift or croak('param missing');

  return @{ $self->{sorted_ids}{$lang} };
}

=item lookup_signature ( $signature )

Look up a term id by signature, undef if not defined.

=cut

sub lookup_signature {
  my $self      = shift or croak('param missing');
  my $signature = shift or croak('param missing');

  my $term_id = $self->{nta}{$signature};

  return $term_id;
}

=item lookup_geo_name ( $geo_name )

Look up a term id by German geo name (case insensitive), undef if not defined.

=cut

sub lookup_geo_name {
  my $self     = shift or confess('param missing');
  my $geo_name = shift or confess('param missing');

  # lazy load
  if ( not defined $self->{geo_name} ) {
    $self->_init_geo_name();
  }

  my $term_id = $self->{geo_name}{ lc($geo_name) };

  return $term_id;
}

=item lookup_ware_name ( $ware_name )

Look up a term id by German ware name (case insensitive), undef if not defined.

=cut

sub lookup_ware_name {
  my $self      = shift or confess('param missing');
  my $ware_name = shift or confess('param missing');

  # lazy load
  if ( not defined $self->{ware_name} ) {
    $self->_init_ware_name();
  }

  my $term_id = $self->{ware_name}{ lc($ware_name) };

  return $term_id;
}

=item vocab_name ()

Return the name of the vocabulary.

=cut

sub vocab_name {
  my $self = shift or confess('param missing');

  return $self->{vocab_name};
}

=back

=head2 Methods for an individual term/category

=over 4

=item label ( $lang, $term_id )

Return the label for a term.

=cut

sub label {
  my $self    = shift or croak('param missing');
  my $lang    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $label = $self->{id}{$term_id}{prefLabel}{$lang};

  # mark unchecked translated labels
  if ( $lang eq 'en' and $label and $label =~ m/^\. / ) {
    $label =~ s/\. (.*)/$1 \*/;
  }

  return $label;
}

=item signature ( $term_id )

Return the signature for a term.

=cut

sub signature {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $signature = $self->{id}{$term_id}{notation};

  return $signature;
}

=item category_uri ( $term_id )

Return the (numerical) URI for a category.

=cut

sub category_uri {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $uri = $URI_STUB . $self->vocab_name . "/i/$term_id";

  return $uri;
}

=item siglink ( $term_id )

Return the signature for a term, formatted suitable for a link.

=cut

sub siglink {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $siglink = $self->{id}{$term_id}{notation};
  $siglink =~ s/ /_/g;

  return $siglink;
}

=item broader ( $term_id )

Return the id for the hierarchically superordinated term.

=cut

sub broader {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $broader = $self->{id}{$term_id}{broader};

  return $broader;
}

=item subheading ( $lang, $key )

Return the subheading for a key (normally, the first letter of the signature).

=cut

sub subheading {
  my $self = shift or croak('param missing');
  my $lang = shift or croak('param missing');
  my $key  = shift or croak('param missing');

  my $subheading = $self->{subhead}{$key}{$lang};

  return $subheading;
}

=item scope_note( $term_id )

Return the scope note for a term, or undef, if not defined.

=cut

sub scope_note {
  my $self    = shift or croak('param missing');
  my $lang    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $scope_note = $self->{id}{$term_id}{scopeNote}{$lang};

  return $scope_note;
}

=item wdlink( $term_id )

Return a link to the exactly matching Wikidata item

=cut

sub wdlink {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $wdlink;
  if ( defined $self->{id}{$term_id}{exactMatch} ) {
    my @exact_links = @{ $self->{id}{$term_id}{exactMatch} };
    foreach my $link_ref (@exact_links) {
      ## replace short links
      my $link = $link_ref->{'@id'};
      $link =~ s|^wd:|http://www\.wikidata\.org/entity/|;
      if ( $link =~ m|^http://www\.wikidata\.org/entity/| ) {
        $wdlink = $link;
        last;
      }
    }
  }

  return $wdlink;
}

=item wplink( $lang, $term_id )

Return a link to the Wikipedia page for a exactly matching Wikidata item

=cut

sub wplink {
  my $self    = shift or croak('param missing');
  my $lang    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $wplink;
  if ( defined $self->{id}{$term_id}{wikipediaArticle} ) {
    my @articles = @{ $self->{id}{$term_id}{wikipediaArticle} };
    foreach my $link_ref (@articles) {
      my $link = $link_ref->{'@id'};
      if ( $link =~ m|^https://$lang\.wikipedia\.org/wiki/| ) {
        $wplink = $link;
        last;
      }
    }
  }

  return $wplink;
}

=item geo_category_type( $term_id )

Return the geo_category_type (A for "Sternchenland", B for normal, C for "Kästchenland"), or undef, if not defined.

=cut

sub geo_category_type {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $geo_category_type = $self->{id}{$term_id}{geoCategoryType};

  return $geo_category_type;
}

=item folders_complete( $term_id )

Return true if all subject folders are comlete for a country, or if all country
folders are complete for a ware, false otherwise.

=cut

sub folders_complete {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $folders_complete;
  if (  $self->{id}{$term_id}{foldersComplete}
    and $self->{id}{$term_id}{foldersComplete} eq 'Y' )
  {
    $folders_complete = 1;
  }

  return $folders_complete;
}

=item folder_count ( $term_id, $detail_type )

Return the folder_count, or undef, if not defined.

=cut

sub folder_count {
  my $self        = shift or croak('param missing');
  my $term_id     = shift or croak('param missing');
  my $detail_type = shift or croak('param missing');

  # get from extended vocab data
  my $category_type = $self->vocab_name;
  my $prop          = $COUNT_PROPERTY{$category_type}{$detail_type};
  my $folder_count  = $self->{id}{$term_id}{$prop}{'@value'};

  return $folder_count;
}

=item folderlist ( $lang, $term_id, $detail_vocab )

Returns a list of folders, sorted by long signature or ware name of the detail
vocabulary.

=cut

sub folderlist {
  my $self       = shift or croak('param missing');
  my $lang       = shift or croak('param missing');
  my $term_id    = shift or croak('param missing');
  my $detail_voc = shift or croak('param missing');

  my @folderlist;

  my $master_type = $self->vocab_name;
  my $detail_type = $detail_voc->vocab_name;

  my @detail_category_ids = $detail_voc->category_ids($lang);
  foreach my $detail_id (@detail_category_ids) {
    my ( $collection, $folder_nk );
    if ( $master_type eq 'ware' and $detail_type eq 'geo' ) {
      $collection = 'wa';
      $folder_nk  = "$term_id,$detail_id";
    } elsif ( $master_type eq 'subject' and $detail_type eq 'geo' ) {
      $collection = 'sh';
      $folder_nk  = "$detail_id,$term_id";
    } elsif ( $master_type eq 'geo' and $detail_type eq 'subject' ) {
      $collection = 'sh';
      $folder_nk  = "$term_id,$detail_id";
    } elsif ( $master_type eq 'geo' and $detail_type eq 'ware' ) {
      $collection = 'wa';
      $folder_nk  = "$detail_id,$term_id";
    } else {
      croak("Strange combination of master $master_type $term_id "
          . "and detail $detail_id" );
    }

    # create a folder from  hypotetical combination of terms
    my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

    # filters for actually existing folders
    # (film sections cannot interfere here)
    if ( $folder->get_doc_count ) {
      push( @folderlist, $folder );
    }
  }

  return @folderlist;
}

=item start_sig ( $term_id, $level )

Returns the start level(s) of the signature, e.g e4 Sm3.IVa

level 1: e4; level 2: e4 Sm3

=cut

sub start_sig {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');
  my $level   = shift or croak('param missing');

  my $signature = $self->signature($term_id);
  my $start_sig;
  if ( $level == 2 ) {
    if ( $signature =~ m/^([a-z]\S*? Sm\d+)(\.[IVX]+|[a-z])/ ) {
      $start_sig = $1;
    } else {
      cluck("no level 2 signature for $term_id $signature");
      return;
    }
  } elsif ( $level == 1 ) {
    if ( $signature =~ m/^([a-z]\S*?) (Sm\d+|\(alt\)|I)/ ) {
      $start_sig = $1;
    } elsif ( $signature =~ m/^\S+$/ ) {
      ## signature does not contain any blanks
      $start_sig = $signature;
    } else {
      cluck("no level 1 signature for $term_id $signature");
      return;
    }
  }
}

=item filmsectionlist( $term_id, $filming, $detail_type )

Return a (currently unsorted) list of film sections of detail category type $detail_type
(defaults see below) for a term of the given (main) category type for either
filming 1 or 2. Leaves out sections already published as folders and not
manually indexed.

Default detail types are subject for geo, geo for ware, or geo for subject.

=cut

sub filmsectionlist {
  my $self        = shift or croak('param missing');
  my $term_id     = shift or croak('param missing');
  my $filming     = shift or croak('param missing');
  my $detail_type = shift;

  my $master_type = $self->vocab_name;

  # set default detail type, if omitted by the caller
  if ( not $detail_type ) {
    if ( $master_type eq 'ware' ) {
      $detail_type = 'geo';
    } elsif ( $master_type eq 'geo' ) {
      $detail_type = 'subject';
    } elsif ( $master_type eq 'subject' ) {
      $detail_type = 'geo';
    }
  }

  my @filmsectionlist;

  # only certain combinations of master/detail categories are valid!
  if ( ( $master_type eq 'geo' and $detail_type eq 'subject' )
    or ( $master_type eq 'ware' and $detail_type eq 'geo' ) )
  {
    @filmsectionlist =
      ZBW::PM20x::Film::Section->categorysections( $master_type, $term_id,
      $filming );
  } elsif ( $master_type eq 'geo' and $detail_type eq 'ware'
    or $master_type eq 'subject' and $detail_type eq 'geo' )
  {
    @filmsectionlist =
      ZBW::PM20x::Film::Section->categorysections_inv( $master_type, $term_id,
      $filming );
  } else {
    croak("Invalid combination of master $master_type and detail $detail_type");
  }

  return @filmsectionlist;
}

=item film_img_count ( $term_id, $filming )

Return the number of images for a primary category from a certain filming.

=cut

sub film_img_count {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');
  my $filming = shift or croak('param missing');

  my $count;
  my @sections = $self->filmsectionlist( $term_id, $filming );
  foreach my $section_ref (@sections) {
    $count += $section_ref->{totalImageCount}{'@value'};
  }
  return $count;
}

=item has_material ( $term_id )

Returns 1, if there are folders or film sections for the term, otherwise 0.

=cut

sub has_material {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $has_material = 0;
  foreach my $prop (qw/ folderCount waFolderCount shFolderCount /) {
    if ( defined $self->{id}{$term_id}{$prop} ) {
      $has_material = 1;
    }
  }
  if ( scalar( $self->filmsectionlist( $term_id, 1 ) ) > 0 ) {
    $has_material = 1;
  }
  if ( scalar( $self->filmsectionlist( $term_id, 2 ) ) > 0 ) {
    $has_material = 1;
  }

  return $has_material;
}

=back

=cut

############ internal

sub _as_array {
  my $var = shift;

  # $var may or may not be a reference
  my @list = ();
  if ($var) {
    if ( reftype($var) and reftype($var) eq 'ARRAY' ) {
      @list = @{$var};
    } else {
      @list = ($var);
    }
  }
  return @list;
}

sub _add_subheadings {
  my $self = shift or croak('param missing');

  if ( $self->vocab_name eq 'geo' ) {
    $self->{subhead} = {
      A => {
        de => 'Europa',
        en => 'Europe',
      },
      B => {
        de => 'Asien',
        en => 'Asia',
      },
      C => {
        de => 'Afrika',
        en => 'Africa',
      },
      D => {
        de => 'Australien und Ozeanien',
        en => 'Australia and Oceania',
      },

      E => {
        de => 'Amerika',
        en => 'America',
      },

      F => {
        de => 'Polargebiete',
        en => 'Polar regions',
      },

      G => {
        de => 'Meere',
        en => 'Seas',
      },

      H => {
        de => 'Welt',
        en => 'World',
      },
      J => {
        de => 'Tropen',
        en => 'Tropics',
      },
    };
  } elsif ( $self->vocab_name eq 'subject' ) {
    foreach my $id ( keys %{ $self->{id} } ) {
      my %terminfo  = %{ $self->{id}{$id} };
      my $signature = $terminfo{notation};
      next if not $signature =~ m/^[a-z]$/;
      foreach my $lang (@LANGUAGES) {
        my $label = $terminfo{prefLabel}{$lang};

        # remove generalizing phrases
        $label =~ s/, Allgemein$//i;
        $label =~ s/, General$//i;

        $self->{subhead}{$signature}{$lang} = $label;
      }
    }
  } elsif ( $self->vocab_name eq 'ware' ) {

    # here we have no signature, but only start chars
    foreach my $id ( keys %{ $self->{id} } ) {
      my %terminfo = %{ $self->{id}{$id} };
      foreach my $lang (@LANGUAGES) {
        my $startchar = uc( substr( $terminfo{prefLabel}{$lang}, 0, 1 ) );
        $self->{subhead}{$startchar}{$lang} = $startchar;
      }
    }
  }
  return;
}

# init geo_name data

sub _init_geo_name {
  my $self = shift or croak('param missing');

  foreach my $id ( keys %{ $self->{id} } ) {
    my %terminfo = %{ $self->{id}{$id} };

    # normalize geo name to lowercase German
    my $name = lc( $terminfo{prefLabel}{de} );

    $self->{geo_name}{$name} = $id;
  }
}

# init ware_name data

sub _init_ware_name {
  my $self = shift or croak('param missing');

  foreach my $id ( keys %{ $self->{id} } ) {
    my %terminfo = %{ $self->{id}{$id} };

    # normalize ware name to lowercase German
    my $name = lc( $terminfo{prefLabel}{de} );

    $self->{ware_name}{$name} = $id;
  }
}

# init the sorted id lists (returns hash of arrays, keyed by language)

sub _init_sorted_ids {
  my $self = shift or croak('param missing');

  my %sorted;
  my %cat_id = %{ $self->{id} };
  foreach my $lang (@LANGUAGES) {
    my @category_ids;
    if ( $self->vocab_name eq 'ware' ) {
      my $uc = Unicode::Collate->new();
      @category_ids = sort {
        $uc->cmp( $cat_id{$a}{'prefLabel'}{$lang},
          $cat_id{$b}{'prefLabel'}{$lang} )
      } keys %cat_id;
    } else {
      @category_ids =
        sort { $cat_id{$a}{notationLong} cmp $cat_id{$b}{notationLong} }
        keys %cat_id;
    }
    $sorted{$lang} = \@category_ids;
  }
  return \%sorted;
}

1;

