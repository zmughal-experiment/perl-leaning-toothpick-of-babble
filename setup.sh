#!/usr/bin/bash

CURDIR=`dirname "$0"`

export PERL5LIB="vendor/Babble/lib:vendor/PPP/lib:$PERL5LIB"

METACPAN_DOWNLOAD_URL_BASE="https://fastapi.metacpan.org/v1/download_url/"

BABBLE_FILTER() {
	PLUGINS="$1"; shift
	FILE="$1"; shift
	perl -MBabble::Filter="$PLUGINS" \
		 -0777 -pe babble $FILE | sponge $FILE
}
export -f BABBLE_FILTER

# requires
# git, perl, sponge, find, sed, xargs, parallel
# cpanm Babble Pod::Strip
#
# tar with support for --strip-components (e.g., GNU tar, bsdtar)
for dist_module in \
			Getopt::Long::Descriptive@0.110 \
			App::Cmd@0.334 \
			Mixin::Linewise@0.110 \
			Dist::Zilla@6.025 \
			Perl::PrereqScanner@1.024 \
			String::Formatter@1.234 \
			MooseX::OneArgNew@0.006 \
			Role::Identifiable@0.008 \
			MooseX::SetOnce@0.201 \
			Config::MVP@2.200012 \
			Config::MVP::Reader::INI@2.101464 \
			CPAN::Uploader@0.103016 \
		; do
	dist=work/$(echo $dist_module | sed 's/::/-/g; s/@.*$//' )

	TAG='base';
	if [ ! -d $dist ]; then
		DOWNLOAD_URL_REQ=$METACPAN_DOWNLOAD_URL_BASE/$( echo $dist_module | sed 's/@/?version===/' )
		TARBALL_URL=$(curl -s $DOWNLOAD_URL_REQ | jq -r .download_url)
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

	# Run tests
	#( cd $dist && prove -lr t )
	#( cd $dist ; if [ -d lib ]; then export PERL5LIB=$(pwd)/lib; fi; yath -j4 -q )
done

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
