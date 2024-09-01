```k
requires "foundry.md"

module OPTIMISM-SUPERCHAIN-LEMMAS
    imports BOOL
    imports FOUNDRY
    imports INT-SYMBOLIC

    // Convert booleans to their word equivalents
    rule bool2Word(true) => 1
    rule bool2Word(false) => 0

    // Associativity and Commutativity Rules:
    rule A +Int (B +Int C) => (A +Int B) +Int C
    rule A *Int B => B *Int A

    // Comparison Normalization:
    rule A +Int B <Int C => A <Int C -Int B
    rule A -Int B <Int C => A <Int C +Int B

    rule A +Int B <Int A => false requires 0 <=Int B
    rule A <Int A -Int B => false requires 0 <=Int B

    rule A -Int A => 0
    rule 0 +Int A => A
    rule A +Int 0 => A
    rule A -Int 0 => A

    rule chop(I) => I requires #rangeUInt(256, I)
    rule chop (chop (X:Int) +Int Y:Int) => chop (X +Int Y)
    rule chop (X:Int +Int chop (Y:Int)) => chop (X +Int Y)
endmodule
```
