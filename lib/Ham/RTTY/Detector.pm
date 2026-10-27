package Ham::RTTY::Detector;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::_Internal::Validate qw(fail number integer options samples named_arguments);
use Ham::RTTY::Decoder;
use Ham::RTTY::Result;
use Ham::RTTY::_Internal::Result;
use Ham::RTTY::_Internal::Backend;
use Ham::RTTY::_Internal::Biquad;
our $VERSION = '0.001';
my $PI = 4 * atan2(1, 1);

# Internal power-domain heuristics, not calibrated receiver SNR. Keep the
# two 22% decisions independent; rationale and tuning evidence are documented
# under "Detector power heuristics" in docs/architecture.md.
my $GUARD_NOISE_MARGIN              = 1.3;
my $ENVELOPE_NOISE_GATE_RATIO       = 12;
my $TRACKED_PEAK_FLOOR_FRACTION     = 0.05;
my $KEY_ON_FRACTION                 = 0.22;
my $KEY_HOLD_FRACTION               = 0.12;
my $TRACKED_PEAK_CLAMP_RATIO        = 2;
my $NOISE_UPDATE_THRESHOLD_FRACTION = 0.25;
my $NOISE_UPDATE_RATE               = 0.02;
my $BURST_TRIM_FRACTION             = 0.22;

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args,
        qw(sample_rate frequency min_frequency max_frequency frequency_step wpm effective_wpm max_frames min_contrast min_purity backend filter_bandwidth min_snr_db mark_snr_db)
    );
    my $rate         = integer('sample_rate', $args{sample_rate} // 16000, 1000, 384000);
    my $default_high = $rate / 2 - 1 < 1500 ? $rate / 2 - 1 : 1500;
    my $low  = number('min_frequency',  $args{min_frequency} // 300,           1,    $rate / 2 - 1);
    my $high = number('max_frequency',  $args{max_frequency} // $default_high, $low, $rate / 2 - 1);
    my $step = number('frequency_step', $args{frequency_step} // 50,           10,   500);
    my @frequencies;

    if (defined $args{frequency}) {
        @frequencies = (number('frequency', $args{frequency}, 1, $rate / 2 - 1));
    }
    else {
        for (my $f = $low; $f <= $high; $f += $step) { push @frequencies, $f }
    }
    fail('RTTY_E_RESOURCE', 'Too many frequency candidates') if @frequencies > 256;
    number('wpm', $args{wpm}, 1, 60) if defined $args{wpm};
    number('effective_wpm', $args{effective_wpm}, 1, $args{wpm} // 60)
        if defined $args{effective_wpm};
    my $self = bless {
        %args,
        sample_rate      => $rate,
        filter_bandwidth => number(
            'filter_bandwidth',
            $args{filter_bandwidth}
                // (defined($args{wpm}) ? ($args{wpm} * 4 < 40 ? 40 : $args{wpm} * 4) : 180),
            20,
            $rate / 2 - 1
        ),
        backend      => Ham::RTTY::_Internal::Backend::resolve($args{backend}),
        frequencies  => \@frequencies,
        frame_size   => int($rate * 0.005 + 0.5),
        max_frames   => integer('max_frames', $args{max_frames} // 24000, 1, 1000000),
        min_contrast => number('min_contrast', $args{min_contrast} // 0.60, 0.01, 1),
        min_snr_db   => number('min_snr_db',   $args{min_snr_db}   // 12,   0,    40),
        mark_snr_db  => number('mark_snr_db',  $args{mark_snr_db}  // 10,   0,    40),
        min_purity   => number('min_purity',   $args{min_purity}   // 0.20, 0.01, 1)
    }, $class;
    my $n = $self->{analysis_size} = $self->{frame_size} * 4;
    $self->{window}       = [map { 0.5 - 0.5 * cos(2 * $PI * $_ / ($n - 1)) } 0 .. $n - 1];
    $self->{coefficients} = [map { 2 * cos(2 * $PI * $_ / $rate) } @frequencies];
    my $offset = $step * 2;
    $offset = 100 if $offset < 100;
    my (%lookup, @acquire, @guards, @centres);

    for my $frequency (@frequencies) {
        my @indices;
        for my $candidate ($frequency, map { $frequency + $_ * $offset } (-3, -2, -1, 1, 2, 3)) {
            next if $candidate < 1 || $candidate >= $rate / 2;
            my $key = sprintf('%.12g', $candidate);
            if (!exists $lookup{$key}) {
                $lookup{$key} = @acquire;
                push @acquire, $candidate;
            }
            push @indices, $lookup{$key};
        }
        push @centres, shift @indices;
        push @guards,  \@indices;
    }
    $self->{acquire_frequencies} = \@acquire;
    $self->{acquire_centres}     = \@centres;
    $self->{acquire_guards}      = \@guards;
    $self->_prepare_acquisition;
    $self->{snr_ratio}      = 10**($self->{min_snr_db} / 10);
    $self->{mark_snr_ratio} = 10**($self->{mark_snr_db} / 10);
    return $self->reset;
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;
    $self->{state}             = 'READY';
    $self->{buffer}            = [];
    $self->{frames}            = [];
    $self->{tone_totals}       = [(0) x @{$self->{frequencies}}];
    $self->{total_samples}     = 0;
    $self->{final}             = undef;
    $self->{snapshot}          = undef;
    $self->{channel_snapshot}  = [];
    $self->{pdl_kernels}       = {};
    $self->{filter_history}    = [map { [(0) x $self->{analysis_size}] } @{$self->{frequencies}}];
    $self->{delay_compensated} = 0;
    $self->{raw_history}       = [(0) x ($self->{acquire_hops} * $self->{frame_size})];
    $self->{acquire_partials}  = [];
    $self->{filters}           = [
        map { Ham::RTTY::_Internal::Biquad->new($self->{sample_rate}, $_, $self->{filter_bandwidth}) }
            @{$self->{frequencies}}
    ];
    return $self;
}
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub _retain_frame {
    my ($self, $frame) = @_;
    push @{$self->{frames}}, $frame;
    $self->{tone_totals}[$_] += $frame->{powers}[$_] for 0 .. $#{$self->{tone_totals}};
    return;
}

sub _frame {
    my ($self, $block) = @_;
    if ($self->{backend} eq 'pdl') {
        Ham::RTTY::_Internal::PDL::frames($self, [$block]);
        return;
    }
    my $channels = $self->_filtered_channels($block);
    my $n        = $self->{analysis_size};
    my $gates    = $self->{last_gates};
    my $window   = $self->{window};
    my $pairs    = $n - $n % 2;
    my (@powers, @energies);
    for my $index (0 .. $#{$channels}) {
        my $channel = $channels->[$index];
        my $mean    = 0;
        $mean += $_ for @{$channel};
        $mean /= $n;
        my $energy = 0;

        # A gated-off channel reports zero power, so only its windowed energy
        # is needed; the recurrence below runs for admitted channels alone.
        if (!$gates->[$index]) {
            for my $i (0 .. $n - 1) {
                my $x = ($channel->[$i] - $mean) * $window->[$i];
                $energy += $x * $x;
            }
            push @powers,   0;
            push @energies, $energy;
            next;
        }
        my ($s1, $s2) = (0, 0);
        my $coeff = $self->{coefficients}[$index];
        for (my $i = 0; $i < $pairs; $i += 2) {
            my $x0 = ($channel->[$i] - $mean) * $window->[$i];
            my $x1 = ($channel->[$i + 1] - $mean) * $window->[$i + 1];
            $energy += $x0 * $x0;
            $energy += $x1 * $x1;
            my $value = $x0 + $coeff * $s1 - $s2;
            $s1 = $x1 + $coeff * $value - $s1;
            $s2 = $value;
        }
        if ($pairs < $n) {
            my $x = ($channel->[$pairs] - $mean) * $window->[$pairs];
            $energy += $x * $x;
            my $value = $x + $coeff * $s1 - $s2;
            $s2 = $s1;
            $s1 = $value;
        }
        my $power = $s1 * $s1 + $s2 * $s2 - $coeff * $s1 * $s2;
        push @powers,   $power > 0 ? $power : 0;
        push @energies, $energy;
    }
    $self->_retain_frame(
        {powers => \@powers, energies => \@energies, samples => scalar(@{$block})});
    return;
}

sub _filtered_channels {
    my ($self, $block, $copy) = @_;
    $self->{last_gates} = $self->_acquire($block);
    my @channels;
    for my $index (0 .. $#{$self->{filters}}) {
        my $history = $self->{filter_history}[$index];
        push @{$history}, @{$self->{filters}[$index]->process($block)};
        splice @{$history}, 0, @{$block};

        # Batched callers keep several hops; the immediate caller reads the
        # history before the next hop replaces it.
        push @channels, $copy ? [@{$history}] : $history;
    }
    return \@channels;
}

sub _prepare_acquisition {
    my ($self) = @_;
    my $hop    = $self->{frame_size};
    my $hops   = $self->{acquire_hops} = 8;
    my $total  = $hop * $hops;
    my $rate   = $self->{sample_rate};

    # One Hann weight per hop: the mean of the periodic window over that hop.
    my @weights;
    for my $position (0 .. $hops - 1) {
        my $weight = 0;
        $weight += 0.5 - 0.5 * cos(2 * $PI * ($position * $hop + $_) / $total) for 0 .. $hop - 1;
        push @weights, $weight / $hop;
    }
    my (@cosines, @sines, @rotate, @offsets);
    for my $frequency (@{$self->{acquire_frequencies}}) {
        my $omega = 2 * $PI * $frequency / $rate;
        push @cosines, [map { cos($omega * $_) } 0 .. $hop - 1];
        push @sines,   [map { sin($omega * $_) } 0 .. $hop - 1];

        # Weighted rotation that places a hop's partial projection at its
        # position inside the window, and the window's own transform for
        # removing the mean afterwards.
        my @rotation;
        for my $position (0 .. $hops - 1) {
            my $angle = $omega * $position * $hop;
            push @rotation, [$weights[$position] * cos($angle), -$weights[$position] * sin($angle)];
        }
        push @rotate, \@rotation;
        my ($real, $imaginary) = (0, 0);
        for my $n (0 .. $total - 1) {
            my $weight = $weights[int($n / $hop)];
            $real      += $weight * cos($omega * $n);
            $imaginary -= $weight * sin($omega * $n);
        }
        push @offsets, [$real, $imaginary];
    }
    $self->{acquire_cos}     = \@cosines;
    $self->{acquire_sin}     = \@sines;
    $self->{acquire_rotate}  = \@rotate;
    $self->{acquire_offsets} = \@offsets;
    return;
}

sub _acquire_partial {
    my ($self, $samples)  = @_;
    my ($cosines, $sines) = @{$self}{qw(acquire_cos acquire_sin)};
    my $count = @{$samples};
    my $pairs = $count - $count % 2;
    my $sum   = 0;
    $sum += $_ for @{$samples};
    my (@real, @imaginary);
    for my $j (0 .. $#{$cosines}) {
        my ($c, $s) = ($cosines->[$j], $sines->[$j]);
        my ($re, $im) = (0, 0);
        for (my $m = 0; $m < $pairs; $m += 2) {
            $re += $samples->[$m] * $c->[$m] + $samples->[$m + 1] * $c->[$m + 1];
            $im += $samples->[$m] * $s->[$m] + $samples->[$m + 1] * $s->[$m + 1];
        }
        if ($pairs < $count) {
            $re += $samples->[$pairs] * $c->[$pairs];
            $im += $samples->[$pairs] * $s->[$pairs];
        }
        push @real,      $re;
        push @imaginary, -$im;
    }
    return {real => \@real, imaginary => \@imaginary, sum => $sum};
}

sub _acquire_powers {
    my ($self)  = @_;
    my $ring    = $self->{acquire_partials};
    my $rotate  = $self->{acquire_rotate};
    my $offsets = $self->{acquire_offsets};
    my $first   = $self->{acquire_hops} - @{$ring};
    my $mean    = 0;
    $mean += $_->{sum} for @{$ring};
    $mean /= $self->{acquire_hops} * $self->{frame_size};
    my @powers;

    for my $j (0 .. $#{$offsets}) {
        my ($re, $im) = (0, 0);
        for my $k (0 .. $#{$ring}) {
            my ($wr, $wi) = @{$rotate->[$j][$first + $k]};
            my ($pr, $pi) = ($ring->[$k]{real}[$j], $ring->[$k]{imaginary}[$j]);
            $re += $wr * $pr - $wi * $pi;
            $im += $wr * $pi + $wi * $pr;
        }
        $re -= $mean * $offsets->[$j][0];
        $im -= $mean * $offsets->[$j][1];
        push @powers, $re * $re + $im * $im;
    }
    return \@powers;
}

sub _acquire {
    my ($self, $block) = @_;
    my $hop     = $self->{frame_size};
    my $history = $self->{raw_history};
    push @{$history}, @{$block};
    splice @{$history}, 0, @{$block};
    my $ring = $self->{acquire_partials};
    if (@{$block} == $hop) {
        push @{$ring}, $self->_acquire_partial($block);
        shift @{$ring} while @{$ring} > $self->{acquire_hops};
    }
    else {
        # A shorter flush block moves the hop grid; rebuild every partial from
        # the retained raw window so the positions stay aligned.
        @{$ring} = ();
        for my $position (0 .. $self->{acquire_hops} - 1) {
            my $start = $position * $hop;
            push @{$ring}, $self->_acquire_partial([@{$history}[$start .. $start + $hop - 1]]);
        }
    }
    my $powers = $self->_acquire_powers;
    my @gates;
    for my $i (0 .. $#{$self->{frequencies}}) {
        my @guard  = sort { $a <=> $b } @{$powers}[@{$self->{acquire_guards}[$i]}];
        my $noise  = @guard ? $guard[int($#guard / 2)] * $GUARD_NOISE_MARGIN : 0;
        my $signal = $powers->[$self->{acquire_centres}[$i]];
        push @gates, $signal > 1e-12 && $signal >= $noise * $self->{snr_ratio} ? 1 : 0;
    }
    return \@gates;
}

sub feed {
    my ($self, $block) = @_;
    fail('RTTY_E_STATE', 'Detector is finalized') if $self->{state} eq 'FINISHED';
    samples($block, 1000000);
    my $future = @{$self->{frames}} +
        int((@{$self->{buffer}} + @{$block} + $self->{frame_size} - 1) / $self->{frame_size});
    fail('RTTY_E_RESOURCE',
        'Detector frame limit exceeded; increase max_frames or decode a shorter recording')
        if $future > $self->{max_frames};
    $self->{snapshot} = undef;
    $self->{total_samples} += @{$block};
    my $offset = 0;

    while ($offset < @{$block}) {
        if (   $self->{backend} eq 'pdl'
            && !@{$self->{buffer}}
            && @{$block} - $offset >= $self->{frame_size})
        {
            my $count = int((@{$block} - $offset) / $self->{frame_size});
            $count = 128 if $count > 128;
            my @blocks;
            for (1 .. $count) {
                push @blocks, [@{$block}[$offset .. $offset + $self->{frame_size} - 1]];
                $offset += $self->{frame_size};
            }
            Ham::RTTY::_Internal::PDL::frames($self, \@blocks);
            next;
        }
        my $take = $self->{frame_size} - @{$self->{buffer}};
        $take = @{$block} - $offset if $take > @{$block} - $offset;
        push @{$self->{buffer}}, @{$block}[$offset .. $offset + $take - 1];
        $offset += $take;
        if (@{$self->{buffer}} == $self->{frame_size}) {
            $self->_frame($self->{buffer});
            $self->{buffer} = [];
        }
    }
    $self->{state} = 'ACTIVE';
    return $self;
}

sub _compensate_delay {
    my ($self) = @_;
    return if $self->{delay_compensated};
    my @counts = map { $_->{samples} } @{$self->{frames}};
    return unless @counts;
    my @delays = map {
        int((($self->{analysis_size} - 1) / 2 + $_->delay_samples) / $self->{frame_size} + 0.5)
    } @{$self->{filters}};
    my $maximum = 0;
    $maximum = $_ > $maximum ? $_ : $maximum for @delays;
    $self->_frame([(0) x $self->{frame_size}]) for 1 .. $maximum;

    # Align each column in place; future rows have not yet been overwritten.
    $self->{tone_totals} = [(0) x @delays];
    for my $channel (0 .. $#delays) {
        for my $i (0 .. $#counts) {
            my $source = $self->{frames}[$i + $delays[$channel]];
            for my $field (qw(powers energies)) {
                $self->{frames}[$i]{$field}[$channel] = $source->{$field}[$channel];
            }
            $self->{tone_totals}[$channel] += $self->{frames}[$i]{powers}[$channel];
        }
    }
    splice @{$self->{frames}}, scalar @counts;
    $self->{delay_compensated} = 1;
    return;
}

sub _candidate_indices {
    my ($self)  = @_;
    my $totals  = $self->{tone_totals};
    my @indices = grep {
               ($_ == 0 || $totals->[$_] > $totals->[$_ - 1])
            && ($_ == $#{$totals} || $totals->[$_] >= $totals->[$_ + 1])
    } 0 .. $#{$totals};
    @indices = sort { $totals->[$b] <=> $totals->[$a] || $a <=> $b } @indices;
    return @indices;
}

sub _analyze {
    my ($self, $complete) = @_;
    my (@channels, $fallback);
    my $separation = $self->{filter_bandwidth} > 100 ? $self->{filter_bandwidth} : 100;
    for my $index ($self->_candidate_indices) {
        my $frequency = $self->{frequencies}[$index];
        next if grep { abs($_->frequency - $frequency) < $separation } @channels;
        my $result = $self->_analyze_channel($complete, $index);
        $fallback //= $result;

        # An invalid group is retained by the primary API, but is not a station.
        next unless $result->text =~ /[^\x{FFFD}\s]/x;
        push @channels, $result;
        last if @channels == 8;
    }
    $self->{channel_snapshot} = \@channels;
    return $channels[0] // $fallback // $self->_analyze_channel($complete, 0);
}

sub channels {
    my ($self) = @_;
    $self->result;
    return [@{$self->{channel_snapshot}}];
}

sub _purity {
    my ($self, $frames, $powers, $peak, $best) = @_;
    my ($inband, $broadband) = (0, 0);
    for my $i (0 .. $#{$frames}) {
        next if $powers->[$i] < 0.25 * $peak;
        $inband    += $powers->[$i] * 2 / $self->{analysis_size};
        $broadband += $frames->[$i]{energies}[$best];
    }
    my $purity = $broadband ? $inband / $broadband : 0;
    return $purity;
}

sub _key_state {
    my ($tracker, $power) = @_;
    my $limited =
          $power < $TRACKED_PEAK_CLAMP_RATIO * $tracker->{ceiling}
        ? $power
        : $TRACKED_PEAK_CLAMP_RATIO * $tracker->{ceiling};
    my $decayed = $tracker->{peak} * $tracker->{decay};
    $tracker->{peak} = $limited > $decayed ? $limited : $decayed;
    $tracker->{peak} = $tracker->{minimum} if $tracker->{peak} < $tracker->{minimum};
    my $fraction  = $tracker->{state} eq 'on' ? $KEY_HOLD_FRACTION : $KEY_ON_FRACTION;
    my $threshold = $tracker->{noise} + ($tracker->{peak} - $tracker->{noise}) * $fraction;
    $threshold = $tracker->{gate} if $threshold < $tracker->{gate};
    $tracker->{state} = $power >= $threshold ? 'on' : 'off';

    # Fading attacks and filter tails just below the switching threshold are
    # not reliable background observations. Keep them out of the noise floor.
    if ($tracker->{state} eq 'off' && $power < $NOISE_UPDATE_THRESHOLD_FRACTION * $threshold) {
        $tracker->{noise} += $NOISE_UPDATE_RATE * ($power - $tracker->{noise});
    }
    return $tracker->{state};
}

sub _segment {
    my ($self, $frames, $powers, $floor, $peak) = @_;
    my @segments;
    my $minimum = $floor + $TRACKED_PEAK_FLOOR_FRACTION * ($peak - $floor);
    my $tracker = {
        state   => 'off',
        noise   => $floor,
        gate    => $floor * $ENVELOPE_NOISE_GATE_RATIO,
        peak    => $minimum,
        minimum => $minimum,
        ceiling => $peak,
        decay   => exp(-$self->{frame_size} / $self->{sample_rate}),
    };
    my (@states, @noises);
    for my $i (0 .. $#{$frames}) {
        push @noises, $tracker->{noise};
        push @states, _key_state($tracker, $powers->[$i]);
    }
    _trim_bursts(\@states, $powers, $TRACKED_PEAK_CLAMP_RATIO * $peak);
    for my $i (0 .. $#{$frames}) {
        my $state = $states[$i];
        if (@segments && $segments[-1]{state} eq $state) {
            $segments[-1]{samples} += $frames->[$i]{samples};
            $segments[-1]{energy}  += $powers->[$i] * $frames->[$i]{samples};
        }
        else {
            push @segments,
                {
                state   => $state,
                samples => $frames->[$i]{samples},
                energy  => $powers->[$i] * $frames->[$i]{samples},
                noise   => $noises[$i]
                };
        }
    }

    # Use the local noise estimate captured on the OFF-to-ON transition.
    # Admission precedes glitch removal, which must not join a weak fragment
    # to a genuine mark across a short OFF interval.
    for my $run (@segments) {
        if (   $run->{state} eq 'on'
            && $run->{energy} / $run->{samples} < $run->{noise} * $self->{mark_snr_ratio})
        {
            $run->{state} = 'off';
        }
    }
    @segments =
        @{_merge_runs([map { +{state => $_->{state}, samples => $_->{samples}} } @segments])};

    # Remove isolated runs below 10 ms only when bounded by the same state.
    for (my $i = 1; $i < $#segments; ++$i) {
        if ($segments[$i]{samples} <
            (defined($self->{wpm}) && 0.36 / $self->{wpm} > 0.010 ? 0.36 / $self->{wpm} : 0.010) *
            $self->{sample_rate})
        {
            $segments[$i - 1]{samples} += $segments[$i]{samples} + $segments[$i + 1]{samples};
            splice @segments, $i, 2;
            $i -= 2;
            $i = 0 if $i < 0;
        }
    }
    return \@segments;
}

sub _trim_bursts {
    my ($states, $powers, $ceiling) = @_;

    # The tracker clamps anything above twice the seeded peak, so a burst far
    # stronger than the message keeps every smeared hop above the switching
    # threshold. Within such a run, hops below 22% of its top yet still above
    # the clamp are treated as burst smear; hops at message level may
    # be a genuine mark underneath the burst and stay keyed.
    my $i = 0;
    while ($i < @{$states}) {
        if ($states->[$i] ne 'on') { ++$i; next }
        my $end = $i;
        ++$end while $end < $#{$states} && $states->[$end + 1] eq 'on';
        my $top = 0;
        $top = $powers->[$_] > $top ? $powers->[$_] : $top for $i .. $end;
        if ($top > $ceiling) {
            $states->[$_] = 'off'
                for grep { $powers->[$_] < $BURST_TRIM_FRACTION * $top && $powers->[$_] > $ceiling }
                $i .. $end;
        }
        $i = $end + 1;
    }
    return;
}

sub _robust_peak {
    my ($powers) = @_;
    my $peak = 0;

    # Replicate endpoints, but do not let duplicated padding make an
    # isolated boundary impulse appear to have three observed support frames.
    for my $i (0 .. $#{$powers}) {
        my @local = sort { $a <=> $b }
            map { $powers->[$_ < 0 ? 0 : $_ > $#{$powers} ? $#{$powers} : $_] } $i - 2 .. $i + 2;
        my $first_frame = $i < 2               ? 0           : $i - 2;
        my $last_frame  = $i + 2 > $#{$powers} ? $#{$powers} : $i + 2;
        my $support     = grep { $powers->[$_] >= 0.25 * $local[2] } $first_frame .. $last_frame;
        next              if @{$powers} >= 3 && $support < 3;
        $peak = $local[2] if $local[2] > $peak;
    }
    return $peak;
}

sub _discard_short {
    my ($segments, $dot) = @_;
    my $changed = 0;
    for my $segment (@{$segments}) {
        if ($segment->{state} eq 'on' && $segment->{samples} < 0.45 * $dot) {
            $segment->{state} = 'off';
            ++$changed;
        }
    }
    @{$segments} = @{_merge_runs($segments)} if $changed;
    return $changed;
}

sub _merge_runs {
    my ($segments) = @_;
    my @merged;
    for my $segment (@{$segments}) {
        if (@merged && $merged[-1]{state} eq $segment->{state}) {
            $merged[-1]{samples} += $segment->{samples};
        }
        else { push @merged, {%{$segment}} }
    }
    return \@merged;
}

sub _group_quality {
    my ($segments, $indices, $dot, $decoder) = @_;
    my ($code, $valid) = ('', 1);
    for my $index (@{$indices}) {
        my $ratio = $segments->[$index]{samples} / $dot;
        $valid = 0 if $ratio < 0.45 || $ratio > 4.5 || ($ratio > 1.6 && $ratio < 2.3);
        $code .= $ratio < 2 ? '.' : '-';
    }
    my $recognized = $valid && eval { $decoder->decode($code); 1 };
    return {
        first  => $indices->[0],
        last   => $indices->[-1],
        count  => scalar(@{$indices}),
        valid  => $recognized                     ? 1 : 0,
        anchor => $recognized && @{$indices} >= 3 ? 1 : 0
    };
}

sub _morse_groups {
    my ($segments, $dot, $decoder) = @_;
    my (@groups, @pending);
    for my $i (0 .. $#{$segments}) {
        my $segment = $segments->[$i];
        if ($segment->{state} eq 'on') { push @pending, $i }
        if (
            @pending
            && ($i == $#{$segments}
                || ($segment->{state} eq 'off' && $segment->{samples} >= 2 * $dot))
            )
        {
            push @groups, _group_quality($segments, \@pending, $dot, $decoder);
            @pending = ();
        }
    }
    return \@groups;
}

sub _clean_margins {
    my ($segments, $dot, $decoder) = @_;
    my $changed = _discard_short($segments, $dot);
    my @groups  = @{_morse_groups($segments, $dot, $decoder)};
    my @anchors = grep { $groups[$_]{anchor} } 0 .. $#groups;
    return $changed unless @anchors;
    my ($first, $end_group) = ($anchors[0], $anchors[-1]);

    # Keep short genuine letters next to supported groups, and one damaged
    # group at either edge. Never edit damaged groups inside the message.
    --$first while $first > 0 && $groups[$first - 1]{valid};
    ++$end_group while $end_group < $#groups && $groups[$end_group + 1]{valid};
    --$first     if $first > 0            && $groups[$first - 1]{count} > 1;
    ++$end_group if $end_group < $#groups && $groups[$end_group + 1]{count} > 1;
    for my $i (0 .. $#{$segments}) {
        if (($i < $groups[$first]{first} || $i > $groups[$end_group]{last})
            && $segments->[$i]{state} eq 'on')
        {
            $segments->[$i]{state} = 'off';
            ++$changed;
        }
    }
    return $changed;
}

sub _smooth_power {
    my ($raw) = @_;
    my @powers;
    for my $i (0 .. $#{$raw}) {
        my @values = sort { $a <=> $b }
            map { $raw->[$_ < 0 ? 0 : $_ > $#{$raw} ? $#{$raw} : $_] } $i - 1 .. $i + 1;
        push @powers, $values[1];
    }
    return \@powers;
}

sub _decode_channel {
    my ($self, $segments, $complete) = @_;
    my $long_mark =
        defined($self->{wpm})
        ? 6 * 1.2 / $self->{wpm} * $self->{sample_rate}
        : 6 * 0.24 * $self->{sample_rate};
    my $ignored_carriers = 0;

    for my $segment (@{$segments}) {
        if ($segment->{state} eq 'on' && $segment->{samples} > $long_mark) {
            $segment->{state} = 'off';
            ++$ignored_carriers;
        }
    }
    $segments = _merge_runs($segments);
    my $events  = {sample_rate => $self->{sample_rate}, segments => $segments};
    my %timing  = map { defined($self->{$_}) ? ($_ => $self->{$_}) : () } qw(wpm effective_wpm);
    my $decoder = Ham::RTTY::Decoder->new(%timing);
    $decoder->feed($events);
    my $r = $complete ? $decoder->finish : $decoder->result;
    my $trimmed =
        $r->wpm && _clean_margins($segments, $self->{sample_rate} * 1.2 / $r->wpm, $decoder);

    if ($trimmed) {
        $events->{segments} = _merge_runs($segments);
        $decoder->reset->feed($events);
        $r = $complete ? $decoder->finish : $decoder->result;
    }
    my $h = $r->as_hash;
    push @{$h->{warnings}},
        {
        code    => 'RTTY_W_INTERFERENCE',
        message => 'Unsupported activity outside coherent Morse groups excluded'
        }
        if $trimmed;
    push @{$h->{warnings}},
        {
        code    => 'RTTY_W_INTERFERENCE',
        message => 'Continuous carrier intervals excluded from Morse timing'
        }
        if $ignored_carriers;

    if (grep { $_->{code} eq 'RTTY_W_TIMING_AMBIGUOUS' } @{$h->{warnings}}) {
        $h->{text} = '';
        push @{$h->{warnings}},
            {
            code    => 'RTTY_W_UNRELIABLE',
            message => 'Specify WPM to resolve ambiguous mark lengths'
            };
    }
    return $h;
}

sub _analyze_channel {
    my ($self, $complete, $best) = @_;
    my @frames = @{$self->{frames}};
    my $empty  = sub {
        my ($code, $message, $diagnostics) = @_;
        return Ham::RTTY::_Internal::Result->from_owned(
            'Ham::RTTY::Result',
            complete    => $complete,
            events      => {sample_rate => $self->{sample_rate}, segments => []},
            warnings    => [{code => $code, message => $message}],
            diagnostics => $diagnostics // {}
        );
    };
    return $empty->('RTTY_W_NO_SIGNAL', 'No usable audio frames') unless @frames;
    my @powers = @{_smooth_power([map { $_->{powers}[$best] } @frames])};
    my @sorted = sort { $a <=> $b } @powers;

    my $peak = _robust_peak(\@powers);

    # At least three marks must support reception. Cap the seed by the energy
    # sustained for half their combined minimum duration, rather than allowing
    # one strong impulse plus filter ringing to set the gain for a weak message.
    my $support =
        int((defined($self->{wpm}) ? 1.8 / $self->{wpm} : 0.060) *
            $self->{sample_rate} /
            $self->{frame_size} + 0.5);
    if (@sorted >= $support && $sorted[-$support] < $peak) { $peak = $sorted[-$support] }
    return $empty->('RTTY_W_NO_SIGNAL', 'Signal below energy floor') if $peak < 1e-10;
    my $floor    = $sorted[int($#sorted * 0.10)];
    my $contrast = ($peak - $floor) / $peak;
    return $empty->('RTTY_W_NOT_CW', 'No keyed envelope contrast', {contrast => $contrast})
        if $contrast < $self->{min_contrast};
    my $purity = $self->_purity(\@frames, \@powers, $peak, $best);
    return $empty->('RTTY_W_NOT_CW', 'Insufficient narrow-band energy', {purity => $purity})
        if $purity < $self->{min_purity};
    my $segments = $self->_segment(\@frames, \@powers, $floor, $peak);
    my @marks    = grep { $_->{state} eq 'on' } @{$segments};
    return $empty->('RTTY_W_NOT_CW', 'Too few keyed marks to identify CW') if @marks < 3;
    my $h = $self->_decode_channel($segments, $complete);
    $h->{frequency}   = $self->{frequencies}[$best];
    $h->{diagnostics} = {
        %{$h->{diagnostics}},
        purity                 => $purity,
        contrast               => $contrast,
        frame_samples          => $self->{frame_size},
        analyzed_samples       => $self->{total_samples},
        filter_bandwidth_hz    => $self->{filter_bandwidth},
        filter_sections        => 2,
        mark_snr_db            => $self->{mark_snr_db},
        frequency_grid_step_hz => defined($self->{frequency}) ? 0 : ($self->{frequency_step} // 50)
    };
    return Ham::RTTY::_Internal::Result->from_owned('Ham::RTTY::Result', %{$h});
}

sub result {
    my ($self) = @_;
    return $self->{final} // ($self->{snapshot} //= $self->_analyze(0));
}

sub finish {
    my ($self) = @_;
    return $self->{final}          if $self->{state} eq 'FINISHED';
    $self->_frame($self->{buffer}) if @{$self->{buffer}};
    $self->{buffer} = [];
    $self->_compensate_delay;
    $self->{final}    = $self->_analyze(1);
    $self->{state}    = 'FINISHED';
    $self->{snapshot} = undef;
    return $self->{final};
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Detector - incremental channelized CW audio reception

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;
    use Ham::RTTY::Detector;

    my $cw = Ham::RTTY->new(sample_rate => 8000, frequency => 650, wpm => 20);
    my $next = $cw->stream_samples('SOS', block_size => 1024);
    my $detector = Ham::RTTY::Detector->new(
        sample_rate => 8000, frequency => 650, wpm => 20);
    while (my $block = $next->()) { $detector->feed($block) }
    my $result = $detector->finish;
    print $result->text, "\n";
    warn "Inspect reception warnings\n" if $result->has_warnings;

=head1 DESCRIPTION

Decodes normalized mono samples into cumulative snapshots. Supply the actual
sample rate; the detector does not resample. For WAV input, L<Ham::RTTY/read_wav>
and L<Ham::RTTY/decode_wav_bytes> read the rate from the header.

Reception is experimental. Separate band-pass channels can recover CW on
distinct tones. C<result> and C<finish> return the strongest accepted channel;
C<channels> returns up to eight candidates with independent timing, text and
warnings. A frequency hint restricts analysis to one tone.

Co-channel signals cannot be separated. Noise can produce false candidates;
fading, interference and large frequency drift can cause missing or incorrect
text. Short messages may need tone and speed hints. Detection requires at
least three keyed marks, so an isolated E or T cannot be recognized as CW.

=head1 METHODS

=head2 new

    my $detector = Ham::RTTY::Detector->new(%options);

Returns a detector in C<READY>. Options and inclusive ranges:

=over 4

=item * C<sample_rate>: 16000 Hz; integer 1000..384000.

=item * C<frequency>: optional known tone, 1..C<sample_rate / 2 - 1> Hz. Undefined/omitted means search the frequency grid.

=item * C<min_frequency>: 300 Hz; range 1..C<sample_rate / 2 - 1>.

=item * C<max_frequency>: the smaller of 1500 and C<sample_rate / 2 - 1> Hz; must be at least C<min_frequency> and at most C<sample_rate / 2 - 1>.

=item * C<frequency_step>: 50 Hz; range 10..500. Grid candidates start at the minimum and advance by this step without exceeding the maximum. At most 256 candidates are allowed.

=item * C<wpm>: optional explicit character speed, range 1..60. Undefined/omitted means estimate within 5..60 WPM.

=item * C<effective_wpm>: optional spacing speed, range 1..WPM when WPM is explicit, otherwise 1..60. Omitted/undefined uses ordinary spacing; specify it for Farnsworth reception.

=item * C<filter_bandwidth>: full single-section half-power width in Hz; default C<max(40, 4 * wpm)> with explicit WPM, otherwise 180. Range 20..C<sample_rate / 2 - 1>. Two identical biquads are cascaded, so the combined half-power width is narrower. Narrow settings improve rejection but increase ringing and can merge fast marks; choose width for the fastest sender of interest.

=item * C<min_snr_db>: 12 dB; range 0..40. Acquisition threshold comparing a raw-window candidate power with a local guard-bin noise estimate. This is an algorithmic spectral contrast threshold, not a calibrated receiver SNR measurement. Lower values admit weaker tones and more false detections.

=item * C<mark_snr_db>: 10 dB; range 0..40. Minimum mean ON-run power relative to the tracker's local noise estimate captured at run start. Failed runs become OFF and merge before short-glitch cleanup. This is a detector feature-power ratio, not a calibrated radio SNR measurement.

=item * C<min_contrast>: 0.60; range 0.01..1, minimum keyed-envelope contrast.

=item * C<min_purity>: 0.20; range 0.01..1, minimum projected narrow-band energy ratio within the filtered channel. Other stations do not contribute directly to the denominator. This ratio is not normalized to 1 for a pure tone.

=item * C<max_frames>: 24000; integer 1..1000000, including frames representing recording silence.

=item * C<backend>: C<perl> (default), C<pdl> or C<auto>. See L<Ham::RTTY/OPTIONAL PDL BACKEND>.

=back

Frequency search settings are still validated when a known tone is given.
Other undefined optional values use defaults. Unknown/duplicate names and
invalid ranges raise C<RTTY_E_ARGUMENT>; too many candidates raise
C<RTTY_E_RESOURCE>. Explicit effective speed must not exceed explicit WPM.

=head2 feed

    $detector->feed($samples);

Accepts an array reference of finite numbers in [-1,1], at most 1000000
samples per call, and returns the object. Empty blocks are valid. Accepted
feeds set C<ACTIVE> and invalidate the preview cache. Validation/resource
errors preserve history, buffer and state. Feed after finish raises
C<RTTY_E_STATE>.

Frames have C<int(sample_rate * 0.005 + 0.5)> samples, approximately 5 ms.
A partial frame is carried between feeds; chunk boundaries do not change the
frame grid. In addition to the partial frame, fixed histories retain four hops per filtered channel and eight raw hops for acquisition. Filter states persist across feeds. Per-channel powers and energies are retained for the entire accepted recording up to C<max_frames>.
A pending partial frame also counts against that limit.

=head2 result

    my $preview = $detector->result;

Returns a provisional L<Ham::RTTY::Result> with C<complete> 0 without flushing
the partial frame. It analyzes all retained complete frames. Earlier text,
tone, timing and diagnostics may change after more audio. Unchanged previews
are cached. Candidate energy totals are accumulated as frames arrive. A fresh
preview after a feed still sorts and resegments the retained history: O(K N log N)
for N frames and K candidate frequencies, with O(N) temporary storage per analyzed channel. K is limited to 256. Throttle previews (for example once
per second); do not request one after every tiny input block. After finish,
this returns the cached final Result.

=head2 finish

    my $final = $detector->finish;

Processes any partial frame once. It flushes the filters with a bounded zero tail,
compensates the nominal filter/window group delay on the hop grid, and
keeps only features corresponding to the actual input length. Padding does not
count as received samples or consume C<max_frames>. It finalizes decoding, sets C<FINISHED> and
returns a complete Result. Repeated calls return the cached Result. Previews use causal, uncompensated features; final alignment can change their text and event boundaries.
No-signal or uncertain input can still finish successfully with empty text and warnings.

=head2 channels

    my $stations = $detector->channels;
    for my $station (@{$stations}) {
        printf "%g Hz: %s\n", $station->frequency, $station->text;
    }

Returns a fresh array reference containing up to eight cached
L<Ham::RTTY::Result> snapshots, in descending accumulated channel-energy order.
The first is the C<result>/C<finish> result when a station was accepted.
Before finish, Results are provisional; this call has the same analysis/cache
cost as C<result> and does not flush partial input. Finished Results are complete.
Changing the returned array cannot alter the cached list.

Candidates are local maxima on the configured frequency grid. Accepted
channels must be separated by at least C<max(100, filter_bandwidth)> Hz;
this de-duplicates neighboring bins, not a universal resolving specification.
The synthetic suite recovers two keyed tones 150 Hz apart at 20 WPM and
250 Hz apart with independently estimated 20/25 WPM timing. Closer tones,
large level differences or different signal conditions may not be separable.
The same WPM/effective-WPM hint applies to all channels; omit WPM to estimate
each independently. A frequency hint produces at most one channel.

An empty array means no channel yielded a decodable symbol. Use C<result>
to inspect the primary rejection warning. A replacement-only result may be
returned by C<result> but is not included as a station. No channel limit or
frequency spacing can prevent every false positive.

=head2 reset

    $detector->reset;

Discards audio features, partial input, progress and snapshots; preserves
configuration, restores C<READY> and returns the object. Previous Results
remain independent.

=head2 state

    my $state = $detector->state;

Returns C<READY>, C<ACTIVE> or C<FINISHED>.

=head1 ANALYSIS AND DIAGNOSTICS

The input advances in approximately 5 ms hops. Each frequency candidate
has two stateful constant-peak biquad band-pass sections. Four filtered hops
form an approximately 20 ms analysis window, with DC removal and Hann
weighting. Perl uses Goertzel power; PDL uses equivalent sinusoidal
projections after the same filters.

Acquisition independently examines eight raw hops (approximately 40 ms).
Each hop contributes one Fourier projection per candidate and guard
frequency; the eight projections are combined under a hop-wise Hann taper
with the window mean removed, so a new hop costs one projection rather than a
transform of the whole window. A candidate must exceed a
noise estimate from up to six guards at offsets of one, two and three times
C<max(100, 2 * frequency_step)> Hz. Out-of-band guards are omitted. The lower
median guard power, scaled by 1.3, supplies the threshold reference. Filtered
power is gated by this test; filtering alone would otherwise turn broadband
noise into a narrow-band envelope. Few available guards near band edges
make acquisition less discriminating.

Accumulated per-channel energy ranks spectral maxima. Each is checked for
keyed contrast, filtered spectral purity, at least three marks and Morse
timing. A three-hop median smooths power. The peak seed uses a five-hop
median with observed endpoint support, capped by sustained power to limit
isolated impulses and filter ringing. The lower decile seeds the noise floor.
Segmentation tracks keyed peaks with one-second decay, updates noise during
OFF frames and uses hysteresis. Each provisional ON run must have a
sample-weighted mean power at least C<10 ** (mark_snr_db / 10)> times the
tracker's noise estimate at the start of that run. Failed runs become OFF;
adjacent OFF runs merge before the existing short-interior-glitch cleanup.
A run whose power exceeds twice the seeded peak is far stronger than the
message; hops below 22% of its own top but still above that clamp are
removed before admission, so a short burst smeared by the analysis window
does not become a mark, while message-level hops underneath the burst stay
keyed.
The gate and its noise reference use the same smoothed channel powers as
the tracker. OFF observations must also be below one quarter of the switching
threshold to update the noise estimate; this avoids treating a fading attack
or filter decay as background noise. This is separate from C<min_snr_db>,
the acquisition threshold.

ON intervals longer than six configured dots (or 1.44 seconds before automatic
timing) are treated as carrier interference. After timing estimation,
sub-tolerance short marks are removed. At the margins, groups with at least
three valid marks anchor the retained message. Adjacent valid short letters
and one neighboring damaged multi-mark group are kept; unsupported outer
activity is suppressed. Damaged groups between anchors remain visible as
replacement characters. These heuristics can discard genuine badly damaged
edge characters; they do not perform linguistic correction. Exclusions
produce C<RTTY_W_INTERFERENCE>. Inspect text, events and warnings together.

C<contrast> is C<(peak - floor) / peak>. C<purity> compares projected tone
energy with the windowed energy of that filtered channel; a matched pure
tone is approximately 0.67, not 1. C<frequency_grid_step_hz> reports candidate
spacing (0 for a supplied tone), not frequency accuracy or filter bandwidth.
The synthetic matrix tests tone error within one configured grid step (50 Hz
by default), an empirical tolerance rather than a universal bound. A 20 ms
Hann window alone has approximately 70 Hz full half-power width; the preceding
filters also shape selectivity. Candidate spacing does not specify the ability
to resolve neighboring stations. L<Ham::RTTY::Result/diagnostics> lists fields.

=head1 LIMITS AND WARNINGS

Maximum retained seconds are approximately
C<max_frames * frame_samples / sample_rate>, about 120 seconds by default.
Increase C<max_frames> explicitly for longer recordings and budget more
memory. Large arrays have their own per-feed limit. Streaming input does not
make this an unlimited-duration receiver.

The design targets reasonably stable CW on distinct tones and mark lengths of about
20 ms or longer. Severe fading, sustained static, co-channel tones and unknown
Farnsworth spacing can cause wrong, partial or empty text. Field accuracy on
off-air recordings has not been established by the synthetic tests.

A single-length mark pattern remains ambiguous without WPM; the detector
suppresses its guessed text and reports warnings. Individual damaged groups
otherwise use replacement characters while retaining other text. Review
L<Ham::RTTY::Result/WARNINGS>; completion is not a confidence estimate.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
