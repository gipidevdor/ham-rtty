package Ham::RTTY::_Internal::Symbols;
use 5.020;
use strict;
use warnings;
use utf8;
use Exporter 'import';
our @EXPORT_OK = qw(alphabet reverse_alphabet prosigns);

sub alphabet {
    return {
        A    => '.-',
        B    => '-...',
        C    => '-.-.',
        D    => '-..',
        E    => '.',
        F    => '..-.',
        G    => '--.',
        H    => '....',
        I    => '..',
        J    => '.---',
        K    => '-.-',
        L    => '.-..',
        M    => '--',
        N    => '-.',
        O    => '---',
        P    => '.--.',
        Q    => '--.-',
        R    => '.-.',
        S    => '...',
        T    => '-',
        U    => '..-',
        V    => '...-',
        W    => '.--',
        X    => '-..-',
        Y    => '-.--',
        Z    => '--..',
        'É'  => '..-..',
        0    => '-----',
        1    => '.----',
        2    => '..---',
        3    => '...--',
        4    => '....-',
        5    => '.....',
        6    => '-....',
        7    => '--...',
        8    => '---..',
        9    => '----.',
        '.'  => '.-.-.-',
        ','  => '--..--',
        ':'  => '---...',
        '?'  => '..--..',
        q{'} => '.----.',
        '-'  => '-....-',
        '/'  => '-..-.',
        '('  => '-.--.',
        ')'  => '-.--.-',
        q{"} => '.-..-.',
        '='  => '-...-',
        '+'  => '.-.-.',
        '@'  => '.--.-.',
        '×'  => '-..-',
    };
}

sub prosigns {
    return {
        BT => '-...-',
        AR => '.-.-.',
        AS => '.-...',
        CT => '-.-.-',
        SK => '...-.-',
        HH => '........',
        SN => '...-.'
    };
}

sub reverse_alphabet {
    my ($prefer_prosigns) = @_;
    my $a = alphabet();
    my %r;

    # The ITU multiplication sign uses the letter X waveform.
    for my $symbol (sort keys %{$a}) { $r{$a->{$symbol}} //= $symbol }
    my $p = prosigns();

    # Only signals from ITU-R M.1677-1, Annex 1, section 1.1.3.
    # These tokens are library mnemonics for the named ITU signals.
    for my $name (qw(AR AS BT CT HH SK SN)) {
        $r{$p->{$name}} = "<$name>" if $prefer_prosigns || !exists $r{$p->{$name}};
    }
    return \%r;
}
1;
