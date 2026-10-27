use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Find qw(find);
use IPC::Open3 qw(open3);
use Symbol     qw(gensym);
use JSON::PP;

BEGIN {
    eval {
        require Markdown::Perl;
        require HTML::TreeBuilder;
        require URI;
        require Pod::Simple::XHTML;
        require PPI;
        1;
    } or plan skip_all => 'Install the development documentation prerequisites';
}

sub read_file {
    my ($path) = @_;
    open my $input, '<:encoding(UTF-8)', $path or die $!;
    my $text = do { local $/; <$input> };
    close $input or die $!;
    return $text;
}

sub write_file {
    my ($path, $text) = @_;
    open my $output, '>:encoding(UTF-8)', $path or die $!;
    print {$output} $text or die $!;
    close $output         or die $!;
    return;
}

sub run_site {
    my (@args) = @_;
    my $error  = gensym();
    my $pid    = open3(undef, my $stdout, $error, $^X, 'maint/build-site.pl', @args);
    my $output = do { local $/; <$stdout> };
    my $errors = do { local $/; <$error> };
    close $stdout or die $!;
    close $error  or die $!;
    waitpid $pid, 0;
    return ($?, ($output // '') . ($errors // ''));
}

my $temporary = tempdir(CLEANUP => 1);
my $site      = "$temporary/site with spaces";
my ($status, $output) = run_site('--output', $site);
is($status, 0, 'complete documentation builds in a path with spaces') or diag($output);
BAIL_OUT('No site to inspect') if $status;
like($output, qr/local links and anchors checked/, 'every local URL and anchor is checked');
my $manifest  = JSON::PP->new->decode(read_file("$site/site-manifest.json"));
my %published = map { $_->{source} => $_->{target} } @{$manifest->{pages}};
my @sources;
find({no_chdir => 1, wanted => sub { push @sources, $File::Find::name if /\.(?:pm|pod)\z/ }},
    'lib');
push @sources, 'bin/ham-rtty';

for my $source (sort @sources) {
    next unless read_file($source) =~ /^=head1\s+NAME\b/m;
    ok(exists $published{$source}, "POD published: $source");
}
find({no_chdir => 1, wanted => sub { push @sources, $File::Find::name if /\.md\z/ }},
    qw(docs examples corpus));
for my $source (sort grep { /\.md\z/ } @sources) {
    ok(exists $published{$source}, "Markdown published: $source");
}
my $home = read_file("$site/index.html");
like($home, qr{<table\b}, 'Markdown tables are real HTML tables');
like($home, qr{<pre\b[^>]*><code class="language-(?:sh|perl)"}, 'fenced code retains its language');
like($home, qr{href="api/Ham/RTTY.html"}, 'Markdown source links lead to rendered POD');
my $pod = read_file("$site/api/Ham/RTTY.html");
like($pod, qr{id="generate_wav"},       'public method headings have linkable anchors');
like($pod, qr{href="RTTY/Encoder.html}, 'links between project modules stay on the site');
like(
    read_file("$site/docs/dependency-audit.html"),
    qr{href="https://metacpan.org/pod/PDL"},
    'external Perl references retain MetaCPAN links'
);
like($pod, qr{href="../../assets/site.css"}, 'nested pages resolve CSS below a project subpath');
my $example     = read_file("$site/examples/text-events.html");
my $tree        = HTML::TreeBuilder->new_from_content($example);
my $source_code = $tree->look_down(_tag => 'code', class => 'language-perl');
is(
    $source_code->as_text,
    read_file('examples/text-events.pl'),
    'Perl highlighting preserves the complete executable source'
);
$tree->delete;
like($example, qr{class="syn-variable"}, 'PPI identifies Perl variables for highlighting');
like(
    $home,
    qr{href="license.html">Code and documentation: Artistic 2.0</a>},
    'the project license is visible in the page footer'
);
like(
    $home,
    qr{href="corpus/real/LICENSES.html">Recording credits and licenses</a>},
    'recording attribution and separate licenses are visible in the page footer'
);
like(
    $example,
    qr{download="download" href="text-events.pl"|href="text-events.pl" download="download"},
    'runnable examples provide the original source download'
);
ok(-f "$site/corpus/real.json",              'recording inventory is available');
ok(-f "$site/docs/performance-results.json", 'raw measurement evidence is available');
ok(
    -f "$site/license.html" && -f "$site/notice.html",
    'project license and attribution are published'
);
ok(-f "$site/.nojekyll", 'site is explicitly static');

my $second = "$temporary/second";
($status, $output) = run_site('--output', $second);
is($status,                         0,     'a second clean build succeeds') or diag($output);
is(read_file("$second/index.html"), $home, 'HTML is deterministic');
is(
    read_file("$second/site-manifest.json"),
    read_file("$site/site-manifest.json"),
    'the inventory is deterministic'
);

for my $case (
    ['missing.html',                    qr/Broken local link/,    'missing page'],
    ['docs/usage.html#missing-section', qr/Broken anchor/,        'missing fragment'],
    ['/docs/usage.html',                qr/Root-relative URL/,    'root-relative link'],
    ['../index.html',                   qr/URL escapes the site/, 'link escaping the Pages subpath']
    )
{
    write_file("$site/index.html", $home =~ s{</article>}{<a href="$case->[0]">bad</a></article>}r);
    ($status, $output) = run_site('--check', $site);
    isnt($status, 0, "$case->[2] blocks publication");
    like($output, $case->[1], "$case->[2] explains its failure");
}
write_file("$site/index.html", $home);
($status, $output) = run_site('--check', $site);
is($status, 0, 'restoring valid HTML clears the gate') or diag($output);
($status, $output) = run_site('--output', $site);
isnt($status, 0, 'a nonempty destination is not overwritten');
is(read_file("$site/index.html"), $home, 'existing output is preserved');
done_testing;
