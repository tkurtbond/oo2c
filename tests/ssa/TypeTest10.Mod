MODULE TypeTest10;

IMPORT Out := Out0;

TYPE
  R0 = RECORD      x: INTEGER END;   P0 = POINTER TO R0;
  R1 = RECORD (R0) END;              P1 = POINTER TO R1;
  R2 = RECORD (R1) END;              P2 = POINTER TO R2;

VAR
  g: P0;

PROCEDURE New (x: INTEGER): P2;
  VAR
    p: P2;
  BEGIN
    NEW (p); p.x := x;
    RETURN p;
  END New;

PROCEDURE Test*;
  VAR
    p: P0;
  BEGIN
    (* type guard applied to the target of an assignment *)
    p := New (1);
    p(P1) := New (2);
    Out.Int (p.x, 0); Out.Ln;
    g := New (3);
    g(P1) := New (4);
    Out.Int (g.x, 0); Out.Ln;
    g(P1)(P2) := New (5);
    Out.Int (g.x, 0); Out.Ln;
  END Test;

END TypeTest10.
