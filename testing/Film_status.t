# 12.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

my ( $film_id, $film );

$film_id = 'h1/wa/W0186H';
ok( $film = ZBW::PM20x::Film->new($film_id), "Film $film_id" );
is( $film->status, 'indexed', "film $film_id is indexed" );

$film_id = 'h1/wa/W0086H';
ok( $film = ZBW::PM20x::Film->new($film_id), "Film $film_id" );
is( $film->status, 'unindexed', "film $film_id is not yet indexed" );
##diag(Dumper $film->sections);

done_testing;
