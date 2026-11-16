#include <PRE2.d>
#include <__oo2c.h>
#include <setjmp.h>
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#pragma GCC diagnostic ignored "-Wunused-parameter"

static OOC_INT16 PRE2__P(OOC_INT16 i, OOC_INT16 a[], OOC_LEN a_0d) {
  register OOC_INT64 i0,i1;

  i0 = i;
  i1 = i0<0;
  if (i1) goto l3;
  i1 = (OOC_INT64)a+i0*2;
  *(OOC_INT16*)i1 = i0;
  i0=i1;
  goto l4;
l3:
  i0 = -i0;
  i1 = (OOC_INT64)a+i0*2;
  *(OOC_INT16*)i1 = (-i0);
  i0=i1;
l4:
  i0 = *(OOC_INT16*)i0;
  return i0;
  ;
}

void OOC_PRE2_init(void) {

  return;
  ;
}

void OOC_PRE2_destroy(void) {
}

/* --- */
