#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use Archive::Tar 3.10;
use ExtUtils::Manifest qw(maniread);

my ($output, $directory) = @ARGV;
die "Usage: perl maint/archive.pl OUTPUT.tar DIST_DIRECTORY\n"
    unless defined($output) && defined($directory) && -d $directory;
croak "Missing distribution MANIFEST" unless -f "$directory/MANIFEST";
my $manifest = maniread("$directory/MANIFEST");
my @files    = map { "$directory/$_" } sort keys %{$manifest};
croak "Empty distribution MANIFEST" unless @files;
for my $path (@files) {
    croak "Missing or unreadable distribution file: $path" unless -f $path && -r $path;
}
my $archive = Archive::Tar->new;
my @added   = $archive->add_files(@files);
croak "Incomplete distribution archive: " . $archive->error unless @added == @files;
for my $file ($archive->get_files) {
    $file->uid(0);
    $file->gid(0);
    $file->uname('');
    $file->gname('');
    $file->mode(($file->mode & oct '111') ? oct '755' : oct '644');
    $file->mtime($ENV{SOURCE_DATE_EPOCH}) if defined $ENV{SOURCE_DATE_EPOCH};
}
$archive->write($output) or croak "Cannot write $output: " . $archive->error;
