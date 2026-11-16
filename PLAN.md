# Plan: getting oo2c running on modern Linux

Goal: a working `oo2c` 2.1.x on current x86-64 Linux (reference system:
Fedora 44, gcc 16.2, clang 22, glibc 2.4x, gc 8.2.6, libtool 2.5.4,
autoconf 2.72), built from this repository, passing `make test`, and
ideally building from a git checkout without a separate tarball download.

Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

## Starting point (2026-11-16)

- HEAD is the post-2.1.11 development tree (version bumped to 2.1.11 in
  2006, last code commits 2011). It has no `stage0/` C sources, so it
  cannot bootstrap on its own (see `AGENTS.md`, "How the build works").
- `oo2c_64-2.1.11.tar.bz2` (and `_32`) are still downloadable from
  SourceForge (`https://downloads.sourceforge.net/project/ooc/ooc2/2.1.11/`).
- Build dependencies are present: gcc, GNU make, perl, xsltproc,
  libtool, autoconf, `gc-devel` (`/usr/include/gc/gc.h`, `-lgc`).
- Nothing has been compiled yet; the risks below come from reading the
  sources, not from build failures.

## Expected problems

1. **Bootstrap**: needs the 2.1.11 tarball's `stage0/`. HEAD may use
   language/library features that 2.1.11 cannot compile (upstream
   sometimes required intermediate releases).
2. **gcc 14–16 strictness**: implicit declarations, int↔pointer
   conversions, incompatible pointer types and return mismatches are now
   errors; default `-std=gnu23`. The generated C and the 2006 `configure`
   tests are both affected. A broken configure test can wrongly fail
   (e.g. "cannot compute sizeof"), so check `config.log`.
3. **Nested functions and the executable stack**: the C back end emits GCC
   nested functions. When their address is taken this needs trampolines →
   executable stack. Expect linker warnings, and possible
   `cannot enable executable stack` failures when loading a shared
   `liboo2c.so` under recent glibc. Must use gcc, not clang.
4. **64-bit issues**: `LONGINT` is 32-bit; code that stores addresses in
   `LONGINT` or C code that casts pointers to `int` would truncate.
5. **Old autotools**: `configure` from autoconf 2.5x; obsolete macros
   (`AC_TYPE_SIGNAL`, `AC_HEADER_STDC`, old-style `AC_DEFUN(NAME,...)`).
   Libtool 2.x behaves differently from the 1.4/1.5 the build expects
   (`--mode`, `--tag=CC`, `.la` handling).
6. **Boehm gc 8**: API mostly compatible; check `GC_INIT` use in
   `lib/src/RT0.c` and the pthreads setup (`GC_PTHREADS`, `GC_THREADS`).
7. **libc**: `readdir_r` is deprecated (`lib/src/OS/Files.c`); check
   other hand-written C (`lib/src/**/*.c`) for removed or changed APIs
   (sockets, `select`, `sys/time.h`, signals, `backtrace_symbols`).
8. **xsltproc** may choke on the generated documentation XML (see
   `PROBLEMS`); it can be disabled in `rsrc/OOC/oo2crc.xml.mk`.

## Phase 0: preparation  `[x]`

- [x] Work branch: `modern-linux`.
- [x] Scratch area outside the repo: `/usr/local/sw/tmp/oo2c-work/`
      (`dl/` tarball, `src/` unpacked tree, `boot/` installed bootstrap
      compiler, `smoke/` smoke tests, `*.log` build logs). Keep `boot/`
      until Phase 2 is done; delete the whole directory afterwards.
- [x] Toolchain used: gcc 16.2.1 20260819 (Red Hat 16.2.1-2), GNU ld
      (binutils, Fedora 44), glibc (Fedora 44), gc 8.2.6, libtool 2.5.4,
      autoconf 2.72, xsltproc (libxslt, Fedora 44), perl 5.

## Phase 1: build the 2.1.11 release tarball as the bootstrap compiler  `[x]`

Working recipe (2026-11-16):

```sh
W=/usr/local/sw/tmp/oo2c-work
curl -L -o $W/dl/oo2c_64-2.1.11.tar.bz2 \
  https://downloads.sourceforge.net/project/ooc/ooc2/2.1.11/oo2c_64-2.1.11.tar.bz2
# sha256 cee9d1bf023ec875edd8ca00535c84078fa79be3a5fd438955659104f07d2d4a
tar -C $W/src -xjf $W/dl/oo2c_64-2.1.11.tar.bz2
cd $W/src/oo2c_64-2.1.11
# throwaway patch: make libtool use the C tag (same string length)
sed -i 's/--tag=CXX/--tag=CC /' stage0/obj/OOC/Config/CCompiler.[cd]
env CFLAGS="-g -O2 -Wno-error=implicit-function-declaration" \
  ./configure --prefix=$W/boot
make && make install
```

What was needed, and why:

- `-Wno-error=implicit-function-declaration`: the generated program main
  file `obj/<Module>_.c` (written by `src/OOC/Make/WriteMainFileC.Mod`)
  calls `OOC_<Module>_open(NULL)` without declaring it. This was the only
  hard compile error in the whole build. The flag has to be in the
  configured `CFLAGS` (it ends up in `oo2crc.xml`), because every program
  oo2c builds gets such a main file.
- `--tag=CXX` → `--tag=CC`: `src/OOC/Config/CCompiler.Mod` hard-codes
  `libtoolTag = " --tag=CXX"` (commit 64ec0582, 2005). With libtool 2.x
  this links `liboo2c.so` via `g++ -nostdlib`, and libtool drops `-lm`
  from `dependency_libs` in `liboo2c.la` because it is in the C++
  runtime deps. Linking `bin/oo2c` then fails with
  `undefined reference to symbol 'floor@@GLIBC_2.2.5'` /
  `DSO missing from command line`.
- Not needed: `-std=gnu17`, `-fno-strict-aliasing`, other
  `-Wno-error=...` flags, `--disable-libs`, disabling xsltproc (54 HTML
  doc pages were generated), `-z execstack`. Configure ran cleanly and
  detected gc, libtool, xsltproc, `-ldl -lrt -lm`, 64-bit `long int`.

Remaining warnings (to fix in Phase 3): `-Wbuiltin-declaration-mismatch`
for `sscanf`/`sprintf` declared in generated `libc.oh` (from
`lib/src/libc.Mod`); `-Wpointer-to-int-cast` in `lib/src/HashCode.c:23`
(pointer hash truncated to 32 bits); `readdir_r` deprecated
(`lib/src/OS/Files.c`); `GC_all_interior_pointers` deprecated
(`lib/src/RT0.c:419`, use `GC_set_all_interior_pointers()`).

Smoke tests (`$W/smoke/src/*.Mod`, built with `$W/boot/bin/oo2c --make`),
all pass:

- `Hello`: prints `Hello`.
- `AdtTest`: generic `ArrayList`/`Dictionary`/`StringBuffer` with
  `Object.String`: correct output.
- `GcTest`: allocates ~4 GB in 1 KB records with ~1 MB live; runs in
  0.9 s with 4 MB max RSS, so the Boehm gc collects.
- `ExcTest`: `TRY`/`CATCH` of a checked exception raised 10 calls deep.
- A NIL dereference gives the expected runtime error with a backtrace.
- `readelf -l`: neither the programs nor `liboo2c.so.3` need an
  executable stack (`GNU_STACK RW`), so hazard 3 did not show up here.

Original steps:

1. [x] Download `oo2c_64-2.1.11.tar.bz2`, unpack it in the scratch area.
2. [x] First try unchanged: `./configure --prefix=$BOOT && make && make install`.
       Save the full log.
3. [x] If it fails, work through the failures with the least invasive
       flags first, in this order, recording each one that is needed:
       - `CFLAGS="-O1 -g -std=gnu17"` (avoid C23 changes),
       - add `-fno-strict-aliasing` (2006-era code generator, unions/casts),
       - add `-Wno-error=implicit-function-declaration
         -Wno-error=int-conversion -Wno-error=incompatible-pointer-types
         -Wno-error=return-mismatch` as needed,
       - `--disable-libs` if libtool 2.x breaks library creation,
       - disable xsltproc if documentation generation fails,
       - `LDFLAGS=-Wl,-z,execstack` if nested-function trampolines fail.
       If configure itself fails, regenerate it or patch the failing test
       (not the source).
4. [x] Smoke test the installed compiler with the "Hello" module from
       `README`, plus one program using `Object`/`ADT` and one that
       allocates heavily (to check the gc is really used).
5. [x] Write down the working recipe here (flags + any tarball patches).
       Tarball patches are throwaway: the real fixes go into this repo in
       Phase 3.

Exit criterion: `$BOOT/bin/oo2c --make` builds and runs Hello.

## Phase 2: build HEAD with the bootstrap compiler  `[x]`

Working recipe (2026-11-16), in the repo checkout:

```sh
W=/usr/local/sw/tmp/oo2c-work
env CFLAGS="-g -O2 -Wno-error=implicit-function-declaration" \
  ./configure --prefix=$W/head
. ./ENV
make "$OOC_DEV_ROOT/oo2crc-install.xml"
$W/boot/bin/oo2c -M --config oo2crc-install.xml oo2c   # stage 1: bin/oo2c
make install BOOTSTRAP_COMPILER=bin/oo2c                # stage 2, installed
```

Results:

- The 2.1.11 compiler compiles HEAD with no source changes and no new
  warnings, so no intermediate compiler was needed.
- `make install BOOTSTRAP_COMPILER=bin/oo2c` failed with the same
  `-lm` / `DSO missing from command line` error as Phase 1, because the
  HEAD compiler also used `--tag=CXX`. A flag can't fix that, so the
  Phase 3 libtool-tag fix was done now: `libtoolTag = " --tag=CC"` in
  `src/OOC/Config/CCompiler.Mod`. After that (rebuilding from a clean
  tree), install succeeded and `liboo2c.la` has
  `dependency_libs=' -lm -lgc -ldl ...'`.
- The smoke tests from Phase 1 all pass with `$W/head/bin/oo2c`
  (programs link against `$W/head/lib/liboo2c.so.3`).
- Self-host check: a copy of the tree, configured with prefix `head2`,
  was built with `make lib/obj/liboo2c.la bin/oo2c
  BOOTSTRAP_COMPILER=$W/head/bin/oo2c`. Its generated C (663 `.c`/`.d`/
  `.oh`/`.h` files under `obj/` and `lib/obj/`) is identical to the C
  stage 1 produced, except the compiled-in config file path, which
  differs because of the prefix (`OOC_Config_Autoconf__configFile`).
  So the compiler reaches a fixpoint.
- The build creates `lib/oocdoc/`, which is not in `.gitignore` yet.

Original steps:

1. [x] In this repo: `./configure --prefix=$PREFIX` with the Phase 1 flags.
2. [x] Follow `INSTALL` ("Build and Install Using a CVS Working Copy"):
       `. ./ENV`, `make $OOC_DEV_ROOT/oo2crc-install.xml`,
       `$BOOT/bin/oo2c -M --config oo2crc-install.xml oo2c`,
       then `make install BOOTSTRAP_COMPILER=bin/oo2c`.
3. [x] (Not needed.) If 2.1.11 cannot compile HEAD (language/library features added after
       the release), find the first commit that breaks it (`git bisect`
       on "2.1.11 can compile `oo2c`") and either build an intermediate
       compiler from that commit's parent or adjust the offending code.
4. [x] Self-host check: rebuild HEAD with the HEAD-built compiler
       (stage 2) and compare the generated C of stage 1 and stage 2; they
       should be identical.

Exit criterion: a HEAD `oo2c` built by itself, installed under `$PREFIX`.

## Phase 3: fix the sources properly  `[ ]`

Replace flag workarounds with source fixes, one commit per topic:

- [ ] **Main file prototype** (found in Phase 1): make
      `src/OOC/Make/WriteMainFileC.Mod` emit
      `extern void OOC_<Module>_open(RT0__Module client);` before `main`.
      Then drop `-Wno-error=implicit-function-declaration`.
- [x] **libtool tag** (found in Phase 1, fixed in Phase 2 because it
      blocked the HEAD build): `libtoolTag` in
      `src/OOC/Config/CCompiler.Mod` is now `" --tag=CC"`.
- [ ] **`.gitignore`**: add `lib/oocdoc/`.
- [ ] **Remaining Phase 1 warnings**: `libc.Mod` `sscanf`/`sprintf`
      declarations, `HashCode.c` pointer cast, `GC_all_interior_pointers`.

- [ ] **C back end / runtime headers**: make generated C clean under
      `-std=gnu17` and then default gcc settings: missing prototypes,
      pointer casts, `int` vs pointer, `const` correctness in
      `lib/src/__oo2c.h`, `__libc.h` (declares `floor`, `lrint`, `memcpy`
      by hand; prefer including `<math.h>`/`<string.h>`). Fixes go in
      `src/OOC/C/*.Mod` and `src/OOC/Make/TranslateToC.Mod`.
- [ ] **Hand-written library C** (`lib/src/**/*.c`): replace `readdir_r`
      with `readdir`, fix warnings at `-Wall`.
- [ ] **Nested functions / executable stack**: find where the back end
      takes addresses of nested functions; decide between (a) accepting
      `-z execstack` for executables only and building `liboo2c` static,
      or (b) changing code generation so nested procedures that are passed
      as values get an explicit static link instead of a trampoline.
      (b) is the real fix but is a compiler change; document the decision
      here.
- [ ] **Autotools**: modernize `configure.ac`/`aclocal.m4` for autoconf
      2.72 (quote macro names in `AC_DEFUN`, drop `AC_TYPE_SIGNAL`,
      `AC_HEADER_STDC`, `AC_HEADER_TIME`, use `AC_CONFIG_HEADERS`), and
      regenerate `configure` and `lib/src/__config.h.in`. Choose sensible
      default `CFLAGS` (e.g. add `-fno-strict-aliasing` if Phase 1 showed
      it is needed).
- [ ] **libtool 2.x**: check how `src/OOC/Make` invokes libtool
      (`--tag=CC`, `--mode=link`, `-rpath`), make shared `liboo2c.so`
      work, and check that installed programs find it.
- [ ] **gc 8.x and threads**: verify `GC_INIT`; build with
      `--enable-threads=pthreads` and run `src/TestThread.Mod`.

## Phase 4: tests  `[ ]`

- [ ] `make test`; record the pass/fail counts here as a baseline before
      fixing anything else.
- [ ] Triage failures: toolchain-caused (fix) vs. expected-output drift
      (e.g. `tests/ssa-c-output` comparing exact C text after Phase 3
      changes: update the expected files deliberately, in their own
      commit).
- [ ] Also try `tests/hostess-ooc1` (`make test-hostess-ooc1`) and
      `tests/benchmark` as extra checks.

## Phase 5: make the repo self-bootstrapping  `[ ]`

- [ ] Run `make dist` (or the `stage0` part of it) with the fixed compiler
      to regenerate `stage0/` C sources for 64-bit Linux.
- [ ] Decide how to ship them: commit `stage0/` (remove it from
      `.gitignore`; easiest for users), or publish a release tarball on
      GitHub. Then `./configure && make && make install` works from a
      fresh clone.
- [ ] Check `make dist` itself: it does `ln -s ooc2 $(DISTDIR)` assuming the
      checkout dir is named `ooc2`; fix it to use the actual directory.

## Phase 6: polish (optional)  `[ ]`

- [ ] GitHub Actions CI on a current Fedora and Ubuntu image: build from
      `stage0`, self-host, `make test`.
- [ ] Update `README`/`INSTALL`/`PROBLEMS`/`README.md` for modern Linux
      (requirements, known issues, the new bootstrap path).
- [ ] Optional: aarch64 build; `oo2c_32` / `-m32` build; check that the
      documentation (`oocdoc` HTML via xsltproc) builds.

## Log

Record findings, recipes, and decisions here, newest first.

- 2026-11-16: Phase 2 done. HEAD builds with the 2.1.11 compiler, then
  rebuilds itself to an identical set of generated C files. One source
  change was needed: `--tag=CC` in `src/OOC/Config/CCompiler.Mod`.
  Installed HEAD compiler: `/usr/local/sw/tmp/oo2c-work/head`. Keep it
  and `boot/` for Phases 3–4 (`boot/` is the fallback if a Phase 3
  change breaks the compiler).

- 2026-11-16: Phases 0 and 1 done. The 2.1.11 tarball builds with gcc 16
  after two workarounds (main-file prototype error, `--tag=CXX`); see
  Phase 1. Ignoring `$Id$` lines, HEAD differs from the 2.1.11 tarball
  in only ~15 files (`src/H2O/*`, `src/OOC/Scanner/Pragma.Mod`,
  `lib/src/XML/Error.Mod`, a few tests and docs), so Phase 2 should not
  need an intermediate compiler.
- 2026-11-16: Plan created from a source survey; no builds attempted yet.
