package Ham::RTTY::_Internal::IO;
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use Exporter 'import';
use File::Basename                 qw(dirname);
use File::Temp                     qw(tempfile);
use Fcntl                          qw(O_RDONLY O_WRONLY O_CREAT O_EXCL);
use Ham::RTTY::_Internal::Validate qw(fail);
our @EXPORT_OK = qw(read_exact write_bytes with_file);

sub read_exact {
    my ($fh, $count) = @_;
    my $out = '';
    while (length($out) < $count) {
        my $n = read($fh, my $part, $count - length($out));
        fail('RTTY_E_IO',            'Cannot read WAV handle') unless defined $n;
        fail('RTTY_E_WAV_TRUNCATED', 'Unexpected end of WAV')  unless $n;
        $out .= $part;
    }
    return $out;
}

sub write_bytes {
    my ($fh, $bytes) = @_;

    # A closed pipe must become an I/O exception, not terminate the caller.
    local $SIG{PIPE} = 'IGNORE' if exists $SIG{PIPE};
    print {$fh} $bytes or fail('RTTY_E_IO', 'Cannot write WAV handle');
    return;
}

sub _file_error {
    my ($path, $action, $reason) = @_;
    return Ham::RTTY::Error->throw(
        code    => 'RTTY_E_IO',
        message => "Cannot $action file '$path': $reason",
        context => {path => $path, action => $action, reason => "$reason"}
    );
}

sub _replacement_mode {
    my ($path) = @_;
    my @info = lstat $path;
    if (!@info) {
        _file_error($path, 'inspect', "$!") unless $!{ENOENT};
        return oct('0666') & ~umask;
    }
    _file_error($path, 'replace', 'symbolic link destinations are not supported') if -l _;
    _file_error($path, 'replace', 'destination must be a regular file') unless -f _;
    return $info[2] & oct('07777');
}

sub with_file {
    my ($path, $mode, $action, $overwrite) = @_;
    fail('RTTY_E_ARGUMENT', 'File path must be a nonempty string without NUL characters')
        if !defined($path) || ref($path) || !length($path) || index($path, "\0") >= 0;
    my $writing = $mode eq 'write';
    my $flags   = $writing ? O_WRONLY | O_CREAT | O_EXCL : O_RDONLY;
    my ($handle, $temporary);
    if ($writing && $overwrite) {
        _replacement_mode($path);
        my $opened = eval {
            ($handle, $temporary) =
                tempfile('.ham-rtty-XXXXXX', DIR => dirname($path), UNLINK => 0);
            1;
        };
        _file_error($path, 'open temporary output for', "$@") unless $opened;
    }
    else {
        sysopen $handle, $path, $flags or _file_error($path, 'open', "$!");
    }
    my $value;
    my $ok = eval {
        binmode $handle, ':raw' or _file_error($path, 'set binary mode on', "$!");
        $value = $action->($handle);
        if (defined $temporary) {
            my $permissions = _replacement_mode($path);
            chmod($permissions, $temporary) == 1
                or _file_error($path, 'set permissions on', "$!");
        }
        1;
    };
    my $error       = $@;
    my $closed      = close $handle;
    my $close_error = "$!";
    if (!$ok || !$closed) {
        unlink($temporary // $path) if $writing;
        croak $error unless $ok;
        _file_error($path, 'close', $close_error);
    }
    if (defined $temporary) {
        if (!rename($temporary, $path)) {
            my $reason = "$!";
            unlink $temporary;
            _file_error($path, 'replace', $reason);
        }
    }
    return $value;
}

1;
