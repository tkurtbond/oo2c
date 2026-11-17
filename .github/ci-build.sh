#!/bin/sh
# Build and test oo2c from a git checkout, as the CI does.
#
# 1. Build the bootstrap compiler stage0/oo2c from the C sources in a
#    release tarball (git does not have them).  It is linked from object
#    files only, so this also works with releases whose own "make"
#    fails to link bin/oo2c on Debian and Ubuntu (2.2.0 and older).
# 2. Build this tree with it, following "Build and Install Using a Git
#    Working Copy" in README.  Fail if gcc prints any warning.
# 3. Run `make test` and compile and run a small program.
#
# Run it from the top of a clean checkout.  Environment:
#   BOOT_VERSION  release used as the bootstrap compiler (default 2.2.2)
#   BOOT_TARBALL  use this local tarball instead of downloading it
#                 (oo2c_64 or oo2c_32)
#   TESTS         "no": stop after the build and install, without make
#                 test and Hello
#   WORK          scratch directory (default: $RUNNER_TEMP/oo2c-ci or
#                 /tmp/oo2c-ci); it must be outside the source tree
#   MAKE          GNU make (default make; gmake on the BSDs)
#   TAR           GNU tar or bsdtar (default tar; gtar on OpenBSD and NetBSD)
#   CC, CPPFLAGS, LDFLAGS  passed on to configure; on the BSDs e.g.
#                 CC=gcc16 CPPFLAGS=-I/usr/local/include
#                 LDFLAGS=-L/usr/local/lib

set -eu

BOOT_VERSION=${BOOT_VERSION:-2.2.2}
BOOT_URL=https://github.com/tkurtbond/oo2c/releases/download/v$BOOT_VERSION/oo2c_64-$BOOT_VERSION.tar.bz2
SRC=$(pwd)
WORK=${WORK:-${RUNNER_TEMP:-/tmp}/oo2c-ci}
MAKE=${MAKE:-make}
TAR=${TAR:-tar}

step () { echo; echo "=== $*"; }

# fail if a log has gcc warnings (oo2c's own messages are "Warning:")
check_warnings () {
  if grep -n 'warning:' "$1"; then
    echo "gcc warnings in $1" >&2
    exit 1
  fi
}

rm -rf "$WORK"
mkdir -p "$WORK"

step "Bootstrap compiler oo2c $BOOT_VERSION"
cd "$WORK"
if [ -n "${BOOT_TARBALL:-}" ]; then
  cp "$BOOT_TARBALL" boot.tar.bz2
else
  curl -fsSL -o boot.tar.bz2 "$BOOT_URL"
fi
"$TAR" --no-same-owner -xjf boot.tar.bz2
cd oo2c_*-*/
BOOT_DIR=$(pwd)
./configure >"$WORK/boot-configure.log" 2>&1
"$MAKE" stage0/oo2c >"$WORK/boot-make.log" 2>&1 \
  || { tail -50 "$WORK/boot-make.log"; exit 1; }
# stage0/oo2c has no usable default configuration; always pass --config
BOOT=$BOOT_DIR/stage0/oo2c

# (actions/checkout marks the directory safe only during its own step)
step "Build $(git -c safe.directory="$SRC" -C "$SRC" describe --always --dirty 2>/dev/null || echo tree)"
cd "$SRC"
# A checkout gives all files about the same mtime; make sure make does
# not think configure or __config.h.in are out of date.
touch configure.ac aclocal.m4
sleep 1; touch lib/src/__config.h.in
sleep 1; touch configure
./configure --prefix="$WORK/inst"
. ./ENV
"$MAKE" "$OOC_DEV_ROOT/oo2crc-install.xml"
"$BOOT" --config oo2crc-install.xml --version
"$BOOT" -M --config oo2crc-install.xml oo2c \
  >"$WORK/stage.log" 2>&1 || { tail -50 "$WORK/stage.log"; exit 1; }
"$MAKE" install BOOTSTRAP_COMPILER=bin/oo2c >"$WORK/install.log" 2>&1 \
  || { tail -50 "$WORK/install.log"; exit 1; }
check_warnings "$WORK/stage.log"
check_warnings "$WORK/install.log"
"$WORK/inst/bin/oo2c" --version
[ "${TESTS:-yes}" = no ] && exit 0

step "make test"
status=0
"$MAKE" -k test >"$WORK/test.log" 2>&1 || status=$?
grep -E '^(passed: |failed: |ok: )' "$WORK/test.log" | grep -v '^ok: ' || true
for r in tests/*/report.xml; do
  echo "$r: $(grep -c "relevance='standard'" "$r") standard," \
       "$(grep -c "class='failed'" "$r") failed (standard or informal)"
done
if [ $status -ne 0 ]; then
  tail -80 "$WORK/test.log"
  echo "make test failed" >&2
  exit $status
fi

step "Hello"
mkdir -p "$WORK/hello/src"
cd "$WORK/hello"
cat >src/Hello.Mod <<'EOF'
MODULE Hello;
IMPORT Out;
BEGIN
  Out.String ("Hello, World"); Out.Ln
END Hello.
EOF
env -u OOC_DEV_ROOT -u MAIN_MAKEFILE "$WORK/inst/bin/oo2c" -M Hello
test "$(./bin/Hello)" = "Hello, World"
echo "Hello OK"
