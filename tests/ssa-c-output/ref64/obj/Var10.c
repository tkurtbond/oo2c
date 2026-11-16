#include <Var10.d>
#include <__oo2c.h>
#include <setjmp.h>
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#pragma GCC diagnostic ignored "-Wunused-parameter"

static OOC_INT16 Var10__F(OOC_CHAR8 b) {
  register OOC_INT64 i0;

  i0 = b;
l1_loop:
  if (!i0) goto l1_loop;
l5:
  return 1;
  ;
}

void Var10__Test(void) {
  register OOC_INT64 i0;

  i0 = Var10__F(1u);
  Out0__Int(i0, 0);
  Out0__Ln();
  return;
  ;
}

void OOC_Var10_init(void) {

  return;
  ;
}

void OOC_Var10_destroy(void) {
}

/* --- */
