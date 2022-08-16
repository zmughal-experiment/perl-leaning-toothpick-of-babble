#!/bin/sh

perlver  work/ | grep -v 'v5.[68].0' | grep -vP '\|\s+~\s+\|\s+~\s+\|\s+n/a'
