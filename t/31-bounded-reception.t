use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Symbol qw(gensym);
use Ham::RTTY;
use Ham::RTTY::_Internal::Backend;
use lib 't/lib';
use FaultHandle;
my @backends = ('perl');
push @backends, 'pdl' if Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl';
my $rtty     = Ham::RTTY->new(sample_rate => 16000);
my $message  = 'CQ TEST 73';
my $known    = $rtty->samples($message);
my $prefix   = $rtty->samples('CQ',     mark => 1900);
my $other    = $rtty->samples($message, mark => 2300);
my @changing = (@{$prefix}[0 .. 7999], @{$other});

for my $backend (@backends) {
    for my $size (137, 4096, scalar @{$known}) {
        my $receiver = $rtty->detector(backend => $backend);
        feed_chunks($receiver, $known, $size);
        is($receiver->finish->text, $message, "$backend known tones, incoming block $size");
        is(
            $receiver->finish->diagnostics->{analyzed_samples},
            scalar @{$known},
            'every sample is retained in the analysis count'
        );
    }
    my $previous;
    for my $size (137, 4096, scalar @changing) {
        my $receiver = $rtty->detector(backend => $backend, search => 1);
        feed_chunks($receiver, \@changing, $size);
        my $result = $receiver->finish;
        is($result->frequency, 1900, "$backend acquires only the initial half second, block $size");
        is($result->text, $previous, 'tone acquisition and decoded output are block independent')
            if defined $previous;
        $previous = $result->text;
    }
}

if (grep { $_ eq 'pdl' } @backends) {
    my $projection = \&Ham::RTTY::_Internal::PDL::powers;
    my $largest    = 0;
    {
        no warnings 'redefine';
        local *Ham::RTTY::_Internal::PDL::powers = sub {
            my ($values, $tones) = @_;
            my $cells = @{$values} * @{$tones};
            $largest = $cells if $cells > $largest;
            return $projection->(@_);
        };
        my $receiver = $rtty->detector(backend => 'pdl', search => 1);
        $receiver->feed($prefix);
        is($receiver->finish->text, 'CQ', 'bounded native projections preserve reception');
    }
    cmp_ok($largest, '>',  0,     'optional backend actually uses native projections');
    cmp_ok($largest, '<=', 65536, 'native projection allocation geometry stays bounded');
}

my $wav = $rtty->wav_bytes($message);
for my $limit (qw(max_frames max_segments)) {
    my $handle = gensym();
    tie *{$handle}, 'FaultHandle',
        bytes => $wav,
        fail  => {read => 5};
    eval { $rtty->decode_wav($handle, $limit => 1) };
    is(ref($@) ? $@->code : "$@",        'RTTY_E_RESOURCE', "$limit is checked before PCM reads");
    is((tied *{$handle})->{calls}{read}, 4, 'only RIFF and format headers were read');
}
done_testing;

sub feed_chunks {
    my ($receiver, $values, $size) = @_;
    for (my $offset = 0; $offset < @{$values}; $offset += $size) {
        my $end = $offset + $size - 1;
        $end = $#{$values} if $end > $#{$values};
        $receiver->feed([@{$values}[$offset .. $end]]);
    }
    return;
}
