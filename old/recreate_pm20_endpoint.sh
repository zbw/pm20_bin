#!/bin/sh
# nbt, 10.8.2018

# use results from rebuild_all_data.sh and extract additional
# data from wikidata to rebuild the pm20 sparql endpoint

# TO BE EXECUTED ON ite-srv26/36 !!!

set -e

ENDPOINT=http://localhost:3030/pm20
WD_GRAPH=http://zbw.eu/beta/wikidata/ng
ROOT_DIR=/opt/pm20_ep
QUERY_DIR=/opt/sparql-queries/pm20
RDF_DIR=$ROOT_DIR/rdf

cd $ROOT_DIR

# drop all graphs
curl --silent -X POST -H "Content-type: application/sparql-update" \
    --data-binary "DROP ALL" $ENDPOINT/update


# load vocabulary graphs for pm20 categories
for vocab in geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng

  # load vocab
  file=$RDF_DIR/${vocab}.skos.ttl
  curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$file $ENDPOINT/data?graph=$vocab_graph > /dev/null
  ## load zbwext vocab to provide field labels for Skosmos
  curl --silent --show-error -X POST -H "Content-type: application/rdf+xml" \
    --data-binary @/opt/thes/var/stw/zbw-extensions/zbw-extensions.rdf $ENDPOINT/data?graph=$vocab_graph > /dev/null
done

# load static "historical" data
for vocab in gk na pr sk ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng

  # load vocab
  file=$RDF_DIR/static_from_ifis/${vocab}.skos.ttl
  curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$file $ENDPOINT/data?graph=$vocab_graph > /dev/null
  ## load zbwext vocab to provide field labels for Skosmos
  curl --silent --show-error -X POST -H "Content-type: application/rdf+xml" \
    --data-binary @/opt/thes/var/stw/zbw-extensions/zbw-extensions.rdf $ENDPOINT/data?graph=$vocab_graph > /dev/null
done

# drop and reload default graph with pm20 rdf
##curl --silent --show-error -X DELETE $ENDPOINT/data?default
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/pm20.ttl $ENDPOINT/data > /dev/null

# load document counts
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/doc_count.ttl $ENDPOINT/data > /dev/null

# add rdfs:labels for text indexing
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @/opt/sparql-queries/add_rdfs_labels.ru $ENDPOINT/update > /dev/null

# add top concepts
# TODO additionally on default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_top_concepts.ru $ENDPOINT/update > /dev/null

# add external links from vocab graphs redundantly to default graph for WD
# TODO still necessary?
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_vocab_links.ru $ENDPOINT/update > /dev/null


# insert folder counts - requieres loaded pm20 dataset
# TODO refactor
curl --silent -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_folder_count_per_concept.ru $ENDPOINT/update #> /dev/null


# create WD graph for easy access to an extract of WD

# get wikidata extract for linked folders (splitted to avoid timeout)
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_links_extract.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_links_extract.ttl
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_geo_subject_codes.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_geo_subject_code.ttl
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_info_extract.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_info_extract.ttl

# get category mappings as SKOS
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_category_mappings.rq $ENDPOINT/query \
  > $RDF_DIR/wd_category_mappings.ttl

# get wikidata folder mapping as SKOS
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_folder_mapping.rq $ENDPOINT/query \
  > $RDF_DIR/wd_folder_mapping.ttl

# get wd page counts
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_page_count.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_page_count.ttl

# get persons life data
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_life.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_life.ttl

# complex way to get all WD labels for mapped concepts
# (federated query to WD endpoint does not work because
# it would have to use a graph clause, which is forbidden)

# create list of all QIDs
cat $RDF_DIR/wd_category_mappings.ttl $RDF_DIR/wd_folder_mapping.ttl | \
  grep skos:[ecbnr] | cut -d ' ' -f 1 | sed -r 's/^wd:(Q[[:digit:]]+)/\"\1\"/' \
  > $RDF_DIR/voc_wd_qid.tsv


# create query
extended_query=/tmp/construct_wd_voc_mapping_labels.rq
perl $QUERY_DIR/../bin/replace_values_list.pl \
  $QUERY_DIR/construct_wd_voc_mapping_labels.rq \
  $RDF_DIR/voc_wd_qid.tsv \
  > $extended_query

# get wd labels
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$extended_query https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_voc_mapping_labels.ttl


# load wikidata graph
for file in wd_links_extract.ttl wd_info_extract.ttl wd_page_count.ttl wd_life.ttl wd_category_mappings.ttl wd_folder_mapping.ttl wd_voc_mapping_labels.ttl wd_geo_subject_code.ttl ; do
 curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$RDF_DIR/$file $ENDPOINT/data?graph=$WD_GRAPH > /dev/null
done

# insert Wikidata folder mapping into default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_wd_mapping.ru $ENDPOINT/update #> /dev/null

# insert Wikidata category mapping into vocab graphs and default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_wd_mapping_categories.ru $ENDPOINT/update #> /dev/null

# insert subject category notations into default graph

# q&d Workarround: load SK (Standardklassifikation Wirtschaft) mapping data to
# WD into default graph in order to allow federaed queries from WD without
# graph clauses
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/static_from_ifis/sk.skos.ttl $ENDPOINT/data?graph=default > /dev/null
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/sk_wd_mapping/sk_wd.ttl $ENDPOINT/data?graph=default > /dev/null


