Using a modern Perl:

```
# need git, perl, sponge, find, sed, xargs, parallel,
./setup.sh
```

Install in older Perl using `perlbrew`:

```shell
perlbrew install perl-5.8.9 -j4 -n -v
perlbrew lib create 5.8.9@dzil
perlbrew use 5.8.9@dzil
cpanm --verbose \
	./work/Getopt-Long-Descriptive \
	./work/Mixin-Linewise \
	./work/Perl-PrereqScanner \
	./work/App-Cmd \
	./work/String-Formatter \
	./work/MooseX-OneArgNew \
	./work/Role-Identifiable \
	./work/MooseX-SetOnce \
	./work/Config-MVP \
	./work/Config-MVP-Reader-INI \
	./work/CPAN-Uploader \
	./work/work/Dist-Zilla \
```
