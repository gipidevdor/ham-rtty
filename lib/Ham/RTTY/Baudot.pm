package Ham::RTTY::Baudot;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::_Internal::Validate qw(fail options named_arguments integer);
our $VERSION = '0.01';
my @LETTERS = (
    "\0", 'E', "\n", 'A',   ' ', 'S', 'I', 'U', "\r", 'D', 'R', 'J',
    'N',  'F', 'C',  'K',   'T', 'Z', 'L', 'W', 'H',  'Y', 'P', 'Q',
    'O',  'B', 'G',  undef, 'M', 'X', 'V', undef
);
my @FIGURES = (
    "\0", '3',   "\n",  '-',   ' ', "'", '8', '7', "\r",  "\x05", '4', "\a",
    ',',  undef, ':',   '(',   '5', '+', ')', '2', undef, '6',    '0', '1',
    '9',  '?',   undef, undef, '.', '/', '=', undef
);
my %VARIANTS = (
    ita2 => {},
    us   => {5 => "\a", 9 => '$', 11 => "'", 13 => '!', 17 => '"', 20 => '#', 26 => '&', 30 => ';'}
);

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(variant usos));
    my $variant = $args{variant} // 'ita2';
    fail('RTTY_E_ARGUMENT', 'variant must be ita2 or us')
        if ref($variant) || !exists $VARIANTS{$variant};
    my @figures = @FIGURES;
    $figures[$_] = $VARIANTS{$variant}{$_} for keys %{$VARIANTS{$variant}};
    return bless {
        letters => [@LETTERS],
        figures => \@figures,
        mode    => 'letters',
        usos    => integer('usos', $args{usos} // 1, 0, 1)
    }, $class;
}

sub tables {
    my ($self) = @_;
    return {letters => [@{$self->{letters}}], figures => [@{$self->{figures}}]};
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;
    $self->{mode} = 'letters';
    return $self;
}

sub character {
    my ($self, $code) = @_;
    integer('code', $code, 0, 31);
    if ($code == 31 || $code == 27) {
        $self->{mode} = $code == 31 ? 'letters' : 'figures';
        return '';
    }
    my $char = $self->{$self->{mode}}[$code];
    fail('RTTY_E_SYMBOL', 'Unassigned figures combination') unless defined $char;
    $self->{mode} = 'letters' if $code == 4 && $self->{usos};
    return $char;
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Baudot - ITA2 code tables and receiver shift state

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Baudot;
    my $codec = Ham::RTTY::Baudot->new;
    print $codec->character(3), "\n";

=head1 METHODS

=head2 new

Ham::RTTY::Baudot->new(variant => 'ita2', usos => 1) constructs a fresh LTRS receiver. C<variant> is C<ita2> or C<us>; C<usos> is integer 0 or 1. Unknown or duplicate options raise C<RTTY_E_ARGUMENT>.

=head2 tables

$codec->tables returns a fresh hash with C<letters> and C<figures> arrays indexed by numeric code 0..31. Undefined entries are shifts or unassigned combinations; changing this copy cannot change the codec.

=head2 reset

$codec->reset restores LTRS state and returns the object.

=head2 character

$codec->character($code) accepts an integer 0..31 and returns a character. Shifts return an empty string and change state. NULL returns U+0000, BELL U+0007 and WRU U+0005. Unassigned figures raise C<RTTY_E_SYMBOL>. SPACE restores LTRS when USOS is enabled.

=head1 TABLE VARIANTS

The ITU table follows S.1 (03/93). ASCII apostrophe and hyphen represent its
printed signs. National FIGS positions F, G and H remain unassigned.
US TTY changes figures as follows; all other assigned positions are shared:

    Letter  ITU       US
    D       WRU       $
    F       reserved  !
    G       reserved  &
    H       reserved  #
    J       BELL      apostrophe
    S       apostrophe BELL
    V       =         ;
    Z       +         double quote

S.1: L<https://www.itu.int/rec/T-REC-S.1-199303-I/en>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli. Artistic License 2.0. See F<LICENSE>.

=cut
