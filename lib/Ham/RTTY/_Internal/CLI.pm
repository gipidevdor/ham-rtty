package Ham::RTTY::_Internal::CLI;
use 5.020;
use strict;
use warnings;
use Encode       qw(encode decode FB_CROAK LEAVE_SRC);
use Getopt::Long ();
use IO::Handle   ();
use JSON::PP;
use File::Temp   qw(tempfile);
use Scalar::Util qw(blessed);
use Text::Wrap   ();
use Ham::RTTY;
use Ham::RTTY::_Internal::IO       qw(with_file write_bytes);
use Ham::RTTY::_Internal::Validate qw(fail integer);

my @ENCODING =
    qw(baud stop-bits variant usos lenient leading-idle trailing-idle max-segments max-input-bytes);
my %COMMANDS = (
    encode => [@ENCODING],
    bits   => [@ENCODING],
    decode => [qw(baud variant usos max-segments max-input-bytes)],
    events => [@ENCODING, 'sample-rate'],
    wav    => [
        @ENCODING,
        qw(mark shift reverse sample-rate amplitude backend bits block-size max-bytes max-samples)
    ],
    midi    => [@ENCODING, qw(mark-note space-note velocity channel program bpm ppqn max-bytes)],
    receive => [
        qw(mark shift reverse baud variant usos atc search backend stereo max-frames max-segments min-frequency max-frequency frequency-step max-bytes block-samples json strict)
    ],
);
my %FLAGS        = map { $_ => 1 } qw(help version overwrite reverse lenient search json strict);
my %DESCRIPTIONS = (
    baud              => 'Configured baud, 20..300 (default: 45.45; no auto baud).',
    'stop-bits'       => 'Stop duration in bits: 1, 1.5 (default), or 2.',
    variant           => 'Alphabet: ita2 (default) or us.',
    usos              => 'Unshift on space: 1 (default) or 0.',
    lenient           => 'Substitute unsupported characters with ? and report a warning.',
    'leading-idle'    => 'Leading MARK seconds, 0..60 (default: 0.1).',
    'trailing-idle'   => 'Trailing MARK seconds, 0..60 (default: 0.1).',
    mark              => 'MARK frequency, 300..3000 Hz (default: 2125).',
    shift             => 'Positive frequency separation (default: 170 Hz).',
    reverse           => 'Swap MARK and SPACE tones.',
    atc               => 'Automatic threshold correction: 1 (default) or 0.',
    search            => 'Acquire a tone pair at the configured shift.',
    'sample-rate'     => 'Samples/second, 1000..384000 (default: 16000).',
    amplitude         => 'Normalized peak amplitude, 0..1 (default: 0.8).',
    backend           => 'perl (default), pdl or auto by availability.',
    bits              => 'PCM depth: 8, 16 (default) or 24.',
    'block-size'      => 'Generated block size (default: 4096).',
    'block-samples'   => 'WAV input block size (default: 4096).',
    'max-samples'     => 'Generation sample ceiling (default: 10000000).',
    'max-input-bytes' => 'Text byte ceiling, 1..1048576 (default: 8192).',
    'max-bytes'       => 'WAV byte ceiling (default: 64000000); MIDI: 8000000.',
    'max-frames'      => 'Retained feature ceiling (default: 200000).',
    'max-segments'    => 'Retained run ceiling (default: 100000).',
    'mark-note'       => 'MARK MIDI note, 0..127 (default: 77).',
    'space-note'      => 'SPACE MIDI note, 0..127 (default: 79).',
    velocity          => 'MIDI velocity, 1..127 (default: 100).',
    channel           => 'MIDI channel, 1..16 (default: 1).',
    program           => 'Zero-based MIDI program, 0..127 (default: 80).',
    bpm               => 'MIDI tempo, 4..1000 (default: 120).',
    ppqn              => 'MIDI ticks per quarter, 1..32767 (default: 480).',
    stereo            => 'Stereo input: mix (default), left or right.',
    'min-frequency'   => 'Search minimum MARK in Hz (default: 300).',
    'max-frequency'   => 'Search maximum MARK (default: 3000 minus shift).',
    'frequency-step'  => 'Search grid spacing, 1..500 Hz (default: 10).',
    json              => 'Write the complete reception Result as JSON.',
    strict            => 'Exit 1 if reception reports any warning.',
);

sub _bytes {
    my ($text) = @_;
    return encode('UTF-8', $text, FB_CROAK | LEAVE_SRC);
}

sub _write {
    my ($handle, $bytes) = @_;
    write_bytes($handle, $bytes);
    $handle->flush or fail('RTTY_E_IO', 'Cannot flush output');
    return;
}

sub _help_options {
    my ($command) = @_;
    my $text      = '';
    my %available = map { $_ => 1 } @{$COMMANDS{$command}};
    my @groups    = (
        ['Results',         qw(json strict)],
        ['Timing and tone', qw(baud stop-bits mark shift reverse leading-idle trailing-idle)],
        ['Text',            qw(variant usos lenient)],
        ['WAV format',      qw(sample-rate bits amplitude)],
        ['MIDI instrument and timing', qw(mark-note space-note velocity channel program bpm ppqn)],
        ['Processing',                 qw(backend stereo atc)],
        ['Tone search',                qw(search min-frequency max-frequency frequency-step)],
        [
            'Limits and buffering',
            qw(max-input-bytes max-bytes max-samples max-frames max-segments block-size block-samples)
        ],
    );
    my %units = (
        backend => 'perl|pdl|auto',
        variant => 'ita2|us',
        usos    => '0|1',
        atc     => '0|1',
        bits    => '8|16|24'
    );
    my %descriptions = %DESCRIPTIONS;
    my $headings     = {};

    for my $group (@groups) {
        my ($title, @names) = @{$group};
        @names = grep { $available{$_} } @names;
        next unless @names;
        $title = $headings->{$title} // $title;
        $text .= "\n$title:\n";
        for my $name (@names) {
            local $Text::Wrap::columns  = 78;
            local $Text::Wrap::unexpand = 0;
            my $label       = "--$name" . ($FLAGS{$name} ? '' : ' ' . ($units{$name} // 'N'));
            my $description = $descriptions{$name};
            my $prefix      = sprintf '  %-27s ', $label;
            $text .= Text::Wrap::wrap($prefix, ' ' x length($prefix), $description) . "\n";
        }
    }
    return $text;
}

sub _help {
    my ($command) = @_;
    my %examples = (
        encode  => 'ham-rtty encode "CQ TEST"',
        decode  => 'ham-rtty decode "[LTRS] 00011"',
        bits    => 'ham-rtty bits "CQ TEST"',
        events  => 'ham-rtty events --baud 50 "SOS"',
        wav     => 'ham-rtty wav --baud 50 --output practice.wav "CQ TEST"',
        midi    => 'ham-rtty midi --output practice.mid "CQ TEST"',
        receive => 'ham-rtty receive --mark 2125 --baud 50 recording.wav',
    );
    my $text;
    if (defined $command) {
        my $input  = $command eq 'receive'                   ? '[FILE]'         : '[TEXT ...]';
        my $output = $command eq 'wav' || $command eq 'midi' ? ' --output FILE' : '';
        $text = "Usage: ham-rtty $command [OPTIONS]$output $input\n\n";
        $text .= "Example:\n  $examples{$command}\n";
        $text .= _help_options($command);
    }
    else {
        $text = <<'HELP';
Usage: ham-rtty COMMAND [OPTIONS] [TEXT ...]
       ham-rtty receive [OPTIONS] [FILE]

RTTY, from text to signal and back.

Commands:
  encode   Text to ITA2 codes.
  decode   ITA2 codes and shift markers to text.
  bits     Framed transmission bits.
  events   Timed MARK/SPACE events as JSON.
  wav      Text to a PCM WAV file.
  midi     Text to a standard MIDI file.
  receive  Recorded PCM WAV to text.

Start here:
  ham-rtty encode "CQ TEST"
  ham-rtty wav --output practice.wav "CQ TEST"
  ham-rtty receive --mark 2125 --baud 50 practice.wav

Run ham-rtty help COMMAND for options and an example.
HELP
    }
    $text .= <<'HELP';

Common options:
  -i, --input FILE            Read a file; - reads stdin.
  -o, --output FILE           Write a file; - writes stdout.
  --overwrite                 Replace an existing output file deliberately.
  -h, --help                  Show help.
  --version                   Show the distribution version.
HELP
    if (defined($command) && $command eq 'receive') {
        $text .=
            "\nOmit FILE or use - to read WAV from stdin (temporary file; --max-bytes limit).\n";
        $text .= "Inspect reception warnings even when text is present; --json includes them.\n";
    }
    else {
        $text .= "\nText is UTF-8. Omit TEXT to read stdin, or use --input FILE.\n";
        $text .= "Use -- before text beginning with a dash. Quote punctuation and shift markers.\n";
    }
    $text .= "Existing output files are protected; use --overwrite to replace them.\n";
    $text .= "WAV and MIDI require --output FILE; binary stdout requires --output -.\n"
        if !defined $command;
    $text .= "Use --output FILE to save the file, or --output - for binary stdout.\n"
        if defined($command) && ($command eq 'wav' || $command eq 'midi');
    $text .= <<'HELP';
Diagnostics use stderr. Text and JSON default to stdout.

Exit codes:
  0  Success.
HELP
    $text .= "  1  No received text, or reception warnings with --strict.\n"
        if !defined($command) || $command eq 'receive';
    $text .= <<'HELP';
  2  Invalid usage or options.
  3  Input, output or processing error.
  4  Unexpected internal error.
HELP
    return $text;
}

sub _options {
    my ($command, $arguments) = @_;
    my (%options, @specification, $duplicate);
    for my $name (qw(input output overwrite help version), @{$COMMANDS{$command}}) {
        my $spec = $name;
        $spec .= '|i' if $name eq 'input';
        $spec .= '|o' if $name eq 'output';
        $spec .= '|h' if $name eq 'help';
        $spec .= $FLAGS{$name} ? '' : '=s';
        my $key = $name;
        $key =~ tr/-/_/;
        push @specification, $spec => sub {
            $duplicate //= $name if exists $options{$key};
            $options{$key} = $_[1];
        };
    }
    my $parser = Getopt::Long::Parser->new(
        config => [qw(no_auto_abbrev no_ignore_case no_getopt_compat permute)]);
    my @warnings;
    my $ok;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        $ok = $parser->getoptionsfromarray($arguments, @specification);
    }
    if (!$ok) {
        my $message = join '', @warnings;
        $message =~ s/\s+\z//x;
        fail('RTTY_E_ARGUMENT', $message || 'Invalid options');
    }
    fail('RTTY_E_ARGUMENT', "Duplicate option: --$duplicate") if defined $duplicate;
    return \%options;
}

sub _copy {
    my ($input, $limit, $consume) = @_;
    my $total = 0;
    while (1) {
        my $size = $limit - $total + 1;
        $size = 65536 if $size > 65536;
        my $count = read($input, my $block, $size);
        fail('RTTY_E_IO', 'Cannot read input') unless defined $count;
        last                                   unless $count;
        $total += $count;
        fail('RTTY_E_RESOURCE', 'Input exceeds its configured byte limit') if $total > $limit;
        $consume->($block);
    }
    return;
}

sub _unicode {
    my ($bytes) = @_;
    my $text;
    my $ok = eval {
        $text = utf8::is_utf8($bytes) ? $bytes : decode('UTF-8', $bytes, FB_CROAK | LEAVE_SRC);
        _bytes($text);
        1;
    };
    fail('RTTY_E_SYMBOL', 'Text input must be valid UTF-8') unless $ok;
    return $text;
}

sub _text {
    my ($arguments, $options, $stdin) = @_;
    my $limit = integer('max_input_bytes', delete($options->{max_input_bytes}) // 8192, 1, 1048576);
    my $path  = delete $options->{input};
    fail('RTTY_E_ARGUMENT', 'Use positional text or --input, not both')
        if defined($path) && @{$arguments};
    my $text;
    if (@{$arguments}) {
        $text = join ' ', map { _unicode($_) } @{$arguments};
        fail('RTTY_E_RESOURCE', 'Input exceeds its configured byte limit')
            if length(_bytes($text)) > $limit;
    }
    else {
        my $bytes = '';
        my $read  = sub {
            _copy($_[0], $limit, sub { $bytes .= $_[0] });
        };
        if (defined($path) && $path ne '-') { with_file($path, 'read', $read) }
        else                                { $read->($stdin) }
        $text = _unicode($bytes);
    }
    $text =~ s/\A\x{feff}//x;
    return $text;
}

sub _receive {
    my ($arguments, $options, $stdin) = @_;
    my $path = delete $options->{input};
    fail('RTTY_E_ARGUMENT', 'Use one WAV path or --input, not both')
        if @{$arguments} > 1 || (defined($path) && @{$arguments});
    $path //= $arguments->[0] // '-';
    my $rtty = Ham::RTTY->new;
    return $rtty->read_wav($path, %{$options}) if $path ne '-';
    my $audio = Ham::RTTY::Audio->new(
        exists($options->{max_bytes}) ? (max_bytes => $options->{max_bytes}) : ());
    my ($temporary) = eval { tempfile('ham-rtty-stdin-XXXXXX', TMPDIR => 1, UNLINK => 1) };
    fail('RTTY_E_IO', 'Cannot create temporary WAV input') unless $temporary;
    binmode $temporary, ':raw' or fail('RTTY_E_IO', 'Cannot set temporary input mode');
    _copy($stdin, $audio->{max_bytes}, sub { write_bytes($temporary, $_[0]) });
    seek($temporary, 0, 0) or fail('RTTY_E_IO', 'Cannot rewind temporary input');
    return $rtty->decode_wav($temporary, %{$options});
}

sub _output {
    my ($path, $overwrite, $stdout, $action) = @_;
    if ($path eq '-') {
        $action->($stdout);
        $stdout->flush or fail('RTTY_E_IO', 'Cannot flush output');
    }
    else { with_file($path, 'write', $action, $overwrite) }
    return;
}

sub _receive_output {
    my ($result, $json, $strict, $stderr) = @_;
    my ($bytes, $status);
    my $all     = ref($result) eq 'ARRAY';
    my @results = $all ? @{$result} : ($result);
    $status = !(grep { $_->has_text } @results)
        || ($strict && (grep { $_->has_warnings } @results)) ? 1 : 0;
    $bytes =
        $json
        ? JSON::PP->new->utf8->canonical->pretty->encode(
        $all ? [map { $_->as_hash } @results] : $result->as_hash)
        : _bytes(
        join('', map { ($all ? $_->frequency . " Hz: " : '') . $_->text . "\n" } @results));
    if (!$json) {
        for my $station (@results) {
            _write($stderr, _bytes("$_->{code}: $_->{message}\n")) for @{$station->warnings};
        }
    }
    return ($bytes, $status);
}

sub _execute {
    my ($command, $arguments, $options, $streams) = @_;
    my ($stdin, $stdout, $stderr) = @{$streams}{qw(stdin stdout stderr)};
    my $explicit_output = exists $options->{output};
    my $path            = delete($options->{output})    // '-';
    my $overwrite       = delete($options->{overwrite}) // 0;
    fail('RTTY_E_ARGUMENT', '--overwrite requires a named output file')
        if $overwrite && $path eq '-';
    fail('RTTY_E_ARGUMENT', "$command requires --output FILE or --output -")
        if ($command eq 'wav' || $command eq 'midi') && !$explicit_output;
    my $json   = delete $options->{json};
    my $strict = delete $options->{strict};
    my ($bytes, $status) = ('', 0);

    if ($command eq 'receive') {
        my $result = _receive($arguments, $options, $stdin);
        ($bytes, $status) = _receive_output($result, $json, $strict, $stderr);
    }
    else {
        my $text = _text($arguments, $options, $stdin);
        my $rtty = Ham::RTTY->new;
        if ($command eq 'wav' || $command eq 'midi') {
            my $method = "generate_$command";
            _output($path, $overwrite, $stdout, sub { $rtty->$method($text, $_[0], %{$options}) });
            return 0;
        }
        if ($command eq 'events') {
            my $rate = delete $options->{sample_rate};
            my $events =
                defined($rate)
                ? $rtty->sampled_events($text, %{$options}, sample_rate => $rate)
                : $rtty->events($text, %{$options});
            $bytes = JSON::PP->new->utf8->canonical->pretty->encode($events);
        }
        else {
            if ($command eq 'encode' || $command eq 'bits') {
                my $encoder = $rtty->encoder(%{$options});
                $bytes = _bytes($encoder->$command($text) . "\n");
                _write($stderr, _bytes("$_->{code}: $_->{message}\n"))
                    for @{$encoder->result->warnings};
            }
            else { $bytes = _bytes($rtty->$command($text, %{$options}) . "\n") }
        }
    }
    _output($path, $overwrite, $stdout, sub { _write($_[0], $bytes) });
    return $status;
}

sub _dispatch {
    my ($arguments, $stdin, $stdout, $stderr) = @_;
    fail('RTTY_E_ARGUMENT', 'A command is required; use ham-rtty --help') unless @{$arguments};
    my $command = shift @{$arguments};
    if ($command eq '--version' && !@{$arguments}) {
        _write($stdout, "ham-rtty $Ham::RTTY::VERSION\n");
        return 0;
    }
    if ($command eq '--help' || $command eq '-h' || $command eq 'help') {
        my $topic = shift @{$arguments};
        fail('RTTY_E_ARGUMENT', 'Unknown help command or extra arguments')
            if @{$arguments} || (defined($topic) && !exists $COMMANDS{$topic});
        _write($stdout, _help($topic));
        return 0;
    }
    fail('RTTY_E_ARGUMENT', "Unknown command '$command'; use ham-rtty --help")
        unless exists $COMMANDS{$command};
    my $options = _options($command, $arguments);
    if (delete $options->{help})    { _write($stdout, _help($command));                  return 0 }
    if (delete $options->{version}) { _write($stdout, "ham-rtty $Ham::RTTY::VERSION\n"); return 0 }
    return _execute($command, $arguments, $options,
        {stdin => $stdin, stdout => $stdout, stderr => $stderr});
}

sub run {
    my ($arguments, $stdin, $stdout, $stderr) = @_;
    local $SIG{PIPE} = 'IGNORE' if exists $SIG{PIPE};
    my $status;
    my $ok = eval {
        binmode($_, ':raw')
            or fail('RTTY_E_IO', 'Cannot set standard stream mode')
            for $stdin, $stdout, $stderr;
        $status = _dispatch([@{$arguments}], $stdin, $stdout, $stderr);
        1;
    };
    return $status if $ok;
    my $error = $@;
    my ($code, $message) =
        blessed($error)
        && $error->isa('Ham::RTTY::Error')
        ? ($error->code, $error->message)
        : ('RTTY_E_INTERNAL', 'Unexpected command failure');
    $status = $code eq 'RTTY_E_ARGUMENT' ? 2 : $code eq 'RTTY_E_INTERNAL' ? 4 : 3;
    my $hint = '';
    if ($code eq 'RTTY_E_ARGUMENT') {
        my $command = $arguments->[0] // '';
        $hint =
            exists($COMMANDS{$command})
            ? "Try: ham-rtty help $command\n"
            : "Try: ham-rtty --help\n";
    }
    eval { _write($stderr, _bytes("ham-rtty: $code: $message\n$hint")); 1 } or return 3;
    return $status;
}
1;
