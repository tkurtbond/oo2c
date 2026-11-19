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

- [x] Work branch: `modern-linux`, renamed `dev` after the 2.2.2
      release; releases are fast-forwarded to `master`.
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

## Phase 3: fix the sources properly  `[x]`

Replace flag workarounds with source fixes, one commit per topic:

Status (2026-11-16): all items done. The build recipe that checked
the first five items, from a clean tree (`$W/p3-build.sh`):

```sh
# stage 1: the Phase 2 recipe, so -Wno-error is still needed, because
# the 2.1.11 compiler writes main files without a prototype
env CFLAGS="-g -O2 -Wno-error=implicit-function-declaration" \
  ./configure --prefix=$W/stage1
. ./ENV && make "$OOC_DEV_ROOT/oo2crc-install.xml"
$W/boot/bin/oo2c -M --config oo2crc-install.xml oo2c
make install BOOTSTRAP_COMPILER=bin/oo2c
# stage 2: plain flags, built with the fixed stage-1 compiler
rm -rf obj sym bin lib/obj lib/sym lib/oocdoc oocdoc oo2crc-install.xml
env CFLAGS="-g -O2" ./configure --prefix=$W/p3
make "$OOC_DEV_ROOT/oo2crc-install.xml"
$W/stage1/bin/oo2c -M --config oo2crc-install.xml oo2c
make install
```

Stage 2 compiles with **no gcc warnings at all** under gcc 16's
defaults (`-std=gnu23`), so the `-Wno-error` workaround is needed only
while the 2.1.11 tarball compiler is the bootstrap (Phase 5 removes
that). `make test` with the result gives exactly the Phase 4 baseline,
plus the two new tests `procvar8`/`procvar9` (ssa 555 tests: 553
passed, 2 informal `div2`/`mod2` failed); all 56 `ssa-c-output` diffs
against `ref64` still pass. Self-host fixpoint: in a copy of the tree,
`bin/oo2c` built `oo2c` (C2), C2 rebuilt it from scratch (C3). The
generated `.c`/`.d`/`.h`/`.oh` and symbol files of both generations
are identical, and C2 and C3 are byte-identical binaries.

- [x] **Main file prototype** (found in Phase 1):
      `src/OOC/Make/WriteMainFileC.Mod` emits
      `extern void OOC_<Module>_open(RT0__Module client);` before `main`.
      `-Wno-error=implicit-function-declaration` is no longer needed
      for programs built by a fixed compiler.
- [x] **libtool tag** (found in Phase 1, fixed in Phase 2 because it
      blocked the HEAD build): `libtoolTag` in
      `src/OOC/Config/CCompiler.Mod` is now `" --tag=CC"`.
- [x] **`.gitignore`**: added `oocdoc` (`lib/oocdoc/`) and the test
      outputs (`tests/*/wd`, `tests/*/report.{html,xml}`,
      `tests/lib-TestCompile`, `tests/lib-oo2c`).
- [x] **Remaining Phase 1 warnings**:
      - `libc.Mod`: Oberon `CHAR` is C `unsigned char`, so no Oberon
        declaration of `sscanf`/`sprintf` can match gcc's built-in
        prototypes (`C.string` didn't help either). The module now has
        `LINK FILE "libc.c"`, and the two procedures have link names
        `oo2c_libc_sscanf`/`oo2c_libc_sprintf`. They are small varargs
        wrappers around `vsscanf`/`vsprintf` in the new
        `lib/src/libc.c`. A `LINK FILE` C file must define
        `OOC_libc_init`/`OOC_libc_destroy`; `open`/`close` come from
        the generated `libc.d`. The Oberon interface is unchanged.
      - `HashCode.c`: cast the pointer via `size_t`. The cast is only
        reached when pointers are 32 bits.
      - `RT0.c`: `GC_set_all_interior_pointers(0)` for gc ≥ 7.2, the old
        variable assignment otherwise.

- [x] **C back end / runtime headers**: make generated C clean under
      `-std=gnu17` and then default gcc settings: missing prototypes,
      pointer casts, `int` vs pointer, `const` correctness in
      `lib/src/__oo2c.h`, `__libc.h` (declares `floor`, `lrint`, `memcpy`
      by hand; prefer including `<math.h>`/`<string.h>`). Fixes go in
      `src/OOC/C/*.Mod` and `src/OOC/Make/TranslateToC.Mod`.
      Status: clean under gcc 16's defaults (`-std=gnu23`, no `-W`
      flags), so `-std=gnu17` is not needed. `-Wall -Wextra` survey (a
      copy of the tree configured with `CFLAGS="-g -O2 -Wall -Wextra"`):
      - About 7000 `-Wunused-but-set-variable`, 3000
        `-Wunused-parameter` and 620 `-Wunused-label` in generated code.
        These are artifacts of how the back end writes SSA temporaries,
        `RT0__Module client` parameters and block labels. The label logic
        in `OOC:C:WriteC` (`WriteBlocks`, `registeredGoto`, `degreeIn`)
        is involved, and removing them buys nothing. **Workaround:**
        `TranslateToC.WriteCodeFile` writes
        `#pragma GCC diagnostic ignored` for these three warnings after
        `#include <setjmp.h>` in every generated `.c` file. Only the
        generated code is affected; user-written C and the `.d` headers
        still get the warnings. Revisit if the back end is reworked.
      - `-Wstrict-aliasing` in `OOC/Scanner/Pragma.c`: the generated C
        reads fields through casted lvalues (a pointer field as
        `*(OOC_INT64*)`). That is type punning, so `configure` now adds
        `-fno-strict-aliasing` to `CFLAGS` for gcc (it ends up in
        `oo2crc.xml`, so it applies to every program oo2c builds).
      - Self-comparisons such as `i3 != i3`, from the run-time checks of
        type guards (`-Wtautological-compare`): `OOC:SSA:Algebraic` now
        folds `x=x`, `x<=x`, `x>=x` to `TRUE` and `x#x`, `x<x`, `x>x` to
        `FALSE` when `x` is not a real, since NaN is not equal to
        itself. New test `tests/ssa` `compare1` (integer, `REAL`/`LONGREAL`
        including NaN, a type guard on a pointer).
      - Left alone: `-Wunused-function` for
        `XML:Parser.ParseDocument.WriteBuffer` (a debug helper, already
        under `<*Warnings:=FALSE*>`), and `-Wclobbered` for `i0` in
        `XML/Writer.c`. The latter is a false positive: `i0` is reassigned
        after the `setjmp`, and later code reloads the value from the
        `volatile` variable.
      After these changes, a `-Wall -Wextra` build of the compiler and
      library shows those two warnings, plus `-Wunused-parameter` for the
      `client` parameter of the `open`/`close` functions in the generated
      `.d` headers. The `ref64` references were regenerated; they differ
      only in the three pragma lines.
- [x] **Hand-written library C** (`lib/src/**/*.c`): `readdir_r`
      replaced with `readdir` in `lib/src/OS/Files.c` (each `DIR*` is used
      by one thread only, so this is thread-safe). `-Wall -Wextra`
      fixes: unused variables in `Exception.c`, `IO/Select.c`,
      `OS/Files.c`; `socklen_t` for `getsockopt`/`getpeername`/`accept`
      in `IO/Socket.c`; `Termination.c`'s signal handler is `static
      void`. The `TIME_WITH_SYS_TIME` blocks in `SysClock.c`, `Files.c`
      and `Logger/TimeStamp.c` now just include `<time.h>` and, if
      present, `<sys/time.h>`. The only warnings left are
      `-Wunused-parameter` where the signature is fixed by the Oberon
      interface.
- [x] **Nested functions / executable stack**: trampolines only appear
      when the address of a nested C function is taken, i.e. when a
      procedure local to another procedure is used as a procedure value.
      The Oberon-2 report forbids this, but oo2c accepted it. Such a
      program got `GNU_STACK RWE` and the linker warning "requires
      executable stack". Upstream had already considered forbidding it
      (commented-out test `procvar7` in `tests/ssa/testsuite.xml`, which
      also notes that the SSA back end miscompiles it).
      **Decision:** (c) enforce the language rule. `src/OOC/IR.Mod`
      (`CheckProcValue`, error 81 "A local procedure cannot be used as a
      procedure value") rejects such a procedure in assignments,
      `RETURN` and value parameters. New reject tests `procvar8`
      (assignment) and `procvar9` (argument) are in `tests/ssa`. The
      compiler and library never did this: all 348 objects and
      `liboo2c.so` have no executable-stack note, and every program has
      `GNU_STACK RW`. Calling a local procedure directly is unaffected.
- [x] **Autotools**: `configure.ac` and `aclocal.m4` updated for autoconf
      2.72: `AC_PREREQ([2.69])`, `AC_CONFIG_HEADERS`, quoted `AC_DEFUN`
      names and macro arguments, `AS_HELP_STRING`; `AC_HEADER_STDC`,
      `AC_HEADER_TIME`, `AC_TYPE_SIGNAL` and the `readdir_r` check
      dropped (`RETSIGTYPE`, `TIME_WITH_SYS_TIME`, `HAVE_READDIR_R`,
      `HAVE_MEMORY_H` are gone from `__config.h.in`). `-fno-strict-aliasing`
      is added to `CFLAGS` for gcc (see above). Regenerate with
      `autoconf -Wall && autoheader -Wall` (no warnings), not
      `autoreconf`: `aclocal.m4` is hand-written, and `aclocal` would
      overwrite it. Remove `autom4te.cache` afterwards (it is in
      `.gitignore`).
- [x] **libtool 2.x** (2.5.4): all libtool calls use `--tag=CC`.
      `make install` installs `liboo2c.so.3`, `liboo2c.a` and
      `liboo2c.la`. The installed `oo2c`, and a program the installed
      compiler builds, both have `NEEDED liboo2c.so.3` and a `RUNPATH`
      of `$prefix/lib`, and run without `LD_LIBRARY_PATH`.
- [x] **gc 8.x and threads** (gc 8.2.6): `GC_INIT` is fine. With
      `--enable-threads=pthreads`, `src/TestThread.Mod` crashed or
      corrupted the heap. gc ≥ 7 only redirects `pthread_create` & co.
      to its wrappers (which register the thread stacks as roots) when
      `GC_THREADS` is defined; `gc_config_macros.h` ignores the old
      `GC_PTHREADS` that `configure` defined. `OOC_ARG_ENABLE_PTHREADS`
      now defines `GC_THREADS`. `liboo2c` then references
      `GC_pthread_create`, and TestThread passed 20 of 20 runs.
      TestThread also needed two source fixes: `Exception.Exception` is
      abstract, so it raises an `Exception.Checked`, and an unused
      import was removed. `make test` on the threads build gives the
      same results as the default build.

## Phase 4: tests  `[x]`

- [x] `make test`; record the pass/fail counts here as a baseline before
      fixing anything else.
- [x] Triage failures: toolchain-caused (fix) vs. expected-output drift
      (e.g. `tests/ssa-c-output` comparing exact C text after Phase 3
      changes: update the expected files deliberately, in their own
      commit).
- [x] 64-bit references for `tests/ssa-c-output` in `ref64/obj` (see below).
- [x] Also try `tests/hostess-ooc1` (`make test-hostess-ooc1`) and
      `tests/benchmark` as extra checks.

### Baseline (2026-11-16, HEAD `70a59444`, x86_64, gcc 16.2.1, gc 8.2.6)

Run in the repo after Phase 2 with
`make -k test` (`OOC` = `bin/oo2c --config oo2crc-install.xml`).

Framework suites (`tests/*/report.xml`):

| Suite | passed | failed |
|---|---|---|
| `tests/lib` | 155 | 2 (`lib_Finalize1`, `lib_WeakRef1`) |
| `tests/ssa` | 553 | 2 (`div2`, `mod2`) |
| `tests/ssa-c-output` (run/error) | 57 | 0 |
| `tests/ssa-c-output` (C text vs `ref/obj`) | 7 | 50 |

Script suites: every script reports only `ok` except
`tests/scanner/not-wf.sh` (31 ok, 1 failed: `not-wf/032.txt`). These
pass: config (sections, cmdline, environment, simple), scanner wf and
identity, parser (wf-compare, wf-stupid-pp, not-wf), symtab, interface,
oberon-doc and h2o.

### Triage

None of the failures is caused by the toolchain or the port.

- **`tests/scanner/not-wf/032`**: a test-data defect. Every other
  `out-err/*.err` file ends with a blank line, which the scanner test
  driver prints. `032.txt.err`, added by hand in 8fb4e73d (2011), lacks
  it. Fixed by appending the newline (uncommitted).
- **`div2`, `mod2`** (`relevance='informal'`): the references expect
  floor semantics for a *negative* divisor. `_div`/`_mod` in
  `lib/src/__oo2c.h` say explicitly "`_x MOD _y >= 0` for `_y>0`, and
  undefined otherwise", so this is a documented limitation, not a
  regression. Leave as is.
- **`lib_Finalize1`, `lib_WeakRef1`** (`relevance='informal'`): one object
  (WeakRef: `{9}`, the last one allocated) stays reachable, and the
  Finalize test finalizes 2 objects that the reference does not expect.
  This is conservative-GC retention, probably a stale pointer in a
  register or stack slot. Both test descriptions say "may fail if the GC
  does not always free all collectable objects". Leave as is.
- **`tests/ssa-c-output` C diffs (50 files)**: all are address-width
  drift. The references were generated on 32-bit, and here the address
  type is `OOC_INT64` instead of `OOC_INT32`. After normalizing
  `OOC_[U]INT{32,64}`, only `CodeMotion2`, `CodeMotion3` and `Generic51`
  still differ, and only in field offsets (`+4` → `+8`), which is also
  pointer width. `ref/obj/CodeMotion1.c` is an orphan: that test is
  commented out in `testsuite.xml` ("fails with the current code
  scheduler").
  **Decision:** keep the 32-bit references in `ref/obj`, and add 64-bit
  references in `ref64/obj`, generated from the HEAD compiler at
  `70a59444` (without the orphaned `CodeMotion1`).
  `tests/ssa-c-output/Makefile` reads `SIZEOF_VOIDP` from
  `lib/src/__config.h` and diffs against `ref64` when it is 8. With
  this, all 56 diffs pass. If a Phase 3 change alters the generated C,
  review the diff, then update `ref64/obj` deliberately in its own
  commit.
- **`tests/hostess-ooc1`**: the test cases come from the external
  `hostess` CVS module (the `hostess/hostess` directory, with
  `testcases.dtd` and `oberon/`). The suite was written for oo2c v1
  (processor `oo2c`, `sample-oo2crc`, `-Ow`), which the v2 `RunTests`
  rejects with "Processor incompatible to O2". It now uses the
  `TestCompile` processor like `tests/ssa`, with `--out-module Out` so
  the generated drivers use the suite's Oakwood `Out`. `testsuite.xml`
  reads the cases through a symlink `tests/hostess-ooc1/hostess`, which
  the Makefile points at `$(HOSTESS)` (default
  `$OOC_DEV_ROOT/../hostess/hostess`, the old relative layout):
  `make test-hostess-ooc1 HOSTESS=/usr/local/sw/src/lang/Oberon/hostess`.
  Result (`$W/p3-hostess-3.log`): **103 passed, 13 failed**, plus 7
  informal failures. The 2.1.11 compiler has the same three compiler
  bugs listed below, so none of them comes from the port. All three
  are now fixed (see Phase 3); after the fixes
  (`$W/p5-hostess.log`): **105 passed, 11 failed**, 5 informal
  failures, all of them v1 test assumptions.
  - `proc6`, `boolexpr0`, `record4`, `record6`, `string0`, `proc4`,
    `proc5`, `for0`: they use `ASSERT`/`HALT` codes ≥ 128, which oo2c
    v2 rejects (codes must be 0..127). `proc4a`, `proc5a`, `proc5b`
    then fail with "Cannot locate module HOTProc4/HOTProc5". These are
    v1-only test assumptions.
  - `array2` (reject test, `TYPE A = ARRAY -1 OF LONGINT`) is
    accepted: **compiler bug**, no check for a negative array length.
    Fixed: `IR.Builder.AssertArrayLength`, used by
    `OOC:AST:CreateIR` (test `tests/ssa` `array14`).
  - `typetest2` (`p(P) := q`, a type guard as an assignment target)
    makes the compiler fail an assertion in `OOC:SSA`: **compiler
    bug**. For a pointer variable the guard is a `typeGuard`
    instruction, not a `get`. Fixed in `IRtoSSA.Assignment`: the guard
    stays for its run-time check and the value is stored into the
    guarded variable (tests `typetest10`, `typetest11`).
  - Informal: `sysBuiltin0`/`sysBuiltin0FOR` import the Oberon System
    module `Texts`, which OOC does not have. `specialexport1A`,
    `specialexport2A`, `specialexport1B` use dotted file names
    (`HOTSpecialExport1.A.Mod`) that the repository can't locate.
  - Informal: `sysarr0`/`sysarr0FOR` segfault at run time: **compiler
    bug**. When an open `ARRAY OF CHAR` parameter is passed to an
    `ARRAY OF SYSTEM.BYTE` formal parameter, the generated call passes
    the length `(-1)` instead of `LEN(b)*SIZE(CHAR)`
    (`HOTSysArr0__Test2_Check1((void*)(OOC_INT64)b, (-1))`); fixed-size
    arrays get the right length (`16`). The callee's
    `OOC_ALLOCATE_VPAR` then asks for a huge VLA (gcc warns
    `-Wvla-larger-than`) and overflows the stack. Fixed in
    `IR.Mod` (`ByteSize` in the call builder): the length is the
    product of the open lengths and the element size (test `array13`).
    The compiler itself had two such calls (`WriteSymbolFile`,
    `Doc:Input:Texinfo`, both harmless because `WriteBytes` takes an
    explicit count); they now pass the real length. The self-host
    fixpoint still holds (generations 2 and 3 identical).
- **`tests/benchmark`** (`make -C tests/benchmark test OOC=$PWD/bin/oo2c`):
  at first it failed to link with undefined `OOC_{Array,FFT,Sort,Warshall}C_close`.
  This is upstream bit-rot: commit 4f503d79 (2004) switched modules to
  `open`/`close`, but only gave the benchmark's hand-written C files an
  `open`. Fixed by adding empty `close` stubs (uncommitted). With them
  the benchmark builds and runs all 31 kernels without errors. The
  Oberon versions run at 87–133% of the hand-written C for most kernels
  (QSORT 123%, Warshall 106%, FFT 67%, FFT2 294%). `ZeroArray1` is the
  outlier at 13%, because gcc turns the C loop into `memset`. The full
  table is in `$W/p4-bench.log`.
  The build log also shows the known `OOC_Benchmark_open` implicit
  declaration warning (Phase 3).

## Phase 5: make the repo self-bootstrapping  `[x]`

- [x] Regenerate `stage0/` with the fixed compiler. Recipe, in a clean
      clone (`$W/dist/oo2c`), with the installed compiler from Phase 3
      in `PATH` so that `configure` sets `OOC` to it:
      ```sh
      PATH=$W/p6/bin:$PATH ./configure --prefix=$W/dist/inst
      . ./ENV && make dist        # -> ../oo2c_64-<version>.tar.bz2
      ```
      `stage0/` is 9.7 MB of C (166 `.c`, 180 `.d`/`.oh`), the tarball
      1.9 MB. In a fresh clone, git gives all files the same mtime, so
      `make dist` may regenerate `configure` and stop with "Stale
      config.status"; rerun `./configure` and `make dist`.
- [x] **Decision:** ship `stage0/` only in release tarballs (a GitHub
      release), not in git; a git checkout still needs
      `BOOTSTRAP_COMPILER`. `README` documents both ("Build and Install
      Using a Git Working Copy", "Making a Release Tarball").
- [x] Verified: the tarball, unpacked into an empty directory with no
      oo2c in `PATH`, builds with `./configure && make && make install`
      and **no gcc warnings**; `make test` in it passes everything (ssa
      558, lib 148, ssa-c-output 57); the installed compiler builds and
      runs a Hello program.
- [x] `make dist` fixes: the tar step did `ln -s ooc2 $(DISTDIR)` (the
      upstream checkout directory name), and piped `tar` into `bzip2`, so
      the failure didn't stop make. It now runs `tar -cj` in place, with
      `--transform` to put the files under `$(DISTDIR)/` (`S`: not the
      symlink targets in `stage0/`) and `--exclude-vcs`. `DISTDIR` in
      `Makefile.config.in` was hard-wired to `oo2c_32-...`; it now uses
      `@ooc_target_address@`. `dist64` (making a 64-bit tarball on a
      32-bit host) is unchanged and untested.
- [x] **Version:** 2.2.0 (`AC_INIT`), so the tarball doesn't share
      upstream's name `oo2c_64-2.1.11.tar.bz2` with different contents.
      A minor bump, not 2.1.12, because error 81 rejects programs that
      2.1.11 accepted. `AC_INIT` now points bug reports at
      https://github.com/tkurtbond/oo2c/issues and sets `PACKAGE_URL`;
      `NEWS` lists the changes since 2.1.11. The libtool version in
      `lib/pkginfo.xml.in` (3:0:0, `liboo2c.so.3`) is separate and
      unchanged. Tag releases as annotated `vX.Y.Z` tags.
- [x] Published `oo2c_64-2.2.0.tar.bz2` (SHA-256 `7046a2be4d7b…8d24`)
      as the GitHub release https://github.com/tkurtbond/oo2c/releases/tag/v2.2.0,
      with `NEWS` as the release notes. It was made from a clean clone of
      `11ac3859`, which is tagged `v2.2.0` (annotated), and verified from
      scratch the same way as above.

## Phase 6: polish (optional)  `[x]`

- [x] GitHub Actions CI on a current Fedora and Ubuntu image: build from
      `stage0`, self-host, `make test`. `.github/workflows/ci.yml` runs
      `.github/ci-build.sh` in `fedora:latest` and `ubuntu:latest`
      containers. First run on GitHub (43931798621, `0d3babba`) passed
      on Fedora 45 (gcc 16.2.1, gc 8.2.6, libtool 2.5.4) and Ubuntu
      26.04 (gcc 15.2), about 5 minutes per job.
- [x] Update `README`/`INSTALL`/`PROBLEMS`/`README.md` for modern Linux
      (requirements, known issues, the new bootstrap path).
- [x] Optional: aarch64 build. CI jobs `fedora-aarch64` and
      `ubuntu-aarch64` on GitHub's `ubuntu-24.04-arm` runners bootstrap
      from the `oo2c_64` tarball (stage0 C depends only on the pointer
      size; configure does not use `config.guess`). First run
      (43945754582) passed with no changes to the sources: 558/148/57,
      no gcc warnings; on aarch64 the informal `lib` tests all pass.
- [x] Optional: check that the documentation (`oocdoc` HTML via
      xsltproc) builds. `make install` runs xsltproc on every library
      module: 123 XML and 123 HTML files in `lib/oo2c/oocdoc`, none
      empty, no xsltproc messages, no broken relative links. Fixed
      one stylesheet bug: the "Import List" also showed the imports
      the compiler adds itself (`-Object`, `-RT0`, `-Exception`) when
      the module was referenced anyway, so e.g. `ADT:ArrayList` and
      `Out` (`Obj := Object`) listed Object twice;
      `rsrc/OOC/xml/interface-description.xsl` now skips names that
      start with `-`. That removes 103 duplicate links in 56 pages and
      changes nothing else.
- [x] 32-bit release (`oo2c_32-<version>.tar.bz2`):
      - [x] `make dist32` (replaces the old `dist64`, which sedded the
        pre-2.60 `config.status` format): after a normal configure on
        x86-64 it rewrites `bitsTargetAddress` and `address` in the
        generated `src/OOC/Config/Autoconf.Mod` (and sets
        `bitsTargetInteger` to 64), then runs `make dist`. The
        `bin/oo2c` that `make dist` builds is a native 64-bit program
        that generates 32-bit `stage0/`. This avoids building a
        `-m32` compiler with the 64-bit installed one. `dist64` does
        the reverse.
      - [x] Regenerated `tests/ssa-c-output/ref` (the 32-bit reference
        set) from a `-m32` build: the differences from the old set are
        only the `#pragma GCC diagnostic` header and the open-array
        parameter declarations; it differs from `ref64` only in the
        address size (`OOC_INT32`/`OOC_INT64` registers and casts,
        offsets 4/8). Removed the stale `ref/obj/CodeMotion1.c`
        (its test is commented out, and `ref64` has none).
      - [x] Verified `oo2c_32-2.2.2.tar.bz2` (made by `make dist32`
        from this tree) with `CC="gcc -m32"` on Fedora 44 x86-64
        (needs `glibc-devel.i686`, `libgcc.i686`, `gc-devel.i686`):
        no gcc warnings in make, install and test; `make test`
        559/148/57, informal failures div2 and mod2 only; Hello is a
        32-bit ELF with `SIZE(SYSTEM.ADDRESS)` = 4.
      - [x] Verified in a native i386 container
        (`podman run --platform linux/386 i386/debian:bookworm`, gcc
        12, gc 8.2): same results (559/148/57, no gcc warnings, Hello).
      - [x] Attached to release 2.2.3 (2026-11-17), with
        `oo2c_64`, the `.asc` signatures and `SHA256SUMS`. The
        2.2.3 tarballs, made with `make dist` and `make dist32` from
        two clean copies, pass `make test` (559/148/57) and Hello with
        no gcc warnings on Fedora 44, Ubuntu (container), NetBSD
        11.0, OpenBSD 7.9 and FreeBSD 15.1 amd64 and arm64
        (`oo2c_64`), and in the i386 container and with `gcc -m32`
        (`oo2c_32`). Informal failures as before: div2, mod2,
        vtable5 without g++, and `lib_Finalize1`/`lib_WeakRef1` now
        and then.
      - [x] CI job `i386`: builds this tree on the x86-64 runner
        (`ci-build.sh` with `TESTS=no`), makes an `oo2c_32` tarball
        from a clean clone with `make dist32`, and runs `ci-build.sh`
        bootstrapping from it in an `i386/debian:bookworm` container.
        Checked locally with podman: 559/148/57, no gcc warnings.
        Docker on the GitHub runner (29.4, kernel 7.0) needs
        `--security-opt seccomp=unconfined` for the container: with
        the default seccomp profile no host name resolves in a 32-bit
        container.
- [x] BSDs (FreeBSD, OpenBSD, NetBSD): never tested upstream; tested here
      since 2.2.2 (below).
      Expected needs: gcc from ports/packages (the generated C uses
      nested functions, so the default clang can't be used; NetBSD has
      gcc in base), GNU make (`gmake`), GNU tar for `make test` and
      `make dist`, boehm-gc and libtool from ports. Check threads with
      the BSD gc packages and OpenBSD's W^X. Test in VMs, or in the CI
      with cross-platform-actions; record the results in `README` and
      `PROBLEMS`.
      - 2026-11-16: tested in local VMs with `.github/ci-build.sh`
        (now takes `MAKE=gmake`, `TAR=gtar`, `CC`, `CPPFLAGS`,
        `LDFLAGS`): FreeBSD 15.1 amd64 (gcc16) and arm64 (gcc14),
        OpenBSD 7.9 amd64 (egcc 15), NetBSD 11.0 amd64 (base gcc 12).
        All pass `make test` (558/148/57) and Hello with no gcc
        warnings. Recipes are in `INSTALL`. Informal failures: div2,
        mod2, plus vtable5 where there is no g++.
      - [x] Threads (`--enable-threads=pthreads`) on the BSDs
        (2026-11-17), with `oo2c_64`/`oo2c_32-2.2.3` and the same
        settings as above: `make test` (559/148/57) with no gcc
        warnings, and `src/TestThread.Mod` 20 of 20 runs, on OpenBSD
        7.9 amd64 and i386, NetBSD 11.0 amd64 and i386, and Fedora 44.
        FreeBSD failed to link `bin/oo2c` (undefined
        `GC_pthread_create`, `GC_pthread_join`, `GC_pthread_sigmask`):
        FreeBSD's `boehm-gc` has no thread support, and the threaded
        gc is a separate package, `boehm-gc-threaded`, with
        `libgc-threaded.so`. With threads, `configure` now checks for
        `GC_pthread_create` in `-lgc` and falls back to
        `-lgc-threaded`. It then puts `-lgc-threaded` in `LIBS`, and
        sets the pragma `HAVE_LIB_GC_THREADED` (`lib/pkginfo.xml.in`,
        `Autoconf.Mod.in` for `TestCompile`), which makes the `RT0.Mod`
        link clause use `LIB "gc-threaded"`. If neither library has
        the wrappers, configure stops with an error. A 2.2.3 tarball
        with this change passes the same checks on FreeBSD 15.1 amd64
        (gcc16) and arm64 (gcc14). Informal
        failures as without threads (div2, mod2, vtable5 without g++,
        lib_Finalize1 and lib_WeakRef1 now and then). The CI's FreeBSD
        job now builds with threads (`THREADS=pthreads` in
        `.github/ci-build.sh`, which also runs TestThread 5 times).
      - [x] i386 VMs: the released `oo2c_32-2.2.3.tar.bz2` passes
        `make test` (559/148/57) and Hello (a 32-bit i386 ELF) with no
        gcc warnings on OpenBSD 7.9 i386 (egcc 15) and NetBSD 11.0
        i386 (base gcc 12), with the same settings as on amd64
        (2026-11-17).
        Informal failures: div2, mod2, plus vtable5 on OpenBSD (no
        g++) and lib_WeakRef1 once on NetBSD.
      - [x] FreeBSD 15.1, OpenBSD 7.9 and NetBSD 11.1 jobs in the CI
        (`vmactions/freebsd-vm`, `openbsd-vm`, `netbsd-vm`: a QEMU VM
        on a Linux runner, 6 to 10 minutes each).
- [x] gcc warnings in `make test`, from two `tests/ssa` programs, on
      every platform: `Array5.c`: `'Array5__WriteArray' accessing 8
      bytes in a region of size 6 [-Wstringop-overflow=]` and
      `Iterator2.c`: `'Iterator2__Write' reading 2 bytes from a region
      of size 0 [-Wstringop-overread]`. False positives: neither
      program reads past the array. gcc assumes that a parameter
      declared with array syntax, `T a[]`, points to at least one `T`.
      Iterator2 passes an empty `ARRAY 0 OF LONGCHAR`, and Array5's
      `ARRAY OF ARRAY OF SHORTINT` parameter was declared `OOC_INT8
      *a[]`, an array of pointers (8 bytes) for a 6-byte array.
      `ConvertDecl` now declares an open-array parameter as a pointer
      to its element type (`T *a`, `T (*a)[]` for two open
      dimensions), the same type in C, and `make test` builds with no
      gcc warnings. Changes only parameter declarations in
      `tests/ssa-c-output/ref64` (23 lines).
- [x] `make test-valgrind` (Linux): runs the `tests/ssa` and
      `tests/lib` suites with every test program under memcheck
      (`RunTests --run-prefix`, set from `TEST_RUN_PREFIX`), with
      `rsrc/OOC/TestFramework/valgrind-gc.supp` for the conservative
      scans of Boehm gc (`Memcheck:Cond`, `Value8`, `Addr8` in
      `fun:GC_*`) and `--error-exitcode=97`, so a memcheck error fails
      a run test. First run (valgrind 3.27.1, Fedora 44, 3.5 minutes):
      558/148 passed, no memcheck output in any of the 327 `.run.err`
      files; informal failures only `div2`, `mod2`, `lib_Finalize1`.
      Memcheck can't see overruns that stay inside a stack frame or a
      gc object; ASan (below) can.
- [x] `make test-asan`: runs the `tests/ssa` and `tests/lib` suites
      with the test programs and the library modules they use
      compiled with `-fsanitize=address,undefined -fno-sanitize=vptr
      -fno-sanitize-recover=all -fno-sanitize-address-use-after-scope
      -fno-omit-frame-pointer` (`RunTests --processor-flags`, set from
      `TEST_PROCESSOR_FLAGS`, adds `--cflags`/`--ldflags` to the
      compile command), with
      `ASAN_OPTIONS=detect_leaks=0:detect_stack_use_after_return=0`.
      The compiler itself is not instrumented. `test-valgrind` and
      `test-asan` call `make -k test`, so `tests/lib` runs even when
      `tests/ssa` fails.
      Without `-fno-sanitize-address-use-after-scope`, building
      liboo2c with ASan stops with a false "unknown-crash" in the
      `memcpy` of a value-parameter copy (`OOC_INITIALIZE_VPAR`, a
      VLA) in `Strings.Length`: a stale partial-granule shadow byte
      written by the caller's caller `OOC:Doc:Input:Texinfo.Parse`, a
      function with nested functions. This is a gcc bug (seen with
      gcc 16.2.1). Its local `bufferPos` (a 12-byte
      `OOC_Doc__Position`) is used by a nested function, so
      tree-nested moves it into the `FRAME.Parse` struct at an offset
      of 4 mod 8. The use-after-scope `ASAN_MARK`s on it still assume
      the variable starts on an 8-byte shadow granule. gcc repeats
      them at every C label, and sanopt keeps them when an earlier
      poison, here of another scoped variable, reaches the label. The
      marks therefore leave a wrong `04` in the shadow. The epilogue
      resets only the redzone shadow bytes, not those under variable
      bodies, so the `04` survives the return. Later, a callee's
      `alloca`/VLA, which poisons only its own redzones, writes over
      it and gets the report. Reduced (fails at -O0, -O1, -O2 with
      `gcc -fsanitize=address`; ASan reports the read of `bp.a`
      inside `g` itself):

      ```c
      struct pos { int a, b, c; };
      __attribute__((noinline)) void set(struct pos *p, int v) { p->a = p->b = p->c = v; }
      __attribute__((noinline)) void use(int *p) { *p += 1; }
      __attribute__((noinline)) int f(int n) {
        struct pos bp;                 /* in FRAME.f at offset 12 */
        int g(void) { set(&bp, n); return bp.a; }
        { int t = n; use(&t); n = t; } /* poison of t reaches l7 */
        goto l7;
      l7:                              /* re-unpoison of bp, misaligned */
        return g();
      }
      int main(int argc, char **argv) { (void)argv; return f(argc) != 2; }
      ```

      `-fno-sanitize-address-use-after-scope` avoids it, and so do
      aligning the struct *type* to 8 or making the struct 8 bytes.
      `__attribute__((aligned(8)))` on the variable does not. No matching gcc
      Bugzilla report found (2026-11-17); a candidate for one. Not
      worth a generator workaround: keep the flag in
      `TEST_PROCESSOR_FLAGS`.
      `-fno-sanitize=vptr`: in `vtable5` (informal) C++ code calls
      methods of objects that Oberon allocated, which have no C++
      type info.
      Fixed findings: `1<<31` in `tests/ssa/src/Out0.c` (`Out0.Set`);
      `ASH` of a negative value shifted a negative signed value
      (`_ashl` in `__oo2c.h` now shifts as `OOC_UINT64`); `ROT` by 0
      shifted by the type's width (`_rot` reduces the count to
      0..bits-1 and returns the value for 0); a zero-length VLA for an
      empty open-array value parameter (`OOC_ALLOCATE_VPAR` in
      `__dynvar.h` allocates at least one element); the `HashCode.c`
      overflow below. Result (Fedora 44, gcc 16): 557/148 passed;
      failed only `cstring1` (below, now fixed); informal failures
      `div2`, `mod2` as without sanitizers.
- [x] ASan: `tests/ssa` `cstring1` read 4 bytes before a string
      constant. For `str: POINTER [CSTRING] TO ARRAY OF CHAR`, passing
      `str^` to an open-array parameter took its length with
      `OOC_ARRAY_LENGTH`, from the word before the data, which a C
      string doesn't have; the test passed only because `Out0.String`
      stops at the NUL. Cause: `IR.Widen` case 9 lets a string
      constant or an `ARRAY OF CHAR` be assigned to a `POINTER
      [CSTRING]`, but in a non-INTERFACE module its base type `ARRAY
      OF CHAR` had length info (`C.string` in `C.Mod`, an INTERFACE
      module, never did). Now `[CSTRING]` implies `NO_LENGTH_INFO` for
      a one-dimensional open array written in the pointer type
      (`CreateNamespace.ResolveModifierFlags`), so `LEN(str^)` and
      passing `str^` to an open-array parameter are errors (new reject
      test `cstring2`), and `cstring1` walks the string to its `0X`.
      Also fixed `IR.NewLen`, which tested `lenOpenArrayHeap` twice;
      the second test is now `lenOpenArrayParam`.
- [x] UBSan: signed `int` overflow in the hash loops of
      `lib/src/HashCode.c` (`1000003*x`). Now unsigned arithmetic;
      the hash values are unchanged.

## Log

Record findings, recipes, and decisions here, newest first.

- 2026-11-17: Released oo2c 2.2.4 (signed tag `v2.2.4` on `761f9090`,
  also `master`), a bug fix release for threads on FreeBSD
  (`-lgc-threaded`), with `oo2c_64-2.2.4.tar.bz2` (sha256
  `2bf6d126...a9d1bbdb`) and `oo2c_32-2.2.4.tar.bz2` (sha256
  `65b02a91...d4a5f963`). Verified from the tarballs: `make test`
  (559/148/57) and Hello with no gcc warnings on Fedora 44, in an i386
  Debian container, on OpenBSD 7.9 and NetBSD 11.0 amd64 and i386;
  with `--enable-threads=pthreads`, `make test` and TestThread 5 of 5
  on Fedora 44 and FreeBSD 15.1 amd64 (gcc16) and arm64 (gcc14).
  Informal failures as before (div2, mod2, vtable5 without g++,
  lib_Finalize1 and lib_WeakRef1 now and then). The CI now bootstraps
  from 2.2.4.

- 2026-11-16: Released oo2c 2.2.2 (signed tag `v2.2.2` on `88be7f74`,
  also `master`) with `oo2c_64-2.2.2.tar.bz2` (sha256
  `9da84f52...f04399`): builds on the BSDs, NetBSD 11.0 workaround,
  no OpenBSD linker warnings. Verified from scratch (configure, make,
  install, `make test`, Hello) on Fedora 44, in an `ubuntu:latest`
  container, and in the VMs: FreeBSD 15.1 amd64 (gcc 16) and arm64
  (gcc 14), OpenBSD 7.9, NetBSD 11.0 (no manual steps needed). All
  558/148/57, no warnings in make or install; `make test` has the two
  `Array5`/`Iterator2` gcc warnings everywhere. The CI now bootstraps
  from 2.2.2.

- 2026-11-16: BSDs. FreeBSD and OpenBSD build the 2.2.1 tarball and
  HEAD unchanged (with gcc, gc, libtool, gmake, gtar from packages; see
  `INSTALL`). OpenBSD's linker warned about `sprintf`, `vsprintf` and
  `strcpy` in the hand-written C; replaced them with `snprintf`,
  `vsnprintf` and `memcpy` everywhere outside the Windows-only files,
  and `libc.sprintf` with a bounded `libc.snprintf` (its only callers
  are `RealStr` and `LRealStr`), also in the test copy
  `tests/ssa/src/Out0.c`. No more linker warnings, except from the
  2.2.1 tarball's own stage0 sources.
  NetBSD 11.0: `stage0/oo2c` crashed in `GC_init` about a third of the
  time when started by gmake. Cause: kernel bug PR kern/60653, a
  process started by `posix_spawn` gets a stale stack base (from an
  earlier exec), so gc's `GC_get_stack_base` is wrong; GNU make 4.4
  uses `posix_spawn` for recipe lines without shell syntax. Running
  the same program directly, via fork+exec, or through `sh -c` never
  crashed. Fixed in NetBSD-current on 2026-08-28 and in NetBSD 11.1
  (ticket #541, `CHANGES-11.1`), also pulled up to netbsd-10 (#1386);
  https://gnats.netbsd.org/60653. Workaround: `Makefile` prefixes
  every recipe line that runs oo2c with `$(VIA_SHELL)` (`exec`), which
  makes gmake use the shell. The test makefiles already run their
  programs with `cd ... &&`. Recorded in `PROBLEMS`.

- 2026-11-16: aarch64 works unchanged: the CI builds and tests on
  Fedora 45 and Ubuntu 26.04 on arm64 runners. CI now runs on branch
  pushes only (a tag push used to start an identical extra run).

- 2026-11-16: Signed the releases with GPG key `E4C824CF66BC045C`.
  Replaced tags `v2.2.0` and `v2.2.1` by signed tags on the same
  commits and force-pushed them, and attached `.asc`, `SHA256SUMS` and
  `SHA256SUMS.asc` to both releases (the tarballs were first checked
  byte-identical to the published assets). The recipe is in README,
  "Making a Release Tarball".

- 2026-11-16: Released oo2c 2.2.1 (tag `v2.2.1` on `8b64ab96`, also
  `master`) with `oo2c_64-2.2.1.tar.bz2` (sha256 `820d1965...7bfd42`):
  the Debian/Ubuntu link fix. Made with `make dist` in a clean clone
  configured without `--prefix`, so stage0's default config path is
  `/usr/local/lib/oo2c/oo2crc.xml`. The tarball builds, installs and
  passes `make test` (558/148/57) with no gcc warnings on Fedora 44
  and in an `ubuntu:latest` (26.04) container. The CI now bootstraps
  from 2.2.1.

- 2026-11-16: Phase 6: CI. `.github/ci-build.sh` builds the bootstrap
  compiler `stage0/oo2c` from the release tarball (only `make
  stage0/oo2c`, which links object files and needs `--config`: its
  compiled-in default config path is the prefix `make dist` was
  configured with, a scratch dir for 2.2.0), builds the tree as in
  README, fails on any gcc warning, runs `make test` and a Hello
  program. Run it locally in a container with
  `podman run -v <clone>:/src:Z -w /src <image> sh -c '<install pkgs>;
  sh .github/ci-build.sh'`; extract tarballs with `--no-same-owner`,
  or the files end up owned by a subuid.
  Found: the 2.2.0 tarball's `make` fails on Ubuntu 26.04 (gcc 15.2,
  libtool 2.5.4, gc 8.2.12) linking `bin/oo2c`: `undefined reference
  to symbol 'floor@@GLIBC_2.2.5'`, `DSO missing from command line`.
  `-lm` was only in `liboo2c.la`'s `dependency_libs`, which Debian's
  libtool (`link_all_deplibs=no`) doesn't pass on, while the generated
  C calls `floor` directly (`_entier` in `__oo2c.h`). Fix:
  `OOC:Make:LinkProgramC` always takes RT0's `LINK LIB` directives, so
  program links end in `liboo2c.la -lm -lgc -ldl`. Needs a rebuilt
  compiler, so 2.2.0 and older stay broken on Debian/Ubuntu (PROBLEMS);
  the CI avoids it by bootstrapping with `stage0/oo2c`. Both containers:
  no warnings, ssa 558, lib 148, ssa-c-output 57 passed. Informal
  failures: `div2`, `mod2`, `lib_Finalize1` (both), `lib_WeakRef1`
  (Fedora), `vtable5` (Ubuntu, no g++; now installed by the CI).

- 2026-11-16: Released oo2c 2.2.0 (tag `v2.2.0` on `11ac3859`) on
  GitHub with `oo2c_64-2.2.0.tar.bz2`. Phase 5 is complete.

- 2026-11-16: Phase 5: `make dist` fixed and run in a clean clone. The
  resulting `oo2c_64-2.1.11.tar.bz2` bootstraps from scratch (no oo2c
  installed) with no gcc warnings, and passes `make test`. Decision:
  ship `stage0/` in release tarballs only. Version bumped to 2.2.0 for
  the first release of the fork; bug reports go to the fork's GitHub
  issues.

- 2026-11-16: Phase 3 done (uncommitted): autotools for autoconf 2.72,
  `-fno-strict-aliasing`, `GC_THREADS` for gc 8 (TestThread now passes
  with `--enable-threads=pthreads`), libtool 2.5 shared-library check,
  `-Wall -Wextra` fixes in the hand-written library C, folding of
  self-comparisons in `OOC:SSA:Algebraic` (test `compare1`), and
  pragmas that silence the three unused-* warnings in generated `.c`
  files. `ref64` regenerated; it had never been committed, because the
  `obj` pattern in `.gitignore` matched `ref64/obj` (now excepted).
  `make test`: ssa 558, lib 148, ssa-c-output 57 passed. Hostess
  105/11 as before. Self-host fixpoint holds.

- 2026-11-16: Fixed the three upstream compiler bugs found by hostess
  (uncommitted): negative array length, type guard as assignment
  target, open array passed to `ARRAY OF BYTE`. New `tests/ssa` tests
  `array13`, `array14`, `typetest10`, `typetest11`. `make test`: ssa
  557 passed (only the informal `div2`/`mod2` fail), lib 148,
  ssa-c-output 57, `ref64` diffs empty. Hostess: 105 passed, 11
  failed (all v1 `ASSERT` codes ≥ 128). Self-host fixpoint holds and
  the compiler builds itself without warnings from these changes.

- 2026-11-16: `tests/hostess-ooc1` runs again against a hostess
  checkout (`HOSTESS=<dir>`, v2 `TestCompile` setup): 103 passed, 13
  failed. The failures are v1-only `ASSERT` codes ≥ 128 and two
  upstream compiler bugs (`array2` negative length, `typetest2` SSA
  assertion). A third bug shows up in the informal `sysarr0` (open
  array passed as `ARRAY OF BYTE` gets length -1). Details in the
  Phase 4 triage.

- 2026-11-16: Phase 3, first part (uncommitted): main-file prototype,
  `.gitignore`, `libc.Mod` wrappers, `HashCode.c`, `RT0.c` gc API,
  `readdir`, and rejecting local procedures as procedure values (no
  more trampolines, so no executable stack is possible). A compiler
  built with these changes builds itself and the library with plain
  `-g -O2` and **zero** gcc 16 warnings. `make test` is unchanged from
  the baseline (plus 2 new passing tests), and the self-host fixpoint
  holds, with byte-identical binaries. Still open: autotools, libtool
  2.x / shared-library checks, gc + pthreads, `-Wall` cleanliness.

- 2026-11-16: Phase 4 baseline: lib 155/2, ssa 553/2, ssa-c-output
  57/0 run plus 50 C-text diffs, and all script suites pass except
  scanner `not-wf/032`. None of this is caused by the port. Two
  test-data fixes (scanner 032 expected file, benchmark `close` stubs),
  plus 64-bit `ssa-c-output` references in `ref64/obj`. After these,
  only the 4 informal lib/ssa tests fail. Details in Phase 4.

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

## macOS (Apple Silicon)  `[x]` first build, 2026-11-19

Darwin 27.2 arm64, Homebrew gcc 16.2 (Apple clang can't be used: nested
functions), bdw-gc 8.2.12, glibtool, macOS xsltproc. The signed 2.2.4
tarball builds and installs, and HEAD builds with it. `make test`:
559/148/57 passed, 0 failed, only the informal `div2`/`mod2` fail (as on
Linux), and the `ssa-c-output` diffs are empty.

Also run on macOS (2026-11-19):
- `make test-asan` (Homebrew gcc 16 has libasan/libubsan): `tests/ssa`
  559 and `tests/lib` 148 passed, only the informal `div2`/`mod2` fail,
  and no `.run.err` file holds a sanitizer report.
- `--enable-threads=pthreads` (separate clone, bootstrapped with the
  non-threaded install): `configure` defines `GC_THREADS` and finds
  `GC_pthread_create` in `-lgc`; `src/TestThread.Mod` passed 20 of 20
  runs.
- Not run: `make test-valgrind` (Linux only) and the hostess tests.

Recipe:

    brew install gcc bdw-gc libtool
    LIBTOOL=/opt/homebrew/bin/glibtool CC=gcc-16 \
      CPPFLAGS=-I/opt/homebrew/include LDFLAGS=-L/opt/homebrew/lib \
      ./configure --prefix=...

Issues found:
- `lib/src/__libc.h`: the SDK's `_FORTIFY_SOURCE` headers define `memcpy`
  as a macro, so the extern declaration was a syntax error. Fixed with
  `#ifndef memcpy`. The 2.2.4 tarball needs the same patch to build.
- `configure` picks Apple's `/usr/bin/libtool` (a different tool) unless
  `LIBTOOL` is an absolute path to `glibtool`. `configure.ac` now uses
  `AC_PATH_PROGS(LIBTOOL,[glibtool libtool],no)`, but `configure` is not
  regenerated yet. TODO: run `autoconf -Wall` with autoconf 2.72 (the
  Mac only has 2.73, which rewrites ~1400 lines of unrelated boilerplate)
  and commit `configure` with `configure.ac`.
- macOS libxml2 2.9.13 rejects `rsrc/OOC/xml/oberon-doc.dtd` ("Content
  error in the external subset"), so the HTML doc step fails. Workaround:
  set `xsltproc` to `no` in `Makefile.config` and `oo2crc*.xml` after
  configure. Cause not found (changing the XML declaration doesn't help).
- Harmless ld warnings: the library is built for a newer macOS minor
  version than the objects (no `-mmacosx-version-min`).
