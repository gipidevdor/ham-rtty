use strict;
use warnings;
use Test::More;
use Config;
use File::Temp qw(tempfile);
use Ham::RTTY;
use lib 't/lib';
use Reference qw(reference_sos);

sub argument_error {
    my ($class, $arguments, $label) = @_;
    eval { $class->new(@{$arguments}) };
    my $error = $@;
    is(ref($error) ? $error->code : "$error", 'RTTY_E_ARGUMENT', $label);
}

for my $arguments (
    [warnings    => undef],
    [warnings    => {}],
    [warnings    => [undef]],
    [warnings    => [{code => [], message => 'bad'}]],
    [warnings    => [{code => 'RTTY_W_TEST'}]],
    [diagnostics => []],
    [diagnostics => {callback => sub { return }}],
    [events      => undef],
    [events      => {unit => undef, segments => []}],
    [events      => {unit => 'us',  segments => [{state => 'on', duration => 0}]}],
    [text        => []],
    [text        => undef],
    [morse       => {}],
    [morse       => undef],
    [frequency   => []],
    [frequency   => -1],
    [wpm         => {}],
    [wpm         => 'NaN'],
    [complete    => undef],
    [complete    => 2]
    )
{
    argument_error('Ham::RTTY::Result', $arguments, 'invalid result payload is structured');
}
for my $arguments (
    [context => undef],
    [context => 'bad'],
    [context => []],
    [context => {callback => sub { return }}],
    [code    => []],
    [code    => undef],
    [message => {}],
    [message => undef],
    [typo    => 1],
    [code    => 'A', code => 'B'],
    ['code'],
    [undef, 'A'],
    [[],    'A']
    )
{
    argument_error('Ham::RTTY::Error', $arguments, 'invalid exception payload is structured');
}
my $cyclic = {};
$cyclic->{self} = $cyclic;
my $deep = {};
$deep = {child => $deep} for 1 .. 66;
for my $payload ($cyclic, $deep, {object => bless({}, 'Local::Payload')}) {
    argument_error('Ham::RTTY::Error',  [context     => $payload], 'unsafe context rejected');
    argument_error('Ham::RTTY::Result', [diagnostics => $payload], 'unsafe diagnostics rejected');
}
delete $cyclic->{self};
my $shared  = {values => [1, undef, 'two']};
my $context = {left   => $shared, right => $shared};
my $error   = Ham::RTTY::Error->new(code => 'RTTY_E_TEST', message => 'test', context => $context);
my $result  = Ham::RTTY::Result->new(diagnostics => $context);
$shared->{values}[0] = 99;
is($error->context->{left}{values}[0],       1, 'exception copies shared input data');
is($result->diagnostics->{right}{values}[0], 1, 'result copies shared input data');
my $copy = $error->context;
$copy->{left}{values}[0] = 88;
is($error->context->{left}{values}[0], 1,               'exception accessor copies nested data');
is(Ham::RTTY::Error->new->code,          'RTTY_E_INTERNAL', 'exception defaults remain valid');

my $decoder = Ham::RTTY::Decoder->new(wpm => 20, max_segments => 1);
my $half    = {unit => 'us', segments => [{state => 'on', duration => 30000}]};
$decoder->feed($half);
ok(eval { $decoder->feed($half); 1 }, 'coalescing at segment cap is accepted');
is($decoder->result->events->{segments}[0]{duration}, 60000, 'split mark is coalesced');
is($half->{segments}[0]{duration},                    30000, 'coalescing preserves caller input');
my $before = $decoder->result->as_hash;
eval { $decoder->feed({unit => 'us', segments => [{state => 'off', duration => 60000}]}) };
is(ref($@) ? $@->code : "$@", 'RTTY_E_RESOURCE', 'new canonical segment still respects cap');
is_deeply($decoder->result->as_hash, $before, 'rejected feed preserves snapshot');
is($decoder->finish->text, 'E', 'rejected feed preserves final decoding');

for my $rate (1400, 1401, 1402) {
    my $generator = eval { Ham::RTTY::Generator->new(sample_rate => $rate) };
    ok($generator, "valid tone defaults at $rate Hz");
    ok($generator && @{$generator->generate(Ham::RTTY->new->events('E'))},
        "default tone generates at $rate Hz");
}

# Detect termination by SIGPIPE in a separate Perl process, with real OS pipes.
SKIP: {
    skip 'SIGPIPE is not available on this platform', 3
        unless $Config{sig_name} =~ /\bPIPE\b/x;
    my $program = <<'CHILD';
use strict;
use warnings;
use IO::Handle;
use Ham::RTTY;
$SIG{PIPE} = 'DEFAULT';
pipe(my $reader, my $writer) or die $!;
$writer->autoflush(1);
my $audio = Ham::RTTY::Audio->new->writer($writer, sample_count => 1);
close $reader or die $!;
eval { $audio->feed([0]) };
print ref($@) ? $@->code : "$@", " ", $audio->state, "\n";
eval { Ham::RTTY::MIDI->new->write($writer, {unit => 'us', segments => []}) };
print ref($@) ? $@->code : "$@", "\n";
print $SIG{PIPE}, "\n";
{
    local $SIG{PIPE} = 'IGNORE';
    close $writer;
}
CHILD

    # A script file avoids platform-specific quoting of multiline -e arguments.
    my ($source, $path) =
        tempfile('ham-rtty-pipe-test-XXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1);
    print {$source} $program or die $!;
    close $source            or die $!;
    open my $child, '-|', $^X, '-Ilib', $path or die $!;
    my $output = do { local $/; <$child> };
    close $child;
    my $status = $?;
    is($status & 127, 0, 'closed pipe does not terminate process with a signal');
    is($status >> 8,  0, 'pipe failure remains catchable');
    is(
        $output,
        "RTTY_E_IO FAILED\nRTTY_E_IO\nDEFAULT\n",
        'WAV and MIDI return I/O errors and restore signal disposition'
    );
}

# Rising zero crossings measure the fixture's actual frequency independently.
my $samples = reference_sos(rate => 48000, drift => 2, amplitude => 1);
my @crossings;
for my $i (1 .. $#{$samples}) {
    next unless $samples->[$i - 1] < 0 && $samples->[$i] > 0;
    push @crossings, $i - 1 - $samples->[$i - 1] / ($samples->[$i] - $samples->[$i - 1]);
}
my @frequencies;
for my $i (1 .. $#crossings) {
    my $period = $crossings[$i] - $crossings[$i - 1];
    push @frequencies, 48000 / $period if $period < 100;
}
ok(@frequencies > 500, 'frequency bound uses hundreds of complete tone cycles');
my @outside = grep { $_ < 647.9 || $_ > 652.1 } @frequencies;
is_deeply(\@outside, [], 'declared 2 Hz drift stays within its frequency bounds');
done_testing;
