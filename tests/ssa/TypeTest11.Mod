MODULE TypeTest11;

TYPE
  R0 = RECORD      END;   P0 = POINTER TO R0;
  R1 = RECORD (R0) END;   P1 = POINTER TO R1;

PROCEDURE Test*;
  VAR
    p: P0;
    q: P1;
  BEGIN
    NEW (p); NEW (q);
    p(P1) := q;   (* the type guard fails, because p is a P0 *)
  END Test;

END TypeTest11.
