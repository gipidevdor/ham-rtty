#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Symbol qw(gensym);
use Ham::RTTY;
use Ham::RTTY::Audio;
use Ham::RTTY::Error;

sub expected_error {
    my ($code, $action) = @_;
    my $ok    = eval { $action->(); 1 };
    my $error = $@;
    croak "Expected $code" if $ok;
    croak "Unexpected exception: $error" unless ref($error) && $error->isa('Ham::RTTY::Error');
    croak "Expected $code, received " . $error->code unless $error->code eq $code;
    print $error->as_string, "\n";
    return $error;
}
my $backend = shift @ARGV // 'perl';
my $rtty    = Ham::RTTY->new(baud => 50, sample_rate => 8000, mark => 650, backend => $backend);
expected_error('RTTY_E_ARGUMENT', sub { Ham::RTTY->new(baud => 0) });
expected_error('RTTY_E_ARGUMENT', sub { Ham::RTTY->new(baud => 50, backend => 'unsupported') });
my $pdl_ready = eval { Ham::RTTY->new(baud => 50, backend => 'pdl'); 1 };
my $pdl_error = $@;
if ($pdl_ready) { print "Optional PDL is available.\n" }
else {
    croak 'Unexpected PDL availability error'
        unless ref($pdl_error)
        && $pdl_error->isa('Ham::RTTY::Error')
        && $pdl_error->code eq 'RTTY_E_ARGUMENT';
    print 'Explicit PDL selection is unavailable (', $pdl_error->code,
        "). Install compatible PDL.\n";
}
my $symbol = expected_error('RTTY_E_SYMBOL', sub { $rtty->encode('A!') });
print 'Symbol position: ', $symbol->context->{position}, '; ', $symbol->message, "\n";
my $decoder = $rtty->decoder(baud => 50);
expected_error(
    'RTTY_E_TIMING',
    sub {
        $decoder->feed(
            {
                unit     => 'us',
                segments =>
                    [{state => 'mark', duration => 60000}, {state => 'mark', duration => 60000}]
            }
        );
    }
);
croak 'Rejected feed changed state' unless $decoder->state eq 'READY';
$decoder->feed($rtty->events('SOS'));
$decoder->finish;
expected_error('RTTY_E_STATE', sub { $decoder->feed($rtty->events('E')) });
$decoder->reset;
$decoder->feed($rtty->events('E'));
croak 'Decoder did not recover' unless $decoder->finish->text eq 'E';

my $generator = $rtty->generator;
my $old       = $generator->stream($rtty->events('SOS'), 137);
$generator->reset;
expected_error('RTTY_E_STATE',         sub { $old->() });
expected_error('RTTY_E_RESOURCE',      sub { $rtty->samples('SOS', max_samples => 1) });
expected_error('RTTY_E_WAV_FORMAT',    sub { $rtty->decode_wav_bytes('NOT A WAVE!!?') });
expected_error('RTTY_E_WAV_TRUNCATED', sub { $rtty->decode_wav_bytes('RIFF') });

my $directory = tempdir(CLEANUP => 1);
my $path      = File::Spec->catfile($directory, 'preserved.wav');
$rtty->write_wav('SOS', $path);
expected_error('RTTY_E_IO', sub { $rtty->write_wav('E', $path) });
expected_error('RTTY_E_IO',
    sub { $rtty->read_wav(File::Spec->catfile($directory, 'missing.wav')) });
expected_error('RTTY_E_RESOURCE',
    sub { $rtty->write_wav('SOS', $path, overwrite => 1, max_samples => 1) });
croak 'Failed replacement changed input'
    unless $rtty->read_wav($path, mark => 650, baud => 50)->text eq 'SOS';

# Validation/count failures are recoverable before I/O fails.
my $audio = Ham::RTTY::Audio->new(backend => $backend);
my $bytes = '';
open my $out, '>:raw', \$bytes or croak $!;
my $writer = $audio->writer($out, sample_rate => 8000, sample_count => 2);
expected_error('RTTY_E_ARGUMENT', sub { $writer->feed([2]) });
expected_error('RTTY_E_ARGUMENT', sub { $writer->finish });
$writer->feed([0, 0]);
$writer->finish;
close $out or croak $!;

# This portable test sink accepts the header and rejects the next write.
# It demonstrates I/O failure without filling a disk or changing permissions.
my $sink = gensym();
tie *{$sink}, 'Example::RejectPCM';
my $failed = $audio->writer($sink, sample_rate => 8000, sample_count => 1);
expected_error('RTTY_E_IO', sub { $failed->feed([0]) });
croak 'I/O failure did not mark writer failed' unless $failed->state eq 'FAILED';
expected_error('RTTY_E_STATE', sub { $failed->finish });
undef $failed;
untie *{$sink};

# Applications can construct or throw the same structured error type.
my $own = Ham::RTTY::Error->new(message => 'Application failure', context => {operation => 'demo'});
croak 'Unexpected default code' unless $own->code eq 'RTTY_E_INTERNAL';
my $context = $own->context;
$context->{operation} = 'changed copy';
croak 'Error context was mutated' unless $own->context->{operation} eq 'demo';
expected_error('RTTY_E_ARGUMENT',
    sub { Ham::RTTY::Error->throw(code => 'RTTY_E_ARGUMENT', message => 'Application validation') }
);
print "Example completed: failure-recovery\n";

package Example::RejectPCM;
use strict;
use warnings;
sub TIEHANDLE { my ($class) = @_; return bless {writes => 0}, $class }
sub BINMODE   { return 1 }
sub PRINT     { my ($self) = @_; return ++$self->{writes} == 1 ? 1 : 0 }
