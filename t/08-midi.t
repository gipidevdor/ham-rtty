use strict;
use warnings;
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Events qw(to_samples);

# A minimal independent SMF reader for the exact event types this exporter emits.
sub vlq {
    my ($bytes, $offset) = @_;
    my $value = 0;
    for (1 .. 4) {
        my $byte = unpack('C', substr($bytes, $$offset, 1));
        ++$$offset;
        $value = ($value << 7) | ($byte & 127);
        return $value unless $byte & 128;
    }
    die 'Invalid VLQ';
}

sub parse {
    my ($bytes, $expected_tempo) = @_;
    $expected_tempo //= 500000;
    my ($magic, $header, $format, $tracks, $division, $track, $size) = unpack('a4Nnnna4N', $bytes);
    is($magic,  'MThd',              'MIDI header');
    is($header, 6,                   'header length');
    is($format, 0,                   'type 0');
    is($tracks, 1,                   'one track');
    is($track,  'MTrk',              'track chunk');
    is($size,   length($bytes) - 22, 'track byte length');
    my ($offset, $time) = (22, 0);
    my @notes;

    while ($offset < length $bytes) {
        $time += vlq($bytes, \$offset);
        my $status = unpack('C', substr($bytes, $offset++, 1));
        if ($status == 255) {
            my $type   = unpack('C', substr($bytes, $offset++, 1));
            my $length = vlq($bytes, \$offset);
            if ($type == 81) {
                is(unpack('N', "\0" . substr($bytes, $offset, 3)),
                    $expected_tempo, 'tempo microseconds per quarter');
            }
            $offset += $length;
            last if $type == 47;
        }
        elsif (($status & 240) == 192) { ++$offset }
        else {
            my ($note, $velocity) = unpack('CC', substr($bytes, $offset, 2));
            $offset += 2;
            push @notes, [$time, $status, $note, $velocity];
        }
    }
    is($offset, length($bytes), 'end-of-track ends file');
    return (\@notes, $time, $division);
}
my $events = {
    unit     => 'us',
    segments => [
        {state => 'off', duration => 100000},
        {state => 'on',  duration => 60000},
        {state => 'off', duration => 60000},
        {state => 'on',  duration => 180000},
        {state => 'off', duration => 100000},
    ]
};
my $midi = Ham::RTTY::MIDI->new;
my ($notes, $time, $division) = parse($midi->encode($events));
is($division, 480, 'PPQN');
is($time,     480, 'trailing silence retained');
is_deeply(
    $notes,
    [[96, 144, 77, 100], [154, 128, 77, 0], [211, 144, 77, 100], [384, 128, 77, 0]],
    'cumulative note timing'
);
is(
    $midi->encode($events),
    $midi->encode(to_samples($events, 16000)),
    'sampled events encode equivalently'
);
my $bytes = '';
open my $fh, '>', \$bytes or die $!;
my $length = Ham::RTTY->new->generate_midi('SOS', $fh);
close $fh;
is($length, length $bytes, 'facade bytes written');
($notes) = parse($bytes);
is(scalar @{$notes}, 18, 'nine keyed notes in SOS');
my $configured = Ham::RTTY::MIDI->new(channel => 3, note => 60, velocity => 50, program => 10);
($notes) = parse($configured->encode($events));
is_deeply($notes->[0], [96, 146, 60, 50], 'channel, pitch and velocity');
my ($empty, $end) = parse($midi->encode({unit => 'us', segments => []}));
is_deeply($empty, [], 'empty MIDI');
is($end, 0, 'empty duration');

for my $args (
    {note     =>  128},
    {velocity =>  0},
    {channel  =>  17},
    {program  => -1},
    {bpm      =>  0},
    {ppqn     => 32768},
    {typo     => 1}
    )
{
    eval { Ham::RTTY::MIDI->new(%{$args}) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'invalid MIDI option');
}
eval { Ham::RTTY::MIDI->new(max_bytes => 64)->encode(Ham::RTTY->new->events('SOS SOS')) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'MIDI size bound');
eval { $midi->encode({unit => 'us', segments => [{state => 'on', duration => 1}]}) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_TIMING', 'zero tick note rejected');
eval { $midi->encode({unit => 'us', segments => [{state => 'off', duration => 2**52}]}) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_TIMING', 'delta overflow rejected');
for my $case ([1624, 32], [1625, 33], [1626, 33]) {
    ($notes, $time) = parse(
        $midi->encode(
            {
                sample_rate => 48000,
                segments    => [{state => 'on', samples => $case->[0]}]
            }
        )
    );
    is($notes->[1][0], $case->[1], 'sample boundary rounds once to a MIDI tick');
    is($time,          $case->[1], 'sample boundary and end-of-track agree');
}
($notes, $time) = parse(
    $midi->encode(
        {
            sample_rate => 48000,
            segments    => [
                {state => 'off', samples => 1625},
                {state => 'on',  samples => 1625},
                {state => 'off', samples => 1625}
            ]
        }
    )
);
is_deeply([map { $_->[0] } @{$notes}], [33, 65], 'sampled leading silence uses cumulative ticks');
is($time, 98, 'sampled trailing silence uses cumulative ticks');
($notes) = parse(
    Ham::RTTY::MIDI->new(ppqn => 32767, bpm => 1000)->encode(
        {
            sample_rate => 384000,
            segments    => [{state => 'on', samples => 1}]
        }
    ),
    60000
);
is($notes->[1][0], 1, 'one sample avoids intermediate microsecond quantization');
done_testing;
