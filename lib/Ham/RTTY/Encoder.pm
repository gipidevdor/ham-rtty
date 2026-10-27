package Ham::RTTY::Encoder;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Baudot;
use Ham::RTTY::Result;
use Ham::RTTY::_Internal::Validate qw(fail number integer options named_arguments);
our $VERSION = '0.01';

sub validate {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args,
        qw(variant usos lenient baud stop_bits leading_idle trailing_idle max_segments));
    Ham::RTTY::Baudot->new(map { exists($args{$_}) ? ($_ => $args{$_}) : () } qw(variant usos));
    my $stop = number('stop_bits', $args{stop_bits} // 1.5, 1, 2);
    fail('RTTY_E_ARGUMENT', 'stop_bits must be 1, 1.5 or 2')
        unless $stop == 1 || $stop == 1.5 || $stop == 2;
    return {
        variant       => $args{variant} // 'ita2',
        usos          => integer('usos',    $args{usos}    // 1, 0, 1),
        lenient       => integer('lenient', $args{lenient} // 0, 0, 1),
        baud          => number('baud', $args{baud} // 45.45, 20, 300),
        stop_bits     => $stop,
        leading_idle  => number('leading_idle',  $args{leading_idle}  // 0.1, 0, 60),
        trailing_idle => number('trailing_idle', $args{trailing_idle} // 0.1, 0, 60),
        max_segments  => integer('max_segments', $args{max_segments} // 100000, 1, 1000000)
    };
}
sub new { my ($class, @args) = @_; return bless $class->validate(@args), $class }

sub frames {
    my ($self, $text) = @_;
    fail('RTTY_E_ARGUMENT', 'Text must be a defined scalar') if !defined($text) || ref($text);
    my $tables = Ham::RTTY::Baudot->new(variant => $self->{variant})->tables;
    my %lookup;
    for my $mode (qw(letters figures)) {
        for my $code (0 .. 31) {
            my $c = $tables->{$mode}[$code];
            $lookup{$c}{$mode} = $code if defined $c;
        }
    }
    my (@frames, @warnings);
    my $mode = '';
    my $emit = sub {
        my ($code, $char, $shift) = @_;
        fail('RTTY_E_RESOURCE', 'Too many frames') if @frames >= $self->{max_segments};
        push @frames,
            {
            code      => $code,
            character => $char,
            shift     => $shift,
            data_bits => join('', map { ($code >> $_) & 1 } 0 .. 4),
            stop_bits => $self->{stop_bits}
            };
    };
    my $position = 0;
    for my $c (split //, $text) {
        ++$position;
        $c =~ tr/a-z/A-Z/;
        if (!exists $lookup{$c}) {
            Ham::RTTY::Error->throw(
                code    => 'RTTY_E_SYMBOL',
                message => "Unsupported character at position $position",
                context => {symbol => $c, position => $position}
            ) unless $self->{lenient};
            push @warnings,
                {
                code    => 'RTTY_W_SYMBOL',
                message => "Substituted unsupported character at position $position"
                };
            $c = '?';
        }
        my $next =
              exists($lookup{$c}{$mode})   ? $mode
            : exists($lookup{$c}{letters}) ? 'letters'
            :                                'figures';
        if ($next ne $mode) {
            $emit->($next eq 'letters' ? 31 : 27, '', $next eq 'letters' ? 'LTRS' : 'FIGS');
            $mode = $next;
        }
        $emit->($lookup{$c}{$mode}, $c, '');
        $mode = 'letters' if $c eq ' ' && $self->{usos};
    }
    $self->{last_result} =
        Ham::RTTY::Result->new(text => $text, warnings => \@warnings, complete => 1);
    return \@frames;
}

sub encode {
    my ($self, $text) = @_;
    return join ' ',
        map { $_->{shift} ? '[' . $_->{shift} . ']' : sprintf('%05b', $_->{code}) }
        @{$self->frames($text)};
}

sub bits {
    my ($self, $text) = @_;
    return join '',
        map { '0' . $_->{data_bits} . ('1' x int($_->{stop_bits} + 0.5)) } @{$self->frames($text)};
}

sub events {
    my ($self, $text) = @_;
    my $frames = $self->frames($text);
    my (@segments, $time, $boundary);
    $time = $boundary = 0;
    my $append = sub {
        my ($state, $seconds) = @_;
        return unless $seconds;
        $time += $seconds * 1000000;
        my $end = int($time + 0.5);
        if (@segments && $segments[-1]{state} eq $state) {
            $segments[-1]{duration} += $end - $boundary;
        }
        else { push @segments, {state => $state, duration => $end - $boundary} }
        $boundary = $end;
        fail('RTTY_E_RESOURCE', 'Too many segments') if @segments > $self->{max_segments};
    };
    if (@{$frames}) {
        $append->('mark', $self->{leading_idle});
        for my $frame (@{$frames}) {
            $append->($_ eq '1' ? 'mark' : 'space', 1 / $self->{baud})
                for split //, '0' . $frame->{data_bits};
            $append->('mark', $self->{stop_bits} / $self->{baud});
        }
        $append->('mark', $self->{trailing_idle});
    }
    return {unit => 'us', segments => \@segments};
}
sub result { my ($self) = @_; return $self->{last_result} // Ham::RTTY::Result->new }
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Encoder - encode ITA2 notation, frames, bits and timed events

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    my $encoder = Ham::RTTY::Encoder->new(baud => 50);
    print $encoder->encode('CQ 123'), "\n";

=head1 METHODS

=head2 new

Ham::RTTY::Encoder->new(%options) returns a stateless message encoder. C<baud> defaults to 45.45, finite range 20..300. C<stop_bits> defaults to 1.5; allowed values 1, 1.5, 2. C<variant> is C<ita2> (default) or C<us>. C<usos> defaults to 1; C<lenient> defaults to 0; both accept integer 0 or 1. C<leading_idle> and C<trailing_idle> default to 0.1 seconds, range 0..60. C<max_segments> defaults to 100000, integer 1..1000000, bounding frames and runs. Unknown/duplicate options raise C<RTTY_E_ARGUMENT>.

=head2 validate

Ham::RTTY::Encoder->validate(%options) validates the same options as C<new> and returns a fresh normalized hash. It produces no output.

=head2 frames

$encoder->frames($text) returns fresh per-frame hashes: numeric C<code>, C<character>, C<shift> (LTRS, FIGS or empty), five C<data_bits> in transmission order and C<stop_bits>. Each message begins with a shift. ASCII lowercase becomes uppercase. Undefined text and references raise C<RTTY_E_ARGUMENT>. Unsupported characters raise C<RTTY_E_SYMBOL>; lenient input substitutes ? and records C<RTTY_W_SYMBOL> in C<result>. Input is a Perl character string, without transliteration.

=head2 encode

$encoder->encode($text) returns space-separated five-bit numeric codes, most significant digit first, with C<[LTRS]> and C<[FIGS]> shift markers. Empty text returns an empty string. Options and text validation are those of C<frames>.

=head2 bits

$encoder->bits($text) returns 0/1 transmission order: SPACE start, five LSB-first data bits, MARK stop. A string cannot represent a fractional bit: stop 1.5 is rounded up to two 1 digits. Use C<frames> or C<events> for exact fractional timing. Idle padding is omitted from this logical bit string.

=head2 events

$encoder->events($text) returns alternating C<mark>/C<space> integer-microsecond runs with C<unit =E<gt> 'us'>. Cumulative boundaries round once to avoid drift; stop duration remains exactly the requested fractional bit before rounding. Empty text has no idle runs. C<usos> resends FIGS after SPACE when needed. Exceeding the configured run/frame limit raises C<RTTY_E_RESOURCE>.

=head2 result

$encoder->result returns an independent L<Ham::RTTY::Result> from the last successful encoding, including substitution warnings; before encoding it returns an empty provisional Result.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli. Artistic License 2.0. See F<LICENSE>.

=cut
