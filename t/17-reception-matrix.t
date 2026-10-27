use strict;
use warnings;
use Test::More;
use JSON::PP;
use Ham::RTTY::Detector;
use lib 't/lib';
use Reference qw(reference_sos noise);
open my $input, '<:raw', 'corpus/reception.json' or die $!;
my $cases = JSON::PP->new->decode(do { local $/; <$input> });
close $input or die $!;
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };

for my $case (@{$cases}) {
    my $signal = reference_sos(%{$case});
    my $noise  = noise(scalar @{$signal}, $case->{noise});
    $signal->[$_] += $noise->[$_] + ($case->{dc} // 0) for 0 .. $#{$signal};
    my $expected = $case->{expected} // 'SOS';
    my $reference;
    my $step = $case->{frequency_step} // 50;
    for my $backend (@backends) {
        for my $block (137, 4096) {
            my $d = Ham::RTTY::Detector->new(
                sample_rate    => $case->{rate},
                wpm            => $case->{wpm},
                backend        => $backend,
                frequency_step => $step
            );
            for (my $offset = 0; $offset < @{$signal}; $offset += $block) {
                my $end = $offset + $block - 1;
                $end = $#{$signal} if $end > $#{$signal};
                $d->feed([@{$signal}[$offset .. $end]]);
            }
            my $r     = $d->finish;
            my $label = "$case->{name} / $backend / $block";
            is($r->text, $expected, "$label text");
            if (length $expected) {
                cmp_ok(abs($r->frequency - $case->{frequency}),
                    '<=', $step, "$label tone within one candidate step");
            }
            else { ok(@{$r->warnings}, "$label rejection warning"); }
            my $summary = {
                text      => $r->text,
                events    => $r->events,
                warnings  => $r->warnings,
                frequency => $r->frequency
            };
            $reference //= $summary;
            is_deeply($summary, $reference, "$label chunk/backend equivalence");
        }
    }
}
done_testing;
