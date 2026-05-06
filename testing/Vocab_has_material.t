# 10.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Vocab';

use_ok($class) or die "Could not load $class\n";

my ( $ware_id, $geo_id, $subject_id, $filming );
my $ware_vocab = $class->new('ware');

$ware_id = 142275;

# TODO activate actual test
##ok( $ware_vocab->has_material($ware_id), "ware $ware_id has material" );

done_testing;
