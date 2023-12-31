#!/bin/bash
# nbt, 08.11.2019

# Generate file from .md

input_file="$1"
if [ ! -f "$input_file" ]; then
  echo input file $input_file missing
  exit
fi

output_file=$(dirname $input_file)/$(basename $input_file .md).html
##echo $output_file

# language variable is used in the form of is_$lang in templates
# (default language is de)
if [[ $input_file == *.en.md ]]; then
  lang=en
else
  lang=de
fi
LANG_OPTS="--variable is_$lang --variable lang:$lang"

TMPL_OPTS="--data-dir /pm20/web --template pm20_default.html --css /styles/simple.css"

EXT_OPTS="-t html+pipe_tables+fenced_divs+bracketed_spans"

pandoc --standalone $EXT_OPTS $TMPL_OPTS $LANG_OPTS -o $output_file

