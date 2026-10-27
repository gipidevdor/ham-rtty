package FaultHandle;
use strict;
use warnings;

sub TIEHANDLE {
    my ($class, %args) = @_;
    return bless {bytes => '', position => 0, calls => {}, %args}, $class;
}

sub _fails {
    my ($self, $operation) = @_;
    my $number = ++$self->{calls}{$operation};
    return defined($self->{fail}{$operation}) && $number == $self->{fail}{$operation};
}
sub BINMODE { my ($self) = @_; return !$self->_fails('binmode') }

sub SEEK {
    my ($self, $offset, $whence) = @_;
    return 0 if $self->_fails('seek');
    $self->{position} =
        ($whence == 2 ? length($self->{bytes}) : $whence == 1 ? $self->{position} : 0) + $offset;
    return 1;
}
sub TELL { return $_[0]->{position} }

sub READ {
    my ($self, undef, $count) = @_;
    return if $self->_fails('read');
    $count = $self->{max_read} if defined($self->{max_read}) && $count > $self->{max_read};
    $_[1]  = substr($self->{bytes}, $self->{position}, $count);
    $self->{position} += length $_[1];
    return length $_[1];
}

sub PRINT {
    my ($self, @bytes) = @_;
    return 0 if $self->_fails('print');
    $self->{bytes} .= join('', @bytes);
    return 1;
}
sub CLOSE { return 1 }
1;
