#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use Path::Tiny;
use JSON::MaybeXS ();
use List::Util qw(sum);
use Permute::Named::Iter qw(permute_named_iter);
use boolean;

# perlbrew exec --with perl-5.18.4@babble,perl-5.34.0@babble bash -c 'cpanm -n --cpanfile cpanfile.process --installdeps . '
sub main {
	my $json = JSON::MaybeXS->new->convert_blessed;
	my $output = path('timing.json');
	my $tempfile = Path::Tiny->tempfile;
	my @data;

	my $runs = 3;

	my $time_path = '/usr/bin/time';
	die "$time_path is not GNU time" unless `$time_path --version` =~ /GNU Time/s;

	my $permute = permute_named_iter(
		cache           => [ map boolean($_), 1 ],
		match_pos_cache => [ map boolean($_), 1 ],
		bail_out_early  => [ map boolean($_), 1 ],
		bail_out_late   => [ map boolean($_), 1 ],
		warm_cache      => [ map boolean($_), 0..1 ],
		workers         => [ 2, 4, 8 ],
		version         => [
			'perl-5.18.4@babble',
			'perl-5.34.0@babble',
		],
		run              => [ 0..$runs-1 ],
	);

	local $ENV{BABBLE_DIST_ALLOW} = 'Dist::Zilla|App::Cmd';
	RUN:
	while (my $p = $permute->()) {
		local $ENV{PERL_BABBLE_CACHE_RE} = 0 + $p->{cache};
		local $ENV{BABBLE_MP_CACHE} = 0 + $p->{match_pos_cache};
		local $ENV{BABBLE_WARM_CACHE} = 0 + $p->{warm_cache};
		local $ENV{BABBLE_PLUGINS_WORKERS} = $p->{workers};
		local $ENV{PERL_BABBLE_BAIL_OUT_EARLY} = 0 + $p->{bail_out_early};
		local $ENV{PERL_BABBLE_BAIL_OUT_LATE}  = 0 + $p->{bail_out_late};

		system(
			$time_path,
				-o => "$tempfile",

				qw(perlbrew exec),
					'--with' => $p->{version},
					'./process.pl'
		) == 0 or die "could not run command";

		my $timing = $tempfile->slurp_utf8;
		my @rev_parts = reverse split ':', ( $timing =~ /([0-9:.]+)elapsed/s)[0];
		my $elapsed = sum map { $rev_parts[$_] * 60**$_ } 0..$#rev_parts;
		push @data, {
			%$p,
			timing => $timing,
			elapsed => $elapsed,
		};
		$output->spew_utf8( $json->encode(\@data) );
	}
}

main;
