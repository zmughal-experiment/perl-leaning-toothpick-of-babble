#!/usr/bin/env perl
# ABSTRACT: Find distribution of minimum Perl versions used on CPAN

use strict;
use warnings;

use lib::projectroot qw(extra=vendor/metacpan-examples);
use feature qw(signatures postderef);
no warnings "experimental::signatures";
use Syntax::Construct qw(non-destructive-subst heredoc-indent);
use IPC::System::Simple (); # for autodie
use autodie qw(:all);

use MetaCPAN::Util qw( es );
use CHI;

use version 0.77;
use CPAN::Meta::Requirements;
use List::Util qw(first uniqstr);

use Text::Trim qw(trim);
use Path::Tiny;
use Capture::Tiny qw(capture_stdout);
use Text::CSV_XS qw( csv );
use Data::Printer;

my $cache = CHI->new(
  driver => 'File',
  expires_in => '1d',
);

main();

sub main() {
  my $module = 'perl';
  my $ADD_PERLBREW = 0;
  my $PLOT_VERSIONS = 1;
  my $work_dir = path('work');

  my $agg = $cache->compute( "query_for_version_agg-$module", {}, sub {
    my $result = es()->search(
      index  => 'cpan',
      type   => 'release',
      body   => query_for_version_agg($module),
    );
  });

  my $buckets = $agg->{aggregations}{dependencies}{filter_module}{version}{buckets};

  my $last_stable = 36;
  # v5.0.0 .. v5.$last_stable.0
  my @versions =
    map version->parse("v5.$_.0"),
    grep $_ % 2 == 0, 0..$last_stable;


  my %perlbrew;
  if( $ADD_PERLBREW ) {
    ($perlbrew{output}, $perlbrew{exit}) = capture_stdout {
      system(qw(perlbrew available));
    };
    if( 0 == delete $perlbrew{exit} ) {
      $perlbrew{available}->@* =
        map { version->parse("v$_") }
        map { s/^[^#]+?\bperl-?//r =~ s/(?:\.tar\.gz)?\s*$//r }
        grep /^[^#]+?\bperl/,
        split /\n/, delete $perlbrew{output};

      push @versions, $perlbrew{available}->@*;
    }
  }

  my @buckets_to_keep = map {
    my $r = CPAN::Meta::Requirements->new;
    $r->add_string_requirement( $module => $_->{key} );
    $r->is_simple ? { req => $r, count =>  $_->{doc_count} } : ();
  } $buckets->@*;

  @versions = uniqstr sort @versions;
  my %version_buckets;
  for my $bucket (@buckets_to_keep) {
    my $min = first {
      $bucket->{req}->accepts_module( $module, $_ );
    } @versions;
    next unless $min;
    $version_buckets{ $min } += $bucket->{count};
  }

  p %version_buckets;
  if( $PLOT_VERSIONS ) {
    my $csv_file = $work_dir->child('vb.csv');
    my $plot_device = 'png'; # png, svg
    my $plot_file = $work_dir->child(
      'vb' .
        ( $plot_device eq 'png' ? '.png'
        : $plot_device eq 'svg' ? '.svg'
        : '.out'
        )
    );

    $csv_file->parent->mkpath;
    csv(
      in => [ map +{
          version => "$_",
          count   => $version_buckets{$_},
        }, @versions ],
      out => "$csv_file",
    );

    local $ENV{IPC_R_INPUT_CSV}          = "$csv_file";
    local $ENV{IPC_R_OUTPUT_PLOT_DEVICE} = $plot_device;
    local $ENV{IPC_R_OUTPUT_PLOT_FILE}   = "$plot_file";
    local $ENV{IPC_R_OUTPUT_WIDTH_IN}    = 11;
    local $ENV{IPC_R_OUTPUT_CAPTION}     = "(@{[ trim(`git describe  --tags`) ]}:@{[ path($0) ]})";
    system(
      qw(R -e), <<~'R'
        library(ggplot2)
        library(ggcharts)
        library(parsedate)

        input_data_file     <- Sys.getenv('IPC_R_INPUT_CSV')
        output_plot_device  <- Sys.getenv('IPC_R_OUTPUT_PLOT_DEVICE')
        output_plot_file    <- Sys.getenv('IPC_R_OUTPUT_PLOT_FILE')
        output_plot_width   <- as.numeric(Sys.getenv('IPC_R_OUTPUT_WIDTH_IN'))
        output_plot_caption <- Sys.getenv('IPC_R_OUTPUT_CAPTION')

        print(paste('Reading from file', input_data_file))
        df <- read.csv(input_data_file,  stringsAsFactors = FALSE)
        df$version <- factor( df$version, levels = df$version )

        chart <- bar_chart(df, x = version, y = count, sort = FALSE) +
          geom_text(aes(label = count, hjust = -0.2)) +
          labs( caption = paste(
            "Prepared on",
            format_iso_8601(Sys.time()),
            output_plot_caption) )

        print(paste('Plotting to file', output_plot_file))
        ggsave(plot = chart,
          filename = output_plot_file,
          device = output_plot_device,
          width = output_plot_width
        )
      R
    );
  }
}

sub query_for_version_agg( $module ) {
  my $query =
    {
      query => {
        filtered => {
          query => { match_all => {} },
          filter => {
            and => [
              { term => { "dependency.module" => $module } },
              { term => { status => "latest" } }
            ]
          },
        }
      },
      aggs => {
        dependencies => {
          nested => { path => "dependency" },
          aggs => {
            filter_module => {
              filter => {
                bool => {
                  must => [
                    { term => { "dependency.module" => $module } }
                  ]
                }
              },
              aggs => {
                version => {
                  terms => {
                    field => "dependency.version",
                    order => { _count => "desc" },
                    size => 0
                  }
                }
              },
            }
          },
        }
      },
      size => 0
    }
}

