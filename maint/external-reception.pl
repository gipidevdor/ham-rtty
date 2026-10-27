#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../t/lib";
use Carp         qw(croak);
use Getopt::Long qw(GetOptions Configure);
use JSON::PP;
use Digest::SHA;
use Ham::RTTY;
use CorpusMetrics qw(character_error_rate);
Configure(qw(no_auto_abbrev no_ignore_case));
my ($backend, $help) = ('perl', 0);
GetOptions('backend=s' => \$backend, 'help' => \$help) or croak 'Use --help for options';

if ($help) {
    print "Usage: perl maint/external-reception.pl [--backend perl|pdl|auto]\n",
        "Compare licensed examples with independent minimodem transcripts.\n",
        "Disagreement is a regression metric, not verified off-air accuracy.\n";
    exit 0;
}
croak 'Unexpected positional arguments' if @ARGV;
chdir "$FindBin::Bin/.." or croak $!;
open my $input, '<:raw', 'corpus/free.json' or croak $!;
my $cases = JSON::PP->new->decode(do { local $/ = undef; <$input> });
close $input or croak $!;
my @results;
my $failed = 0;

for my $case (@{$cases}) {
    open my $audio, '<:raw', $case->{file} or croak $!;
    my $hash = Digest::SHA->new(256)->addfile($audio)->hexdigest;
    close $audio or croak $!;
    croak "Fixture hash mismatch: $case->{file}" unless $hash eq $case->{sha256};
    my $result = Ham::RTTY->new->read_wav(
        $case->{file},
        backend => $backend,
        map { $_ => $case->{$_} } qw(baud shift mark)
    );
    my ($reference, $text) = ($case->{reference}, $result->text);
    s/\r\n?/\n/gx for $reference, $text;
    my $rate = character_error_rate($reference, $text);
    $failed = 1 if $rate > $case->{max_disagreement_rate};
    push @results,
        {
        id                       => $case->{id},
        kind                     => $case->{kind},
        backend                  => $backend,
        disagreement_rate        => $rate,
        max_disagreement_rate    => $case->{max_disagreement_rate},
        text                     => $result->text,
        warnings                 => $result->warnings,
        authoritative_transcript => JSON::PP::false
        };
}
print JSON::PP->new->utf8->canonical->pretty->encode(\@results);
exit $failed;
