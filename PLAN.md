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

Status (2026-11-16): the first five items are done, uncommitted. The
build recipe that checks them, from a clean tree (`$W/p3-build.sh`):

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

- [ ] **C back end / runtime headers**: make generated C clean under
      `-std=gnu17` and then default gcc settings: missing prototypes,
      pointer casts, `int` vs pointer, `const` correctness in
      `lib/src/__oo2c.h`, `__libc.h` (declares `floor`, `lrint`, `memcpy`
      by hand; prefer including `<math.h>`/`<string.h>`). Fixes go in
      `src/OOC/C/*.Mod` and `src/OOC/Make/TranslateToC.Mod`.
      Status: clean under gcc 16's defaults (`-std=gnu23`, no `-W`
      flags), so `-std=gnu17` is not needed. `-Wall`/`-Wextra` not
      checked yet.
- [ ] **Hand-written library C** (`lib/src/**/*.c`): [x] `readdir_r`
      replaced with `readdir` in `lib/src/OS/Files.c` (each `DIR*` is used
      by one thread only, so this is thread-safe; drop `readdir_r`
      from `AC_CHECK_FUNCS` in the autotools pass); [ ] fix warnings at
      `-Wall`.
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
