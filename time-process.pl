#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use Path::Tiny;
use JSON::MaybeXS ();
use List::Util qw(sum);
use boolean;

# perlbrew exec --with perl-5.18.4@babble,perl-5.34.0@babble bash -c 'cpanm -n --cpanfile cpanfile.process --installdeps . '
sub main {
	my $json = JSON::MaybeXS->new->convert_blessed;
	my $output = path('timing.json');
	my $tempfile = Path::Tiny->tempfile;
	my @data;

	RUN:
	for my $cache (0..1) {
	for my $mp_cache (0..1) { for my $warm_cache (0..1) {
		for my $version ('perl-5.18.4@babble', 'perl-5.34.0@babble') {
			for my $run (0..2) { # 5
				local $ENV{PERL_BABBLE_CACHE_RE} = $cache;
				local $ENV{BABBLE_MP_CACHE} = $mp_cache;
				local $ENV{BABBLE_WARM_CACHE} = $warm_cache;
				system(
					'/usr/bin/time',
						-o => "$tempfile",

						qw(perlbrew exec),
							'--with' => $version,
							'./process.pl'
				) == 0 or die "could not run command";
				my $timing = $tempfile->slurp_utf8;
				my @rev_parts = reverse split ':', ( $timing =~ /([0-9:.]+)elapsed/s)[0];
				my $elapsed = sum map { $rev_parts[$_] * 60**$_ } 0..$#rev_parts;
				push @data, {
					cache => boolean($cache),
					match_pos_cache => boolean($mp_cache),
					warm_cache => boolean($warm_cache),
					version => $version,
					run   => $run,
					timing => $timing,
					elapsed => $elapsed,
				};
				$output->spew_utf8( $json->encode(\@data) );
			}
		}
	} }
	}
}

main;
