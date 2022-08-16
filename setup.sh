#!/usr/bin/bash

CURDIR=`dirname "$0"`

BABBLE_FILTER() {
	PLUGINS="$1"; shift
	FILE="$1"; shift
	perl -I ../Babble/lib -MBabble::Filter="$PLUGINS" \
		 -0777 -pe babble $FILE | sponge $FILE
}
export -f BABBLE_FILTER

# requires
# git, perl, sponge, find, sed, xargs, parallel
# cpanm Git::CPAN::Patch Babble
for dist_module in \
			Getopt::Long::Descriptive \
			App::Cmd \
			Dist::Zilla \
		; do
	dist=work/$(echo $dist_module | sed 's/::/-/g' )

	TAG='base';
	if [ ! -d $dist ]; then
		git-cpan clone --latest --norepository $dist_module
		git -C $dist tag $TAG
	else
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
		#( cd $dist && cs --yes 'use v?5[.0-9]*;$' -r '#use v5;' ) 2>&1 >/dev/null
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
	( cd $dist ; if [ -d lib ]; then export PERL5LIB=$(pwd)/lib; fi; yath -j4 -q )
done
BABBLE_FILTER ::DefinedOr,::PostfixDeref  Dist-Zilla/t/plugins/archive_builder.t
BABBLE_FILTER ::DefinedOr  Dist-Zilla/t/plugins/cpanfile.t
