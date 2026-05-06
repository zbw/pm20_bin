#!/bin/sh

# make all .md files of the PM20 web site
# (execute different find command for parts of the website - find everything
# from root is too large)

make -s -C /pm20/web
make -s -C /pm20/web SET=category
make -s -C /pm20/web SET=pe
make -s -C /pm20/web SET=co
make -s -C /pm20/web SET=sh
make -s -C /pm20/web SET=wa

