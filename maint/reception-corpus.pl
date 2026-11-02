#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp qw(croak);
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Ham::RTTY;
use Ham::RTTY::_Internal::Validate qw(number);
open my $in, '<:raw', 'corpus/real.json' or croak $!;
my $cases = JSON::PP->new->decode(do { local $/ = undef; <$in> });
close $in or croak $!;
validate_manifest($cases);
my (%ids, %files, %hashes);
my @missing = map { $_->{file} } grep { $_->{status} ne 'reviewed' || !-f $_->{file} } @{$cases};
croak "Missing reviewed real RTTY fixtures: @missing\n" if @missing;
my @results;

for my $case (@{$cases}) {
    validate_case($case);
    croak "Duplicate real RTTY fixture\n"
        if $ids{$case->{id}}++ || $files{$case->{file}}++ || $hashes{$case->{sha256}}++;
    open my $header, '<:raw', $case->{file} or croak $!;
    my $recording = Ham::RTTY::Audio->new->reader($header);
    close $header or croak $!;
    croak "Empty real RTTY recording: $case->{file}\n" unless $recording->{sample_count};
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
    croak "No signal in real RTTY recording: $case->{file}\n"
        if grep { $_->{code} eq 'RTTY_W_NO_SIGNAL' } @{$result->warnings};
    my $cer = distance($result->text, $case->{reference}) / length($case->{reference});
    push @results,
        {file => $case->{file}, cer => $cer, text => $result->text, warnings => $result->warnings};
    croak "CER exceeds quality target or regression budget: $case->{file}: $cer\n"
        if $cer > 0.25 || $cer > $case->{max_regression_cer};
}
print JSON::PP->new->canonical->pretty->encode(\@results);

sub validate_manifest {
    my ($entries) = @_;
    croak "Expected exactly four real RTTY fixtures\n"
        unless ref($entries) eq 'ARRAY' && @{$entries} == 4;

    for my $case (@{$entries}) {
        croak "Invalid real RTTY fixture entry\n" unless ref($case) eq 'HASH';
        for my $key (qw(id file status)) {
            croak "Missing fixture field: $key\n"
                if !defined($case->{$key}) || ref($case->{$key}) || $case->{$key} !~ /\S/x;
        }
    }
    return;
}

sub validate_case {
    my ($case) = @_;
    for my $key (qw(source_url license sha256 reference)) {
        croak "Missing provenance/reference: $case->{file} $key\n"
            if !defined($case->{$key}) || ref($case->{$key}) || $case->{$key} !~ /\S/x;
    }
    croak "Invalid source URL: $case->{file}\n" unless $case->{source_url} =~ m{\Ahttps?://\S+\z}x;
    croak "Invalid fixture hash: $case->{file}\n" unless $case->{sha256}   =~ /\A[0-9a-f]{64}\z/x;
    number('quality_target_cer', $case->{quality_target_cer}, 0.25, 0.25);
    number('max_regression_cer', $case->{max_regression_cer}, 0,    0.25);
    return;
}

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
