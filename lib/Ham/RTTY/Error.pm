package Ham::RTTY::Error;
use 5.020;
use strict;
use warnings;
use overload q{""} => 'as_string', fallback => 1;
use Carp                       qw(croak);
use Storable                   qw(dclone);
use Ham::RTTY::_Internal::Data qw(plain_data);
our $VERSION = '0.001';

sub _argument_error {
    my ($message) = @_;
    croak bless {code => 'RTTY_E_ARGUMENT', message => $message, context => {}}, __PACKAGE__;
}

sub new {
    my ($class, @pairs) = @_;
    if (@pairs % 2) {
        _argument_error('Options must be name/value pairs');
    }
    my %args;
    my %allowed = map { $_ => 1 } qw(code message context);
    while (@pairs) {
        my ($name, $value) = splice @pairs, 0, 2;
        _argument_error('Unknown, duplicate or invalid error option')
            if !defined($name) || ref($name) || !$allowed{$name} || exists $args{$name};
        $args{$name} = $value;
    }
    for my $name (qw(code message)) {
        _argument_error("$name must be a defined scalar")
            if exists($args{$name}) && (!defined($args{$name}) || ref($args{$name}));
    }
    _argument_error('context must be a hash of plain, acyclic data, at most 64 levels deep')
        if exists($args{context})
        && (ref($args{context}) ne 'HASH' || !plain_data($args{context}));
    return bless {
        code    => $args{code}    // 'RTTY_E_INTERNAL',
        message => $args{message} // 'Unspecified error',
        context => dclone($args{context} // {})
    }, $class;
}
sub throw     { my ($class, @args) = @_; croak $class->new(@args) }
sub code      { my ($self) = @_; return $self->{code} }
sub message   { my ($self) = @_; return $self->{message} }
sub context   { my ($self) = @_; return dclone($self->{context}) }
sub as_string { my ($self) = @_; return $self->{code} . ': ' . $self->{message} }
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Error - structured exceptions for argument, timing and I/O failures

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;

    my $rtty = Ham::RTTY->new;
    my $ok = eval { $rtty->encode('CQ!'); 1 };
    if (!$ok) {
        my $error = $@;
        if (ref($error) && $error->isa('Ham::RTTY::Error')) {
            warn $error->code . ': ' . $error->message . "\n";
            my $context = $error->context;
        }
        else { die $error; }
    }

=head1 DESCRIPTION

Fatal library failures throw Error objects. Catch them using C<eval> and save
C<$@> immediately; later evals or destructors can change that variable.
Branch on C<code> instead of parsing prose or a stack-location suffix.
Recoverable reception uncertainty is returned as Result warnings instead.

=head1 METHODS

=head2 new

    my $error = Ham::RTTY::Error->new(
        code => 'RTTY_E_ARGUMENT', message => 'Invalid input', context => {});

Constructs and returns an exception without throwing it. C<code> defaults to
C<RTTY_E_INTERNAL>, C<message> to C<Unspecified error> and C<context> to an empty
hash. Explicit code/message values must be defined scalars. Context must be
an unblessed hash containing plain scalar leaves and unblessed arrays/hashes,
with no cycles and depth at most 64. It is copied on construction.
Unknown/duplicate options and invalid payloads throw C<RTTY_E_ARGUMENT>.

=head2 throw

    Ham::RTTY::Error->throw(code => 'RTTY_E_ARGUMENT', message => 'Invalid input');

Class method accepting C<new> options. Constructs and throws the object using
Carp; normal execution does not return from this call.

=head2 code

    my $code = $error->code;

Returns the machine-readable code. Public library codes and suggested checks
are listed in L<Ham::RTTY/ERRORS>.

=head2 message

    my $message = $error->message;

Returns the human-readable explanation without requiring string parsing.
Message wording is descriptive; use the code for program decisions.

=head2 context

    my $context = $error->context;

Returns a deep copy of the context hash. Fields are optional and depend on
the failure. Unsupported encoding symbols provide C<symbol> and one-based
C<position> in the original character string. Path open/close/replacement
errors provide C<path>, C<action> and C<reason>. Processing errors propagated
through a path helper can retain their original context instead.

=head2 as_string

    my $description = $error->as_string;

Returns C<code: message>. The same conversion is used when the object is
interpolated or stringified. Carp can add a call location when throwing it;
that formatted representation should not be parsed as a protocol.

=head1 SEE ALSO

L<Ham::RTTY/ERRORS>, L<Ham::RTTY::Result/WARNINGS>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
