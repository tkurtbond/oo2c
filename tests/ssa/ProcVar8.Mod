MODULE ProcVar8;

TYPE
  P = PROCEDURE(x: INTEGER);

VAR
  p: P;

PROCEDURE Outer*();
  VAR
    sum: INTEGER;

  PROCEDURE Add(x: INTEGER);
    BEGIN
      INC(sum, x);
    END Add;

  BEGIN
    p := Add;
  END Outer;

END ProcVar8.
