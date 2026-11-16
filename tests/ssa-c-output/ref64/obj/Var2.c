#include <Var2.d>
#include <__oo2c.h>
#include <setjmp.h>
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#pragma GCC diagnostic ignored "-Wunused-parameter"

static OOC_INT16 Var2__F(void) {

  Var2__x = 2;
  return 2;
  ;
}

void Var2__Test(void) {
  register OOC_INT64 i0;

  Var2__x = 0;
  i0 = Var2__F();
  Out0__Int(i0, 0);
  Out0__Ln();
  i0 = Var2__x;
  Out0__Int(i0, 0);
  Out0__Ln();
  return;
  ;
}

void OOC_Var2_init(void) {

  return;
  ;
}

void OOC_Var2_destroy(void) {
}

/* --- */
