#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use File::Spec;
use FindBin;
use JSON::PP;
use Ham::RTTY;
binmode STDOUT, ':encoding(UTF-8)' or croak $!;

my $backend  = shift @ARGV // 'perl';
my $root     = File::Spec->catdir($FindBin::Bin, '..');
my $manifest = File::Spec->catfile($root, 'corpus', 'real.json');
open my $input, '<:raw', $manifest or croak $!;
my $bytes = do { local $/ = undef; <$input> };
close $input or croak $!;
my $cases = decode_json($bytes);
my $cw    = Ham::RTTY->new(backend => $backend);

for my $case (@{$cases}) {
    my $path   = File::Spec->catfile($root, split m{/}x, $case->{file});
    my $result = $cw->read_wav($path, wpm => $case->{wpm});
    croak 'Recording was not finalized' unless $result->complete;
    printf "%s: reference=[%s], received=[%s], warnings=%d\n",
        $case->{name}, $case->{reference}, $result->text, scalar(@{$result->warnings});
    for my $warning (@{$result->warnings}) { print "  $warning->{code}: $warning->{message}\n" }
    print "  $case->{license}; author: $case->{author}\n";
}
print "References are comparisons, not expected decoder guarantees. See corpus/real/LICENSES.md.\n";
print "Example completed: corpus-reception\n";
