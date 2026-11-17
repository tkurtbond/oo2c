dnl Autoconf requirements
AC_PREREQ([2.69])
AC_INIT([OOC],[2.2.4],[https://github.com/tkurtbond/oo2c/issues],[oo2c],[https://github.com/tkurtbond/oo2c])
AC_CONFIG_SRCDIR([src/OOC/Parser.Mod])
AC_CONFIG_HEADERS([lib/src/__config.h])

dnl information on the package
AC_SUBST(OOC_DEV_ROOT,[`cd "$srcdir" && pwd`])
AC_SUBST(COMPILER_VERSION,[$PACKAGE_VERSION])
AC_SUBST(COMPILER_MAJOR,[`echo $COMPILER_VERSION|sed -e 's:\..*$::'`])
AC_SUBST(COMPILER_MINOR,[`echo $COMPILER_VERSION|sed -e 's:^[[^.]]*\.::' -e 's:\..*$::'`])
AC_PROG_CC
dnl The generated C code reads and writes record fields, pointers, and
dnl variables through casted lvalues (e.g. a pointer field as `OOC_INT64'),
dnl which breaks C's aliasing rules.  Don't let gcc optimize based on them.
dnl CFLAGS is copied into oo2crc.xml, so this applies to every program
dnl that oo2c builds.
if test "$GCC" = yes; then
  case " $CFLAGS " in
    *" -fno-strict-aliasing "*) ;;
    *) CFLAGS="$CFLAGS -fno-strict-aliasing" ;;
  esac
fi
AC_SUBST(TARGET_OS)
AC_EGREP_CPP(yes,
[#ifdef WIN32
  yes
#endif], TARGET_OS="Win32", TARGET_OS="Unix")
AC_SUBST(OFLAGS)

dnl checks for programs
AC_PROG_INSTALL
AC_PATH_PROG(OOC,oo2c,[bin/oo2c --config oo2crc-install.xml])
AC_PATH_PROG(OOEF,ooef,[bin/ooef])
AC_PATH_PROG(DIFF,diff,diff)
AC_PATH_PROG(XSLTPROC,xsltproc,no)
AC_PATH_PROG(PERL,perl,/usr/bin/perl)

AC_ARG_ENABLE([libs],
  [AS_HELP_STRING([--disable-libs],
                  [don't build static/shared libraries with libtool])],
  [], [enable_libs=yes])
if test $enable_libs = yes; then
  AC_PATH_PROG(LIBTOOL,libtool,no)
else
  LIBTOOL="no";
  AC_MSG_CHECKING([for libtool])
  AC_MSG_RESULT([disabled])
fi

dnl optional packages
OOC_ARG_ENABLE_PTHREADS()

dnl checks for libraries
OOC_CHECK_LIB(dl,dlopen)
OOC_CHECK_LIB(gc,GC_malloc)
dnl With threads, gc must have its pthread wrappers (GC_pthread_create &
dnl co.).  FreeBSD ships them in a separate library, libgc-threaded
dnl (package boehm-gc-threaded), next to a libgc without them.
ooc_have_lib_gc_threaded=FALSE
if test $ooc_have_lib_pthread = TRUE && test $ooc_have_lib_gc = TRUE; then
  AC_CHECK_LIB(gc,GC_pthread_create,[:],
    [AC_CHECK_LIB(gc-threaded,GC_pthread_create,
       [ooc_have_lib_gc_threaded=TRUE
        LIBS=`echo " $LIBS " | sed 's/ -lgc / -lgc-threaded /'`],
       [AC_MSG_ERROR([--enable-threads=pthreads needs a gc built with thread support (GC_pthread_create), found neither in -lgc nor in -lgc-threaded])],
       [-lpthread])],
    [-lpthread])
fi
AC_SUBST(ooc_have_lib_gc_threaded)
OOC_CHECK_LIB(xnet,socket)
OOC_CHECK_LIB(rt,sem_init)
OOC_CHECK_LIB(posix4,sem_init)
if test $TARGET_OS = Win32; then
  ooc_have_lib_m=FALSE
  OOC_CHECK_LIB(mingwex,main)
  OOC_CHECK_LIB(wsock32,main)
else
  OOC_CHECK_LIB(m,sin)
  ooc_have_lib_mingwex=FALSE
  ooc_have_lib_wsock32=FALSE
fi

dnl checks for header files
AC_CHECK_HEADERS([sys/time.h unistd.h io.h pwd.h utime.h stdint.h inttypes.h gc/gc.h])

dnl checks for types
OOC_CHECK_INT64_T()
AC_CHECK_SIZEOF([void*])
AC_SUBST(ooc_target_address,[`expr $ac_cv_sizeof_voidp '*' 8`])
AC_SUBST(ooc_target_address_type,["longint"])
if test $ooc_target_address = 64; then
  ooc_target_address_type="hugeint"
fi
AC_CHECK_TYPES([ssize_t],,,[#include <unistd.h>])

dnl checks for structures
AC_CHECK_MEMBER(struct stat.st_mtime_usec,[AC_DEFINE(HAVE_STRUCT_STAT_USEC,1,[Define to 1 if struct stat has usec members.])],,[#include <sys/stat.h>])

dnl checks for compiler characteristics

dnl checks for library functions
dnl   ANSI functions:
AC_CHECK_FUNCS(atexit raise)
dnl   POSIX functions:
AC_CHECK_FUNCS(ftruncate)
dnl   BSD functions:
AC_CHECK_FUNCS(gettimeofday settimeofday mkstemp)
dnl   GNU extensions:
AC_CHECK_FUNCS(backtrace_symbols)
dnl   math functions:
AC_CHECK_FUNCS(lrint)

dnl checks for system services

AC_CONFIG_FILES([ENV Makefile.config rsrc/OOC/oo2crc.xml.mk lib/pkginfo.xml 
		 src/OOC/Config/Autoconf.Mod rsrc/OOC/TestFramework/config.xml
		 rsrc/OOC/oobacktrace])
AC_OUTPUT
