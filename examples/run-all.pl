#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use File::Spec;
use FindBin;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Text::Wrap ();

my ($backend, $only, $list, $help) = ('perl', undef, 0, 0);
GetOptions('backend=s' => \$backend, 'only=s' => \$only, 'list' => \$list, 'help|h' => \$help)
    or die "Invalid options. Try: perl -Ilib examples/run-all.pl --help\n";
if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/run-all.pl [OPTIONS]

Explore the library through independent, runnable examples.

  --list                   List scenarios without running them.
  --only NAME              Run one scenario from the list.
  --backend perl|auto|pdl   Select a numerical backend (default: perl).
  -h, --help               Show help.

Start here:
  perl -Ilib examples/run-all.pl --list
  perl -Ilib examples/run-all.pl --only text-events

Generated files use temporary directories and are removed automatically.
Explicit pdl selection requires PDL 2.081 or later; auto falls back to Perl.
HELP
    exit 0;
}
die "Unexpected arguments. Try: perl -Ilib examples/run-all.pl --help\n" if @ARGV;
die "Unknown backend '$backend'; choose perl, auto or pdl.\n"
    unless $backend =~ /\A(?:perl|auto|pdl)\z/x;
open my $input, '<:raw', File::Spec->catfile($FindBin::Bin, 'routes.json') or croak $!;
my $bytes = do { local $/ = undef; <$input> };
close $input or croak $!;
my $routes   = decode_json($bytes);
my @includes = map { '-I' . File::Spec->rel2abs($_) } grep { !ref $_ } @INC;
my $selected = 0;

for my $route (@{$routes}) {
    (my $name = $route->{file}) =~ s/\.pl\z//x;
    next if defined($only) && $only ne $name;
    ++$selected;
    if ($list) {
        local $Text::Wrap::columns  = 78;
        local $Text::Wrap::unexpand = 0;
        print Text::Wrap::wrap(sprintf('  %-20s ', $name), ' ' x 23, $route->{description}), "\n";
        next;
    }
    print "Running $name", $route->{backend} ? " ($backend)" : '', "\n";
    my @arguments = $route->{backend} ? ($backend) : ();
    system $^X, @includes, File::Spec->catfile($FindBin::Bin, $route->{file}), @arguments;
    croak "Example failed: $name" if $?;
}
die "No matching example. Try: perl -Ilib examples/run-all.pl --list\n" unless $selected;
print "All selected examples completed.\n"                              unless $list;
