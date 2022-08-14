#!/bin/sh

perlver  . | grep -v 'v5.[68].0' | grep -vF '| ~        | ~       | n/a'
