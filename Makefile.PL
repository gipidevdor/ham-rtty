use 5.020;
use strict;
use warnings;
use ExtUtils::MakeMaker 7.22;
my %provides;
for my $module (
    qw(Ham::RTTY Ham::RTTY::Baudot Ham::RTTY::Encoder Ham::RTTY::Decoder Ham::RTTY::Events
    Ham::RTTY::Generator Ham::RTTY::Detector Ham::RTTY::Audio Ham::RTTY::MIDI
    Ham::RTTY::Result Ham::RTTY::Error)
    )
{
    my $file = "lib/$module.pm";
    $file =~ s{::}{/}gx;
    $provides{$module} = {file => $file, version => MM->parse_version($file)};
}
WriteMakefile(
    NAME               => 'Ham::RTTY',
    VERSION_FROM       => 'lib/Ham/RTTY.pm',
    ABSTRACT_FROM      => 'lib/Ham/RTTY.pm',
    AUTHOR             => 'Giacomo Picchiarelli',
    LICENSE            => 'artistic_2',
    MIN_PERL_VERSION   => '5.020',
    EXE_FILES          => ['bin/ham-rtty'],
    CONFIGURE_REQUIRES => {'ExtUtils::MakeMaker' => '7.22'},
    BUILD_REQUIRES     => {'ExtUtils::MakeMaker' => '7.22'},
    PREREQ_PM          => {
        'Carp'           => 0,
        'Exporter'       => 0,
        'Scalar::Util'   => 0,
        'Storable'       => 0,
        'Hash::Util'     => 0,
        'File::Basename' => 0,
        'File::Temp'     => 0,
        'Fcntl'          => 0,
        'Encode'         => 0,
        'Getopt::Long'   => 0,
        'IO::Handle'     => 0,
        'JSON::PP'       => 0,
        'Text::Wrap'     => 0
    },
    TEST_REQUIRES => {
        'Test::More'  => '0.98',
        'JSON::PP'    => 0,
        'Symbol'      => 0,
        'Config'      => 0,
        'Cwd'         => 0,
        'IPC::Open3'  => 0,
        'File::Temp'  => 0,
        'File::Spec'  => 0,
        'Digest::SHA' => '5.96'
    },
    dist =>
        {TAR => '$(PERLRUN) maint/archive.pl', TARFLAGS => q{ }, COMPRESS => 'gzip -n -f --best'},
    META_MERGE => {
        provides       => \%provides,
        dynamic_config => 0,
        keywords       => [qw(rtty ita2 baudot afsk amateur-radio wav midi)],
        'meta-spec'    => {version => 2},
        resources      => {
            repository => {
                type => 'git',
                url  => 'https://github.com/gipidevdor/ham-rtty.git',
                web  => 'https://github.com/gipidevdor/ham-rtty'
            },
            bugtracker => {web => 'https://github.com/gipidevdor/ham-rtty/issues'},
            homepage   => 'https://github.com/gipidevdor/ham-rtty',
        },
        no_index => {
            directory => [qw(xt examples maint lib/Ham/RTTY/_Internal)],
            namespace => ['Ham::RTTY::_Internal']
        },
        prereqs => {
            runtime => {recommends => {PDL => '2.081'}},
            develop => {
                requires => {
                    'Perl::Tidy'              => '20260826',
                    'Perl::Critic'            => 0,
                    'Perl::MinimumVersion'    => '1.44',
                    'Devel::Cover'            => 0,
                    'Test::Pod'               => '1.48',
                    'Test::CPAN::Meta'        => 0,
                    'CPAN::Meta'              => 0,
                    'ExtUtils::Manifest'      => 0,
                    'Test::CPAN::Changes'     => 0,
                    'Archive::Tar'            => '3.10',
                    'Pod::Man'                => 'v6.1.1',
                    'CPAN::Audit'             => '20261013.002',
                    'PPI'                     => '1.291',
                    'Module::CPANTS::Analyse' => '1.03',
                    'Test::Kwalitee'          => 0,
                    'Pod::Simple'             => '3.48',
                    'Markdown::Perl'          => '1.14',
                    'HTML::Tree'              => '5.07',
                    'URI'                     => '5.36',
                }
            }
        },
    },
);
