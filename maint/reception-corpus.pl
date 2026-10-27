#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../t/lib";
use JSON::PP;
use Ham::RTTY;
use CorpusMetrics qw(character_error_rate);
use File::Spec;
use Carp qw(croak);
my $root = "$FindBin::Bin/..";
open my $input, '<:raw', "$root/corpus/real.json" or croak $!;
my $cases = JSON::PP->new->decode(do { local $/ = undef; <$input> });
close $input or croak $!;
my @results;

for my $case (@{$cases}) {
    my $result =
        Ham::RTTY->new->read_wav(File::Spec->catfile($root, $case->{file}), wpm => $case->{wpm});
    my $cer           = character_error_rate($case->{reference}, $result->text);
    my $estimated     = Ham::RTTY->new->read_wav(File::Spec->catfile($root, $case->{file}));
    my $cer_estimated = character_error_rate($case->{reference}, $estimated->text);
    push @results,
        {
        name                         => $case->{name},
        reference                    => $case->{reference},
        text                         => $result->text,
        cer                          => $cer,
        cer_hinted                   => $cer,
        cer_estimated                => $cer_estimated,
        text_estimated               => $estimated->text,
        estimated_wpm                => $estimated->wpm,
        max_regression_cer_hinted    => $case->{max_regression_cer_hinted},
        max_regression_cer_estimated => $case->{max_regression_cer_estimated},
        quality_target_cer           => $case->{quality_target_cer},
        meets_quality_target         => $cer <= $case->{quality_target_cer} ? JSON::PP::true
        : JSON::PP::false,
        meets_quality_target_estimated => $cer_estimated <= $case->{quality_target_cer}
        ? JSON::PP::true
        : JSON::PP::false,
        max_regression_cer  => $case->{max_regression_cer},
        warnings            => $result->warnings,
        warnings_estimated  => $estimated->warnings,
        frequency           => $result->frequency,
        frequency_estimated => $estimated->frequency
        };
}
print JSON::PP->new->utf8->canonical->pretty->encode(\@results);
