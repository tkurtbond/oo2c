MODULE CString1;

IMPORT Out := Out0;
TYPE
  CString = POINTER [CSTRING] TO ARRAY OF CHAR;

PROCEDURE OutString(str : CString);
(* [CSTRING] implies NO_LENGTH_INFO, so str^ has no length: write the
   characters up to the terminating 0X.  *)
VAR
  i : LONGINT;
BEGIN
  i := 0;
  WHILE (str[i] # 0X) DO
    Out.Char(str[i]); INC(i);
  END;
  Out.Ln;
END OutString;

PROCEDURE Test*;
VAR
  a : POINTER TO ARRAY OF CHAR;
  b : ARRAY 32 OF CHAR;
BEGIN
  OutString("String Constant");
  OutString('X');
  NEW(a, 32);
  COPY("Open Array", a^);
  OutString(a^);
  COPY("Fixed Array", b);
  OutString(b);
END Test;

END CString1.
