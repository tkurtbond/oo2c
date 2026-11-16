MODULE ProcVar9;

TYPE
  P = PROCEDURE(x: INTEGER);

PROCEDURE Iterate(a: ARRAY OF INTEGER; p: P);
  VAR
    i: LONGINT;
  BEGIN
    FOR i := 0 TO LEN(a)-1 DO
      p(a[i]);
    END;
  END Iterate;

PROCEDURE Sum*(a: ARRAY OF INTEGER): INTEGER;
  VAR
    sum: INTEGER;

  PROCEDURE Add(x: INTEGER);
    BEGIN
      INC(sum, x);
    END Add;

  BEGIN
    sum := 0;
    Iterate(a, Add);
    RETURN sum;
  END Sum;

END ProcVar9.
