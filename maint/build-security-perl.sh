#!/bin/sh
set -eu

# Perl 5.44.0 is still the latest stable release. Build the two upstream
# CVE-2026-15534 fixes together; changing the version label cannot prove a fix.
if [ "$#" -ne 1 ]; then
    echo 'Usage: sh maint/build-security-perl.sh ABSOLUTE_NEW_BUILD_DIRECTORY' >&2
    exit 2
fi
root=$1
case "$root" in
    /*) ;;
    *) echo 'Build directory must be absolute' >&2; exit 2 ;;
esac
jobs=${BUILD_JOBS:-2}
case "$jobs" in
    ''|*[!0-9]*|0) echo 'BUILD_JOBS must be a positive integer' >&2; exit 2 ;;
esac

# Refuse to reuse a build or install over an existing interpreter.
mkdir "$root"
mkdir "$root/downloads"
cd "$root/downloads"

download() {
    name=$1
    url=$2
    digest=$3
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \
        --output "$name" "$url"
    printf '%s  %s\n' "$digest" "$name" | shasum -a 256 -c -
    printf '%s  %s\n' "$digest" "$name" >> "$root/source-sha256.txt"
}

# Archive hash agrees with the author's CPAN CHECKSUMS; patch hashes identify
# the exact bytes reviewed from the immutable upstream commits.
download perl-5.44.0.tar.gz \
    https://cpan.metacpan.org/authors/id/L/LE/LEONT/perl-5.44.0.tar.gz \
    3b855066b92491cb40e86affb1ca57d1a388aa43e51b91c7806a32c2f65f96c3
download 568e6fd238867bb9e99fa3f47cba3169009239e0.patch \
    https://github.com/Perl/perl5/commit/568e6fd238867bb9e99fa3f47cba3169009239e0.patch \
    b763455236629383cf720ae6e60cfa42ce01e23728693a779abb8275f90a9e40
download 54cf3d44cbbedd17d774e9a37921963e8fd5d0cb.patch \
    https://github.com/Perl/perl5/commit/54cf3d44cbbedd17d774e9a37921963e8fd5d0cb.patch \
    c7cc877ae64338c3a91398116d34ae9bb76c8835632f3259aa205eb70ded920a

tar -xzf perl-5.44.0.tar.gz -C "$root"
cd "$root/perl-5.44.0"
patch --batch --forward --fuzz=0 -p1 \
    < "$root/downloads/568e6fd238867bb9e99fa3f47cba3169009239e0.patch"
patch --batch --forward --fuzz=0 -p1 \
    < "$root/downloads/54cf3d44cbbedd17d774e9a37921963e8fd5d0cb.patch"
sh Configure -des "-Dprefix=$root/install" -Dman1dir=none -Dman3dir=none
make -j "$jobs"
if ! TEST_JOBS="$jobs" make test-reonly > "$root/regex-tests.txt" 2>&1; then
    cat "$root/regex-tests.txt"
    exit 1
fi
tail -n 5 "$root/regex-tests.txt"
make install
"$root/install/bin/perl" -V > "$root/perl-configuration.txt"
