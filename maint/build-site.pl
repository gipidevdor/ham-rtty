#!/usr/bin/env perl
use 5.026;
use strict;
use warnings;
use utf8;
use Carp               qw(croak);
use Cwd                qw(abs_path);
use Encode             qw(decode);
use ExtUtils::Manifest qw(maniread);
use File::Basename     qw(dirname);
use File::Copy         qw(copy);
use File::Find         qw(find);
use File::Path         qw(make_path);
use File::Spec;
use FindBin        qw($Bin);
use Getopt::Long   qw(GetOptions);
use HTML::Entities qw(encode_entities);
use HTML::TreeBuilder 5.07;
use HTML::Element;
use JSON::PP;
use Markdown::Perl 1.14;
use Pod::Simple::XHTML 3.48;
use PPI 1.291;
use URI;
use URI::Escape qw(uri_unescape);

my $ROOT          = abs_path("$Bin/..");
my $REPOSITORY    = 'https://github.com/gipidevdor/ham-rtty';
my %PERL_KEYWORDS = map { $_ => 1 }
    qw(use no my our sub return if elsif else unless for foreach while until last next
    die warn print say package require state shift bless);

sub read_text {
    my ($path) = @_;
    open my $input, '<:encoding(UTF-8)', $path or croak "Cannot read $path: $!";
    my $text = do { local $/ = undef; <$input> };
    close $input or croak "Cannot close $path: $!";
    return $text;
}

sub write_text {
    my ($path, $text) = @_;
    make_path(dirname($path));
    open my $output, '>:encoding(UTF-8)', $path or croak "Cannot write $path: $!";
    print {$output} $text or croak "Cannot write $path: $!";
    close $output         or croak "Cannot close $path: $!";
    return;
}

sub escape_html {
    my ($text) = @_;
    return encode_entities($text, q{<>&"'});
}

sub relative_url {
    my ($target, $current) = @_;
    my $relative = File::Spec->abs2rel("/$target", '/' . dirname($current));
    $relative =~ s{\\}{/}gx;
    return $relative;
}

sub document_tree {
    my ($html) = @_;
    my $tree = HTML::TreeBuilder->new;
    $tree->ignore_unknown(0);
    $tree->ignore_ignorable_whitespace(0);
    $tree->no_space_compacting(1);
    $tree->parse_content($html);
    $tree->eof;
    return $tree;
}

sub inventory {
    my $manifest = maniread("$ROOT/MANIFEST");
    my (@pages, @assets);
    for my $source (sort keys %{$manifest}) {
        my ($kind, $target, $title);
        if ($source =~ /\.md\z/x) {
            $kind = 'guide';
            ($title) = read_text("$ROOT/$source") =~ /^\#\s+(.+)$/mx;
            $title //= $source;
            $title =~ s/`//gx;
            ($target = $source) =~ s{(?:README\.md|\.md)\z}{index.html}x
                if $source =~ /(?:\A|\/)README\.md\z/x;
            ($target = $source) =~ s/\.md\z/.html/x unless defined $target;
        }
        if (!defined($kind) && ($source eq 'bin/ham-rtty' || $source =~ /\.(?:pm|pod)\z/x)) {
            my $pod = read_text("$ROOT/$source");
            next unless $pod =~ /^=head1\s+NAME\b/mx;
            $kind = 'pod';
            ($title) = $pod =~ /^=head1\s+NAME\s+([^\n]+)/mx;
            $title              =~ s/\s+--?\s+.*\z//x;
            ($target = $source) =~ s{\Alib/}{api/}x;
            $target             =~ s/\.(?:pm|pod)\z/.html/x;
            $target = 'api/ham-rtty.html' if $source eq 'bin/ham-rtty';
        }
        if ($source =~ m{\Aexamples/.+\.pl\z}x) {
            ($kind, $title) = ('example', $source);
            ($target = $source) =~ s/\.pl\z/.html/x;
            push @assets, $source;
        }
        if ($source =~ /\A(?:Changes|LICENSE|NOTICE)\z/x) {
            ($kind, $title, $target) = ('text', $source, lc($source) . '.html');
        }
        if ($source =~ m{\A(?:docs|examples|corpus)/.+\.(?:json|txt|wav)\z}x) {
            push @assets, $source;
            next;
        }
        next unless defined $kind;
        push @pages, {source => $source, target => $target, title => $title, kind => $kind};
    }
    push @pages,
        {source => '@api', target => 'api/index.html', title => 'API reference', kind => 'index'};
    return (\@pages, \@assets, $manifest);
}

sub local_target {
    my ($url, $current) = @_;
    return                                      if $url =~ m{\A(?:[a-z][a-z0-9+.-]*:|//)}ix;
    croak "Root-relative URL in $current: $url" if $url =~ m{\A/}x;
    my $prefix = '/__ham_cw_site__/';
    my $parsed = URI->new_abs($url, "https://site.invalid$prefix$current");
    my $path   = uri_unescape($parsed->path);
    croak "URL escapes the site in $current: $url"
        unless $path =~ s{\A\Q$prefix\E}{}x;
    croak "URL escapes the site in $current: $url" if $path =~ m{(?:\A|/)\.\.(?:/|\z)}x;
    $path .= 'index.html' if $path =~ m{/\z}x;
    return ($path, $parsed->fragment);
}

sub rewrite_links {
    my ($tree, $page, $site) = @_;
    my ($routes, $modules, $manifest, $assets) = @{$site}{qw(routes modules manifest assets)};
    for my $element ($tree->look_down(sub { defined $_[0]->attr('href') })) {
        my $url = $element->attr('href');
        if ($url =~ m{\Ahttps://metacpan\.org/pod/([^\#?]+)(.*)\z}x) {
            my ($module, $suffix) = (uri_unescape($1), $2);
            $element->attr(href => relative_url($modules->{$module}, $page->{target}) . $suffix)
                if exists $modules->{$module};
            next;
        }
        next if $url =~ /\A\#/x;
        my ($source) = local_target($url, $page->{source});
        next unless defined $source;
        my $parsed = URI->new($url);
        if (exists $routes->{$source} && !defined $element->attr('download')) {
            $parsed->path(relative_url($routes->{$source}, $page->{target}));
        }
        else {
            croak "Unknown local link in $page->{source}: $url" unless exists $manifest->{$source};
            $assets->{$source} = 1;
            $parsed->path(relative_url($source, $page->{target}));
        }
        $element->attr(href => "$parsed");
    }
    return;
}

sub highlight_perl {
    my ($tree, $page) = @_;
    for my $code ($tree->look_down(_tag => 'code')) {
        next unless $code->parent && $code->parent->tag eq 'pre';
        my $source = $code->as_text;
        my $is_perl =
               ($code->attr('class') // '') =~ /\blanguage-perl\b/x
            || $page->{kind} eq 'example'
            || ($page->{kind} eq 'pod' && $source =~ /\b(?:use|my|our|sub|package)\b|\$\w/x);
        next unless $is_perl;
        my $document = PPI::Document->new(\$source);
        next unless $document;
        my @tokens = $document->tokens;
        next unless join('', map { $_->content } @tokens) eq $source;
        my @nodes;

        for my $token (@tokens) {
            my $text = $token->content;
            my $class;
            $class = 'comment' if $token->isa('PPI::Token::Comment');
            $class = 'string'
                if $token->isa('PPI::Token::Quote')
                || $token->isa('PPI::Token::QuoteLike');
            $class = 'variable' if $token->isa('PPI::Token::Symbol');
            $class = 'number'   if $token->isa('PPI::Token::Number');
            $class = 'keyword'
                if $token->isa('PPI::Token::Word')
                && $PERL_KEYWORDS{$text};
            if (defined $class) {
                my $span = HTML::Element->new('span', class => "syn-$class");
                $span->push_content($text);
                push @nodes, $span;
            }
            else { push @nodes, $text }
        }
        $code->delete_content;
        $code->push_content(@nodes);
        $code->attr(class => 'language-perl');
        $code->parent->attr('data-language' => 'Perl');
    }
    return;
}

sub body_and_contents {
    my ($html, $page, $site) = @_;
    my $tree = document_tree($html);
    my (%seen, @contents);
    for my $heading ($tree->look_down(sub { $_[0]->tag =~ /\Ah[1-6]\z/x })) {
        my $title = $heading->as_text;
        if ($page->{kind} eq 'guide') {
            my $id = lc $title;
            $id =~ s/[^\p{L}\p{N}_\s-]//gx;
            $id =~ s/\s/-/gx;
            my $count = $seen{$id}++;
            $id .= "-$count" if $count;
            $heading->attr(id => $id);
        }
        my $id = $heading->attr('id');
        push @contents, [$id, $title] if defined $id && $heading->tag eq 'h2';
    }
    rewrite_links($tree, $page, $site)
        unless $page->{kind} eq 'index';
    highlight_perl($tree, $page);
    my $body     = $tree->find_by_tag_name('body');
    my $rendered = join '',
        map { ref($_) ? $_->as_HTML(undef, '', {}) : escape_html($_) } $body->content_list;
    $tree->delete;
    my $contents =
        @contents
        ? '<details class="contents"><summary>On this page</summary><ul>'
        . join('',
        map { '<li><a href="#' . escape_html($_->[0]) . '">' . escape_html($_->[1]) . '</a></li>' }
            @contents)
        . '</ul></details>'
        : '';
    return ($rendered, $contents);
}

sub navigation {
    my ($pages, $current) = @_;
    my @featured  = qw(README.md docs/installing.md docs/usage.md examples/README.md @api);
    my %featured  = map { $_           => 1 } @featured;
    my %by_source = map { $_->{source} => $_ } @{$pages};
    my @groups    = (
        ['Guides',  map { $by_source{$_} } @featured],
        ['Modules', grep { $_->{kind} eq 'pod' } @{$pages}],
        [
            'Documentation',
            grep { $_->{source} =~ m{\Adocs/}x && !$featured{$_->{source}} } @{$pages}
        ],
        [
            'Distribution',
            grep {
                       $_->{kind} ne 'example'
                    && $_->{kind} ne 'pod'
                    && $_->{source} !~ m{\Adocs/}x
                    && !$featured{$_->{source}}
            } @{$pages}
        ]
    );
    my $html = '';
    for my $group (@groups) {
        my ($title, @entries) = @{$group};
        $html .=
              '<section><h2><span class="pod-directive" aria-hidden="true">=head1 </span>'
            . escape_html($title)
            . '</h2><ul>';
        for my $entry (@entries) {
            my $active = $entry->{target} eq $current ? ' aria-current="page"' : '';
            $html .=
                  '<li><a'
                . $active
                . ' href="'
                . escape_html(relative_url($entry->{target}, $current)) . '">'
                . escape_html($entry->{title})
                . '</a></li>';
        }
        $html .= '</ul></section>';
    }
    return $html;
}

sub page_html {
    my ($page, $body, $contents, $site) = @_;
    my ($pages, $version, $revision) = @{$site}{qw(pages version revision)};
    my $title      = escape_html($page->{title});
    my $home       = escape_html(relative_url('index.html',                $page->{target}));
    my $css        = escape_html(relative_url('assets/site.css',           $page->{target}));
    my $api        = escape_html(relative_url('api/index.html',            $page->{target}));
    my $guides     = escape_html(relative_url('docs/index.html',           $page->{target}));
    my $license    = escape_html(relative_url('license.html',              $page->{target}));
    my $recordings = escape_html(relative_url('corpus/real/LICENSES.html', $page->{target}));
    my $nav        = navigation($pages, $page->{target});
    my $source     = $page->{source} eq '@api' ? 'maint/build-site.pl' : $page->{source};
    my $source_url = escape_html("$REPOSITORY/blob/$revision/$source");
    my $label =
        $page->{kind} eq 'pod'
        ? 'perldoc ' . escape_html($page->{title})
        : '=pod / Ham::RTTY documentation';
    $body =~ s{(\A\s*<h1\b[^>]*>.*?</h1>)}{$1$contents}sx;
    return <<"HTML";
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Pod::Simple::XHTML and Markdown::Perl">
<title>$title · Ham::RTTY</title><link rel="stylesheet" href="$css"></head>
<body><a class="skip" href="#content">Skip to content</a>
<header class="masthead"><a class="brand" aria-label="Ham::RTTY" href="$home"><span class="syn-keyword">use</span> <span>Ham::RTTY</span><span class="semicolon">;</span></a>
<nav aria-label="Project"><a href="$api">perldoc</a><a href="$guides">Guides</a><a href="$REPOSITORY">Source</a><span class="version">\$VERSION = '$version';</span></nav></header>
<div class="layout"><details class="navigation" open><summary>Documentation menu</summary>
<nav aria-label="Documentation">$nav</nav></details>
<main id="content"><div class="eyebrow">$label</div><article>$body</article>
<footer><div>Ham::RTTY $version · Built with Perl · <a href="$source_url">Page source</a></div>
<div><a href="$license">Code and documentation: Artistic 2.0</a> · <a href="$recordings">Recording credits and licenses</a></div></footer>
</main></div></body></html>
HTML
}

sub render_body {
    my ($page, $pages, $markdown) = @_;
    if ($page->{kind} eq 'index') {
        return '<h1>API reference</h1><p>Library modules and command-line manual.</p><dl>' . join(
            '',
            map {
                      '<dt><a href="'
                    . escape_html(relative_url($_->{target}, $page->{target})) . '">'
                    . escape_html($_->{title})
                    . '</a></dt><dd>'
                    . escape_html($_->{source}) . '</dd>'
                }
                grep { $_->{kind} eq 'pod' } @{$pages}
        ) . '</dl>';
    }
    if ($page->{kind} eq 'guide') {
        return $markdown->convert(read_text("$ROOT/$page->{source}"));
    }
    if ($page->{kind} eq 'pod') {
        my $parser = Pod::Simple::XHTML->new;
        $parser->html_header('');
        $parser->html_footer('');
        $parser->html_charset('UTF-8');
        $parser->html_h_level(2);
        $parser->anchor_items(1);
        $parser->output_string(\my $html);
        $parser->parse_file("$ROOT/$page->{source}");
        croak "POD errors in $page->{source}" if $parser->any_errata_seen;
        return '<h1>' . escape_html($page->{title}) . '</h1>' . $html;
    }
    my $download =
        $page->{kind} eq 'example'
        ? '<p><a download href="'
        . escape_html(relative_url($page->{source}, $page->{target}))
        . '">Download Perl source</a></p>'
        : '';
    return
          '<h1>'
        . escape_html($page->{title}) . '</h1>'
        . $download
        . '<pre><code>'
        . escape_html(read_text("$ROOT/$page->{source}"))
        . '</code></pre>';
}

sub check_site {
    my ($output) = @_;
    croak "Missing site index in $output" unless -f "$output/index.html";
    my (@html, %ids, @links);
    find({no_chdir => 1, wanted => sub { push @html, $File::Find::name if /\.html\z/x && -f $_ }},
        $output);
    for my $file (sort @html) {
        my $current = File::Spec->abs2rel($file, $output);
        $current =~ s{\\}{/}gx;
        my $tree = document_tree(read_text($file));
        for my $element ($tree->look_down(sub { defined $_[0]->attr('id') })) {
            my $id = $element->attr('id');
            croak "Duplicate anchor $current#$id" if $ids{$current}{$id}++;
        }
        for my $attribute (qw(href src)) {
            for my $element ($tree->look_down(sub { defined $_[0]->attr($attribute) })) {
                my $url = $element->attr($attribute);
                my ($path, $fragment) = local_target($url, $current);
                push @links, [$current, $url, $path, $fragment] if defined $path;
            }
        }
        $tree->delete;
    }
    for my $link (@links) {
        my ($current, $url, $path, $fragment) = @{$link};
        croak "Broken local link in $current: $url" unless -f "$output/$path";
        next unless $path =~ /\.html\z/x && defined($fragment) && length($fragment);
        my $id = uri_unescape($fragment);
        $id = decode('UTF-8', $id) unless utf8::is_utf8($id);
        croak "Broken anchor in $current: $url" unless exists $ids{$path}{$id};
    }
    print scalar(@html) . ' HTML pages; ' . scalar(@links) . " local links and anchors checked\n";
    return;
}

sub main {
    my ($output, $check, $help, $revision) = ("$ROOT/_site", undef, 0, 'main');
    GetOptions(
        'output=s'   => \$output,
        'check=s'    => \$check,
        'revision=s' => \$revision,
        'help'       => \$help
    ) or croak 'Invalid site options; use --help';
    croak 'Unexpected positional arguments; use --help' if @ARGV;
    if ($help) {
        print "Usage: perl maint/build-site.pl [--output EMPTY_DIRECTORY] [--revision SHA]\n"
            . "       perl maint/build-site.pl --check SITE_DIRECTORY\n";
        return 0;
    }
    if (defined $check) { check_site(File::Spec->rel2abs($check)); return 0 }
    croak 'Revision must be main or a complete Git commit SHA'
        unless $revision eq 'main' || $revision =~ /\A[0-9a-f]{40}\z/x;
    $output = File::Spec->rel2abs($output);
    make_path($output);
    opendir my $directory, $output or croak "Cannot inspect $output: $!";
    my @existing = grep { $_ ne '.' && $_ ne '..' } readdir $directory;
    closedir $directory or croak "Cannot close $output: $!";
    croak "Output directory must be empty: $output" if @existing;
    my ($pages, $asset_list, $manifest) = inventory();
    my %assets    = map { $_           => 1 } @{$asset_list};
    my %routes    = map { $_->{source} => $_->{target} } @{$pages};
    my %modules   = map { $_->{title}  => $_->{target} } grep { $_->{kind} eq 'pod' } @{$pages};
    my ($version) = read_text("$ROOT/lib/Ham/RTTY.pm") =~ /our\s+\$VERSION\s*=\s*'([^']+)'/x;
    croak 'Cannot read Ham::RTTY version' unless defined $version;
    my $markdown = Markdown::Perl->new(mode => 'github');
    my $site     = {
        pages    => $pages,
        version  => $version,
        revision => $revision,
        routes   => \%routes,
        modules  => \%modules,
        manifest => $manifest,
        assets   => \%assets
    };

    for my $page (@{$pages}) {
        my $html = render_body($page, $pages, $markdown);
        my ($body, $contents) = body_and_contents($html, $page, $site);
        write_text("$output/$page->{target}", page_html($page, $body, $contents, $site));
    }
    for my $source (sort keys %assets) {
        make_path(dirname("$output/$source"));
        copy("$ROOT/$source", "$output/$source") or croak "Cannot copy $source: $!";
    }
    make_path("$output/assets");
    copy("$ROOT/maint/site.css", "$output/assets/site.css") or croak "Cannot copy site CSS: $!";
    write_text("$output/.nojekyll", '');
    write_text(
        "$output/site-manifest.json",
        JSON::PP->new->canonical->pretty->encode(
            {
                version  => $version,
                revision => $revision,
                pages    => $pages,
                renderers => {pod => $Pod::Simple::XHTML::VERSION, markdown => $Markdown::Perl::VERSION,
                    perl_tokens => $PPI::VERSION},
                assets => [sort keys %assets]
            }
        )
    );
    check_site($output);
    print "Built Ham::RTTY $version documentation in $output\n";
    return 0;
}

exit main() unless caller;
1;
