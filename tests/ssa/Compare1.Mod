MODULE Compare1;

IMPORT SYSTEM, Out := Out0;

TYPE
  R = RECORD a: LONGINT END;
  P = POINTER TO R;

PROCEDURE Int (x: LONGINT);
  BEGIN
    Out.Bool (x = x); Out.Bool (x # x);
    Out.Bool (x < x); Out.Bool (x <= x);
    Out.Bool (x > x); Out.Bool (x >= x);
    Out.Ln;
  END Int;

PROCEDURE Real (x: REAL);
  BEGIN
    Out.Bool (x = x); Out.Bool (x # x);
    Out.Bool (x < x); Out.Bool (x <= x);
    Out.Bool (x > x); Out.Bool (x >= x);
    Out.Ln;
  END Real;

PROCEDURE LongReal (x: LONGREAL);
  BEGIN
    Out.Bool (x = x); Out.Bool (x # x);
    Out.Bool (x < x); Out.Bool (x <= x);
    Out.Bool (x > x); Out.Bool (x >= x);
    Out.Ln;
  END LongReal;

PROCEDURE Guard (): LONGINT;
  VAR
    p: P;
  BEGIN
    NEW (p);
    p(P).a := 42;
    RETURN p^(R).a;
  END Guard;

PROCEDURE Test* ();
  VAR
    h: HUGEINT;
  BEGIN
    Int (3);
    Real (1.5);
    Real (SYSTEM.VAL (REAL, 7FC00000H));  (* NaN *)
    h := 7FF80000H;
    h := h * 100000000H;
    LongReal (SYSTEM.VAL (LONGREAL, h));  (* NaN *)
    Out.Int (Guard(), 0); Out.Ln;
  END Test;

END Compare1.
