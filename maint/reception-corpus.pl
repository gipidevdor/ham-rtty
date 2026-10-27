#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp qw(croak);
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Ham::RTTY;
open my $in, '<:raw', 'corpus/real.json' or croak $!;
my $cases = JSON::PP->new->decode(do { local $/ = undef; <$in> });
close $in or croak $!;
my @missing = map { $_->{file} } grep { $_->{status} ne 'reviewed' || !-f $_->{file} } @{$cases};
croak "Missing reviewed real RTTY fixtures: @missing\n" if @missing;
my @results;

for my $case (@{$cases}) {
    for my $key (qw(source_url license sha256 reference max_regression_cer)) {
        croak "Missing provenance/budget: $case->{file} $key\n" unless defined $case->{$key};
    }
    open my $audio, '<:raw', $case->{file} or croak $!;
    my $hash = Digest::SHA->new(256)->addfile($audio)->hexdigest;
    close $audio or croak $!;
    croak "Fixture hash mismatch: $case->{file}\n" unless $hash eq $case->{sha256};
    my $result = Ham::RTTY->new->read_wav(
        $case->{file},
        baud  => $case->{baud},
        shift => $case->{shift},
        mark  => $case->{mark} // 2125
    );
    my $cer = distance($result->text, $case->{reference}) / (length($case->{reference}) || 1);
    push @results,
        {file => $case->{file}, cer => $cer, text => $result->text, warnings => $result->warnings};
    croak "CER exceeds quality target or regression budget: $case->{file}: $cer\n"
        if $cer > 0.25 || $cer > $case->{max_regression_cer};
}
print JSON::PP->new->canonical->pretty->encode(\@results);

sub distance {
    my ($actual, $expected) = @_;
    my @previous = (0 .. length $expected);
    for my $i (1 .. length $actual) {
        my @next = ($i);
        for my $j (1 .. length $expected) {
            my @choices = (
                $previous[$j] + 1,
                $next[$j - 1] + 1,
                $previous[$j - 1] + (substr($actual, $i - 1, 1) ne substr($expected, $j - 1, 1))
            );
            $next[$j] = (sort { $a <=> $b } @choices)[0];
        }
        @previous = @next;
    }
    return $previous[-1];
}
