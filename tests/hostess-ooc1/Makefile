TEST_DRIVER=RunTests
TEST_DRIVER_FLAGS=--out-module Out
TEST_PROCESSOR=TestCompile
TEST_BASE=tests/hostess-ooc1

# HOSTESS: directory of the hostess test cases (the "hostess/hostess"
# directory of the hostess CVS module, holding testcases.dtd and oberon/).
# testsuite.xml refers to it through the symlink ./hostess.  Override with
#   make test-hostess-ooc1 HOSTESS=/path/to/hostess
HOSTESS=$(OOC_DEV_ROOT)/../hostess/hostess

include $(OOC_DEV_ROOT)/rsrc/OOC/Makefile.tests-framework

.PHONY: hostess-link
hostess-link:
	@if test ! -f "$(HOSTESS)/testcases.dtd"; then \
	  echo "error: no hostess test cases in $(HOSTESS); set HOSTESS=<dir>" >&2; \
	  exit 1; \
	fi
	ln -sfn "$(HOSTESS)" $(OOC_DEV_ROOT)/$(TEST_BASE)/hostess

test1-setup: hostess-link
