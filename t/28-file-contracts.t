use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(sample_rate => 8000);
my $root = tempdir(CLEANUP => 1);
my $path = File::Spec->catfile($root, 'permissions.wav');
$rtty->write_wav('SOS', $path);
$rtty->write_wav('CQ TEST', $path, overwrite => 1);
SKIP: {
    skip 'POSIX permission bits are not portable on Windows', 1 if $^O eq 'MSWin32';
    chmod 0644, $path or die $!;
    $rtty->write_wav('CQ TEST', $path, overwrite => 1);
    is((stat($path))[2] & 0777, 0644, 'atomic overwrite preserves permissions');
}
my $link = File::Spec->catfile($root, 'linked.wav');
SKIP: {
    skip 'symbolic links unavailable', 3 unless eval { symlink($path, $link) };
    eval { $rtty->write_wav('TEST', $link, overwrite => 1) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'overwrite rejects symlink destinations');
    ok(-l $link, 'overwrite preserves the symbolic link');
    is($rtty->read_wav($path)->text, 'CQ TEST', 'symlink target remains unchanged');
}
my $decoder = Ham::RTTY::Decoder->new(baud => 50);
$decoder->feed({unit => 'us', segments => [{state => 'mark', duration => 30000}]});
my $before = $decoder->result;
$decoder->feed({unit => 'us', segments => [{state => 'mark', duration => 30000}]});
is($before->events->{segments}[0]{duration}, 30000, 'old snapshot survives a coalescing feed');
is($decoder->result->events->{segments}[0]{duration}, 60000,
    'new snapshot includes coalesced mark');

my $fresh = File::Spec->catfile($root, 'new-overwrite.wav');
$rtty->write_wav('SOS', $fresh, overwrite => 1);
is($rtty->read_wav($fresh)->text, 'SOS', 'overwrite permits a new regular destination');
my @temporary = glob(File::Spec->catfile($root, '.ham-rtty-*'));
is_deeply(\@temporary, [], 'replacement leaves no temporary files');

SKIP: {
    skip 'POSIX umask permissions unavailable on Windows', 1 if $^O eq 'MSWin32';
    my $new_path = File::Spec->catfile($root, 'umask.wav');
    my $previous = umask oct('0027');
    my $ok       = eval { $rtty->write_wav('SOS', $new_path, overwrite => 1); 1 };
    my $error    = $@;
    umask $previous;
    die $error unless $ok;
    is((stat($new_path))[2] & 0777, 0640, 'new replacement respects umask');
}
my $dangling = File::Spec->catfile($root, 'dangling.wav');
SKIP: {
    skip 'symbolic links unavailable', 2 unless eval { symlink('missing.wav', $dangling) };
    eval { $rtty->write_wav('TEST', $dangling, overwrite => 1) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'dangling link rejected');
    ok(-l $dangling, 'dangling link preserved');
}
eval { $rtty->write_wav('SOS', $root, overwrite => 1) };
is(ref($@) ? $@->code : "$@", 'RTTY_E_IO', 'directory replacement rejected');
{
    open my $append, '>>:raw', $fresh or die $!;
    print {$append} 'trailing' or die $!;
    close $append              or die $!;
}
my $callbacks = 0;
my $metadata  = Ham::RTTY::Audio->new(block_samples => 137)->read_blocks(
    $fresh,
    sub {
        my ($block, $info) = @_;
        if (++$callbacks <= 2) {
            is(scalar @{$info->{warnings}}, 1, 'callback warning list is independent');
            is($info->{warnings}[0]{code},
                'RTTY_W_WAV_TRAILING', 'nested callback warning is independent');
        }
        $info->{warnings}[0]{code} = 'changed';
        push @{$info->{warnings}}, {code => 'extra', message => 'caller mutation'};
    }
);
is($metadata->{warnings}[0]{code}, 'RTTY_W_WAV_TRAILING', 'returned metadata preserves warning');
done_testing;
