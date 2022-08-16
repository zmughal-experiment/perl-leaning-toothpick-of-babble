#!/usr/bin/bash

CURDIR=`dirname "$0"`

for dist_module in Dist::Zilla App::Cmd Getopt::Long::Descriptive; do
	dist=$(echo $dist_module | sed 's/::/-/g' )
	( cd $dist ; if [ -d lib ]; then export PERL5LIB=$(pwd)/lib; fi; yath -j4 -q )
done
