MODULE CString2;

IMPORT Out := Out0;
TYPE
  CString = POINTER [CSTRING] TO ARRAY OF CHAR;

PROCEDURE OutString(str : CString);
BEGIN
  Out.String(str^);
END OutString;

END CString2.
