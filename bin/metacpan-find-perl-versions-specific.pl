#!/usr/bin/env perl
# PODNAME: Find a specific version string for perl dependency

use strict;
use warnings;

use lib::projectroot qw(extra=vendor/metacpan-examples);
use feature qw(signatures postderef);
no warnings "experimental::signatures";
use MetaCPAN::Util qw( es );

use Data::Printer;

main();

sub main() {
  die "Need version to match: $0 VERSION" unless @ARGV;
  my $version = shift @ARGV;

  my $module = 'perl';
  my $result = es()->search(
    index  => 'cpan',
    type   => 'release',
    body   => query_for_module_version($module, $version),
  );

  my @dists = map { $_->{_source}{name} } $result->{hits}{hits}->@*;
  p @dists;
}

sub query_for_module_version( $module, $version ) {
  my $query =
    {
      query => {
        filtered => {
          query => { match_all => {} },
          filter => {
            and => [
              {
                nested => {
                  path => "dependency",
                  filter => {
                    bool => {
                      must => [
                        { term => { "dependency.module"  => $module  } },
                        { term => { "dependency.version" => $version } },
                      ]
                    }
                  },
                }
              },
              { term => { status => "latest" } }
            ]
          },
        }
      },
      size => 10
    }
}
