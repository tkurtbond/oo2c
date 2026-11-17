# NOTE: To use this makefile in a development setup, the environment
# variables OOC_DEV_ROOT and MAIN_MAKEFILE must be set.  This is
# easiest done by cd-ing to the top-level directory of the project and
# sourcing the file ENV there: `. ENV' (this assumes a Bourne
# compatible shell).
# 
# In an installation setup, simply run "./configure" and do "make
# install".  In this case, OOC_DEV_ROOT must not be set.

ifndef OOC_DEV_ROOT
export OOC_DEV_ROOT=$(shell pwd)
export MAIN_MAKEFILE=$(OOC_DEV_ROOT)/rsrc/OOC/Makefile.ooc-main
endif

include $(OOC_DEV_ROOT)/Makefile.config

# When build from a distribution tarball, then the bootstrap compiler is
# the one build from the C sources in the tarball.  To be able to run
# "make install" directly from the development environment, this variable
# must point to an existing compiler executable.
BOOTSTRAP_COMPILER?=stage0/oo2c

# Recipe lines that run oo2c start with $(VIA_SHELL) so that GNU make
# runs them through the shell.  A line without shell syntax is started
# with posix_spawn, and on NetBSD 11.0 that gives the program a wrong
# stack base, so the garbage collector crashes in GC_init (NetBSD PR
# kern/60653, fixed in 11.1; see PROBLEMS).
VIA_SHELL=exec

# TEST_SUBDIRS: List of subdirectories with testcases.
TEST_SUBDIRS=\
  $(addprefix tests/config/,sections cmdline environment simple) \
  tests/scanner \
  tests/parser \
  tests/symtab \
  tests/interface \
  tests/oberon-doc \
  tests/h2o \
  tests/ssa \
  tests/lib \
  tests/ssa-c-output \

#  tests/ssa-x86-output \

top_builddir=$(OOC_DEV_ROOT)

test_programs=TestScanner TestParser TestSymTab TestConfigSections TestConfigCmdLine TestConfigEnv TestConfigSimple TestInterfaceGen TestTexinfo TestCompile TestH2O TestWebServer TestCodec encdec AllModules RunTests

all: lib/obj/liboo2c.la bin/oo2c

.PHONY: clean distclean test test-valgrind test-asan main-clean oo2c install intall-strip

### `clean'
###      Delete all files from the current directory that are normally
###      created by building the program.  Don't delete the files that
###      record the configuration.  Also preserve files that could be made
###      by building, but normally aren't because the distribution comes
###      with them.
main-clean: test-cleanall
	for i in sym obj bin oocdoc; do rm -Rf ${top_builddir}/$$i; done
	for i in lib/sym lib/obj lib/bin lib/oocdoc; do rm -Rf ${top_builddir}/$$i; done
	rm -f src/XML oo2c
	for i in ${test_programs}; do rm -f $$i; done
	-${MAKE} -C stage0 -f Makefile.ext clean
	rm -Rf stage1 stage2 tests/lib-TestCompile tests/lib-oo2c gmon.out
	${MAKE} -C tests/hostess-ooc1 test-clean
	${MAKE} -C tests/benchmark clean
	${MAKE} -C rsrc/OOC/emacs clean

### `distclean'
###      Delete all files from the current directory that are created by
###      configuring or building the program.  If you have unpacked the
###      source and built the program without creating any other files,
###      `make distclean' should leave only the files that were in the
###      distribution.
distclean: main-clean
	rm -f ENV Makefile.config rsrc/OOC/oo2crc.xml rsrc/OOC/oo2crc.xml.mk oo2crc-install.xml lib/pkginfo.xml rsrc/OOC/TestFramework/config.xml rsrc/OOC/oobacktrace src/OOC/Config/Autoconf.Mod
	rm -f lib/src/__config.h config.log config.status config.status64
	rm -Rf autom4te.cache stage0/bin bin

### `cvs-clean'
###      Delete everything that should not appear in the CVS.
cvsclean: distclean
	rm -Rf stage0

FRC:


test-hostess-ooc1:
	${MAKE} -C tests/hostess-ooc1 test-runall

### `test-valgrind'
###      Run the programs of the test suites tests/ssa and tests/lib
###      under valgrind's memcheck (Linux).  A memcheck error makes a
###      test that should run successfully fail with exit status 97, and
###      the error report is in the test's wd/txt/*.run.err.  Tests of
###      type "error" exit with an error anyway, so for them memcheck
###      errors only show up in that file.  Needs valgrind.
VALGRIND=valgrind
VALGRIND_FLAGS=-q --error-exitcode=97 --suppressions=$(OOC_DEV_ROOT)/rsrc/OOC/TestFramework/valgrind-gc.supp
test-valgrind:
	${MAKE} -k test TEST_SUBDIRS="tests/ssa tests/lib" TEST_RUN_PREFIX="$(VALGRIND) $(VALGRIND_FLAGS)"

### `test-asan'
###      Run the test suites tests/ssa and tests/lib with the test
###      programs, and the library modules that they use, compiled with
###      gcc's AddressSanitizer and UndefinedBehaviorSanitizer.  The
###      compiler itself is not instrumented.  An error report from a
###      sanitizer ends the program with an error, so a test that should
###      run successfully fails; the report is in the test's
###      wd/txt/*.run.err.  Needs libasan and libubsan.  Use-after-scope
###      checking is off: it reports false errors in code with nested
###      procedures (see PLAN.md).  Leak checking is off, because the
###      memory belongs to the garbage collector.
SANITIZE_CFLAGS=-fsanitize=address,undefined -fno-sanitize=vptr -fno-sanitize-recover=all -fno-sanitize-address-use-after-scope -fno-omit-frame-pointer
SANITIZE_LDFLAGS=-fsanitize=address,undefined
TEST_ASAN_OPTIONS=detect_leaks=0:detect_stack_use_after_return=0
test-asan:
	ASAN_OPTIONS=$(TEST_ASAN_OPTIONS) UBSAN_OPTIONS=print_stacktrace=1 \
	${MAKE} -k test TEST_SUBDIRS="tests/ssa tests/lib" TEST_PROCESSOR_FLAGS="--cflags '$(CFLAGS) $(SANITIZE_CFLAGS)' --ldflags '$(LDFLAGS) $(SANITIZE_LDFLAGS)'"



### Create header file that is used as input for GNU autoconf.
lib/src/__config.h.in: configure.ac aclocal.m4
	autoheader

### Create configure script using GNU autoconf.
configure: configure.ac aclocal.m4 lib/src/__config.h.in
	autoconf

### Some variables are defined recursively by configure.  Expanding these
### variables is best done by the make utility itself.  This rule puts the
### expanded values into the OOC configuration file oo2crc.xml.
$(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml: $(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml.mk $(OOC_DEV_ROOT)/Makefile.config
	sed -e 's?%libdir%?$(libdir)?g' \
	    -e 's?%oocdir%?$(oocdir)?g' \
	    -e 's?%bindir%?$(bindir)?g' \
	    -e 's?%INSTALL%?$(INSTALL)?g' \
	    -e 's?%INSTALL_PROGRAM%?$(INSTALL_PROGRAM)?g' \
	    -e 's?%INSTALL_DATA%?$(INSTALL_DATA)?g' \
		$(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml.mk >$(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml
rsrc/OOC/oo2crc.xml: $(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml

### This configuration file is used to build and install the compiler and
### library from scratch.  It must not refer to any stale data that may
### be present on the target system.
$(OOC_DEV_ROOT)/oo2crc-install.xml: $(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml
	sed -e 's:<file-system>:<!--:g' \
		-e 's:</file-system>:-->:g' \
		-e 's:<repositories>:<repositories><file-system>$(OOC_DEV_ROOT)/lib</file-system><file-system>$(OOC_DEV_ROOT)</file-system>:' \
		 $(OOC_DEV_ROOT)/rsrc/OOC/oo2crc.xml >$(OOC_DEV_ROOT)/oo2crc-install.xml

config.status: configure
	@echo Error: Stale config.status.  Please run ./configure and try again.
	@/bin/false

dist: $(OOC_DEV_ROOT)/oo2crc-install.xml configure config.status
	-$(MKDIR) $(OOC_DEV_ROOT)/sym $(OOC_DEV_ROOT)/obj $(OOC_DEV_ROOT)/bin 2>/dev/null
	$(VIA_SHELL) $(OOC) --config $(OOC_DEV_ROOT)/oo2crc-install.xml -v --make $(OFLAGS) oo2c
	rm -Rf stage0
	mkdir stage0 stage0/lib
	ln -s ../src stage0/src
	ln -s ../../lib/src stage0/lib/src
	$(VIA_SHELL) bin/oo2c --config oo2crc-install.xml -v --make -r stage0/lib -r stage0 --cc "" $(OFLAGS) stage0/src/oo2c.Mod
	rm -Rf stage0/sym/* stage0/lib/sym/*
	cd stage0 && $(PERL) $(OOC_DEV_ROOT)/rsrc/OOC/makefilegen.pl >Makefile.ext
	${MAKE} distclean
	tar -c -j -f ../$(DISTDIR).tar.bz2 --exclude-vcs \
	  --exclude '*~' --exclude '.#*' --transform 's,^,$(DISTDIR)/,S' *

dist64:
	sed -e '/^s,@ooc_target_integer@,/ s:32:64:' \
	    -e '/^s,@ooc_target_address@,/ s:32:64:' \
	    -e '/^s,@ooc_target_address_type@,/ s:longint:hugeint:' \
		config.status >config.status64
	/bin/sh config.status64
	${MAKE} dist DISTDIR=oo2c_64-$(PACKAGE_VERSION)

### Create initial compiler executable from distributed C sources.
stage0/oo2c:
	${MAKE} -C stage0 -f Makefile.ext setup-src oo2c

### Build library from core modules using the initial compiler executable.
lib/obj/liboo2c.la: $(BOOTSTRAP_COMPILER) $(OOC_DEV_ROOT)/oo2crc-install.xml
	$(VIA_SHELL) $(BOOTSTRAP_COMPILER) --config oo2crc-install.xml -v -r lib -r . $(OFLAGS) --build-package liboo2c

### Build second compiler using the initial compiler executable and the
### library lib/obj/liboo2c.la.
bin/oo2c: $(BOOTSTRAP_COMPILER) $(OOC_DEV_ROOT)/oo2crc-install.xml lib/obj/liboo2c.la
	$(VIA_SHELL) $(BOOTSTRAP_COMPILER) --config oo2crc-install.xml -v -r lib -r . $(OFLAGS) --build-package oo2c

### Remove manual pages.
uninstall-man:
	for i in oo2c oob ooef oowhereis; do \
	  rm -f "$(mandir)/$$i$(manext)" "$(mandir)/$$i$(manext).gz"; \
	done

### Install manual pages.
install-man: uninstall-man
	$(INSTALL) -d "$(mandir)"
	for i in oo2c oob ooef oowhereis; do \
	  $(INSTALL_DATA) "man/$$i.1" "$(mandir)/$$i$(manext)"; \
	done

### Install binaries and support files.  To place the files into a directory
### different from the targets supplied during configuration, override the
### parameter `prefix'.
install: lib/obj/liboo2c.la bin/oo2c install-man
	$(INSTALL) -d "$(oocdir)/pkginfo"
	$(VIA_SHELL) $(BOOTSTRAP_COMPILER) --config oo2crc-install.xml -v --bindir "$(bindir)" --libdir "$(libdir)" --oocdir "$(oocdir)" -r lib -r . --install-program "$(INSTALL_PROGRAM)" $(OFLAGS) --install-package liboo2c
	$(VIA_SHELL) $(BOOTSTRAP_COMPILER) --config oo2crc-install.xml -v --bindir "$(bindir)" --libdir "$(libdir)" --oocdir "$(oocdir)" -r lib -r . --install-program "$(INSTALL_PROGRAM)" $(OFLAGS) --install-package oo2c
	$(INSTALL_SCRIPT) rsrc/OOC/oobacktrace "$(bindir)/oobacktrace"
	chmod a+x "$(oocdir)/install-sh"

install-strip:
	${MAKE} INSTALL_PROGRAM='$(INSTALL_PROGRAM) -s' install

uninstall: uninstall-man FRC
	$(VIA_SHELL) $(BOOTSTRAP_COMPILER) --config oo2crc-install.xml -v $(OFLAGS) --uninstall-package oo2c liboo2c
	rm -f "$(bindir)/oobacktrace" "$(oocdir)/pkginfo.xml"

ifdef MAIN_MAKEFILE
include $(MAIN_MAKEFILE)
endif
