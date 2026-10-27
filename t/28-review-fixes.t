use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;

# More repeated short marks must not remove the longer timing evidence.
my @estimates;
for my $count (31, 32, 100) {
    my @marks = ((40000) x $count, (45000) x 20, (140000) x 30);
    my ($dot) = Ham::RTTY::Decoder::_estimate_dot([map { +{state => 'on', duration => $_} } @marks]);
    push @estimates, $dot;
}
cmp_ok(abs($estimates[1] - $estimates[0]), '<', 1000,  'timing has no 32-mark discontinuity');
cmp_ok($estimates[2],                      '>', 45000, 'long-message timing retains dash evidence');

# This schedule is independent of the project encoder and generator.
sub independent_sos {
    my ($speed, $ramp_ms) = @_;
    my $rate  = 8000;
    my $unit  = $rate * 1.2 / $speed;
    my $words = 12;
    my @runs  = ([0, 3]);
    for my $word (1 .. $words) {
        for my $letter (0 .. 2) {
            push @runs, [0, 3] if $letter;
            for my $mark (0 .. 2) {
                push @runs, [0, 1] if $mark;
                push @runs, [1, $letter == 1 ? 3 : 1];
            }
        }
        push @runs, [0, 7] if $word < $words;
    }
    push @runs, [0, 3];
    my (@out, $position);
    $position = 0;
    my $pi = 4 * atan2(1, 1);
    for my $run (@runs) {
        my $length = int($unit * $run->[1] + 0.5);
        my $ramp   = $rate * $ramp_ms / 1000;
        for my $offset (0 .. $length - 1) {
            my $gain = 1;
            $gain *= 0.5 * (1 - cos($pi * $offset / $ramp)) if $ramp && $offset < $ramp;
            my $remaining = $length - 1 - $offset;
            $gain *= 0.5 * (1 - cos($pi * $remaining / $ramp)) if $ramp && $remaining < $ramp;
            push @out, $run->[0] * $gain * 0.6 * sin(2 * $pi * 650 * $position++ / $rate);
        }
    }
    return \@out;
}
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };
for my $backend (@backends) {
    for my $case ([25, 0], [50, 0], [25, 5], [50, 5]) {
        my ($speed, $ramp_ms) = @{$case};
        my $samples = independent_sos($speed, $ramp_ms);
        my $d = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, backend => $backend);
        for (my $i = 0; $i < @{$samples}; $i += 4096) {
            my $end = $i + 4095;
            $end = $#{$samples} if $end > $#{$samples};
            $d->feed([@{$samples}[$i .. $end]]);
        }
        my $r = $d->finish;
        is(
            $r->text,
            join(' ', ('SOS') x 12),
            "$backend independent message at $speed WPM, ramp $ramp_ms ms"
        );
        cmp_ok(abs($r->wpm - $speed), '<', $speed * 0.05, 'speed estimate within five percent');
        ok(!grep($_->{code} eq 'RTTY_W_SPACING_AMBIGUOUS', @{$r->warnings}),
            'ordinary word gaps do not suggest Farnsworth');
    }
}
my $cw   = Ham::RTTY->new(sample_rate => 8000);
my $root = tempdir(CLEANUP => 1);
my $path = File::Spec->catfile($root, 'permissions.wav');
$cw->write_wav('SOS', $path);
$cw->write_wav('CQ TEST', $path, overwrite => 1);
SKIP: {
    skip 'POSIX permission bits are not portable on Windows', 1 if $^O eq 'MSWin32';
    chmod 0644, $path or die $!;
    $cw->write_wav('CQ TEST', $path, overwrite => 1);
    is((stat($path))[2] & 0777, 0644, 'atomic overwrite preserves permissions');
}
my $link = File::Spec->catfile($root, 'linked.wav');
SKIP: {
    skip 'symbolic links unavailable', 3 unless eval { symlink($path, $link) };
    eval { $cw->write_wav('TEST', $link, overwrite => 1) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'overwrite rejects symlink destinations');
    ok(-l $link, 'overwrite preserves the symbolic link');
    is($cw->read_wav($path)->text, 'CQ TEST', 'symlink target remains unchanged');
}
my $decoder = Ham::RTTY::Decoder->new(wpm => 20);
$decoder->feed({unit => 'us', segments => [{state => 'on', duration => 30000}]});
my $before = $decoder->result;
$decoder->feed({unit => 'us', segments => [{state => 'on', duration => 30000}]});
is($before->events->{segments}[0]{duration}, 30000, 'old snapshot survives a coalescing feed');
is($decoder->result->events->{segments}[0]{duration}, 60000,
    'new snapshot includes coalesced mark');

my $fresh = File::Spec->catfile($root, 'new-overwrite.wav');
$cw->write_wav('SOS', $fresh, overwrite => 1);
is($cw->read_wav($fresh)->text, 'SOS', 'overwrite permits a new regular destination');
my @temporary = glob(File::Spec->catfile($root, '.ham-rtty-*'));
is_deeply(\@temporary, [], 'replacement leaves no temporary files');

SKIP: {
    skip 'POSIX umask permissions unavailable on Windows', 1 if $^O eq 'MSWin32';
    my $new_path = File::Spec->catfile($root, 'umask.wav');
    my $previous = umask oct('0027');
    my $ok       = eval { $cw->write_wav('SOS', $new_path, overwrite => 1); 1 };
    my $error    = $@;
    umask $previous;
    die $error unless $ok;
    is((stat($new_path))[2] & 0777, 0640, 'new replacement respects umask');
}
my $dangling = File::Spec->catfile($root, 'dangling.wav');
SKIP: {
    skip 'symbolic links unavailable', 2 unless eval { symlink('missing.wav', $dangling) };
    eval { $cw->write_wav('TEST', $dangling, overwrite => 1) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'dangling link rejected');
    ok(-l $dangling, 'dangling link preserved');
}
eval { $cw->write_wav('SOS', $root, overwrite => 1) };
is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'directory replacement rejected');
{
    open my $append, '>>:raw', $fresh or die $!;
    print {$append} 'trailing' or die $!;
    close $append              or die $!;
}
my $callbacks = 0;
my $metadata  = Ham::RTTY::Audio->new(block_samples => 137)->read_blocks(
    $fresh,
    sub {
        my ($block, $info) = @_;
        if (++$callbacks <= 2) {
            is(scalar @{$info->{warnings}}, 1, 'callback warning list is independent');
            is($info->{warnings}[0]{code},
                'RTTY_W_WAV_TRAILING', 'nested callback warning is independent');
        }
        $info->{warnings}[0]{code} = 'changed';
        push @{$info->{warnings}}, {code => 'extra', message => 'caller mutation'};
    }
);
is($metadata->{warnings}[0]{code}, 'RTTY_W_WAV_TRAILING', 'returned metadata preserves warning');
my @varied;
for my $i (0 .. 99) {
    push @varied, {state => 'on', duration => 60000 + $i - 50},
        {state => 'on', duration => 180000 + $i - 50};
}
my ($fitted) = Ham::RTTY::Decoder::_estimate_dot(\@varied);
cmp_ok(abs($fitted - 60000), '<', 100, 'bounded candidates cover a wide set of distinct widths');

my $invalid =
    {unit => 'us', segments => [{state => 'on', duration => 60000, extra => sub { return }}]};
my $validated = Ham::RTTY::Decoder->new(wpm => 20);
$validated->feed($invalid);
is_deeply(
    $validated->result->events->{segments},
    [{state => 'on', duration => 60000}],
    'only validated canonical fields are retained; unsafe metadata is ignored'
);
is($validated->state, 'ACTIVE', 'unrelated metadata does not prevent canonical decoding');
done_testing;
