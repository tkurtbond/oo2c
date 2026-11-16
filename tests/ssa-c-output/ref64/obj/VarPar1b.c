#include <VarPar1b.d>
#include <__oo2c.h>
#include <setjmp.h>
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#pragma GCC diagnostic ignored "-Wunused-parameter"

static OOC_INT16 VarPar1b__F(OOC_INT16 *p) {
  register OOC_INT64 i0;

  VarPar1b__x = 1;
  *p = 2;
  i0 = VarPar1b__x;
  return (i0+2);
  ;
}

void VarPar1b__Test(void) {
  register OOC_INT64 i0;

  i0 = VarPar1b__F((void*)(OOC_INT64)&VarPar1b__a);
  Out0__Int(i0, 0);
  Out0__Ln();
  i0 = VarPar1b__F((void*)(OOC_INT64)&VarPar1b__x);
  Out0__Int(i0, 0);
  Out0__Ln();
  return;
  ;
}

void OOC_VarPar1b_init(void) {

  return;
  ;
}

void OOC_VarPar1b_destroy(void) {
}

/* --- */
