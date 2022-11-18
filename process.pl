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

	lazy ua => sub { Mojo::UserAgent->new };

	ro 'main_module_name';
	rw 'version' => ( required => 0 , predicate => 1 );

	lazy url => sub {
		my ($self) = @_;
		$self->_dist_info->{download_url};
	};

	lazy _dist_info => sub {
		my ($self) = @_;
		my $METACPAN_DOWNLOAD_URL_BASE = "https://fastapi.metacpan.org/v1/download_url/";
		my $dist_info = $self->ua->get(
			"$METACPAN_DOWNLOAD_URL_BASE/@{[ $self->main_module_name ]}"
			. ($self->has_version ? "?version===@{[ $self->version ]}" : '')

		)->result->json;
		$self->version( $dist_info->{version} ) unless $self->has_version;
		$dist_info;
	};

	sub BUILD {
		my ($self) = @_;
		die "Not a valid module name" unless is_module_name($self->main_module_name);
	}
};

package Process {
	use Mu;
	use PerlX::Maybe;
	use Env qw(@PERL5LIB);
	use Module::Runtime qw(use_module);

	use Config::INI::Reader::Multiline;
	use File::Find::Rule::Perl;
	use Path::Tiny;

	use Babble::Grammar;

	use File::Which;
	use Pod::Strip;

	use autodie qw(:all);
	use IPC::System::Simple;
	use File::chdir;
	use File::Find::Rule       ();
	use File::Find::Rule::Perl ();

	use MCE;
	use curry;
	use Term::ProgressBar;
	use Babble::PluginChain;
	use With::Roles;

	ro 'config_path';

	lazy work_dir => sub { path($FindBin::Bin, 'work') };

	sub fetch_or_reset {
		my ($self, $dist) = @_;
	}

	sub get_plugin {
		my ($plugin_name, $grammar) = @_;
		$grammar ||= Babble::Grammar->new;
		$plugin_name =~ s/^::/Babble::Plugin::/;
		my $p = use_module($plugin_name)->new;
		$p->extend_grammar($grammar) if $p->can('extend_grammar');
		$p;
	}

	sub run {
		my ($self) = @_;
		my $config = Config::INI::Reader::Multiline
			->read_file($self->config_path);
		my @dists;
		for my $module (sort keys %$config) {
			next if $module =~ /^-/;
			my $data = $config->{$module};

			push @dists, Dist->new(
				main_module_name => $module,
				maybe version => $data->{version},
			);
		}

		my @plugins =  sort map { my $p = $_; grep { $p->{$_} } keys %$p } $config->{-plugins=>};

		die "Need git" unless which('git');
		die "Need curl" unless which('curl');
		die "Need make" unless which('make');
		die "Need tar with support for --strip-components (e.g., GNU tar, bsdtar)" unless which('tar');

		my $rule =  File::Find::Rule->or(
			File::Find::Rule::Perl->perl_module,
			File::Find::Rule::Perl->perl_script,
		);
		my $all_perl_rule = File::Find::Rule::Perl->perl_file;
		my $eumm_rule = File::Find::Rule->file->name( 'Makefile.PL' );

		my %plugin_cache;
		my $grammar = Babble::Grammar->new;
		@plugin_cache{@plugins} = map get_plugin($_, $grammar), @plugins;
		my $blank_top = $grammar->match(Document => '');
		$_->transform_to_plain($blank_top) for values %plugin_cache;

		my $mce = MCE->new(
			max_workers => 4,
			#chunk_size => 64,
		);

		DIST:
		for my $dist (@dists) {
			local $ENV{TARBALL_URL} = $dist->url;
			local $ENV{dist_module} = my $dist_module = $dist->main_module_name;

			my $dist_dir = $self->work_dir->child(
				$dist->main_module_name =~ s/::/-/gr
			);
			local $ENV{dist_dir} = "$dist_dir";

			{
				my $TAG = 'base';
				if( ! -d $dist_dir ) {
					print "Downloading @{[ $dist->url ]}\n";
					system(qw(git init -q), $dist_dir);
					system 'curl -s $TARBALL_URL | tar -C $dist_dir --strip-components 1 -xzf -';
					{
						local $CWD = "$dist_dir";
						system qw(git add --all --force .);
						system qw(git commit -q -m), "initial import of $dist_module";
						system qw(git tag), $TAG;
					}
				} else {
					if( -f $dist_dir->child('Makefile') ) {
						system qw(make -C), $dist_dir, qw(clean);
					}
					{
						local $CWD = "$dist_dir";
						system qw(git checkout main);
						system qw(git reset --hard), $TAG;
					}
				}
			}

			my @FIND_FILES = $rule->in( $dist_dir );
			my @ALL_PERL_FILES = $all_perl_rule->in($dist_dir);
			my @EUMM_FILES = $eumm_rule->in($dist_dir);

			{
				# Removing POD
				my $TAG = 'pod';
				for my $file (@FIND_FILES) {
					next if $file =~ m,/t/|/corpus/,;
					path($file)->edit(sub {
						s/^ \#pod \N*? \n//xmsg;
						my $p = Pod::Strip->new;
						my $podless;
						$p->output_string( \$podless );
						$p->parse_string_document( $_ );
						$_ = $podless;
					});
				}
				{
					local $CWD = "$dist_dir";
					system qw(git add .);
					system qw(git commit -q -m), 'Remove POD', '--allow-empty';
					system qw(git tag -f), $TAG;
				}
			}

			{
				# Removing Perl version...
				my $TAG = 'perl-version';
				use version;
				my $min = version->parse('v5.8.0');
				for my $file (@ALL_PERL_FILES) {
					next if $file =~ m,/corpus/,;
					path($file)->edit_lines(sub {
						s{^use \s+ (v?5[.0-9]*) \s* ; $}{
							(version->parse($1) > $min ? "#" : "") . $&
						}xe
					} );
				}
				for my $file (@ALL_PERL_FILES) {
					path($file)->edit_lines(sub { s/^ no \s+ feature \s+ 'switch'; \s* $/#$&/x } );
				}
				for my $file (@EUMM_FILES) {
					path($file)->edit_lines(sub { s/^ .* MIN_PERL_VERSION .* $/#$&/x });
				}
				{
					local $CWD = "$dist_dir";
					system qw(git add .);
					system qw(git commit -q -m), 'Remove explicit use Perl version / extra features', '--allow-empty';
					system qw(git tag -f), $TAG;
				}
			}

			for my $plugin ( @plugins ) {
				my $TAG = "babble-@{[ $plugin =~ s/::/-/gr ]}";
				my $progress_bar = Term::ProgressBar->new({
					count => 0+@ALL_PERL_FILES,
					name  => $plugin,
				});
				my $pc;
				$mce->foreach(\@ALL_PERL_FILES,
					{
						progress => $progress_bar->curry::update,
						user_begin => sub {
							my $p = $plugin_cache{$plugin};
							$pc = Babble::PluginChain->new( plugins => [ $p ], grammar => $grammar );
						},
					},
					sub {
						my ($mce, $chunk_ref, $chunk_id) = @_;
						return if $chunk_ref->[0] =~ m,/corpus/,;
						my $file = path($chunk_ref->[0]);
						$file->edit(sub {
							$_ = $pc->transform_document($_);
						});
					}
				);
				{
					local $CWD = "$dist_dir";
					system qw(git add .);
					system qw(git commit -q -m), "Apply Babble plugin $plugin", '--allow-empty';
					system qw(git tag -f), $TAG;
					system qw(git -P show --format= --shortstat), $TAG;
				}
			}

			{
				local $CWD = "$dist_dir";
				system qw(git tag -f), 'pre-extra-pass';
			}

			{
				my $TAG = 'extra-pass';
				local $CWD = "$dist_dir";
				#system qw(git reset --hard), 'pre-extra-pass';
				my $eval = $config->{ $dist->main_module_name }{eval};
				if( $eval ) {
					eval $eval;
					system qw(git commit -q -m), 'Apply extra pass', '--allow-empty';
					system qw(git tag -f), $TAG;
				}
			}
		}
	}
}


sub main {
	Process->new( config_path => 'dist-zilla.ini' )->run;
}

main;
