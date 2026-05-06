#!/bin/sh
# nbt, 28.2.2018

# recreate all PM20 data (except METS and IIIF manifest)

# As part of the processing, input files (pm20.ttl {category}.skos.ttl) are
# copied to the remote host where an sparql endpoint is created. After some
# sparql processing, extended versions of the data are retrieved.

# stop at error
set -e

# currently, still ite-srv26
REMOTE_HOST="134.245.93.73"
REMOTE_USER=nbt
REMOTE_DIR=/opt/pm20_ep
ENDPOINT=https://zbw.eu/beta/sparql/pm20


echo "CAUTION: should not run currently, because the process creates slightly
different results (.extended.jsonld) from the former process on ite-srv24. 
This caused later steps (e.g., create_category_pages.pl) to break"
exit 1



cd /pm20/bin
##echo "`date "+%F %T"` start"


# SKIP expensive action on the file system
# (would only be required if files have been added/delted/moved/...)
if false; then

# Traverse filesystem for image files
# EXPENSIVE
./get_image_lists.sh

# Parse for filenames and paths
/usr/bin/perl parse_imagelists.pl

# Create IIIF info.json and thumbnail files
# VERY EXPENSIVE
# TODO check if necessary!
/usr/bin/perl create_iiif_img.pl ALL

# Read .txt files and extract document data
# (created beacons with document counts, too)
# should be run after recreate_document_locks.pl!!
# EXPENSIVE
/usr/bin/perl parse_docdata.pl

# formerly, on ite-srv24, with pm-opac drive mounted
# Copy IFIS .dat files and parse them
## TODO is it necessary any more (or in parse_docdata.pl? is there any equivalent on pm20?
##cp -p /mnt/pm20/4Do/???.dat ../var/dat/src/
##chmod 664 ../var/dat/src/*
##/usr/bin/perl parse_dat.pl
# backup here at ../var/backup/pm20x/bin/parse_dat.pl

### END SKIP
fi

# use existing rdf output from the ifis database
# in ../data/rdf/input
#   pm20.ttl
#   {category}.skos.ttl
# (CAN NOT be updated on pm20, would require ifis database)

# TODO can URL maps be created on pm20?
# ../data/url_map/geo_sig2id.txt
# ../data/url_map/subject_sig2id.txt
# ../data/url_map/ware_sig2id.txt


# copy rdf content to sparql server
for file in pm20.ttl geo.skos.ttl subject.skos.ttl ware.skos.ttl ; do
  scp -pq ../data/rdf/input/$file $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/rdf
done
scp -pq ../data/rdf/doc_count.ttl $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/rdf
##echo "`date "+%F %T"` done copy rdf"

# recreate sparql endpoint (and extend data)
scp -pq recreate_pm20_endpoint.sh $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/bin
ssh $REMOTE_USER@$REMOTE_HOST "cd $REMOTE_DIR/bin ; ./recreate_pm20_endpoint.sh"
# TODO reset git-controlled var data
##echo "`date "+%F %T"` done recreate endpoint"

# dump all RDF from endpoint (with all extensions)

# (must be executed on remote machine, to have endpoint directly accessible)
##ssh $REMOTE_HOST 'curl --silent -X GET -H "Accept: text/turtle" http://localhost:3030/pm20/get?graph=default' > ../data/rdf/pm20.extended.ttl
##for vocab in geo subject ware ; do
##  vocab_graph=http://zbw.eu/beta/$vocab/ng
##  ssh $REMOTE_HOST "curl --silent -X GET -H \"Accept: text/turtle\" http://localhost:3030/pm20/get?graph=$vocab_graph" > ../data/rdf/${vocab}.skos.extended.ttl
##done
curl --silent -X GET -H "Accept: text/turtle" $ENDPOINT/get?graph=default > ../data/rdf/pm20.extended.ttl
for vocab in geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng
  curl --silent -X GET -H \"Accept: text/turtle\" $ENDPOINT/get?graph=$vocab_graph > ../data/rdf/${vocab}.skos.extended.ttl
done
##echo "`date "+%F %T"` done dump rdf"


# convert to jsonld

# prior version, using Jena riot for conversion of vocab files
# abandoned, because that would require a java / jena installation on pm20
##for vocab in geo subject ware ; do
##  input=../data/rdf/${vocab}.skos.extended.ttl
##  # prepend with defined prefixes for control of jsonld conversion
##  sed -i '1s;^;@prefix zbwext: <http://zbw.eu/namespaces/zbw-extensions/> \.\n;' $input
##  sed -i '1s;^;@prefix skos: <http://www.w3.org/2004/02/skos/core#> \.\n;' $input
##  /opt/jena/bin/riot --output=jsonld $input > ../data/rdf/${vocab}.skos.extended.jsonld
##done
##echo "`date "+%F %T"` done riot convert skos.extended.ttl to .jsonld"

# dump in interim jsonld format and transform
curl --silent -X GET -H "Accept: application/ld+json" $ENDPOINT/get?graph=default > ../data/rdf/pm20.interim.jsonld
python3 transform_jsonld.py frame_folder > ../data/rdf/pm20.extended.jsonld

for vocab in geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng
  curl --silent -X GET -H "Accept: application/ld+json" $ENDPOINT/get?graph=$vocab_graph > ../data/rdf/${vocab}.skos.interim.ttl
  python3 transform_jsonld.py frame_category > ../data/rdf/${vocab}.skos.extended.jsonld
done
##echo "`date "+%F %T"` done dump rdf + transform to jsonld"


# dump all RDF from endpoint (with all extensions) for publication
##./dump_pm20_endpoint.sh
##echo "`date "+%F %T"` done dump rdf"


# SKIP temporarily, until fixed
if false; then

# create sparql results ánd provde them on´pm20 server
# (both scripts based on sparql_results.yaml)
# +# TODO procedures have been copied over from ite-srv24; they have to be adapted
# cp_reports.pl should finally not be necessary, but may provide hints re. the target locations

# on ite-srv24, a symlink ../sparql -> /opt/sparql-queries/pm20 was in place
# on pm20, the location is /pm20/var/sparql-queries

/usr/bin/perl mk_sparql_results.pl
/usr/bin/perl cp_reports.pl
##echo "`date "+%F %T"` done make+copy sparql results"

fi

##echo "`date "+%F %T"` end"


