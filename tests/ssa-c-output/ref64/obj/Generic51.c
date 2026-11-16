#include <Generic51.d>
#include <__oo2c.h>
#include <setjmp.h>

Generic51__Table Generic51__DictionaryDesc_Resize(Generic51__Dictionary dict) {
  register OOC_INT64 i0,i1;

  i0 = (OOC_INT64)dict;
  i0 = i0+8;
  i1 = (OOC_INT64)*(OOC_INT64*)i0;
  *(OOC_INT64*)i0 = ((OOC_INT64)RT0__NewObject(_td_Generic51__Table.baseTypes[0], 123));
  return (Generic51__Table)i1;
  ;
}

void Generic51__Test(void) {
  register OOC_INT64 i0;

  i0 = (OOC_INT64)RT0__NewObject(_td__qtd1.baseTypes[0]);
  *(OOC_INT64*)(i0+8) = (OOC_INT64)0;
  i0 = (OOC_INT64)Generic51__DictionaryDesc_Resize((Generic51__Dictionary)i0);
  _assert((i0==(OOC_INT64)0), 127, 790);
  return;
  ;
}

void OOC_Generic51_init(void) {

  return;
  ;
}

void OOC_Generic51_destroy(void) {
}

/* --- */
