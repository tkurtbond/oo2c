MODULE Array13;

IMPORT SYSTEM, Out := Out0;

TYPE
  Matrix = POINTER TO ARRAY OF ARRAY OF INTEGER;

PROCEDURE Size (x: ARRAY OF SYSTEM.BYTE);
  BEGIN
    Out.Int (LEN(x), 0); Out.Ln;
  END Size;

PROCEDURE SizeVar (VAR x: ARRAY OF SYSTEM.BYTE);
  BEGIN
    Out.Int (LEN(x), 0); Out.Ln;
  END SizeVar;

PROCEDURE Sum (x: ARRAY OF SYSTEM.BYTE): LONGINT;
  VAR
    i, s: LONGINT;
  BEGIN
    s := 0;
    FOR i := 0 TO LEN(x)-1 DO
      INC (s, ORD(SYSTEM.VAL(CHAR, x[i])));
    END;
    RETURN s;
  END Sum;

PROCEDURE Open1 (b: ARRAY OF CHAR);
  BEGIN
    Size (b); SizeVar (b);
    Out.Int (Sum (b), 0); Out.Ln;
  END Open1;

PROCEDURE Open2 (VAR m: ARRAY OF ARRAY OF INTEGER);
  BEGIN
    Size (m); SizeVar (m);
  END Open2;

PROCEDURE Test* ();
  VAR
    a: ARRAY 16 OF CHAR;
    m: ARRAY 3, 5 OF INTEGER;
    p: Matrix;
    i: LONGINT;
  BEGIN
    FOR i := 0 TO LEN(a)-1 DO a[i] := CHR(i) END;
    Open1 (a);
    Open2 (m);
    NEW (p, 4, 7);
    Size (p^);
    Open2 (p^);
  END Test;

END Array13.
