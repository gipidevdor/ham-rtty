use 5.020;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw(refaddr);
use File::Temp   qw(tempdir);
use Ham::RTTY;
use Ham::RTTY::_Internal::Biquad;
use Ham::RTTY::_Internal::CLI;
use JSON::PP;
use lib 't/lib';
use Reference qw(reference_sos noise);
my $pi = 4 * atan2(1, 1);

# Check steady-state response against the transfer function, independently of
# the streaming recurrence. No external signal recordings are used here.
for my $frequency (650, 850, 1500) {
    my $filter = Ham::RTTY::_Internal::Biquad->new(8000, 650, 80);
    my $wave   = [map { sin(2 * $pi * $frequency * $_ / 8000) } 0 .. 7999];
    my $out    = $filter->process($wave);
    my $power  = 0;
    $power += $out->[$_]**2 for 4000 .. 7999;
    my $alpha    = sin($pi * 80 / 8000) / cos($pi * 80 / 8000);
    my $omega    = 2 * $pi * $frequency / 8000;
    my $expected = ($alpha * sin($omega))**2 /
        ((cos($omega) - cos(2 * $pi * 650 / 8000))**2 + ($alpha * sin($omega))**2);
    cmp_ok(abs(sqrt($power / 2000) - $expected),
        '<', 1e-9, "cascaded biquad response at $frequency Hz");
}
for my $frequency (1, 650, 3999) {
    my $filter = Ham::RTTY::_Internal::Biquad->new(8000, $frequency, 80);
    my $out    = $filter->process([1, (0) x 15999]);
    ok(!grep($_ != $_ || abs($_) > 1, @{$out}), "bounded impulse response at $frequency Hz");
}
my @dc = (1) x 8000;
my $dc = Ham::RTTY::_Internal::Biquad->new(8000, 650, 80)->process(\@dc);
cmp_ok(abs($dc->[-1]), '<', 1e-12, 'DC is rejected');
my $input  = noise(16000, 0.6);
my $whole  = Ham::RTTY::_Internal::Biquad->new(8000, 650, 80)->process($input);
my $filter = Ham::RTTY::_Internal::Biquad->new(8000, 650, 80);
my @chunked;

for (my $i = 0; $i < @{$input}; $i += 137) {
    my $end = $i + 136 < $#{$input} ? $i + 136 : $#{$input};
    push @chunked, @{$filter->process([@{$input}[$i .. $end]])};
}
is_deeply(\@chunked, $whole, 'filter state is continuous across arbitrary input chunks');

# Literal independent CQ schedule, offset relative to the independent SOS.
sub cq {
    my ($frequency, $speed) = @_;
    my (@out, $position);
    $position = 0;
    for my $run (
        [0, 3], [1, 3], [0, 1], [1, 1], [0, 1], [1, 3], [0, 1], [1, 1], [0, 3], [1, 3],
        [0, 1], [1, 3], [0, 1], [1, 1], [0, 1], [1, 3], [0, 3]
        )
    {
        my $count = int(8000 * 1.2 / $speed * $run->[1] + 0.5);
        push @out,
            map { $run->[0] * 0.2 * sin(2 * $pi * $frequency * $position++ / 8000) } 1 .. $count;
    }
    return [(0) x 296, @out];
}
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };
my $mixed;
for my $case ([800, 20], [1050, 20], [900, 25]) {
    my $a      = reference_sos(amplitude => 0.4);
    my $b      = cq(@{$case});
    my $count  = @{$a} > @{$b} ? @{$a} : @{$b};
    my $static = noise($count, 0.06);
    my @mix    = map { ($a->[$_] // 0) + ($b->[$_] // 0) + $static->[$_] } 0 .. $count - 1;
    my $expected;
    for my $backend (@backends) {
        for my $chunk (137, 4096) {
            my $d = Ham::RTTY::Detector->new(
                sample_rate => 8000,
                backend     => $backend,
                $case->[1] == 20 ? (wpm => 20) : ()
            );
            is_deeply($d->channels, [], 'no stations before input');
            for (my $i = 0; $i < @mix; $i += $chunk) {
                my $end = $i + $chunk - 1 < $#mix ? $i + $chunk - 1 : $#mix;
                $d->feed([@mix[$i .. $end]]);
            }
            my $primary  = $d->finish;
            my $stations = $d->channels;
            is_deeply(
                [map { [$_->frequency, $_->text] } @{$stations}],
                [[650, 'SOS'], [$case->[0], 'CQ']],
                "$backend separates keyed tones, $chunk samples"
            );
            is(
                refaddr($primary),
                refaddr($stations->[0]),
                'primary is the strongest accepted station'
            );
            is(
                refaddr($d->channels->[1]),
                refaddr($stations->[1]),
                'unchanged station snapshots are cached'
            );
            my @events = map { $_->events } @{$stations};
            $expected //= \@events;
            is_deeply(\@events, $expected, 'station timing is independent of input chunks');

            for my $events (@events) {
                my $total = 0;
                $total += $_->{samples} for @{$events->{segments}};
                is($total, scalar @mix, 'delay compensation preserves real recording length');
            }
            pop @{$stations};
            is(scalar @{$d->channels}, 2, 'caller cannot mutate the cached station list');
            $d->reset;
            is_deeply($d->channels, [], 'reset clears all stations');
        }
    }
    if ($case->[0] == 1050) { $mixed = \@mix }
}
my $cw       = Ham::RTTY->new(sample_rate => 8000);
my $stations = $cw->decode_samples_channels($mixed, wpm => 20);
is_deeply([map { $_->text } @{$stations}], ['SOS', 'CQ'], 'sample facade exposes all stations');
my $root = tempdir(CLEANUP => 1);
my $path = "$root/two.wav";
Ham::RTTY::Audio->new->write_file($path, $mixed, sample_rate => 8000);
my $from_path = $cw->read_wav_channels($path, wpm => 20);
is_deeply([map { $_->text } @{$from_path}], ['SOS', 'CQ'], 'WAV path facade exposes all stations');
open my $wav, '<:raw', $path or die $!;
is_deeply(
    [map { $_->text } @{$cw->decode_wav_channels($wav, wpm => 20)}],
    ['SOS', 'CQ'],
    'WAV handle facade exposes all stations'
);
close $wav or die $!;

for my $json (0, 1) {
    open my $stdin,  '<', \my $empty  or die $!;
    open my $stdout, '>', \my $output or die $!;
    open my $stderr, '>', \my $errors or die $!;
    my $status = Ham::RTTY::_Internal::CLI::run(
        ['receive', '--all-stations', '--wpm', '20', $json ? '--json' : (), $path],
        $stdin, $stdout, $stderr);
    is($status, 0, 'CLI receives multiple stations');
    if ($json) {
        is_deeply(
            [map { $_->{text} } @{JSON::PP->new->decode($output)}],
            ['SOS', 'CQ'],
            'CLI JSON is an array of full results'
        );
    }
    else { is($output, "650 Hz: SOS\n1050 Hz: CQ\n", 'CLI labels each station with its frequency') }
}
for my $options (
    {filter_bandwidth => 19},
    {filter_bandwidth => 4000},
    {min_snr_db       => -1},
    {min_snr_db       => 41}
    )
{
    eval { $cw->detector(%{$options}) };
    is(ref($@) ? $@->code : "$@",
        'RTTY_E_ARGUMENT', 'invalid filter/acquisition settings are rejected');
}
done_testing;
