/*	$Id$	*/
/*  Wrappers for C library functions declared in module libc.
    Copyright (C) 2026  T. Kurt Bond

    This module is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public License
    as published by the Free Software Foundation; either version 2 of
    the License, or (at your option) any later version.

    This module is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with OOC. If not, write to the Free Software Foundation,
    59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
#include <stdarg.h>
#include <stdio.h>
#include <libc.d>

/* Oberon's CHAR is unsigned char, so the prototypes generated for the
   Oberon declarations cannot match the ones of sscanf and sprintf.  These
   wrappers take the Oberon signatures and forward to vsscanf/vsprintf.  */

/* the C type of SYSTEM.ADDRESS, as chosen by configure */
#if SIZEOF_VOIDP == 8
typedef OOC_INT64 libc_address;
#else
typedef OOC_INT32 libc_address;
#endif

OOC_INT32 oo2c_libc_sscanf(libc_address s, const OOC_CHAR8 _template[], ...) {
  va_list ap;
  int res;

  va_start(ap, _template);
  res = vsscanf((const char*)s, (const char*)_template, ap);
  va_end(ap);
  return res;
}

void oo2c_libc_sprintf(OOC_CHAR8 s[], const OOC_CHAR8 _template[], ...) {
  va_list ap;

  va_start(ap, _template);
  vsprintf((char*)s, (const char*)_template, ap);
  va_end(ap);
}

void OOC_libc_init(void) {
}

void OOC_libc_destroy(void) {
}
