package Ham::RTTY::Decoder;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Baudot;
use Ham::RTTY::Events qw(validate_events to_timed);
use Ham::RTTY::Result;
use Ham::RTTY::_Internal::Validate qw(fail number integer options named_arguments);
our $VERSION = '0.001';

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(variant usos baud max_segments));
    my $self = bless {
        baud         => number('baud', $args{baud}                  // 45.45, 20, 300),
        max_segments => integer('max_segments', $args{max_segments} // 100000, 1, 1000000),
        codec        => Ham::RTTY::Baudot->new(
            map { exists($args{$_}) ? ($_ => $args{$_}) : () } qw(variant usos)
        )
    }, $class;
    return $self->reset;
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;
    @{$self}{qw(state text time previous framing)} = ('READY', '', 0, 'mark', 0);
    $self->{warnings} = [];
    $self->{segments} = [];
    $self->{codec}->reset;
    delete @{$self}{qw(candidate final)};
    return $self;
}
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub decode {
    my ($self, $notation) = @_;
    fail('RTTY_E_ARGUMENT', 'Notation must be a defined scalar')
        if !defined($notation) || ref($notation);
    my @codes;
    for my $token (grep { length } split /\s+/x, $notation) {
        if    ($token eq '[LTRS]')       { push @codes, 31 }
        elsif ($token eq '[FIGS]')       { push @codes, 27 }
        elsif ($token =~ /\A[01]{5}\z/x) { push @codes, oct('0b' . $token) }
        else { fail('RTTY_E_SYMBOL', 'Expected five binary digits or shift marker') }
    }

    # Symbolic decoding is independent of incremental event history.
    my $codec = Ham::RTTY::Baudot->new(usos => $self->{codec}{usos});
    $codec->{letters} = [@{$self->{codec}{letters}}];
    $codec->{figures} = [@{$self->{codec}{figures}}];
    return join '', map { $codec->character($_) } @codes;
}

sub decode_bits {
    my ($self, $bits) = @_;
    fail('RTTY_E_ARGUMENT', 'Bits must contain only 0 and 1')
        if !defined($bits) || ref($bits) || $bits =~ /[^01]/x;
    my @segments;
    for my $bit (split //, $bits) {
        my $state = $bit eq '1' ? 'mark' : 'space';
        if (@segments && $segments[-1]{state} eq $state) { $segments[-1]{samples}++ }
        else { push @segments, {state => $state, samples => 1} }
    }

    # A synthetic rate makes every bit exactly one configured period.
    my $events = {unit => 'us', segments => []};
    my ($time, $boundary) = (0, 0);
    for my $s (@segments) {
        $time += $s->{samples} * 1000000 / $self->{baud};
        my $end = int($time + 0.5);
        push @{$events->{segments}}, {state => $s->{state}, duration => $end - $boundary};
        $boundary = $end;
    }
    $self->feed($events);
    return $self->finish;
}

sub _run {
    my ($self, $state, $duration) = @_;
    my $end = $self->{time} + $duration;
    my $bit = 1000000 / $self->{baud};
    if (!$self->{candidate} && $state eq 'space' && $self->{previous} eq 'mark') {
        $self->{candidate} = {start => $self->{time}, index => 0, code => 0};
    }
    while (my $c = $self->{candidate}) {
        my $centre = $c->{start} + ($c->{index} + 0.5) * $bit;
        last if $centre >= $end;
        my $mark = $state eq 'mark' ? 1 : 0;
        if ($c->{index} == 0 && $mark)            { delete $self->{candidate}; last }
        if ($c->{index} >= 1 && $c->{index} <= 5) { $c->{code} |= $mark << ($c->{index} - 1) }
        if ($c->{index} == 6) {
            if (!$mark) {
                ++$self->{framing};
                push @{$self->{warnings}},
                    {code => 'RTTY_W_FRAMING', message => 'Stop bit is SPACE; resynchronising'};
            }
            else {
                my $char = eval { $self->{codec}->character($c->{code}) };
                if ($@) {
                    push @{$self->{warnings}},
                        {code => 'RTTY_W_SYMBOL', message => 'Unassigned figures combination'};
                    $char = "\x{fffd}";
                }
                $self->{text} .= $char;
            }
            delete $self->{candidate};
            last;
        }
        ++$c->{index};
    }
    $self->{time}     = $end;
    $self->{previous} = $state;
    return;
}

sub feed {
    my ($self, $events) = @_;
    fail('RTTY_E_STATE', 'Decoder is finalized') if $self->{state} eq 'FINISHED';
    my $field = validate_events($events);
    my $timed = to_timed($events);
    fail('RTTY_E_RESOURCE', 'Event history exceeds max_segments')
        if @{$self->{segments}} + @{$timed->{segments}} > $self->{max_segments};
    my $total = $self->{time};
    $total += $_->{duration} for @{$timed->{segments}};
    fail('RTTY_E_RESOURCE', 'Cumulative duration exceeds exact integer range') if $total > 2**52;

    for my $s (@{$timed->{segments}}) {
        $self->_run($s->{state}, $s->{duration});
        if (@{$self->{segments}} && $self->{segments}[-1]{state} eq $s->{state}) {
            $self->{segments}[-1]{duration} += $s->{duration};
        }
        else { push @{$self->{segments}}, {state => $s->{state}, duration => $s->{duration}} }
    }
    $self->{state} = 'ACTIVE';
    return $self;
}

sub result {
    my ($self) = @_;
    return $self->{final} // Ham::RTTY::Result->new(
        text        => $self->{text},
        baud        => $self->{baud},
        warnings    => $self->{warnings},
        events      => {unit => 'us', segments => $self->{segments}},
        diagnostics =>
            {configured_bit_period => 1 / $self->{baud}, framing_error_count => $self->{framing}},
        complete => 0
    );
}

sub finish {
    my ($self) = @_;
    return $self->{final} if $self->{state} eq 'FINISHED';
    if ($self->{candidate}) {
        push @{$self->{warnings}},
            {code => 'RTTY_W_FRAMING', message => 'Incomplete frame at end of input'};
    }
    my $h = $self->result->as_hash;
    $h->{complete} = 1;
    $self->{final} = Ham::RTTY::Result->new(%{$h});
    $self->{state} = 'FINISHED';
    return $self->{final};
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Decoder - incremental start-stop ITA2 event receiver

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    use Ham::RTTY::Decoder;

    my $decoder = Ham::RTTY::Decoder->new(baud => 50);
    $decoder->feed(Ham::RTTY::Encoder->new(baud => 50)->events('CQ'));
    print $decoder->finish->text, "\n";

=head1 DESCRIPTION

Decodes ITA2 notation or incremental timed/sampled events. Event reception
uses the configured baud rate to sample start, data and stop bits. The Baudot
codec retains shift state between accepted frames.

=head1 METHODS

=head2 new

    my $decoder = Ham::RTTY::Decoder->new(%options);

Returns a decoder in C<READY> state. Named options:

=over 4

=item * C<baud>

45.45 by default; finite number 20..300 bits per second.

=item * C<variant>

C<ita2> by default, or C<us>.

=item * C<usos>

1 by default; integer 0 or 1. SPACE restores LTRS when enabled.

=item * C<max_segments>

100000 by default; integer 1..1000000, bounding retained event history.

=back

Undefined optional values use defaults. Invalid, duplicate and unknown
options raise C<RTTY_E_ARGUMENT>.

=head2 decode

    my $text = $decoder->decode($notation);

Returns text from five-bit numeric codes and shift markers. This operation
uses fresh LTRS state and does not modify incremental history. Invalid tokens
or unassigned codes raise C<RTTY_E_SYMBOL>; undefined or reference input
raises C<RTTY_E_ARGUMENT>.

=head2 decode_bits

    my $result = $decoder->decode_bits($bits);

Feeds a defined 0/1 scalar into the incremental receiver at one configured bit
period per digit and finalizes it. Returns a Result. Use a fresh/reset
receiver for a new message; fractional stop duration belongs in events.

=head2 feed

    $decoder->feed($events);

Validates timed or sampled runs, then appends them to bounded history and
returns the receiver. Runs can be split across calls; each input must validate
independently. A MARK-to-SPACE transition starts a UART frame. The receiver
validates start at half a bit, samples five data centres and checks MARK at
the stop centre. Invalid stops produce C<RTTY_W_FRAMING> and
resynchronisation. Unassigned received figures produce U+FFFD and
C<RTTY_W_SYMBOL>. A retained-history overflow raises C<RTTY_E_RESOURCE> before
mutation. Feed after finish raises C<RTTY_E_STATE>.

=head2 result

    my $result = $decoder->result;

Returns a cumulative deep-copied Result, with complete 0 before finalization.
Replace previous snapshots; do not append them. Diagnostics include configured
bit period in seconds and framing error count.

=head2 finish

    my $result = $decoder->finish;

Returns a complete Result, warning on an incomplete frame. Repeated calls
return the same final snapshot. It does not add stop bits to incomplete input.

=head2 reset

    $decoder->reset;

Discards history, text, warnings and partial frames, restores LTRS and READY,
and returns the object. Previously returned Results remain independent.

=head2 state

    my $state = $decoder->state;

Returns READY, ACTIVE or FINISHED.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
