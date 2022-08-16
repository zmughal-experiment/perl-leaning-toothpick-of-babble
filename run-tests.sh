#!/usr/bin/bash

CURDIR=`dirname "$0"`

find work/ -mindepth 1 -maxdepth 1 -type d -print -exec sh -c '
	cd {} ; if [ -d lib ]; then export PERL5LIB=$(pwd)/lib; fi; yath -j4 -q
' \;
