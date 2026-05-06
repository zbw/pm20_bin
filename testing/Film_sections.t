# 2025-12-14

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

my $section_id = 'h1/wa/W0087H/0002';
ok( my ($film_id) = $section_id =~ m;(.+?)/\d{4}$;, "film_id" );
is( $film_id, 'h1/wa/W0087H', 'new film' );
my $film     = ZBW::PM20x::Film->new($film_id);
my @sections = $film->sections;

my $section = $sections[0];

#diag Dumper $section;

# TODO change to blessed Film::Section!!
my $retrieved_section_id = substr( $section->{'@id'}, 25 );
is( $retrieved_section_id, $section_id, 'first section id' );

done_testing;
