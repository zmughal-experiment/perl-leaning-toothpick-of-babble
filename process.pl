#!/usr/bin/env perl
# PODNAME: process.pl
# ABSTRACT: Processes a distribution and its dependencies

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;

use Path::Tiny;


BEGIN {
	unshift @INC,
		our @VENDOR_LIB = map { ( -d $_
			&& $_ !~ /~/
			&& $_->child('lib')->stringify
			) || () }
		path($FindBin::Bin, 'vendor')->children;
}

package Dist {
	use Mu;
	use Module::Runtime qw(is_module_name);
	use Mojo::UserAgent;
	use feature qw(signatures postderef);
	no warnings "experimental::signatures";

	lazy ua => sub { Mojo::UserAgent->new };

	ro 'main_module_name';
	rw 'version' => ( required => 0 , predicate => 1 );

	rw [qw(url)] => ( required => 0  );

	sub BUILD($self, @) {
		die "Not a valid module name" unless is_module_name($self->main_module_name);

		my $METACPAN_DOWNLOAD_URL_BASE = "https://fastapi.metacpan.org/v1/download_url/";
		my $dist_info = $self->ua->get(
			"$METACPAN_DOWNLOAD_URL_BASE/@{[ $self->main_module_name ]}"
			. ($self->has_version ? "?version===@{[ $self->version ]}" : '')

		)->result->json;

		$self->url( $dist_info->{download_url} );
		$self->version( $dist_info->{version} ) unless $self->has_version;
	}
};

package Process {
	use Mu;
	use feature qw(signatures postderef);
	no warnings "experimental::signatures";
	use PerlX::Maybe;
	use Env qw(@PERL5LIB);

	use Config::INI::Reader::Multiline;
	use File::Find::Rule::Perl;

	ro 'config_path';

	lazy work_dir => sub { path($FindBin::Bin, 'work') };

	sub fetch_or_reset($self, $dist) {
	}

	sub run($self) {
		my $config = Config::INI::Reader::Multiline
			->read_file($self->config_path);
		my @dists;
		while( my ($module, $data) = each %$config ) {
			push @dists, Dist->new(
				main_module_name => $module,
				maybe version => $data->{version},
			);
		}

		my $babble_filter = <<'BASH';
BABBLE_FILTER() {
	PLUGINS="$1"; shift
	FILE="$1"; shift
	perl -MBabble::Filter="$PLUGINS" \
		 -0777 -pe babble $FILE | sponge $FILE
}
export -f BABBLE_FILTER

BASH
		do {
		local $ENV{PERL5LIB} = $ENV{PERL5LIB};
		unshift @PERL5LIB, @main::VENDOR_LIB;

		for my $dist (@dists) {
			local $ENV{TARBALL_URL} = $dist->url;
			local $ENV{dist_module} = $dist->main_module_name;

			system(qw(bash -c), $babble_filter . <<'BASH');
	#set -eoxu pipefail
	set -eou pipefail

# requires
# git, perl, sponge, find, sed, xargs, parallel
# cpanm Babble Pod::Strip
#
# tar with support for --strip-components (e.g., GNU tar, bsdtar)

	dist=work/$(echo $dist_module | sed 's/::/-/g; s/@.*$//' )

	TAG='base';
	if [ ! -d $dist ]; then
		git init -q $dist
		curl -s $TARBALL_URL | tar -C $dist --strip-components 1 -xzf -
		git -C $dist add --all --force .
		git -C $dist commit -q -m "initial import of $dist_module"
		git -C $dist tag $TAG
	else
		if [ -f $dist/Makefile ]; then make -C $dist clean; fi
		git -C $dist checkout main
		git -C $dist reset --hard $TAG
	fi

	FIND_FILES='\( \( -type f -name "*.pm" \) -o \( -type f -regex ".*/bin/.*" -exec grep -qP "^#!.*perl$" {} \; \) \)'
	if true; then
		echo -n "Removing POD..."
		TAG='pod'
		eval "find $dist $FIND_FILES -print" | grep -vP '/t/|/corpus/' | xargs sed -i '/^#pod/d'
		eval "find $dist $FIND_FILES -print" | grep -vP '/t/|/corpus/' | xargs -I{} sh -c "perl -MPod::Strip -e 'Pod::Strip->filter(shift @ARGV)' {} | sponge {}"
		git -C $dist add . && git -C $dist commit -q -m 'Remove POD' --allow-empty
		git -C $dist tag -f $TAG
	fi

	if true; then
		echo -n "Removing Perl version..."
		TAG='perl-version'
		find $dist -type f | grep -v '/corpus/' | xargs perl -pi -e 's/^use \s+ v?5[.0-9]* \s* ; $/#$&/x'
		find $dist -type f | xargs perl -pi -e "s/^ no \s+ feature \s+ 'switch'; \s+ $/#$&/x"
		find $dist -type f -name 'Makefile.PL' | xargs perl -pi -e 's/^ .* MIN_PERL_VERSION .* $/#$&/x'
		git -C $dist add . && git -C $dist commit -q -m 'Remove explicit use Perl version / extra features' --allow-empty
		git -C $dist tag -f $TAG
	fi

	for plugin in \
			PackageBlock PackageVersion \
			DefinedOr \
			PostfixDeref \
			State SubstituteAndReturn \
			Ellipsis \
		; do
		TAG="babble-$plugin"
		TIMING_TEMP=$(mktemp BABBLE_TIMING_XXXXXX)
		/usr/bin/time -p -o $TIMING_TEMP bash -c "
			find $dist $FIND_FILES -print \
				| grep -v '/corpus/' \
				| parallel -j4 -N1 --bar -X \
					'BABBLE_FILTER ::$plugin {}'
			"
		git -C $dist add . && git -C $dist commit -q -m "Apply Babble plugin $plugin" -m "$(cat $TIMING_TEMP)" --allow-empty
		git -C $dist tag -f $TAG | tr -d '\n'; echo -n "...";
		git -P -C $dist show --format= --shortstat $TAG
		rm $TIMING_TEMP
	done

BASH
		}

		system(qw(bash -c), $babble_filter . <<'BASH');

perl -pi -e 's/"feature" =>/#$&/' work/Dist-Zilla/Makefile.PL
BABBLE_FILTER ::DefinedOr,::PostfixDeref  work/Dist-Zilla/t/plugins/archive_builder.t
BABBLE_FILTER ::DefinedOr  work/Dist-Zilla/t/plugins/cpanfile.t
perl -MBabble::Grammar -MRole::Tiny -MBabble::Filter=::DefinedOr -0777 -pe 'Role::Tiny->apply_roles_to_package( qw(Babble::Grammar), qw(PPP::Babble::Grammar::Role::TryTiny) ); babble' work/Dist-Zilla/lib/Dist/Zilla.pm | sponge work/Dist-Zilla/lib/Dist/Zilla.pm
perl -MBabble::Grammar -MRole::Tiny -MBabble::Filter=::PostfixDeref -0777 -pe 'Role::Tiny->apply_roles_to_package( qw(Babble::Grammar), qw(PPP::Babble::Grammar::Role::TryTiny) ); babble' work/Dist-Zilla/lib/Dist/Zilla/Dist/Builder.pm | sponge work/Dist-Zilla/lib/Dist/Zilla/Dist/Builder.pm
git -C work/Dist-Zilla add . && git -C work/Dist-Zilla commit -q -m 'Apply extra' --allow-empty
git -C work/Dist-Zilla tag -f extra-pass

perl -pi -e 's/^#(\Quse 5.008;\E)$/$1/' work/Perl-PrereqScanner/lib/Perl/PrereqScanner.pm
git -C work/Perl-PrereqScanner add . && git -C work/Perl-PrereqScanner commit -q -m 'Apply extra' --allow-empty
git -C work/Perl-PrereqScanner tag -f extra-pass
BASH

		};
	};
}


sub main {
	Process->new( config_path => 'dist-zilla.ini' )->run;
}

main;
