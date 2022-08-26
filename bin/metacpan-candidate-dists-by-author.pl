#!/usr/bin/env perl
# ABSTRACT: Finds candidate releases to backport for a given author

use strict;
use warnings;

use lib::projectroot qw(extra=vendor/metacpan-examples);
use MetaCPAN::Util qw( es );

use Syntax::Construct qw(hash-slice);
use feature qw(postderef);

use JSON::MaybeXS qw( decode_json );
use WWW::Mechanize::GZip ();
use URI ();
use List::UtilsBy qw(nsort_by);

use Data::Printer;

my $author = shift @ARGV;
die "usage: $0 PAUSEID" if !$author;

my $min_perl_version = v5.20;

my $latest = es()->search(
    index  => 'cpan',
    type   => 'release',
    #fields => [ 'distribution', 'version', 'dependency' ],
    size   => 500,
    body   => {
        query => {
            filtered => {
                query  => { match_all => {} },
                filter => {
                    and => [
                        { term => { 'dependency.module' => 'perl' } },
                        { term => { 'status' => 'latest' } },
                        { term => { 'author' => $author }, },
                    ],
                },
            },
        },
        sort => [ { 'date' => 'desc' } ],
    },
);

my $mech = WWW::Mechanize::GZip->new;
my $rev_dep_base = URI->new('https://fastapi.metacpan.org/v1/reverse_dependencies/dist/');

my @releases =
	nsort_by { $_->{reverse_deps_count} }
	map {
		my $dist = $_;
		$mech->get(
			URI->new_abs( $dist->{distribution}, $rev_dep_base ),
		);
		my $results = decode_json( $mech->content );

		# how many reverse dependencies found
		$dist->{reverse_deps_count} = $results->{total};
		# some of the actual reverse dependency distributions (did not
		# use paging for MetaCPAN API call above in order to
		# get larger list)
		$dist->{reverse_deps}->@* =
			map { $_->{distribution} } $results->{data}->@*;

		$dist;
	}
	map {
		my $release = $_->{_source};
		my %h = $release->%{qw(distribution version)};
		my ($perl) = grep { $_->{module} eq 'perl' } @{ $release->{dependency} };
		if( $perl ) {
			$h{minperl} = version->new($perl->{version});
		}
		exists $h{minperl} && $h{minperl} >= $min_perl_version ? \%h : ()
	} @{ $latest->{hits}->{hits} };

p @releases;
