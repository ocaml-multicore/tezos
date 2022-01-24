Michelson: the language of Smart Contracts in Tezos
===================================================

This specification gives a detailed formal semantics of the Michelson
language and a short explanation of how smart contracts are executed
and interact in the blockchain.

The language is stack-based, with high level data types and primitives,
and strict static type checking. Its design cherry picks traits from
several language families. Vigilant readers will notice direct
references to Forth, Scheme, ML and Cat.

A Michelson program is a series of instructions that are run in
sequence: each instruction receives as input the stack resulting from the
previous instruction, and rewrites it for the next one. The stack
contains both immediate values and heap allocated structures. All values
are immutable and garbage collected.

The types of the input and output stack are fixed and monomorphic,
and the program is typechecked before being introduced into the system.
No smart contract execution can fail because an instruction has been
executed on a stack of unexpected length or contents.

This specification gives the complete instruction set, type system and
semantics of the language. It is meant as a precise reference manual,
not an easy introduction. Even though, some examples are provided at
the end of the document and can be read first or at the same time as
the specification. The document also starts with a less formal
explanation of the context: how Michelson code interacts with the
blockchain.

Semantics of smart contracts and transactions
---------------------------------------------

The Tezos ledger currently has two types of accounts that can hold
tokens (and be the destinations of transactions).

  - An implicit account is a non programmable account, whose tokens
    are spendable and delegatable by a public key. Its address is
    directly the public key hash, and starts with ``tz1``, ``tz2`` or
    ``tz3``.
  - A smart contract is a programmable account. A transaction to such
    an address can provide data, and can fail for reasons decided by
    its Michelson code. Its address is a unique hash that depends on
    the operation that led to its creation, and starts with ``KT1``.

From Michelson, they are indistinguishable. A safe way to think about
this is to consider that implicit accounts are smart contracts that
always succeed to receive tokens, and does nothing else.

Intra-transaction semantics
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Alongside their tokens, smart contracts keep a piece of storage. Both
are ruled by a specific logic specified by a Michelson program. A
transaction to a smart contract will provide an input value and in
option some tokens, and in return, the smart contract can modify its
storage and transfer its tokens.

The Michelson program receives as input a stack containing a single
pair whose first element is an input value and second element the
content of the storage space. It must return a stack containing a
single pair whose first element is the list of internal operations
that it wants to emit, and second element is the new contents of the
storage space. Alternatively, a Michelson program can fail, explicitly
using a specific opcode, or because something went wrong that could
not be caught by the type system (e.g. gas exhaustion).

A bit of polymorphism can be used at contract level, with a
lightweight system of named entrypoints: instead of an input value,
the contract can be called with an entrypoint name and an argument,
and these two components are transformed automatically in a simple and
deterministic way to an input value. This feature is available both
for users and from Michelson code. See the dedicated section.

Inter-transaction semantics
~~~~~~~~~~~~~~~~~~~~~~~~~~~

An operation included in the blockchain is a sequence of "external
operations" signed as a whole by a source address. These operations
are of three kinds:

  - Transactions to transfer tokens to implicit accounts or tokens and
    parameters to a smart contract (or, optionally, to a specified
    entrypoint of a smart contract).
  - Originations to create new smart contracts from its Michelson
    source code, an initial amount of tokens transferred from the
    source, and an initial storage contents.
  - Delegations to assign the tokens of the source to the stake of
    another implicit account (without transferring any tokens).

Smart contracts can also emit "internal operations". These are run
in sequence after the external transaction completes, as in the
following schema for a sequence of two external operations.

::

    +------+----------------+-------+----------------+
    | op 1 | internal ops 1 |  op 2 | internal ops 2 |
    +------+----------------+-------+----------------+

Smart contracts called by internal transactions can in turn also emit
internal operation. The interpretation of the internal operations
of a given external operation uses a stack, as in the following
example, also with two external operations.

::

   +-----------+---------------+--------------------------+
   | executing | emissions     | resulting stack          |
   +-----------+---------------+--------------------------+
   | op 1      | 1a, 1b, 1c    | 1a, 1b, 1c               |
   | op 1a     | 1ai, 1aj      | 1ai, 1aj, 1b, 1c         |
   | op 1ai    |               | 1aj, 1b, 1c              |
   | op 1aj    |               | 1b, 1c                   |
   | op 1b     | 1bi           | 1bi, 1c                  |
   | op 1bi    |               | 1c                       |
   | op 1c     |               |                          |
   | op 2      | 2a, 2b        | 2a, 2b                   |
   | op 2a     | 2ai           | 2ai, 2b                  |
   | op 2ai    | 2ai1          | 2ai1, 2b                 |
   | op 2ai1   |               | 2b                       |
   | op 2b     | 2bi           | 2bi                      |
   | op 2bi    | 2bi1          | 2bi1                     |
   | op 2bi1   | 2bi2          | 2bi2                     |
   | op 2bi2   |               |                          |
   +-----------+---------------+--------------------------+

Failures
~~~~~~~~

All transactions can fail for a few reasons, mostly:

  - Not enough tokens in the source to spend the specified amount.
  - The script took too many execution steps.
  - The script failed programmatically using the ``FAILWITH`` instruction.

External transactions can also fail for these additional reasons:

  - The signature of the external operations was wrong.
  - The code or initial storage in an origination did not typecheck.
  - The parameter in a transfer did not typecheck.
  - The destination did not exist.
  - The specified entrypoint did not exist.

All these errors cannot happen in internal transactions, as the type
system catches them at operation creation time. In particular,
Michelson has two types to talk about other accounts: ``address`` and
``contract t``. The ``address`` type merely gives the guarantee that
the value has the form of a Tezos address. The ``contract t`` type, on
the other hand, guarantees that the value is indeed a valid, existing
account whose parameter type is ``t``. To make a transaction from
Michelson, a value of type ``contract t`` must be provided, and the
type system checks that the argument to the transaction is indeed of
type ``t``. Hence, all transactions made from Michelson are well
formed by construction.

In any case, when a failure happens, either total success or total
failure is guaranteed. If a transaction (internal or external) fails,
then the whole sequence fails and all the effects up to the failure
are reverted. These transactions can still be included in blocks, and
the transaction fees are given to the implicit account who baked the
block.

Language semantics
------------------

This specification explains in a symbolic way the computation performed by the
Michelson interpreter on a given program and initial stack to produce
the corresponding resulting stack. The Michelson interpreter is a pure
function: it only builds a result stack from the elements of an initial
one, without affecting its environment. This semantics is then naturally
given in what is called a big step form: a symbolic definition of a
recursive reference interpreter. This definition takes the form of a
list of rules that cover all the possible inputs of the interpreter
(program and stack), and describe the computation of the corresponding
resulting stacks.

Rules form and selection
~~~~~~~~~~~~~~~~~~~~~~~~

The rules have the main following form.

::

    > (syntax pattern) / (initial stack pattern)  =>  (result stack pattern)
        iff (conditions)
        where (recursions)
        and (more recursions)

The left hand side of the ``=>`` sign is used for selecting the rule.
Given a program and an initial stack, one (and only one) rule can be
selected using the following process. First, the toplevel structure of
the program must match the syntax pattern. This is quite simple since
there are only a few non-trivial patterns to deal with instruction
sequences, and the rest is made of trivial patterns that match one
specific instruction. Then, the initial stack must match the initial
stack pattern. Finally, some rules add extra conditions over the values
in the stack that follow the ``iff`` keyword. Sometimes, several rules
may apply in a given context. In this case, the one that appears first
in this specification is to be selected. If no rule applies, the result
is equivalent to the one for the explicit ``FAILWITH`` instruction. This
case does not happen on well-typed programs, as explained in the next
section.

The right hand side describes the result of the interpreter if the rule
applies. It consists in a stack pattern, whose parts are either
constants, or elements of the context (program and initial stack) that
have been named on the left hand side of the ``=>`` sign.

Recursive rules (big step form)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Sometimes, the result of interpreting a program is derived from the
result of interpreting another one (as in conditionals or function
calls). In these cases, the rule contains a clause of the following
form.

::

    where (intermediate program) / (intermediate stack)  =>  (partial result)

This means that this rule applies in case interpreting the intermediate
state on the left gives the pattern on the right.

The left hand sign of the ``=>`` sign is constructed from elements of
the initial state or other partial results, and the right hand side
identify parts that can be used to build the result stack of the rule.

If the partial result pattern does not actually match the result of the
interpretation, then the result of the whole rule is equivalent to the
one for the explicit ``FAILWITH`` instruction. Again, this case does not
happen on well-typed programs, as explained in the next section.

Format of patterns
~~~~~~~~~~~~~~~~~~

Code patterns are of one of the following syntactical forms.

-  ``INSTR`` (an uppercase identifier) is a simple instruction (e.g.
   ``DROP``).
-  ``INSTR (arg) ...`` is a compound instruction, whose arguments can be
   code, data or type patterns (e.g. ``PUSH nat 3``).
-  ``{ (instr) ; ... }`` is a possibly empty sequence of instructions,
   (e.g. ``IF { SWAP ; DROP } { DROP }``), nested sequences can drop the
   braces.
-  ``name`` is a pattern that matches any program and names a part of
   the matched program that can be used to build the result.
-  ``_`` is a pattern that matches any instruction.

Stack patterns are of one of the following syntactical forms.

-  ``[FAILED]`` is the special failed state.
-  ``[]`` is the empty stack.
-  ``(top) : (rest)`` is a stack whose top element is matched by the
   data pattern ``(top)`` on the left, and whose remaining elements are
   matched by the stack pattern ``(rest)`` on the right (e.g.
   ``x : y : rest``).
-  ``name`` is a pattern that matches any stack and names it in order to
   use it to build the result.
-  ``_`` is a pattern that matches any stack.

Data patterns are of one of the following syntactical forms.

-  integer/natural number literals, (e.g. ``3``).
-  string literals, (e.g. ``"contents"``).
-  raw byte sequence literals (e.g. ``0xABCDEF42``).
-  ``Tag`` (capitalized) is a symbolic constant, (e.g. ``Unit``,
   ``True``, ``False``).
-  ``(Tag (arg) ...)`` tagged constructed data, (e.g. ``(Pair 3 4)``).
-  a code pattern for first class code values.
-  ``name`` to name a value in order to use it to build the result.
-  ``_`` to match any value.

The domain of instruction names, symbolic constants and data
constructors is fixed by this specification. Michelson does not let the
programmer introduce its own types.

Be aware that the syntax used in the specification may differ from
the :ref:`concrete syntax <ConcreteSyntax_012>`. In particular
some instructions are annotated with types that are not present in the
concrete language because they are synthesized by the typechecker.

Shortcuts
~~~~~~~~~

Sometimes, it is easier to think (and shorter to write) in terms of
program rewriting than in terms of big step semantics. When it is the
case, and when both are equivalents, we write rules of the form:

::

    p / S  =>  S''
    where   p' / S'  =>  S''

using the following shortcut:

::

    p / S  =>  p' / S'

The concrete language also has some syntax sugar to group some common
sequences of operations as one. This is described in this specification
using a simple regular expression style recursive instruction rewriting.

.. _michelson_type_system_012:

Introduction to the type system and notations
---------------------------------------------

This specification describes a type system for Michelson. To make things
clear, in particular to readers that are not accustomed to reading
formal programming language specifications, it does not give a
typechecking or inference algorithm. It only gives an intentional
definition of what we consider to be well-typed programs. For each
syntactical form, it describes the stacks that are considered well-typed
inputs, and the resulting outputs.

The type system is sound, meaning that if a program can be given a type,
then if run on a well-typed input stack, the interpreter will never
apply an interpretation rule on a stack of unexpected length or
contents. Also, it will never reach a state where it cannot select an
appropriate rule to continue the execution. Well-typed programs do not
block, and do not go wrong.

Type notations
~~~~~~~~~~~~~~

The specification introduces notations for the types of values, terms
and stacks. Apart from a subset of value types that appear in the form
of type annotations in some places throughout the language, it is
important to understand that this type language only exists in the
specification.

A stack type can be written:

-  ``[]`` for the empty stack.
-  ``(top) : (rest)`` for the stack whose first value has type ``(top)``
   and queue has stack type ``(rest)``.

Instructions, programs and primitives of the language are also typed,
their types are written:

::

    (type of stack before) -> (type of stack after)

The types of values in the stack are written:

-  ``identifier`` for a primitive data-type (e.g. ``bool``).
-  ``identifier (arg)`` for a parametric data-type with one parameter
   type ``(arg)`` (e.g. ``list nat``).
-  ``identifier (arg) ...`` for a parametric data-type with several
   parameters (e.g. ``map string int``).
-  ``[ (type of stack before) -> (type of stack after) ]`` for a code
   quotation, (e.g. ``[ int : int : [] -> int : [] ]``).
-  ``lambda (arg) (ret)`` is a shortcut for
   ``[ (arg) : [] -> (ret) : [] ]``.

Meta type variables
~~~~~~~~~~~~~~~~~~~

The typing rules introduce meta type variables. To be clear, this has
nothing to do with polymorphism, which Michelson does not have. These
variables only live at the specification level, and are used to express
the consistency between the parts of the program. For instance, the
typing rule for the ``IF`` construct introduces meta variables to
express that both branches must have the same type.

Here are the notations for meta type variables:

-  ``'a`` for a type variable.
-  ``'A`` for a stack type variable.
-  ``_`` for an anonymous type or stack type variable.

Typing rules
~~~~~~~~~~~~

The system is syntax directed, meaning that it defines a single
typing rule for each syntax construct. A typing rule restricts the type
of input stacks that are authorized for this syntax construct, links the
output type to the input type, and links both of them to the
subexpressions when needed, using meta type variables.

Typing rules are of the form:

::

    (syntax pattern)
    :: (type of stack before) -> (type of stack after) [rule-name]
       iff (premises)

Where premises are typing requirements over subprograms or values in the
stack, both of the form ``(x) :: (type)``, meaning that value ``(x)``
must have type ``(type)``.

A program is shown well-typed if one can find an instance of a rule that
applies to the toplevel program expression, with all meta type variables
replaced by non variable type expressions, and of which all type
requirements in the premises can be proven well-typed in the same
manner. For the reader unfamiliar with formal type systems, this is
called building a typing derivation.

Here is an example typing derivation on a small program that computes
``(x+5)*10`` for a given input ``x``, obtained by instantiating the
typing rules for instructions ``PUSH``, ``ADD`` and for the sequence, as
found in the next sections. When instantiating, we replace the ``iff``
with ``by``.

::

    { PUSH nat 5 ; ADD ; PUSH nat 10 ; MUL }
    :: [ nat : [] -> nat : [] ]
       by { PUSH nat 5 ; ADD }
          :: [ nat : [] -> nat : [] ]
             by PUSH nat 5
                :: [ nat : [] -> nat : nat : [] ]
                   by 5 :: nat
            and ADD
                :: [ nat : nat : [] -> nat : [] ]
      and { PUSH nat 10 ; MUL }
          :: [ nat : [] -> nat : [] ]
             by PUSH nat 10
                :: [ nat : [] -> nat : nat : [] ]
                   by 10 :: nat
            and MUL
                :: [ nat : nat : [] -> nat : [] ]

Producing such a typing derivation can be done in a number of manners,
such as unification or abstract interpretation. In the implementation of
Michelson, this is done by performing a recursive symbolic evaluation of
the program on an abstract stack representing the input type provided by
the programmer, and checking that the resulting symbolic stack is
consistent with the expected result, also provided by the programmer.

Side note
~~~~~~~~~

As with most type systems, it is incomplete. There are programs that
cannot be given a type in this type system, yet that would not go wrong
if executed. This is a necessary compromise to make the type system
usable. Also, it is important to remember that the implementation of
Michelson does not accept as many programs as the type system describes
as well-typed. This is because the implementation uses a simple single
pass typechecking algorithm, and does not handle any form of
polymorphism.

Core data types and notations
-----------------------------

-  ``string``, ``nat``, ``int`` and ``bytes``: The core primitive
   constant types.

-  ``bool``: The type for booleans whose values are ``True`` and
   ``False``.

-  ``unit``: The type whose only value is ``Unit``, to use as a
   placeholder when some result or parameter is not necessary. For
   instance, when the only goal of a contract is to update its storage.

-  ``never``: The empty type. Since ``never`` has no inhabitant, no value of
   this type is allowed to occur in a well-typed program.

-  ``list (t)``: A single, immutable, homogeneous linked list, whose
   elements are of type ``(t)``, and that we write ``{}`` for the empty
   list or ``{ first ; ... }``. In the semantics, we use chevrons to
   denote a subsequence of elements. For instance: ``{ head ; <tail> }``.

-  ``pair (l) (r)``: A pair of values ``a`` and ``b`` of types ``(l)``
   and ``(r)``, that we write ``(Pair a b)``.

-  ``pair (t{1}) ... (t{n})`` with ``n > 2``: A shorthand for ``pair (t{1}) (pair (t{2}) ... (pair (t{n-1}) (t{n})) ...)``.

-  ``option (t)``: Optional value of type ``(t)`` that we write ``None``
   or ``(Some v)``.

-  ``or (l) (r)``: A union of two types: a value holding either a value
   ``a`` of type ``(l)`` or a value ``b`` of type ``(r)``, that we write
   ``(Left a)`` or ``(Right b)``.

-  ``set (t)``: Immutable sets of values of type ``(t)`` that we write as
   lists ``{ item ; ... }``, of course with their elements unique, and
   sorted.

-  ``map (k) (t)``: Immutable maps from keys of type ``(k)`` of values
   of type ``(t)`` that we write ``{ Elt key value ; ... }``, with keys
   sorted.

-  ``big_map (k) (t)``: Lazily deserialized maps from keys of type
   ``(k)`` of values of type ``(t)``.
   These maps should be used if you intend to store large amounts of data in a map.
   Using ``big_map`` can reduce gas costs significantly compared to standard maps, as data is lazily deserialized.
   Note however that individual operations on ``big_map`` have higher gas costs than those over standard maps.
   A ``big_map`` also has a lower storage cost than a standard map of the same size, when large keys are used, since only the hash of each key is stored in a ``big_map``.

   A ``big_map`` cannot appear inside another ``big_map``.
   See the section on :ref:`operations on big maps <OperationsOnBigMaps_012>` for a description of the syntax of values of type ``big_map (k) (t)`` and available operations.

Core instructions
-----------------

Control structures
~~~~~~~~~~~~~~~~~~

-  ``FAILWITH``: Explicitly abort the current program.

::

    :: 'a : \_   ->   \_

This special instruction aborts the current program exposing the top
element of the stack in its error message (first rule below). It makes
the output useless since all subsequent instructions will simply
ignore their usual semantics to propagate the failure up to the main
result (second rule below). Its type is thus completely generic.

::

    > FAILWITH / a : _  =>  [FAILED]
    > _ / [FAILED]  =>  [FAILED]

-  ``{}``: Empty sequence.

::

    :: 'A   ->   'A

    > {} / SA  =>  SA

-  ``{ I ; C }``: Sequence.

::

    :: 'A   ->   'C
       iff   I :: [ 'A -> 'B ]
             C :: [ 'B -> 'C ]

    > I ; C / SA  =>  SC
        where   I / SA  =>  SB
        and   C / SB  =>  SC

-  ``IF bt bf``: Conditional branching.

::

    :: bool : 'A   ->   'B
       iff   bt :: [ 'A -> 'B ]
             bf :: [ 'A -> 'B ]

    > IF bt bf / True : S  =>  bt / S
    > IF bt bf / False : S  =>  bf / S

-  ``LOOP body``: A generic loop.

::

    :: bool : 'A   ->   'A
       iff   body :: [ 'A -> bool : 'A ]

    > LOOP body / True : S  =>  body ; LOOP body / S
    > LOOP body / False : S  =>  S

-  ``LOOP_LEFT body``: A loop with an accumulator.

::

    :: (or 'a 'b) : 'A   ->  'b : 'A
       iff   body :: [ 'a : 'A -> (or 'a 'b) : 'A ]

    > LOOP_LEFT body / (Left a) : S  =>  body ; LOOP_LEFT body / a : S
    > LOOP_LEFT body / (Right b) : S  =>  b : S

-  ``DIP code``: Runs code protecting the top element of the stack.

::

    :: 'b : 'A   ->   'b : 'C
       iff   code :: [ 'A -> 'C ]

    > DIP code / x : S  =>  x : S'
        where    code / S  =>  S'

-  ``DIP n code``: Runs code protecting the ``n`` topmost elements of
   the stack. In particular, ``DIP 0 code`` is equivalent to ``code``
   and ``DIP 1 code`` is equivalent to ``DIP code``.

::

    :: 'a{1} : ... : 'a{n} : 'A   ->   'a{1} : ... : 'a{n} : 'B
       iff   code :: [ 'A -> 'B ]

    > DIP n code / x{1} : ... : x{n} : S  =>  x{1} : ... : x{n} : S'
        where    code / S  =>  S'

-  ``EXEC``: Execute a function from the stack.

::

    :: 'a : lambda 'a 'b : 'C   ->   'b : 'C

    > EXEC / a : f : S  =>  r : S
        where f / a : []  =>  r : []

-  ``APPLY``: Partially apply a tuplified function from the stack.
   Values that are not both pushable and storable
   (values of type ``operation``, ``contract _`` and ``big map _ _``)
   cannot be captured by ``APPLY`` (cannot appear in ``'a``).

::

    :: 'a : lambda (pair 'a 'b) 'c : 'C   ->   lambda 'b 'c : 'C

    > APPLY / a : f : S  => { PUSH 'a a ; PAIR ; f } : S

Stack operations
~~~~~~~~~~~~~~~~

-  ``DROP``: Drop the top element of the stack.

::

    :: _ : 'A   ->   'A

    > DROP / _ : S  =>  S

- ``DROP n``: Drop the `n` topmost elements of the stack. In
  particular, ``DROP 0`` is a noop and ``DROP 1`` is equivalent to
  ``DROP``.

::

   :: 'a{1} : ... : 'a{n} : 'A   ->   'A

   > DROP n / x{1} : ... : x{n} : S  =>  S

-  ``DUP``: Duplicate the top element of the stack.

::

    :: 'a : 'A   ->   'a : 'a : 'A

    > DUP / x : S  =>  x : x : S

-  ``DUP n``: Duplicate the N-th element of the stack. `DUP 1` is equivalent to `DUP`. `DUP 0` is rejected.

::

    DUP 1 :: 'a : 'A   ->   'a : 'a : 'A

    DUP (n+1) :: 'a : 'A   ->   'b : 'a : 'A
        iff DUP n :: 'A   ->    'b : 'A

    > DUP 1 / x : S  =>  x : x : S

    > DUP (n+1) / x : S  =>  y : x : S
      iff DUP n / S  =>  y : S


-  ``SWAP``: Exchange the top two elements of the stack.

::

    :: 'a : 'b : 'A   ->   'b : 'a : 'A

    > SWAP / x : y : S  =>  y : x : S

- ``DIG n``: Take the element at depth ``n`` of the stack and move it
  on top. The element on top of the stack is at depth ``0`` so that
  ``DIG 0`` is a no-op and ``DIG 1`` is equivalent to ``SWAP``.

::

    :: 'a{1} : ... : 'a{n} : 'b : 'A   ->   'b : 'a{1} : ... : 'a{n} : 'A

    > DIG n / x{1} : ... : x{n} : y : S  =>  y : x{1} : ... : x{n} : S

- ``DUG n``: Place the element on top of the stack at depth ``n``. The
  element on top of the stack is at depth ``0`` so that ``DUG 0`` is a
  no-op and ``DUG 1`` is equivalent to ``SWAP``.

::

    :: 'b : 'a{1} : ... : 'a{n} : 'A   ->   'a{1} : ... : 'a{n} : 'b : 'A

    > DUG n / y : x{1} : ... : x{n} : S  =>  x{1} : ... : x{n} : y : S

-  ``PUSH 'a x``: Push a constant value of a given type onto the stack.

::

    :: 'A   ->   'a : 'A
       iff   x :: 'a

    > PUSH 'a x / S  =>  x : S

-  ``LAMBDA 'a 'b code``: Push a lambda with the given parameter type `'a` and return
   type `'b` onto the stack.

::

    :: 'A ->  (lambda 'a 'b) : 'A

    > LAMBDA _ _ code / S  =>  code : S

Generic comparison
~~~~~~~~~~~~~~~~~~

Comparison only works on a class of types that we call comparable. A
``COMPARE`` operation is defined in an ad hoc way for each comparable
type, but the result of compare is always an ``int``, which can in turn
be checked in a generic manner using the following combinators. The
result of ``COMPARE`` is ``0`` if the top two elements of the stack are
equal, negative if the first element in the stack is less than the
second, and positive otherwise.

-  ``EQ``: Checks that the top element of the stack is equal to zero.

::

    :: int : 'S   ->   bool : 'S

    > EQ / 0 : S  =>  True : S
    > EQ / v : S  =>  False : S
        iff v <> 0

-  ``NEQ``: Checks that the top element of the stack is not equal to zero.

::

    :: int : 'S   ->   bool : 'S

    > NEQ / 0 : S  =>  False : S
    > NEQ / v : S  =>  True : S
        iff v <> 0

-  ``LT``: Checks that the top element of the stack is less than zero.

::

    :: int : 'S   ->   bool : 'S

    > LT / v : S  =>  True : S
        iff  v < 0
    > LT / v : S  =>  False : S
        iff v >= 0

-  ``GT``: Checks that the top element of the stack is greater than zero.

::

    :: int : 'S   ->   bool : 'S

    > GT / v : S  =>  C / True : S
        iff  v > 0
    > GT / v : S  =>  C / False : S
        iff v <= 0

-  ``LE``: Checks that the top element of the stack is less than or equal to
   zero.

::

    :: int : 'S   ->   bool : 'S

    > LE / v : S  =>  True : S
        iff  v <= 0
    > LE / v : S  =>  False : S
        iff v > 0

-  ``GE``: Checks that the top of the stack is greater than or equal to
   zero.

::

    :: int : 'S   ->   bool : 'S

    > GE / v : S  =>  True : S
        iff  v >= 0
    > GE / v : S  =>  False : S
        iff v < 0

Operations
----------

Operations on unit
~~~~~~~~~~~~~~~~~~

-  ``UNIT``: Push a unit value onto the stack.

::

    :: 'A   ->   unit : 'A

    > UNIT / S  =>  Unit : S

-  ``COMPARE``: Unit comparison

::

    :: unit : unit : 'S   ->   int : 'S

    > COMPARE / Unit : Unit : S  =>  0 : S

Operations on type never
~~~~~~~~~~~~~~~~~~~~~~~~

The type ``never`` is the type of forbidden values. The most prominent
scenario in which ``never`` is used is when implementing a contract
template with no additional entrypoint. A contract template defines a set
of basic entrypoints, and its ``parameter`` declaration contains a type
variable for additional entrypoints in some branch of an union type, or
wrapped inside an option type. Letting this type variable be ``never`` in
a particular implementation indicates that the contract template has not
been extended, and turns the branch in the code that processes the
additional entrypoints into a forbidden branch.

Values of type ``never`` cannot occur in a well-typed program. However,
they can be abstracted in the ``parameter`` declaration of a contract---or
by using the ``LAMBDA`` operation---thus indicating that the corresponding
branches in the code are forbidden. The type ``never`` also plays a role
when introducing values of union or option type with ``LEFT never``,
``RIGHT never``, or ``NONE never``. In such cases, the created values can
be inspected with the operations ``IF_LEFT``, ``IF_RIGHT``, or
``IF_NONE``, and the corresponding branches in the code are forbidden
branches.

-  ``NEVER``: Close a forbidden branch.

::

    :: never : 'A  ->  'B

- ``COMPARE``: Trivial comparison on type ``never``

::

   :: never : never : 'S   ->   int : 'S


Operations on booleans
~~~~~~~~~~~~~~~~~~~~~~

-  ``OR``

::

    :: bool : bool : 'S   ->   bool : 'S

    > OR / x : y : S  =>  (x | y) : S

-  ``AND``

::

    :: bool : bool : 'S   ->   bool : 'S

    > AND / x : y : S  =>  (x & y) : S

-  ``XOR``

::

    :: bool : bool : 'S   ->   bool : 'S

    > XOR / x : y : S  =>  (x ^ y) : S

-  ``NOT``

::

    :: bool : 'S   ->   bool : 'S

    > NOT / x : S  =>  ~x : S

-  ``COMPARE``: Boolean comparison

::

    :: bool : bool : 'S   ->   int : 'S

    > COMPARE / False : False : S  =>  0 : S
    > COMPARE / False : True : S  =>  -1 : S
    > COMPARE / True : False : S  =>  1 : S
    > COMPARE / True : True : S  =>  0 : S

Operations on integers and natural numbers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Integers and naturals are arbitrary-precision, meaning that the only size
limit is gas.

-  ``NEG``

::

    :: int : 'S   ->   int : 'S
    :: nat : 'S   ->   int : 'S

    > NEG / x : S  =>  -x : S

-  ``ABS``

::

    :: int : 'S   ->   nat : 'S

    > ABS / x : S  =>  abs (x) : S

-  ``ISNAT``

::

    :: int : 'S   ->   option nat : 'S

    > ISNAT / x : S  =>  Some (x) : S
       iff x >= 0

    > ISNAT / x : S  =>  None : S
       iff x < 0

-  ``INT``

::

    :: nat : 'S   ->   int : 'S

    > INT / x : S  =>  x : S

-  ``ADD``

::

    :: int : int : 'S   ->   int : 'S
    :: int : nat : 'S   ->   int : 'S
    :: nat : int : 'S   ->   int : 'S
    :: nat : nat : 'S   ->   nat : 'S

    > ADD / x : y : S  =>  (x + y) : S

-  ``SUB``

::

    :: int : int : 'S   ->   int : 'S
    :: int : nat : 'S   ->   int : 'S
    :: nat : int : 'S   ->   int : 'S
    :: nat : nat : 'S   ->   int : 'S

    > SUB / x : y : S  =>  (x - y) : S

-  ``MUL``

::

    :: int : int : 'S   ->   int : 'S
    :: int : nat : 'S   ->   int : 'S
    :: nat : int : 'S   ->   int : 'S
    :: nat : nat : 'S   ->   nat : 'S

    > MUL / x : y : S  =>  (x * y) : S

-  ``EDIV``: Perform Euclidean division

::

    :: int : int : 'S   ->   option (pair int nat) : 'S
    :: int : nat : 'S   ->   option (pair int nat) : 'S
    :: nat : int : 'S   ->   option (pair int nat) : 'S
    :: nat : nat : 'S   ->   option (pair nat nat) : 'S

    > EDIV / x : 0 : S  =>  None : S
    > EDIV / x : y : S  =>  Some (Pair (x / y) (x % y)) : S
        iff y <> 0

Bitwise logical operators are also available on unsigned integers.

-  ``OR``

::

    :: nat : nat : 'S   ->   nat : 'S

    > OR / x : y : S  =>  (x | y) : S

-  ``AND``: (also available when the top operand is signed)

::

    :: nat : nat : 'S   ->   nat : 'S
    :: int : nat : 'S   ->   nat : 'S

    > AND / x : y : S  =>  (x & y) : S

-  ``XOR``

::

    :: nat : nat : 'S   ->   nat : 'S

    > XOR / x : y : S  =>  (x ^ y) : S

-  ``NOT``: Two's complement

::

    :: nat : 'S   ->   int : 'S
    :: int : 'S   ->   int : 'S

    > NOT / x : S  =>  ~x : S


The return type of ``NOT`` is an ``int`` and not a ``nat``.  This is
because the sign is also negated. The resulting integer is computed
using two's complement. For instance, the boolean negation of ``0`` is
``-1``. To get a natural back, a possibility is to use ``AND`` with an
unsigned mask afterwards.


-  ``LSL``

::

    :: nat : nat : 'S   ->   nat : 'S

    > LSL / x : s : S  =>  (x << s) : S
        iff   s <= 256
    > LSL / x : s : S  =>  [FAILED]
        iff   s > 256

-  ``LSR``

::

    :: nat : nat : 'S   ->   nat : 'S

    > LSR / x : s : S  =>  (x >> s) : S
        iff   s <= 256
    > LSR / x : s : S  =>  [FAILED]
        iff   s > 256

-  ``COMPARE``: Integer/natural comparison

::

    :: int : int : 'S   ->   int : 'S
    :: nat : nat : 'S   ->   int : 'S

    > COMPARE / x : y : S  =>  -1 : S
        iff x < y
    > COMPARE / x : y : S  =>  0 : S
        iff x = y
    > COMPARE / x : y : S  =>  1 : S
        iff x > y

Operations on strings
~~~~~~~~~~~~~~~~~~~~~

Strings are mostly used for naming things without having to rely on
external ID databases. They are restricted to the printable subset of
7-bit ASCII, plus some escaped characters (see section on
constants). So what can be done is basically use string constants as
is, concatenate or splice them, and use them as keys.


-  ``CONCAT``: String concatenation.

::

    :: string : string : 'S   -> string : 'S

    > CONCAT / s : t : S  =>  (s ^ t) : S

    :: string list : 'S   -> string : 'S

    > CONCAT / {} : S  =>  "" : S
    > CONCAT / { s ; <ss> } : S  =>  (s ^ r) : S
       where CONCAT / { <ss> } : S  =>  r : S

-  ``SIZE``: number of characters in a string.

::

     :: string : 'S   ->   nat : 'S

-  ``SLICE``: String access.

::

    :: nat : nat : string : 'S   ->  option string : 'S

    > SLICE / offset : length : s : S  =>  Some ss : S
       where ss is the substring of s at the given offset and of the given length
         iff offset and (offset + length) are in bounds
    > SLICE / offset : length : s : S  =>  None  : S
         iff offset or (offset + length) are out of bounds

-  ``COMPARE``: Lexicographic comparison.

::

    :: string : string : 'S   ->   int : 'S

    > COMPARE / s : t : S  =>  -1 : S
        iff s < t
    > COMPARE / s : t : S  =>  0 : S
        iff s = t
    > COMPARE / s : t : S  =>  1 : S
        iff s > t

Operations on pairs and right combs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The type ``pair l r`` is the type of binary pairs composed of a left
element of type ``l`` and a right element of type ``r``. A value of
type ``pair l r`` is written ``Pair x y`` where ``x`` is a value of
type ``l`` and ``y`` is a value of type ``r``.

To build tuples of length greater than 2, right combs have specific
optimized operations. For any ``n > 2``, the compact notations ``pair
t{0} t{1} ... t{n-2} t{n-1}`` is provided for the type of right combs
``pair t{0} (pair t{1} ... (pair t{n-2} t{n-1}) ...)``. Similarly, the
compact notation ``Pair x{0} x{1} ... x{n-2} x{n-1}`` is provided for
the right-comb value ``Pair x{0} (Pair x{1} ... (Pair x{n-2} x{n-1})
...)``. Right-comb values can also be written using sequences; ``Pair
x{0} x{1} ... x{n-2} x{n-1}`` can be written ``{x{0}; x{1}; ...; x{n-2}; x{n-1}}``.

-  ``PAIR``: Build a binary pair from the stack's top two elements.

::

    :: 'a : 'b : 'S   ->   pair 'a 'b : 'S

    > PAIR / x : y : S  =>  Pair x y : S

-  ``PAIR n``: Fold ``n`` values on the top of the stack in a right comb.
   ``PAIR 0`` and ``PAIR 1`` are rejected. ``PAIR 2`` is equivalent to ``PAIR``.

::

    PAIR 2 :: 'a : 'b : 'S   ->   pair 'a 'b : 'S
    PAIR (k+1) :: 'x : 'S   ->   pair 'x 'y : 'T
         iff PAIR k :: 'S   ->   'y : 'T

    Or equivalently, for n >= 2,
    PAIR n :: 'a{0} : ... : 'a{n-1} : 'A -> pair 'a{0} ...  'a{n-1} : 'A

    > PAIR 2 / x : y : S  =>  Pair x y : S
    > PAIR (k+1) / x : S  =>  Pair x y : T
         iff PAIR k / S  =>  y : T

    Or equivalently, for n >= 2,
    > PAIR n / x{0} : ... : x{n-1} : S  =>  Pair x{0} ... x{n-1} : S

-  ``UNPAIR``: Split a pair into its components.

::

    :: pair 'a 'b : 'S   ->   'a : 'b : 'S

    > UNPAIR / Pair a b : S  =>  a : b : S


-  ``UNPAIR n``: Unfold ``n`` values from a right comb on the top of the stack. ``UNPAIR 0`` and ``UNPAIR 1`` are rejected. ``UNPAIR 2`` is equivalent to ``UNPAIR``.

::

    UNPAIR 2 :: pair 'a 'b : 'A   ->   'a : 'b : 'A
    UNPAIR (k+1) :: pair 'a 'b : 'A   ->   'a : 'B
         iff UNPAIR k :: 'b : 'A   ->   'B

    Or equivalently, for n >= 2,
    UNPAIR n :: pair 'a{0} ... 'a{n-1} : S   ->   'a{0} : ... : 'a{n-1} : S

    > UNPAIR 2 / Pair x y : S  =>  x : y : S
    > UNPAIR (k+1) / Pair x y : SA  =>  x : SB
         iff UNPAIR k / y : SA  =>  SB

    Or equivalently, for n >= 2,
    > UNPAIR n / Pair x{0} ... x{n-1} : S  =>  x{0} : ... : x{n-1} : S

-  ``CAR``: Access the left part of a pair.

::

    :: pair 'a _ : 'S   ->   'a : 'S

    > CAR / Pair x _ : S  =>  x : S

-  ``CDR``: Access the right part of a pair.

::

    :: pair _ 'b : 'S   ->   'b : 'S

    > CDR / Pair _ y : S  =>  y : S

- ``GET k``: Access an element or a sub comb in a right comb.

  The nodes of a right comb of size ``n`` are canonically numbered as follows:

::

         0
       /   \
     1       2
           /   \
         3       4
               /   \
             5       ...
                          2n-2
                        /      \
                   2n-1          2n


Or in plain English:

  - The root is numbered with 0,
  - The left child of the node numbered by ``k`` is numbered by ``k+1``, and
  - The right child of the node numbered by ``k`` is numbered by ``k+2``.

The ``GET k`` instruction accesses the node numbered by ``k``. In
particular, for a comb of size ``n``, the ``n-1`` first elements are
accessed by ``GET 1``, ``GET 3``, ..., and ``GET (2n-1)`` and the last
element is accessed by ``GET (2n)``.

::

    GET 0 :: 'a : 'S   ->   'a : 'S
    GET 1 :: pair 'x _ : 'S   ->   'x : 'S
    GET (k+2) :: pair _ 'y : 'S   ->   'z : 'S
         iff GET k :: 'y : 'S   ->   'z : 'S

    Or equivalently,
    GET 0 :: 'a : 'S   ->   'a : 'S
    GET (2k) :: pair 'a{0} ... 'a{k-1} 'a{k} : 'S   ->   'a{k} : 'S
    GET (2k+1) :: pair 'a{0} ... 'a{k} 'a{k+1} : 'S   ->   'a{k} : 'S

    > GET 0 / x : S  =>  x : S
    > GET 1 / Pair x _ : S  =>  x : S
    > GET (k+2) / Pair _ y : S  =>  GET k / y : S

    Or equivalently,
    > GET 0 / x : S  =>  x : S
    > GET (2k) / Pair x{0} ... x{k-1} x{k} : 'S   ->   x{k} : 'S
    > GET (2k+1) / Pair x{0} ... x{k} x{k+1} : 'S   ->   x{k} : 'S


- ``UPDATE k``: Update an element or a sub comb in a right comb. The topmost stack element is the new value to insert in the comb, the second stack element is the right comb to update. The meaning of ``k`` is the same as for the ``GET k`` instruction.

::

    UPDATE 0 :: 'a : 'b : 'S   ->   'a : 'S
    UPDATE 1 :: 'a2 : pair 'a1 'b : 'S   ->   pair 'a2 'b : 'S
    UPDATE (k+2) :: 'c : pair 'a 'b1 : 'S   ->   pair 'a 'b2 : 'S
         iff UPDATE k :: 'c : 'b1 : 'S   ->   'b2 : 'S

    Or equivalently,
    UPDATE 0 :: 'a : 'b : 'S   ->   'a : 'S
    UPDATE (2k) :: 'c : pair 'a{0} ... 'a{k-1} 'a{k} : 'S   ->   pair 'a{0} ... 'a{k-1} 'c : 'S
    UPDATE (2k+1) :: 'c : pair 'a{0} ... 'a{k} 'a{k+1} : 'S   ->   pair 'a{0} ... 'a{k-1} 'c 'a{k+1} : 'S

    > UPDATE 0 / x : _ : S  =>  x : S
    > UPDATE 1 / x2 : Pair x1 y : S  =>  Pair x2 y : S
    > UPDATE (k+2) / z : Pair x y1 : S  =>  Pair x y2 : S
         iff UPDATE k / z : y1 : S  =>  y2 : S

    Or equivalently,
    > UPDATE 0 / x : _ : S  =>  x : S
    > UPDATE (2k) / z : Pair x{0} ... x{k-1} x{k} : 'S  =>  Pair x{0} ... x{k-1} z : 'S
    > UPDATE (2k+1) / z : Pair x{0} ... x{k-1} x{k} x{k+1} : 'S  =>  Pair x{0} ... x{k-1} z x{k+1} : 'S

-  ``COMPARE``: Lexicographic comparison.

::

    :: pair 'a 'b : pair 'a 'b : 'S   ->   int : 'S

    > COMPARE / (Pair sa sb) : (Pair ta tb) : S  =>  -1 : S
        iff COMPARE / sa : ta : S => -1 : S
    > COMPARE / (Pair sa sb) : (Pair ta tb) : S  =>  1 : S
        iff COMPARE / sa : ta : S => 1 : S
    > COMPARE / (Pair sa sb) : (Pair ta tb) : S  =>  r : S
        iff COMPARE / sa : ta : S => 0 : S
            COMPARE / sb : tb : S => r : S

Operations on sets
~~~~~~~~~~~~~~~~~~

-  ``EMPTY_SET 'elt``: Build a new, empty set for elements of a given
   type.

   The ``'elt`` type must be comparable (the ``COMPARE``
   primitive must be defined over it).

::

    :: 'S   ->   set 'elt : 'S

    > EMPTY_SET _ / S  =>  {} : S

-  ``MEM``: Check for the presence of an element in a set.

::

    :: 'elt : set 'elt : 'S   ->  bool : 'S

    > MEM / x : {} : S  =>  false : S
    > MEM / x : { hd ; <tl> } : S  =>  r : S
        iff COMPARE / x : hd : []  =>  1 : []
        where MEM / x : { <tl> } : S  =>  r : S
    > MEM / x : { hd ; <tl> } : S  =>  true : S
        iff COMPARE / x : hd : []  =>  0 : []
    > MEM / x : { hd ; <tl> } : S  =>  false : S
        iff COMPARE / x : hd : []  =>  -1 : []

-  ``UPDATE``: Inserts or removes an element in a set, replacing a
   previous value.

::

    :: 'elt : bool : set 'elt : 'S   ->   set 'elt : 'S

    > UPDATE / x : false : {} : S  =>  {} : S
    > UPDATE / x : true : {} : S  =>  { x } : S
    > UPDATE / x : v : { hd ; <tl> } : S  =>  { hd ; <tl'> } : S
        iff COMPARE / x : hd : []  =>  1 : []
        where UPDATE / x : v : { <tl> } : S  =>  { <tl'> } : S
    > UPDATE / x : false : { hd ; <tl> } : S  =>  { <tl> } : S
        iff COMPARE / x : hd : []  =>  0 : []
    > UPDATE / x : true : { hd ; <tl> } : S  =>  { hd ; <tl> } : S
        iff COMPARE / x : hd : []  =>  0 : []
    > UPDATE / x : false : { hd ; <tl> } : S  =>  { hd ; <tl> } : S
        iff COMPARE / x : hd : []  =>  -1 : []
    > UPDATE / x : true : { hd ; <tl> } : S  =>  { x ; hd ; <tl> } : S
        iff COMPARE / x : hd : []  =>  -1 : []

-  ``ITER body``: Apply the body expression to each element of a set.
   The body sequence has access to the stack.

::

    :: (set 'elt) : 'A   ->  'A
       iff body :: [ 'elt : 'A -> 'A ]

    > ITER body / {} : S  =>  S
    > ITER body / { hd ; <tl> } : S  =>  ITER body / { <tl> } : S'
       iff body / hd : S  =>  S'


-  ``SIZE``: Get the cardinality of the set.

::

    :: set 'elt : 'S -> nat : 'S

    > SIZE / {} : S  =>  0 : S
    > SIZE / { _ ; <tl> } : S  =>  1 + s : S
        where SIZE / { <tl> } : S  =>  s : S

Operations on maps
~~~~~~~~~~~~~~~~~~

-  ``EMPTY_MAP 'key 'val``: Build a new, empty map from keys of a
   given type to values of another given type.

   The ``'key`` type must be comparable (the ``COMPARE`` primitive must
   be defined over it).

::

    :: 'S -> map 'key 'val : 'S

    > EMPTY_MAP _ _ / S  =>  {} : S


-  ``GET``: Access an element in a map, returns an optional value to be
   checked with ``IF_SOME``.

::

    :: 'key : map 'key 'val : 'S   ->   option 'val : 'S

    > GET / x : {} : S  =>  None : S
    > GET / x : { Elt k v ; <tl> } : S  =>  opt_y : S
        iff COMPARE / x : k : []  =>  1 : []
        where GET / x : { <tl> } : S  =>  opt_y : S
    > GET / x : { Elt k v ; <tl> } : S  =>  Some v : S
        iff COMPARE / x : k : []  =>  0 : []
    > GET / x : { Elt k v ; <tl> } : S  =>  None : S
        iff COMPARE / x : k : []  =>  -1 : []

-  ``MEM``: Check for the presence of a binding for a key in a map.

::

    :: 'key : map 'key 'val : 'S   ->  bool : 'S

    > MEM / x : {} : S  =>  false : S
    > MEM / x : { Elt k v ; <tl> } : S  =>  r : S
        iff COMPARE / x : k : []  =>  1 : []
        where MEM / x : { <tl> } : S  =>  r : S
    > MEM / x : { Elt k v ; <tl> } : S  =>  true : S
        iff COMPARE / x : k : []  =>  0 : []
    > MEM / x : { Elt k v ; <tl> } : S  =>  false : S
        iff COMPARE / x : k : []  =>  -1 : []

-  ``UPDATE``: Assign or remove an element in a map.

::

    :: 'key : option 'val : map 'key 'val : 'S   ->   map 'key 'val : 'S

    > UPDATE / x : None : {} : S  =>  {} : S
    > UPDATE / x : Some y : {} : S  =>  { Elt x y } : S
    > UPDATE / x : opt_y : { Elt k v ; <tl> } : S  =>  { Elt k v ; <tl'> } : S
        iff COMPARE / x : k : []  =>  1 : []
	      where UPDATE / x : opt_y : { <tl> } : S  =>  { <tl'> } : S
    > UPDATE / x : None : { Elt k v ; <tl> } : S  =>  { <tl> } : S
        iff COMPARE / x : k : []  =>  0 : []
    > UPDATE / x : Some y : { Elt k v ; <tl> } : S  =>  { Elt k y ; <tl> } : S
        iff COMPARE / x : k : []  =>  0 : []
    > UPDATE / x : None : { Elt k v ; <tl> } : S  =>  { Elt k v ; <tl> } : S
        iff COMPARE / x : k : []  =>  -1 : []
    > UPDATE / x : Some y : { Elt k v ; <tl> } : S  =>  { Elt x y ; Elt k v ; <tl> } : S
        iff COMPARE / x : k : []  =>  -1 : []

-  ``GET_AND_UPDATE``: A combination of the ``GET`` and ``UPDATE`` instructions.

::

    :: 'key : option 'val : map 'key 'val : 'S   ->   option 'val : map 'key 'val : 'S

This instruction is similar to ``UPDATE`` but it also returns the
value that was previously stored in the ``map`` at the same key as
``GET`` would.

::

    > GET_AND_UPDATE / x : None : {} : S  =>  None : {} : S
    > GET_AND_UPDATE / x : Some y : {} : S  =>  None : { Elt x y } : S
    > GET_AND_UPDATE / x : opt_y : { Elt k v ; <tl> } : S  =>  opt_y' : { Elt k v ; <tl'> } : S
        iff COMPARE / x : k : []  =>  1 : []
	      where GET_AND_UPDATE / x : opt_y : { <tl> } : S  =>  opt_y' : { <tl'> } : S
    > GET_AND_UPDATE / x : None : { Elt k v ; <tl> } : S  =>  Some v : { <tl> } : S
        iff COMPARE / x : k : []  =>  0 : []
    > GET_AND_UPDATE / x : Some y : { Elt k v ; <tl> } : S  =>  Some v : { Elt k y ; <tl> } : S
        iff COMPARE / x : k : []  =>  0 : []
    > GET_AND_UPDATE / x : None : { Elt k v ; <tl> } : S  =>  None : { Elt k v ; <tl> } : S
        iff COMPARE / x : k : []  =>  -1 : []
    > GET_AND_UPDATE / x : Some y : { Elt k v ; <tl> } : S  =>  None : { Elt x y ; Elt k v ; <tl> } : S
        iff COMPARE / x : k : []  =>  -1 : []

-  ``MAP body``: Apply the body expression to each element of a map. The
   body sequence has access to the stack.

::

    :: (map 'key 'val) : 'A   ->  (map 'key 'b) : 'A
       iff   body :: [ (pair 'key 'val) : 'A -> 'b : 'A ]

    > MAP body / {} : S  =>  {} : S
    > MAP body / { Elt k v ; <tl> } : S  =>  { Elt k v' ; <tl'> } : S''
        where body / Pair k v : S  =>  v' : S'
        and MAP body / { <tl> } : S'  =>  { <tl'> } : S''

-  ``ITER body``: Apply the body expression to each element of a map.
   The body sequence has access to the stack.

::

    :: (map 'elt 'val) : 'A   ->  'A
       iff   body :: [ (pair 'elt 'val : 'A) -> 'A ]

    > ITER body / {} : S  =>  S
    > ITER body / { Elt k v ; <tl> } : S  =>  ITER body / { <tl> } : S'
       iff body / (Pair k v) : S  =>  S'

-  ``SIZE``: Get the cardinality of the map.

::

    :: map 'key 'val : 'S -> nat : 'S

    > SIZE / {} : S  =>  0 : S
    > SIZE / { _ ; <tl> } : S  =>  1 + s : S
        where  SIZE / { <tl> } : S  =>  s : S


Operations on ``big_maps``
~~~~~~~~~~~~~~~~~~~~~~~~~~
.. _OperationsOnBigMaps_012:

Big maps have three possible representations. A map literal is always
a valid representation for a big map. Big maps can also be represented
by integers called big-map identifiers. Finally, big maps can be
represented as pairs of a big-map identifier (an integer) and a
big-map diff (written in the same syntax as a map whose values are
options).

So for example, ``{ Elt "bar" True ; Elt "foo" False }``, ``42``, and
``Pair 42 { Elt "foo" (Some False) }`` are all valid representations
of type ``big_map string bool``.

The behavior of big-map operations is the same as if they were normal
maps, except that under the hood, the elements are loaded and
deserialized on demand.

-  ``EMPTY_BIG_MAP 'key 'val``: Build a new, empty big map from keys of a
   given type to values of another given type.

   The ``'key`` type must be comparable (the ``COMPARE`` primitive must
   be defined over it).

::

    :: 'S -> map 'key 'val : 'S

-  ``GET``: Access an element in a ``big_map``, returns an optional value to be
   checked with ``IF_SOME``.

::

    :: 'key : big_map 'key 'val : 'S   ->   option 'val : 'S

-  ``MEM``: Check for the presence of an element in a ``big_map``.

::

    :: 'key : big_map 'key 'val : 'S   ->  bool : 'S

-  ``UPDATE``: Assign or remove an element in a ``big_map``.

::

    :: 'key : option 'val : big_map 'key 'val : 'S   ->   big_map 'key 'val : 'S


-  ``GET_AND_UPDATE``: A combination of the ``GET`` and ``UPDATE`` instructions.

::

    :: 'key : option 'val : big_map 'key 'val : 'S   ->   option 'val : big_map 'key 'val : 'S

This instruction is similar to ``UPDATE`` but it also returns the
value that was previously stored in the ``big_map`` at the same key as
``GET`` would.


Operations on optional values
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  ``SOME``: Pack a value as an optional value.

::

    :: 'a : 'S   ->   option 'a : 'S

    > SOME / v : S  =>  (Some v) : S

-  ``NONE 'a``: The absent optional value.

::

    :: 'S   ->   option 'a : 'S

    > NONE / S  =>  None : S

-  ``IF_NONE bt bf``: Inspect an optional value.

::

    :: option 'a : 'A   ->   'B
       iff   bt :: [ 'A -> 'B]
             bf :: [ 'a : 'A -> 'B]

    > IF_NONE bt bf / (None) : S  =>  bt / S
    > IF_NONE bt bf / (Some a) : S  =>  bf / a : S

-  ``COMPARE``: Optional values comparison

::

    :: option 'a : option 'a : 'S   ->   int : 'S

    > COMPARE / None : None : S  =>  0 : S
    > COMPARE / None : (Some _) : S  =>  -1 : S
    > COMPARE / (Some _) : None : S  =>  1 : S
    > COMPARE / (Some a) : (Some b) : S  =>  COMPARE / a : b : S

- ``MAP body``: Apply the body expression to the value inside the option if there is one.

::

   :: option 'a : 'S -> option 'b : 'S
      iff    body :: [ 'a : 'S -> 'b : 'S ]

   > MAP body / None : S => None : S
   > MAP body / (Some a) : S => (Some b) : S'
      where body / a : S => b : S'

Operations on unions
~~~~~~~~~~~~~~~~~~~~

-  ``LEFT 'b``: Pack a value in a union (left case).

::

    :: 'a : 'S   ->   or 'a 'b : 'S

    > LEFT / v : S  =>  (Left v) : S

-  ``RIGHT 'a``: Pack a value in a union (right case).

::

    :: 'b : 'S   ->   or 'a 'b : 'S

    > RIGHT / v : S  =>  (Right v) : S

-  ``IF_LEFT bt bf``: Inspect a value of a union.

::

    :: or 'a 'b : 'A   ->   'B
       iff   bt :: [ 'a : 'A -> 'B]
             bf :: [ 'b : 'A -> 'B]

    > IF_LEFT bt bf / (Left a) : S  =>  bt / a : S
    > IF_LEFT bt bf / (Right b) : S  =>  bf / b : S

-  ``COMPARE``: Unions comparison

::

    :: or 'a 'b : or 'a 'b : 'S   ->   int : 'S

    > COMPARE / (Left a) : (Left b) : S  =>  COMPARE / a : b : S
    > COMPARE / (Left _) : (Right _) : S  =>  -1 : S
    > COMPARE / (Right _) : (Left _) : S  =>  1 : S
    > COMPARE / (Right a) : (Right b) : S  =>  COMPARE / a : b : S

Operations on lists
~~~~~~~~~~~~~~~~~~~

-  ``CONS``: Prepend an element to a list.

::

    :: 'a : list 'a : 'S   ->   list 'a : 'S

    > CONS / a : { <l> } : S  =>  { a ; <l> } : S

-  ``NIL 'a``: The empty list.

::

    :: 'S   ->   list 'a : 'S

    > NIL / S  =>  {} : S

-  ``IF_CONS bt bf``: Inspect a list.

::

    :: list 'a : 'A   ->   'B
       iff   bt :: [ 'a : list 'a : 'A -> 'B]
             bf :: [ 'A -> 'B]

    > IF_CONS bt bf / { a ; <rest> } : S  =>  bt / a : { <rest> } : S
    > IF_CONS bt bf / {} : S  =>  bf / S

-  ``MAP body``: Apply the body expression to each element of the list.
   The body sequence has access to the stack.

::

    :: (list 'elt) : 'A   ->  (list 'b) : 'A
       iff   body :: [ 'elt : 'A -> 'b : 'A ]

    > MAP body / {} : S  =>  {} : S
    > MAP body / { a ; <rest> } : S  =>  { b ; <rest'> } : S''
        where body / a : S  =>  b : S'
        and MAP body / { <rest> } : S'  =>  { <rest'> } : S''

-  ``SIZE``: Get the number of elements in the list.

::

    :: list 'elt : 'S -> nat : 'S

    > SIZE / { _ ; <rest> } : S  =>  1 + s : S
        where  SIZE / { <rest> } : S  =>  s : S
    > SIZE / {} : S  =>  0 : S


-  ``ITER body``: Apply the body expression to each element of a list.
   The body sequence has access to the stack.

::

    :: (list 'elt) : 'A   ->  'A
         iff body :: [ 'elt : 'A -> 'A ]
    > ITER body / {} : S  =>  S
    > ITER body / { a ; <rest> } : S  =>  ITER body / { <rest> } : S'
       iff body / a : S  =>  S'


Domain specific data types
--------------------------

-  ``timestamp``: Dates in the real world.

-  ``mutez``: A specific type for manipulating tokens.

-  ``address``: An untyped address (implicit account or smart contract).

-  ``contract 'param``: A contract, with the type of its code,
   ``contract unit`` for implicit accounts.

-  ``operation``: An internal operation emitted by a contract.

-  ``key``: A public cryptographic key.

-  ``key_hash``: The hash of a public cryptographic key.

-  ``signature``: A cryptographic signature.

-  ``chain_id``: An identifier for a chain, used to distinguish the test and the main chains.

-  ``bls12_381_g1``, ``bls12_381_g2`` : Points on the BLS12-381 curves G\ :sub:`1`\  and G\ :sub:`2`\ , respectively.

-  ``bls12_381_fr`` : An element of the scalar field F\ :sub:`r`\ , used for scalar multiplication on the BLS12-381 curves G\ :sub:`1`\  and G\ :sub:`2`\ .

-  ``sapling_transaction ms``: A :doc:`Sapling <sapling>` transaction

-  ``sapling_state ms``: A :doc:`Sapling <sapling>` state

-  ``ticket (t)``: A ticket used to authenticate information of type ``(t)`` on-chain.

-  ``chest``: a timelocked chest containing bytes and information to open it.
   see :doc:`Timelock <timelock>` .

-  ``chest_key``: used to open a chest, also contains a proof
   to check the correctness of the opening. see :doc:`Timelock <timelock>` .


Domain specific operations
--------------------------

Operations on timestamps
~~~~~~~~~~~~~~~~~~~~~~~~

Timestamps can be obtained by the ``NOW`` operation, or retrieved from
script parameters or globals.

-  ``ADD`` Increment / decrement a timestamp of the given number of
   seconds.

::

    :: timestamp : int : 'S -> timestamp : 'S
    :: int : timestamp : 'S -> timestamp : 'S

    > ADD / seconds : nat (t) : S  =>  (seconds + t) : S
    > ADD / nat (t) : seconds : S  =>  (t + seconds) : S

-  ``SUB`` Subtract a number of seconds from a timestamp.

::

    :: timestamp : int : 'S -> timestamp : 'S

    > SUB / seconds : nat (t) : S  =>  (seconds - t) : S

-  ``SUB`` Subtract two timestamps.

::

    :: timestamp : timestamp : 'S -> int : 'S

    > SUB / seconds(t1) : seconds(t2) : S  =>  (t1 - t2) : S

-  ``COMPARE``: Timestamp comparison.

::

    :: timestamp : timestamp : 'S   ->   int : 'S

    > COMPARE / seconds(t1) : seconds(t2) : S  =>  -1 : S
        iff t1 < t2
    > COMPARE / seconds(t1) : seconds(t2) : S  =>  0 : S
        iff t1 = t2
    > COMPARE / seconds(t1) : seconds(t2) : S  =>  1 : S
        iff t1 > t2


Operations on Mutez
~~~~~~~~~~~~~~~~~~~

Mutez (micro-Tez) are internally represented by a 64 bit signed
integers. There are restrictions to prevent creating a negative amount
of mutez. Operations are limited to prevent overflow and mixing them
with other numerical types by mistake. They are also mandatory checked
for under/overflows.

-  ``ADD``

::

    :: mutez : mutez : 'S   ->   mutez : 'S

    > ADD / x : y : S  =>  [FAILED]   on overflow
    > ADD / x : y : S  =>  (x + y) : S

-  ``SUB_MUTEZ``

::

    :: mutez : mutez : 'S   ->   option mutez : 'S

    > SUB_MUTEZ / x : y : S  =>  None
        iff   x < y
    > SUB_MUTEZ / x : y : S  =>  Some (x - y) : S

-  ``MUL``

::

    :: mutez : nat : 'S   ->   mutez : 'S
    :: nat : mutez : 'S   ->   mutez : 'S

    > MUL / x : y : S  =>  [FAILED]   on overflow
    > MUL / x : y : S  =>  (x * y) : S

-  ``EDIV``

::

    :: mutez : nat : 'S   ->   option (pair mutez mutez) : 'S
    :: mutez : mutez : 'S   ->   option (pair nat mutez) : 'S

    > EDIV / x : 0 : S  =>  None
    > EDIV / x : y : S  =>  Some (Pair (x / y) (x % y)) : S
        iff y <> 0

-  ``COMPARE``: Mutez comparison

::

   :: mutez : mutez : 'S -> int : 'S

   > COMPARE / x : y : S  =>  -1 : S
       iff x < y
   > COMPARE / x : y : S  =>  0 : S
       iff x = y
   > COMPARE / x : y : S  =>  1 : S
       iff x > y

Operations on contracts
~~~~~~~~~~~~~~~~~~~~~~~

-  ``CREATE_CONTRACT { storage 'g ; parameter 'p ; code ... }``:
   Forge a new contract from a literal.

::

    :: option key_hash : mutez : 'g : 'S
       -> operation : address : 'S

Originate a contract based on a literal. The parameters are the
optional delegate, the initial amount taken from the current
contract, and the initial storage of the originated contract.
The contract is returned as a first class value (to be dropped, passed
as parameter or stored). The ``CONTRACT 'p`` instruction will fail
until it is actually originated.

-  ``TRANSFER_TOKENS``: Forge a transaction.

::

    :: 'p : mutez : contract 'p : 'S   ->   operation : 'S

The parameter must be consistent with the one expected by the
contract, unit for an account.

.. _MichelsonSetDelegate_012:

-  ``SET_DELEGATE``: Set or withdraw the contract's delegation.

::

    :: option key_hash : 'S   ->   operation : 'S

Using this instruction is the only way to modify the delegation of a
smart contract. If the parameter is ``None`` then the delegation of the
current contract is withdrawn; if it is ``Some kh`` where ``kh`` is the
key hash of a registered delegate that is not the current delegate of
the contract, then this operation sets the delegate of the contract to
this registered delegate. The operation fails if ``kh`` is the current
delegate of the contract or if ``kh`` is not a registered delegate.

-  ``BALANCE``: Push the current amount of mutez held by the executing
   contract, including any mutez added by the calling transaction.

::

    :: 'S   ->   mutez : 'S

-  ``ADDRESS``: Cast the contract to its address.

::

    :: contract _ : 'S   ->   address : 'S

    > ADDRESS / addr : S  =>  addr : S

-  ``CONTRACT 'p``: Cast the address to the given contract type if possible.

::

    :: address : 'S   ->   option (contract 'p) : 'S

    > CONTRACT / addr : S  =>  Some addr : S
        iff addr exists and is a contract of parameter type 'p
    > CONTRACT / addr : S  =>  Some addr : S
        iff 'p = unit and addr is an implicit contract
    > CONTRACT / addr : S  =>  None : S
        otherwise

-  ``SOURCE``: Push the contract that initiated the current
   transaction, i.e. the contract that paid the fees and
   storage cost, and whose manager signed the operation
   that was sent on the blockchain. Note that since
   ``TRANSFER_TOKENS`` instructions can be chained,
   ``SOURCE`` and ``SENDER`` are not necessarily the same.

::

    :: 'S   ->   address : 'S

-  ``SENDER``: Push the contract that initiated the current
   internal transaction. It may be the ``SOURCE``, but may
   also be different if the source sent an order to an intermediate
   smart contract, which then called the current contract.

::

    :: 'S   ->   address : 'S

-  ``SELF``: Push the current contract.

::

    :: 'S   ->   contract 'p : 'S
       where   contract 'p is the type of the current contract

Note that ``SELF`` is forbidden in lambdas because it cannot be
type-checked; the type of the contract executing the lambda cannot be
known at the point of type-checking the lambda's body.

-  ``SELF_ADDRESS``: Push the address of the current contract. This is
   equivalent to ``SELF; ADDRESS`` except that it is allowed in
   lambdas.

::

    :: 'S   ->   address : 'S

Note that ``SELF_ADDRESS`` inside a lambda returns the address of the
contract executing the lambda, which can be different from the address
of the contract in which the ``SELF_ADDRESS`` instruction is written.

-  ``AMOUNT``: Push the amount of the current transaction.

::

    :: 'S   ->   mutez : 'S

-  ``IMPLICIT_ACCOUNT``: Return a default contract with the given
   public/private key pair. Any funds deposited in this contract can
   immediately be spent by the holder of the private key. This contract
   cannot execute Michelson code and will always exist on the
   blockchain.

::

    :: key_hash : 'S   ->   contract unit : 'S

-  ``VOTING_POWER``: Return the voting power of a given contract. This voting power
   coincides with the weight of the contract in the voting listings (i.e., the rolls
   count) which is calculated at the beginning of every voting period.

::

    :: key_hash : 'S   ->   nat : 'S

Special operations
~~~~~~~~~~~~~~~~~~

-  ``NOW``: Push the minimal injection time for the current block,
   namely the block whose validation triggered this execution. The
   minimal injection time is 60 seconds after the timestamp of the
   predecessor block. This value does not change during the execution
   of the contract.

::

    :: 'S   ->   timestamp : 'S

-  ``CHAIN_ID``: Push the chain identifier.

::

    :: 'S   ->   chain_id : 'S

-  ``COMPARE``: Chain identifier comparison

::

    :: chain_id : chain_id : 'S   ->   int : 'S

    > COMPARE / x : y : S  =>  -1 : S
        iff x < y
    > COMPARE / x : y : S  =>  0 : S
        iff x = y
    > COMPARE / x : y : S  =>  1 : S
        iff x > y

-  ``LEVEL``: Push the level of the current transaction's block.

::

    :: 'S   ->   nat : 'S

-  ``TOTAL_VOTING_POWER``: Return the total voting power of all contracts. The total
   voting power coincides with the sum of the rolls count of every contract in the voting
   listings. The voting listings is calculated at the beginning of every voting period.

::

    :: 'S   ->   nat : 'S

Operations on bytes
~~~~~~~~~~~~~~~~~~~

Bytes are used for serializing data, in order to check signatures and
compute hashes on them. They can also be used to incorporate data from
the wild and untyped outside world.

-  ``PACK``: Serializes a piece of data to its optimized
   binary representation.

::

     :: 'a : 'S   ->   bytes : 'S

-  ``UNPACK 'a``: Deserializes a piece of data, if valid.

::

     :: bytes : 'S   ->   option 'a : 'S

-  ``CONCAT``: Byte sequence concatenation.

::

    :: bytes : bytes : 'S   -> bytes : 'S

    > CONCAT / s : t : S  =>  (s ^ t) : S

    :: bytes list : 'S   -> bytes : 'S

    > CONCAT / {} : S  =>  0x : S
    > CONCAT / { s ; <ss> } : S  =>  (s ^ r) : S
       where CONCAT / { <ss> } : S  =>  r : S

-  ``SIZE``: size of a sequence of bytes.

::

     :: bytes : 'S   ->   nat : 'S

-  ``SLICE``: Bytes access.

::

    :: nat : nat : bytes : 'S   -> option bytes : 'S

    > SLICE / offset : length : s : S  =>  Some ss : S
       where ss is the substring of s at the given offset and of the given length
         iff offset and (offset + length) are in bounds
    > SLICE / offset : length : s : S  =>  None : S
         iff offset or (offset + length) are out of bounds

-  ``COMPARE``: Lexicographic comparison.

::

    :: bytes : bytes : 'S   ->   int : 'S

    > COMPARE / s : t : S  =>  -1 : S
        iff s < t
    > COMPARE / s : t : S  =>  0 : S
        iff s = t
    > COMPARE / s : t : S  =>  1 : S
        iff s > t


Cryptographic primitives
~~~~~~~~~~~~~~~~~~~~~~~~

-  ``HASH_KEY``: Compute the b58check of a public key.

::

    :: key : 'S   ->   key_hash : 'S

-  ``BLAKE2B``: Compute a cryptographic hash of the value contents using the
   Blake2b-256 cryptographic hash function.

::

    :: bytes : 'S   ->   bytes : 'S

-  ``KECCAK``: Compute a cryptographic hash of the value contents using the
   Keccak-256 cryptographic hash function.

::

    :: bytes : 'S   ->   bytes : 'S

-  ``SHA256``: Compute a cryptographic hash of the value contents using the
   Sha256 cryptographic hash function.

::

    :: bytes : 'S   ->   bytes : 'S

-  ``SHA512``: Compute a cryptographic hash of the value contents using the
   Sha512 cryptographic hash function.

::

    :: bytes : 'S   ->   bytes : 'S

-  ``SHA3``: Compute a cryptographic hash of the value contents using the
   SHA3-256 cryptographic hash function.

::

    :: bytes : 'S   ->   bytes : 'S

-  ``CHECK_SIGNATURE``: Check that a sequence of bytes has been signed
   with a given key.

::

    :: key : signature : bytes : 'S   ->   bool : 'S

-  ``COMPARE``: Key hash, key and signature comparison

::

    :: key_hash : key_hash : 'S   ->   int : 'S
    :: key : key : 'S   ->   int : 'S
    :: signature : signature : 'S   ->   int : 'S

    > COMPARE / x : y : S  =>  -1 : S
        iff x < y
    > COMPARE / x : y : S  =>  0 : S
        iff x = y
    > COMPARE / x : y : S  =>  1 : S
        iff x > y

BLS12-381 primitives
~~~~~~~~~~~~~~~~~~~~~~~~

-  ``NEG``: Negate a curve point or field element.

::

    :: bls12_381_g1 : 'S -> bls12_381_g1 : 'S
    :: bls12_381_g2 : 'S -> bls12_381_g2 : 'S
    :: bls12_381_fr : 'S -> bls12_381_fr : 'S

-  ``ADD``: Add two curve points or field elements.

::

    :: bls12_381_g1 : bls12_381_g1 : 'S -> bls12_381_g1 : 'S
    :: bls12_381_g2 : bls12_381_g2 : 'S -> bls12_381_g2 : 'S
    :: bls12_381_fr : bls12_381_fr : 'S -> bls12_381_fr : 'S

-  ``MUL``: Multiply a curve point or field element by a scalar field element. Fr
   elements can be built from naturals by multiplying by the unit of Fr using ``PUSH bls12_381_fr 1; MUL``. Note
   that the multiplication will be computed using the natural modulo the order
   of Fr.

::

    :: bls12_381_g1 : bls12_381_fr : 'S -> bls12_381_g1 : 'S
    :: bls12_381_g2 : bls12_381_fr : 'S -> bls12_381_g2 : 'S
    :: bls12_381_fr : bls12_381_fr : 'S -> bls12_381_fr : 'S
    :: nat : bls12_381_fr : 'S -> bls12_381_fr : 'S
    :: int : bls12_381_fr : 'S -> bls12_381_fr : 'S
    :: bls12_381_fr : nat : 'S -> bls12_381_fr : 'S
    :: bls12_381_fr : int : 'S -> bls12_381_fr : 'S

- ``INT``: Convert a field element to type ``int``. The returned value is always between ``0`` (inclusive) and the order of Fr (exclusive).

::

    :: bls12_381_fr : 'S   ->   int : 'S

-  ``PAIRING_CHECK``:
   Verify that the product of pairings of the given list of points is equal to 1 in Fq12. Returns ``true`` if the list is empty.
   Can be used to verify if two pairings P1 and P2 are equal by verifying P1 * P2^(-1) = 1.

::

    :: list (pair bls12_381_g1 bls12_381_g2) : 'S -> bool : 'S


Sapling operations
~~~~~~~~~~~~~~~~~~

Please see the :doc:`Sapling integration<sapling>` page for a more
comprehensive description of the Sapling protocol.

-  ``SAPLING_VERIFY_UPDATE``: verify and apply a transaction on a Sapling state.

::

    :: sapling_transaction ms : sapling_state ms : 'S   ->   option (pair int (sapling_state ms)): 'S

    > SAPLING_VERIFY_UPDATE / t : s : S  =>  Some (Pair b s') : S
        iff the transaction t successfully applied on state s resulting
        in balance b and an updated state s'
    > SAPLING_VERIFY_UPDATE / t : s : S  =>  None : S
        iff the transaction t is invalid with respect to the state

-  ``SAPLING_EMPTY_STATE ms``: Pushes an empty state on the stack.

   ::

    ::  'S   ->   sapling_state ms: 'S

    > SAPLING_EMPTY_STATE ms /  S  =>  sapling_state ms : S
        with `sapling_state ms` being the empty state (ie. no one can spend tokens from it)
        with memo_size `ms`


.. _MichelsonTickets_012:

Operations on tickets
~~~~~~~~~~~~~~~~~~~~~

The following operations deal with tickets. Tickets are a way for smart-contracts
to authenticate data with respect to a Tezos address. This authentication can
then be used to build composable permission systems.

A contract can create a ticket from a value and an amount. The ticket, when
inspected reveals the value, the amount, and the address of the ticketer (the contract that created the ticket). It is
impossible for a contract to “forge” a ticket that appears to have been created
by another ticketer.

The amount is a meta-data that can be used to implement UTXOs.

Tickets cannot be duplicated using the ``DUP`` instruction.

For example, a ticket could represent a Non Fungible Token (NFT) or a Unspent
Transaction Output (UTXO) which can then be passed around and behave like a value.
This process can happen without the need to interact with a centralized NFT contract,
simplifying the code.

- ``TICKET``: Create a ticket with the given content and amount. The ticketer is the address
  of `SELF`.

::

   :: 'a : nat : 'S -> ticket 'a : 'S

Type ``'a`` must be comparable (the ``COMPARE`` primitive must be defined over it).

- ``READ_TICKET``: Retrieve the information stored in a ticket. Also return the ticket.

::

   :: ticket 'a : 'S -> pair address 'a nat : ticket 'a : 'S

- ``SPLIT_TICKET``: Delete the given ticket and create two tickets with the
  same content and ticketer as the original, but with the new provided amounts.
  (This can be used to easily implement UTXOs.)
  Return None iff the ticket's original amount is not equal to the sum of the
  provided amounts.

::

   :: ticket 'a : (pair nat nat) : 'S ->
   option (pair (ticket 'a) (ticket 'a)) : 'S

- ``JOIN_TICKETS``: The inverse of ``SPLIT_TICKET``. Delete the given tickets and create a ticket with an amount equal to the
  sum of the amounts of the input tickets.
  (This can be used to consolidate UTXOs.)
  Return None iff the input tickets have a different ticketer or content.

::

   :: (pair (ticket 'a) (ticket 'a)) : 'S ->
   option (ticket 'a) : 'S

Operations on timelock
~~~~~~~~~~~~~~~~~~~~~~

- ``OPEN_CHEST``: opens a timelocked chest given its key and the time. The results can be bytes
  if the opening is correct, or a boolean indicating whether the chest was incorrect,
  or its opening was. See :doc:`Timelock <timelock>` for more information.

::

   ::  chest_key : chest : nat : 'S -> or bytes bool : 'S



Removed instructions
~~~~~~~~~~~~~~~~~~~~

:doc:`../protocols/005_babylon` deprecated the following instructions. Because no smart
contract used these on Mainnet before they got deprecated, they have been
removed. The Michelson type-checker will reject any contract using them.

-  ``CREATE_CONTRACT { storage 'g ; parameter 'p ; code ... }``:
   Forge a new contract from a literal.

::

    :: key_hash : option key_hash : bool : bool : mutez : 'g : 'S
       -> operation : address : 'S

See the documentation of the new ``CREATE_CONTRACT`` instruction. The
first, third, and fourth parameters are ignored.

-  ``CREATE_ACCOUNT``: Forge an account creation operation.

::

    :: key_hash : option key_hash : bool : mutez : 'S
       ->   operation : address : 'S

Takes as argument the manager, optional delegate, the delegatable flag
and finally the initial amount taken from the currently executed
contract. This instruction originates a contract with two entrypoints;
``%default`` of type ``unit`` that does nothing and ``%do`` of type
``lambda unit (list operation)`` that executes and returns the
parameter if the sender is the contract's manager.

-  ``STEPS_TO_QUOTA``: Push the remaining steps before the contract
   execution must terminate.

::

    :: 'S   ->   nat : 'S

.. _MichelsonViews_012:

Operations on views
~~~~~~~~~~~~~~~~~~~~

Views are a mechanism for contract calls that:

- are read-only: they may depend on the storage of the contract declaring the view but cannot modify it nor emit operations (but they can call other views),
- take arguments as input in addition to the contract storage,
- return results as output,
- are synchronous: the result is immediately available on the stack of the caller contract.

In other words, the execution of a view is included in the operation of caller's contract, but accesses the storage of the declarer's contract, in read-only mode.
Thus, in terms of execution, views are more like lambda functions rather than contract entrypoints,
Here is an example:

::

    code {
    ...;
    TRANSFER_TOKENS;
    ...;
    VIEW "view_ex" unit;
    ...;
    };

This contract calls a contract ``TRANSFER_TOKENS``, and, later on, a view called "view_ex".
No matter if the callee "view_ex" is defined in the same contract with this caller contract or not,
this view will be executed immediately in the current operation,
while the operations emitted by ``TRANSFER_TOKENS`` will be executed later on.
As a result, although it may seem that "view_ex" receives the storage modified by ``TRANSFER_TOKENS``,
this is not the case.
In other words, the storage of the view is the same as when the current contract was called.
In particular, in case of re-entrance, i.e., if a contract A calls a contract B that calls a view on A, the storage of the view will be the same as when B started, not when A started.

Views are **declared** at the toplevel of the script of the contract on which they operate,
alongside the contract parameter type, storage type, and code.
To declare a view, the ``view`` keyword is used; its syntax is
``view name 'arg 'return { instr; ... }`` where:

- ``name`` is a string of at most 31 characters matching the regular expression ``[a-zA-Z0-9_.%@]*``; it is used to identify the view, hence it must be different from the names of the other views declared in the same script;
- ``'arg`` is the type of the argument of the view;
- ``'return`` is the type of the result returned by the view;
- ``{ instr; ... }`` is a sequence of instructions of type ``lambda (pair 'arg 'storage_ty) 'return`` where ``'storage_ty`` is the type of the storage of the current contract. Certain specific instructions have different semantics in ``view``: ``BALANCE`` represents the current amount of mutez held by the contract where ``view`` is; ``SENDER`` represents the contract which is the caller of ``view``; ``SELF_ADDRESS`` represents the contract where ``view`` is; ``AMOUNT`` is always 0 mutez.

Note that in both view input (type ``'arg``) and view output (type ``'return``), the following types are forbidden: ``ticket``, ``operation``, ``big_map`` and ``sapling_state``.

Views are **called** using the following Michelson instruction:

-  ``VIEW name 'return``: Call the view named ``name`` from the contract whose address is the second element of the stack, sending it as input the top element of the stack.

::

    :: 'arg : address : 'S  ->  option 'return : 'S

    > VIEW name 'return / x : addr : S  =>  Some y : S
        iff addr is the address of a smart contract c with storage s
        where c has a toplevel declaration of the form "view name 'arg 'return { code }"
        and code / Pair x s : []  =>  y : []

    > VIEW name 'return / _ : _ : S  =>  None : S
        otherwise



If the given address is nonexistent or if the contract at that address does not have a view of the expected name and type,
``None`` will be returned.
Otherwise, ``Some a`` will be returned where ``a`` is the result of the view call.
Note that if a contract address containing an entrypoint ``address%entrypoint`` is provided,
only the ``address`` part will be taken.
``operation``, ``big_map`` and ``sapling_state`` and ``ticket`` types are forbidden for the ``'return`` type.


Here is an example using views, consisting of two contracts.
The first contract defines two views at toplevel that are named ``add_v`` and ``mul_v``.

::

    { parameter nat;
      storage nat;
      code { CAR; NIL operation ; PAIR };
      view "add_v" nat nat { UNPAIR; ADD };
      view "mul_v" nat nat { UNPAIR; MUL };
    }


The second contract calls the ``add_v`` view of the above contract and obtains a result immediately.

::

    { parameter (pair nat address) ;
      storage nat ;
      code { CAR ; UNPAIR; VIEW "add_v" nat ;
             IF_SOME { } { FAIL }; NIL operation; PAIR }; }

Macros
------

In addition to the operations above, several extensions have been added
to the language's concrete syntax. If you are interacting with the node
via RPC, bypassing the client, which expands away these macros, you will
need to desugar them yourself.

These macros are designed to be unambiguous and reversible, meaning that
errors are reported in terms of desugared syntax. Below you'll see
these macros defined in terms of other syntactic forms. That is how
these macros are seen by the node.

Compare
~~~~~~~

Syntactic sugar exists for merging ``COMPARE`` and comparison
combinators, and also for branching.

-  ``CMP{EQ|NEQ|LT|GT|LE|GE}``

::

    > CMP(\op) / S  =>  COMPARE ; (\op) / S

-  ``IF{EQ|NEQ|LT|GT|LE|GE} bt bf``

::

    > IF(\op) bt bf / S  =>  (\op) ; IF bt bf / S

-  ``IFCMP{EQ|NEQ|LT|GT|LE|GE} bt bf``

::

    > IFCMP(\op) / S  =>  COMPARE ; (\op) ; IF bt bf / S

Fail
~~~~

The ``FAIL`` macros is equivalent to ``UNIT; FAILWITH`` and is callable
in any context since it does not use its input stack.

-  ``FAIL``

::

    > FAIL / S  =>  UNIT; FAILWITH / S

Assertion macros
~~~~~~~~~~~~~~~~

All assertion operations are syntactic sugar for conditionals with a
``FAIL`` instruction in the appropriate branch. When possible, use them
to increase clarity about illegal states.

-  ``ASSERT``

::

    > ASSERT  =>  IF {} {FAIL}

-  ``ASSERT_{EQ|NEQ|LT|LE|GT|GE}``

::

    > ASSERT_(\op)  =>  IF(\op) {} {FAIL}

-  ``ASSERT_CMP{EQ|NEQ|LT|LE|GT|GE}``

::

    > ASSERT_CMP(\op)  =>  IFCMP(\op) {} {FAIL}

-  ``ASSERT_NONE``

::

    > ASSERT_NONE  =>  IF_NONE {} {FAIL}

-  ``ASSERT_SOME``

::

    > ASSERT_SOME @x =>  IF_NONE {FAIL} {RENAME @x}

-  ``ASSERT_LEFT``

::

    > ASSERT_LEFT @x =>  IF_LEFT {RENAME @x} {FAIL}

-  ``ASSERT_RIGHT``

::

    > ASSERT_RIGHT @x =>  IF_LEFT {FAIL} {RENAME @x}

Syntactic Conveniences
~~~~~~~~~~~~~~~~~~~~~~

These macros are simply more convenient syntax for various common
operations.

-  ``P(\left=A|P(\left)(\right))(\right=I|P(\left)(\right))R``: A syntactic sugar
   for building nested pairs. In the case of right combs, `PAIR n` is more efficient.

::

    > PA(\right)R / S => DIP ((\right)R) ; PAIR / S
    > P(\left)IR / S => (\left)R ; PAIR / S
    > P(\left)(\right)R =>  (\left)R ; DIP ((\right)R) ; PAIR / S

A good way to quickly figure which macro to use is to mentally parse the
macro as ``P`` for pair constructor, ``A`` for left leaf and ``I`` for
right leaf. The macro takes as many elements on the stack as there are
leaves and constructs a nested pair with the shape given by its name.

Take the macro ``PAPPAIIR`` for instance:

::

    P A  P P A  I    I R
    ( l, ( ( l, r ), r ))

A typing rule can be inferred:

::

   PAPPAIIR
   :: 'a : 'b : 'c : 'd : 'S  ->  (pair 'a (pair (pair 'b 'c) 'd))

-  ``UNP(\left=A|P(\left)(\right))(\right=I|P(\left)(\right))R``: A syntactic sugar
   for destructing nested pairs. These macros follow the same convention
   as the previous one.

::

    > UNPA(\right)R / S => UNPAIR ; DIP (UN(\right)R) / S
    > UNP(\left)IR / S => UNPAIR ; UN(\left)R / S
    > UNP(\left)(\right)R => UNPAIR ; DIP (UN(\right)R) ; UN(\left)R / S

-  ``C[AD]+R``: A syntactic sugar for accessing fields in nested pairs. In the case of right combs, ``CAR k`` and ``CDR k`` are more efficient.

::

    > CA(\rest=[AD]+)R / S  =>  CAR ; C(\rest)R / S
    > CD(\rest=[AD]+)R / S  =>  CDR ; C(\rest)R / S

-  ``CAR k``: Access the ``k`` -th part of a right comb of size ``n > k + 1``. ``CAR 0`` is equivalent to ``CAR`` and in general ``CAR k`` is equivalent to ``k`` times the ``CDR`` instruction followed by once the ``CAR`` instruction. Note that this instruction cannot access the last element of a right comb; ``CDR k`` should be used for that.

::

    > CAR n / S  =>  GET (2n+1) / S

-  ``CDR k``: Access the rightmost element of a right comb of size ``k``. ``CDR 0`` is a no-op, ``CDR 1`` is equivalent to ``CDR`` and in general ``CDR k`` is equivalent to ``k`` times the ``CDR`` instruction. Note that on a right comb of size ``n > k >= 2``, ``CDR k`` will return the right comb composed of the same elements but the ``k`` leftmost ones.

::

    > CDR n / S  =>  GET (2n) / S

-  ``IF_SOME bt bf``: Inspect an optional value.

::

    > IF_SOME bt bf / S  =>  IF_NONE bf bt / S

-  ``IF_RIGHT bt bf``: Inspect a value of a union.

::

    > IF_RIGHT bt bf / S  =>  IF_LEFT bf bt / S

-  ``SET_CAR``: Set the left field of a pair. This is equivalent to ``SWAP; UPDATE 1``.

::

    > SET_CAR  =>  CDR ; SWAP ; PAIR

-  ``SET_CDR``: Set the right field of a pair. This is equivalent to ``SWAP; UPDATE 2``.

::

    > SET_CDR  =>  CAR ; PAIR

-  ``SET_C[AD]+R``: A syntactic sugar for setting fields in nested
   pairs. In the case of right combs, `UPDATE n` is more efficient.

::

    > SET_CA(\rest=[AD]+)R / S   =>
        { DUP ; DIP { CAR ; SET_C(\rest)R } ; CDR ; SWAP ; PAIR } / S
    > SET_CD(\rest=[AD]+)R / S   =>
        { DUP ; DIP { CDR ; SET_C(\rest)R } ; CAR ; PAIR } / S

-  ``MAP_CAR`` code: Transform the left field of a pair.

::

    > MAP_CAR code  =>  DUP ; CDR ; DIP { CAR ; code } ; SWAP ; PAIR

-  ``MAP_CDR`` code: Transform the right field of a pair.

::

    > MAP_CDR code  =>  DUP ; CDR ; code ; SWAP ; CAR ; PAIR

-  ``MAP_C[AD]+R`` code: A syntactic sugar for transforming fields in
   nested pairs.

::

    > MAP_CA(\rest=[AD]+)R code / S   =>
        { DUP ; DIP { CAR ; MAP_C(\rest)R code } ; CDR ; SWAP ; PAIR } / S
    > MAP_CD(\rest=[AD]+)R code / S   =>
        { DUP ; DIP { CDR ; MAP_C(\rest)R code } ; CAR ; PAIR } / S

Concrete syntax
---------------
.. _ConcreteSyntax_012:

The concrete language is very close to the formal notation of the
specification. Its structure is extremely simple: an expression in the
language can only be one of the five following constructs.

1. An integer in decimal notation.
2. A character string.
3. A byte sequence in hexadecimal notation prefixed by ``0x``.
4. The application of a primitive to a sequence of expressions.
5. A sequence of expressions.

This simple five cases notation is called :doc:`../shell/micheline`.

In the Tezos protocol, the primitive ``constant`` with a single
character string applied has special meaning. See
:doc:`global_constants`.

Constants
~~~~~~~~~

There are three kinds of constants:

1. Integers or naturals in decimal notation.
2. Strings, with some usual escape sequences: ``\n``, ``\\``,
   ``\"``. Unescaped line-breaks (both ``\n`` and ``\r``) cannot
   appear in a Michelson string. Moreover, the current version of
   Michelson restricts strings to be the printable subset of 7-bit
   ASCII, namely characters with codes from within `[32, 126]` range,
   plus the escaped characters mentioned above.
3. Byte sequences in hexadecimal notation, prefixed with ``0x``.

Differences with the formal notation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The concrete syntax follows the same lexical conventions as the
specification: instructions are represented by uppercase identifiers,
type constructors by lowercase identifiers, and constant constructors
are capitalized.

All domain specific constants are Micheline constants with specific
formats. Some have two variants accepted by the data type checker: a
readable one in a string and an optimized.

-  ``mutez`` amounts are written as naturals.
-  ``timestamp``\ s are written either using ``RFC3339`` notation
   in a string (readable), or as the number of seconds since Epoch
   in a natural (optimized).
-  ``contract``\ s, ``address``\ es, ``key``\ s and ``signature``\ s
   are written as strings, in their usual Base58 encoded versions
   (readable), or as their raw bytes (optimized).
-  ``bls12_381_g1``\ s and ``bls12_381_g2``\ s are written as their raw bytes, using a big-endian point encoding, `as specified here <https://docs.rs/bls12_381/latest/bls12_381/notes/serialization/index.html#bls12-381-serialization>`__.
-  ``bls12_381_fr``\ s are written as their raw bytes, using a little-endian encoding.

The optimized versions should not reach the RPCs, the protocol code
will convert to optimized by itself when forging operations, storing
to the database, and before hashing to get a canonical representation
of a datum for a given type.

To prevent errors, control flow primitives that take instructions as
parameters require sequences in the concrete syntax.

::

    IF { instr1_true ; instr2_true ; ... }
       { instr1_false ; instr2_false ; ... }

Main program structure
~~~~~~~~~~~~~~~~~~~~~~

The toplevel of a smart contract file must be an un-delimited sequence
of three primitive applications (in no particular order) that provide its
``code``, ``parameter`` and ``storage`` fields.

See the next section for a concrete example.

Annotations
-----------

The annotation mechanism of Michelson provides ways to better track
data on the stack and to give additional type constraints. Except for
a single exception specified just after, annotations are only here to
add constraints, *i.e.* they cannot turn an otherwise rejected program
into an accepted one. The notable exception to this rule is for
entrypoints: the semantics of the `CONTRACT` and `SELF` instructions vary depending on
their constructor annotations, and some contract origination may fail due
to invalid entrypoint constructor annotations.

Stack visualization tools like the Michelson's Emacs mode print
annotations associated with each type in the program, as propagated by
the typechecker as well as variable annotations on the types of elements
in the stack. This is useful as a debugging aid.

We distinguish three kinds of annotations:

- type annotations, written ``:type_annot``,
- variable annotations, written ``@var_annot``,
- and field or constructors annotations, written ``%field_annot``.

Type annotations
~~~~~~~~~~~~~~~~

Each type can be annotated with at most one type annotation. They are
used to give names to types. For types to be equal, their unnamed
version must be equal and their names must be the same or at least one
type must be unnamed.

For instance, the following Michelson program which put its integer
parameter in the storage is not well typed:

.. code-block:: michelson

    parameter (int :p) ;
    storage (int :s) ;
    code { UNPAIR ; SWAP ; DROP ; NIL operation ; PAIR }

Whereas this one is:

.. code-block:: michelson

    parameter (int :p) ;
    storage int ;
    code { UNPAIR ; SWAP ; DROP ; NIL operation ; PAIR }

Inner components of composed typed can also be named.

::

   (pair :point (int :x_pos) (int :y_pos))

Push-like instructions, that act as constructors, can also be given a
type annotation. The stack type will then have on top a type with a corresponding name.

::

   UNIT :t
   :: 'A -> (unit :t) : 'A

   PAIR :t
   :: 'a : 'b : 'S -> (pair :t 'a 'b) : 'S

   SOME :t
   :: 'a : 'S -> (option :t 'a) : 'S

   NONE :t 'a
   :: 'S -> (option :t 'a) : 'S

   LEFT :t 'b
   :: 'a : 'S -> (or :t 'a 'b) : 'S

   RIGHT :t 'a
   :: 'b : 'S -> (or :t 'a 'b) : 'S

   NIL :t 'a
   :: 'S -> (list :t 'a) : 'S

   EMPTY_SET :t 'elt
   :: 'S -> (set :t 'elt) : 'S

   EMPTY_MAP :t 'key 'val
   :: 'S -> (map :t 'key 'val) : 'S

   EMPTY_BIG_MAP :t 'key 'val
   :: 'S -> (big_map :t 'key 'val) : 'S


A no-op instruction ``CAST`` ensures the top of the stack has the
specified type, and change its type if it is compatible. In particular,
this allows to change or remove type names explicitly.

::

   CAST 'b
   :: 'a : 'S   ->   'b : 'S
      iff  'a = 'b

   > CAST t / a : S  =>  a : S


Variable annotations
~~~~~~~~~~~~~~~~~~~~

Variable annotations can only be used on instructions that produce
elements on the stack. An instruction that produces ``n`` elements on
the stack can be given at most ``n`` variable annotations.

The stack type contains both the types of each element in the stack, as
well as an optional variable annotation for each element. In this
sub-section we note:

- ``[]`` for the empty stack,
- ``@annot (top) : (rest)`` for the stack whose first value has type ``(top)`` and is annotated with variable annotation ``@annot`` and whose queue has stack type ``(rest)``.

The instructions which do not accept any variable annotations are:

::

   DROP
   SWAP
   DIG
   DUG
   IF_NONE
   IF_LEFT
   IF_CONS
   ITER
   IF
   LOOP
   LOOP_LEFT
   DIP
   FAILWITH

The instructions which accept at most one variable annotation are:

::

   DUP
   PUSH
   UNIT
   SOME
   NONE
   PAIR
   CAR
   CDR
   LEFT
   RIGHT
   NIL
   CONS
   SIZE
   MAP
   MEM
   EMPTY_SET
   EMPTY_MAP
   EMPTY_BIG_MAP
   UPDATE
   GET
   LAMBDA
   EXEC
   ADD
   SUB
   CONCAT
   MUL
   OR
   AND
   XOR
   NOT
   ABS
   ISNAT
   INT
   NEG
   EDIV
   LSL
   LSR
   COMPARE
   EQ
   NEQ
   LT
   GT
   LE
   GE
   ADDRESS
   CONTRACT
   SET_DELEGATE
   IMPLICIT_ACCOUNT
   NOW
   LEVEL
   AMOUNT
   BALANCE
   HASH_KEY
   CHECK_SIGNATURE
   BLAKE2B
   SOURCE
   SENDER
   SELF
   SELF_ADDRESS
   CAST
   RENAME
   CHAIN_ID

The instructions which accept at most two variable annotations are:

::

   UNPAIR
   CREATE_CONTRACT

Annotations on instructions that produce multiple elements on the stack
will be used in order, where the first variable annotation is given to
the top-most element on the resulting stack. Instructions that produce
``n`` elements on the stack but are given less than ``n`` variable
annotations will see only their top-most stack type elements annotated.

::

   UNPAIR @fist @second
   :: pair 'a 'b : 'S
      ->  @first 'a : @second 'b : 'S

   UNPAIR @first
   :: pair 'a 'b : 'S
      ->  @first 'a : 'b : 'S

A no-op instruction ``RENAME`` allows to rename variables in the stack
or to erase variable annotations in the stack.

::

   RENAME @new
   :: @old 'a ; 'S -> @new 'a : 'S

   RENAME
   :: @old 'a ; 'S -> 'a : 'S


Field and constructor annotations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Components of pair types, option types and or types can be annotated
with a field or constructor annotation. This feature is useful to encode
records fields and constructors of sum types.

::

   (pair :point
         (int %x)
         (int %y))

The previous Michelson type can be used as visual aid to represent the
record type (given in OCaml-like syntax):

::

   type point = { x : int ; y : int }

Similarly,

::

   (or :t
       (int %A)
       (or
          (bool %B)
          (pair %C
                (nat %n1)
                (nat %n2))))

can be used to represent the algebraic data type (in OCaml-like syntax):

::

   type t =
     | A of int
     | B of bool
     | C of { n1 : nat ; n2 : nat }


Field annotations are part of the type (at the same level as type name
annotations), and so types with differing field names (if present) are
not considered equal.

Instructions that construct elements of composed types can also be
annotated with one or multiple field annotations (in addition to type
and variable annotations).

::

   PAIR %fst %snd
   :: 'a : 'b : 'S -> (pair ('a %fst) ('b %snd)) : 'S

   LEFT %left %right 'b
   :: 'a : 'S -> (or ('a %left) ('b %right)) : 'S

   RIGHT %left %right 'a
   :: 'b : 'S -> (or ('a %left) ('b %right)) : 'S

To improve readability and robustness, instructions ``CAR`` and ``CDR``
accept one field annotation. For the contract to type check, the name of
the accessed field in the destructed pair must match the one given here.

::

   CAR %fst
   :: (pair ('a %fst) 'b) : S -> 'a : 'S

   CDR %snd
   :: (pair 'a ('b %snd)) : S -> 'b : 'S


Syntax
~~~~~~

Primitive applications can receive one or many annotations.

An annotation is a sequence of characters that matches the regular
expression ``@%|@%%|%@|[@:%][_0-9a-zA-Z][_0-9a-zA-Z\.%@]*``.
Note however that ``@%``, ``@%%`` and ``%@`` are
:ref:`special annotations <SpecialAnnotations_012>` and are not allowed everywhere.

Annotations come after the primitive name and before its potential arguments.

::

    (prim @v :t %x arg1 arg2 ...)


Ordering between different kinds of annotations is not significant, but
ordering among annotations of the same kind is. Annotations of the same
kind must be grouped together.

For instance these two annotated instructions are equivalent:

::

   PAIR :t @my_pair %x %y

   PAIR %x %y :t @my_pair

An annotation can be empty, in this case it will mean *no annotation*
and can be used as a wildcard. For instance, it is useful to annotate
only the right field of a pair instruction ``PAIR % %right`` or to
ignore field access constraints, *e.g.* in the macro ``UNPPAIPAIR %x1 %
%x3 %x4``.

Annotations and macros
~~~~~~~~~~~~~~~~~~~~~~

Macros also support annotations, which are propagated on their expanded
forms. As with instructions, macros that produce ``n`` values on the
stack accept ``n`` variable annotations.

::

   DUU+P @annot
   > DUU(\rest=U*)P @annot / S  =>  DIP (DU(\rest)P @annot) ; SWAP / S

   C[AD]+R @annot %field_name
   > CA(\rest=[AD]+)R @annot %field_name / S  =>  CAR ; C(\rest)R @annot %field_name / S
   > CD(\rest=[AD]+)R @annot %field_name / S  =>  CDR ; C(\rest)R @annot %field_name / S

   CMP{EQ|NEQ|LT|GT|LE|GE} @annot
   > CMP(\op) @annot / S  =>  COMPARE ; (\op) @annot / S

The variable annotation on ``SET_C[AD]+R`` and ``MAP_C[AD]+R`` annotates
the resulting toplevel pair while its field annotation is used to check
that the modified field is the expected one.

::

   SET_C[AD]+R @var %field
   > SET_CAR @var %field =>  CDR %field ; SWAP ; PAIR @var
   > SET_CDR @var %field =>  CAR %field ; PAIR @var
   > SET_CA(\rest=[AD]+)R @var %field / S   =>
     { DUP ; DIP { CAR ; SET_C(\rest)R %field } ; CDR ; SWAP ; PAIR @var } / S
   > SET_CD(\rest=[AD]+)R  @var %field/ S   =>
     { DUP ; DIP { CDR ; SET_C(\rest)R %field } ; CAR ; PAIR @var } / S

   MAP_C[AD]+R @var %field code
   > MAP_CAR code  =>  DUP ; CDR ; DIP { CAR %field ; code } ; SWAP ; PAIR @var
   > MAP_CDR code  =>  DUP ; CDR %field ; code ; SWAP ; CAR ; PAIR @var
   > MAP_CA(\rest=[AD]+)R @var %field code / S   =>
     { DUP ; DIP { CAR ; MAP_C(\rest)R %field code } ; CDR ; SWAP ; PAIR @var} / S
   > MAP_CD(\rest=[AD]+)R @var %field code / S   =>
    { DUP ; DIP { CDR ; MAP_C(\rest)R %field code } ; CAR ; PAIR @var} / S

Macros for nested ``PAIR`` accept multiple annotations. Field
annotations for ``PAIR`` give names to leaves of the constructed
nested pair, in order.  This next snippet gives examples instead of
generic rewrite rules for readability purposes.

::

   PAPPAIIR @p %x1 %x2 %x3 %x4
   :: 'a : 'b : 'c : 'd : 'S
      -> @p (pair ('a %x1) (pair (pair ('b %x) ('c %x3)) ('d %x4))) : 'S

   PAPAIR @p %x1 %x2 %x3
   :: 'a : 'b : 'c : 'S  ->  @p (pair ('a %x1) (pair ('b %x) ('c %x3))) : 'S

Annotations for nested ``UNPAIR`` are deprecated.

Automatic variable and field annotations inferring
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When no annotation is provided by the Michelson programmer, the
typechecker infers some annotations in specific cases. This greatly
helps users track information in the stack for bare contracts.

For unannotated accesses with ``CAR`` and ``CDR`` to fields that are
named will be appended (with an additional ``.`` character) to the pair
variable annotation.

::

   CDAR
   :: @p (pair ('a %foo) (pair %bar ('b %x) ('c %y))) : 'S ->  @p.bar.x 'b : 'S

If fields are not named but the pair is still named in the stack then
``.car`` or ``.cdr`` will be appended.

::

   CDAR
   :: @p (pair 'a (pair 'b 'c)) : 'S ->  @p.cdr.car 'b : 'S

If the original pair is not named in the stack, but a field annotation
is present in the pair type the accessed value will be annotated with a
variable annotation corresponding to the field annotation alone.

::

   CDAR
   :: (pair ('a %foo) (pair %bar ('b %x) ('c %y))) : 'S ->  @bar.x 'b : 'S

A similar mechanism is used for context dependent instructions:

::

   ADDRESS  :: @c contract _ : 'S   ->   @c.address address : 'S

   CONTRACT 'p  :: @a address : 'S   ->   @a.contract contract 'p : 'S

   BALANCE :: 'S   ->   @balance mutez : 'S

   SOURCE  :: 'S   ->   @source address : 'S

   SENDER  :: 'S   ->   @sender address : 'S

   SELF  :: 'S   ->   @self contract 'p : 'S

   SELF_ADDRESS  :: 'S   ->   @self address : 'S

   AMOUNT  :: 'S   ->   @amount mutez : 'S

   NOW  :: 'S   ->   @now timestamp : 'S

   LEVEL :: 'S  ->   @level nat : 'S

Inside nested code blocks, bound items on the stack will be given a
default variable name annotation depending on the instruction and stack
type (which can be changed). For instance the annotated typing rule for
``ITER`` on lists is:

::

   ITER body
   :: @l (list 'e) : 'A  ->  'A
      iff body :: [ @l.elt e' : 'A -> 'A ]

Special annotations
~~~~~~~~~~~~~~~~~~~
.. _SpecialAnnotations_012:

The special variable annotations ``@%`` and ``@%%`` can be used on instructions
``CAR``, ``CDR``, and ``UNPAIR``. It means to use the accessed field name (if any) as
a name for the value on the stack. The following typing rule
demonstrates their use for instruction ``CAR``.

::

   CAR @%
   :: @p (pair ('a %fst) ('b %snd)) : 'S   ->   @fst 'a : 'S

   CAR @%%
   :: @p (pair ('a %fst) ('b %snd)) : 'S   ->   @p.fst 'a : 'S

The special field annotation ``%@`` can be used on instructions
``PAIR``, ``LEFT`` and ``RIGHT``. It means to use the variable
name annotation in the stack as a field name for the constructed
element. Two examples with ``PAIR`` follows, notice the special
treatment of annotations with ``.``.

::

   PAIR %@ %@
   :: @x 'a : @y 'b : 'S   ->   (pair ('a %x) ('b %y)) : 'S

   PAIR %@ %@
   :: @p.x 'a : @p.y 'b : 'S   ->  @p (pair ('a %x) ('b %y)) : 'S
   :: @p.x 'a : @q.y 'b : 'S   ->  (pair ('a %x) ('b %y)) : 'S

Entrypoints
-----------

The specification up to this point has been mostly ignoring existence
of entrypoints: a mechanism of contract level polymorphism. This
mechanism is optional, non intrusive, and transparent to smart
contracts that don't use them. This section is to be read as a patch
over the rest of the specification, introducing rules that apply only
in presence of contracts that make use of entrypoints.

Defining and calling entrypoints
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Entrypoints piggyback on the constructor annotations. A contract with
entrypoints is basically a contract that takes a disjunctive type (a
nesting of ``or`` types) as the root of its input parameter, decorated
with constructor annotations. An extra check is performed on these
constructor annotations: a contract cannot define two entrypoints with
the same name.

An external transaction can include an entrypoint name alongside the
parameter value. In that case, if there is a constructor annotation
with this name at any position in the nesting of ``or`` types, the
value is automatically wrapped into the according constructors. If the
transaction specifies an entrypoint, but there is no such constructor
annotation, the transaction fails.

For instance, suppose the following input type.

``parameter (or (or (nat %A) (bool %B)) (or %maybe_C (unit %Z) (string %C)))``

The input values will be wrapped as in the following examples.

::

   +------------+-----------+---------------------------------+
   | entrypoint | input     | wrapped input                   |
   +------------+-----------+---------------------------------+
   | %A         | 3         | Left (Left 3)                   |
   | %B         | False     | Left (Right False)              |
   | %C         | "bob"     | Right (Right "bob")             |
   | %Z         | Unit      | Right (Left Unit)               |
   | %maybe_C   | Right "x" | Right (Right "x")               |
   | %maybe_C   | Left Unit | Right (Left Unit)               |
   +------------+-----------+---------------------------------+
   | not given  | value     | value (untouched)               |
   | %BAD       | _         | failure, contract not called    |
   +------------+-----------+---------------------------------+

The ``default`` entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~

A special semantics is assigned to the ``default`` entrypoint. If the
contract does not explicitly declare a ``default`` entrypoint, then it
is automatically assigned to the root of the parameter
type. Conversely, if the contract is called without specifying an
entrypoint, then it is assumed to be called with the ``default``
entrypoint. This behaviour makes the entrypoint system completely
transparent to contracts that do not use it.

This is the case for the previous example, for instance. If a value is
passed to such a contract specifying entrypoint ``default``, then the
value is fed to the contract untouched, exactly as if no entrypoint
was given.

A non enforced convention is to make the entrypoint ``default`` of
type unit, and to implement the crediting operation (just receive the
transferred tokens).

A consequence of this semantics is that if the contract uses the
entrypoint system and defines a ``default`` entrypoint somewhere else
than at the root of the parameter type, then it must provide an
entrypoint for all the paths in the toplevel disjunction. Otherwise,
some parts of the contracts would be dead code.

Another consequence of setting the entrypoint somewhere else than at
the root is that it makes it impossible to send the raw values of the
full parameter type to a contract. A trivial solution for that is to
name the root of the type. The conventional name for that is ``root``.

Let us recapitulate this by tweaking the names of the previous example.

``parameter %root (or (or (nat %A) (bool %B)) (or (unit %default) string))``

The input values will be wrapped as in the following examples.

::

   +------------+---------------------+-----------------------+
   | entrypoint | input               | wrapped input         |
   +------------+---------------------+-----------------------+
   | %A         | 3                   | Left (Left 3)         |
   | %B         | False               | Left (Right False)    |
   | %default   | Unit                | Right (Left Unit)     |
   | %root      | Right (Right "bob") | Right (Right "bob")   |
   +------------+---------------------+-----------------------+
   | not given  | Unit                | Right (Left Unit)     |
   | %BAD       | _                   | failure, contract not |
   +------------+---------------------+-----------------------+

Calling entrypoints from Michelson
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Michelson code can also produce transactions to a specific entrypoint.

For this, both types ``address`` and ``contract`` have the ability to
denote not just an address, but a pair of an address and an
entrypoint. The concrete notation is ``"address%entrypoint"``.
Note that ``"address"`` is strictly equivalent to ``"address%default"``,
and for clarity, the second variant is forbidden in the concrete syntax.

When the ``TRANSFER_TOKENS`` instruction is called, it places the
entrypoint provided in the contract handle in the transaction.

The ``CONTRACT t`` instruction has a variant ``CONTRACT %entrypoint
t``, that works as follows. Note that ``CONTRACT t`` is strictly
equivalent to ``CONTRACT %default t``, and for clarity, the second
variant is forbidden in the concrete syntax.

::

   +---------------+---------------------+------------------------------------------+
   | input address | instruction         | output contract                          |
   +---------------+---------------------+------------------------------------------+
   | "addr"        | CONTRACT t          | (Some "addr") if contract exists, has a  |
   |               |                     | default entrypoint of type t, or has no  |
   |               |                     | default entrypoint and parameter type t  |
   +---------------+---------------------+------------------------------------------+
   | "addr%name"   | CONTRACT t          | (Some "addr%name") if addr exists and    |
   +---------------+---------------------+ has an entrypoint %name of type t        |
   | "addr"        | CONTRACT %name t    |                                          |
   +---------------+---------------------+------------------------------------------+
   | "addr%_"      | CONTRACT %_ t       | None                                     |
   +---------------+---------------------+------------------------------------------+

Similarly, the ``SELF`` instruction has a variant ``SELF %entrypoint``,
that is only well-typed if the current contract has an entrypoint named ``%entrypoint``.

-  ``SELF %entrypoint``

::

    :: 'S   ->   contract 'p : 'S
       where   contract 'p is the type of the entrypoint %entrypoint of the current contract

Implicit accounts are considered to have a single ``default``
entrypoint of type ``Unit``.

JSON syntax
-----------

Micheline expressions are encoded in JSON like this:

-  An integer ``N`` is an object with a single field ``"int"`` whose
   value is the decimal representation as a string.

   ``{ "int": "N" }``

-  A string ``"contents"`` is an object with a single field ``"string"``
   whose value is the decimal representation as a string.

   ``{ "string": "contents" }``

-  A sequence is a JSON array.

   ``[ expr, ... ]``

- A primitive application is an object with two fields ``"prim"`` for
  the primitive name and ``"args"`` for the arguments (that must
  contain an array). A third optional field ``"annots"`` contains a
  list of annotations, including their leading ``@``, ``%`` or ``:``
  sign.

   ``{ "prim": "pair", "args": [ { "prim": "nat", "args": [] }, { "prim": "nat", "args": [] } ], "annots": [":t"] }``

As in the concrete syntax, all domain specific constants are encoded as
strings.

Examples
---------

Contracts in the system are stored as a piece of code and a global data
storage. The type of the global data of the storage is fixed for each
contract at origination time. This is ensured statically by checking on
origination that the code preserves the type of the global data. For
this, the code of the contract is checked to be of  type
``lambda (pair 'arg 'global) -> (pair (list operation) 'global)`` where
``'global`` is the type of the original global store given on origination.
The contract also takes a parameter and returns a list of internal operations,
hence the complete calling convention above. The internal operations are
queued for execution when the contract returns.

Empty contract
~~~~~~~~~~~~~~

The simplest contract is the contract for which the ``parameter`` and
``storage`` are all of type ``unit``. This contract is as follows:

.. code-block:: michelson

    code { CDR ;           # keep the storage
           NIL operation ; # return no internal operation
           PAIR };         # respect the calling convention
    storage unit;
    parameter unit;


Example contract with entrypoints
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The following contract maintains a number in its storage. It has two
entrypoints ``add`` and ``sub`` to modify it, and the default
entrypoint, of type ``unit`` will reset it to ``0``.

::

   { parameter (or (or (nat %add) (nat %sub)) (unit %default)) ;
     storage int ;
     code { AMOUNT ; PUSH mutez 0 ; ASSERT_CMPEQ ; UNPAIR ;
            IF_LEFT
              { IF_LEFT { ADD } { SWAP ; SUB } }
              { DROP ; DROP ; PUSH int 0 } ;
            NIL operation ; PAIR } }

Multisig contract
~~~~~~~~~~~~~~~~~

The multisig is a typical access control contract. The ownership of
the multisig contract is shared between ``N`` participants represented
by their public keys in the contract's storage. Any action on the
multisig contract needs to be signed by ``K`` participants where the
threshold ``K`` is also stored in the storage.

To avoid replay of the signatures sent to the contract, the signed
data include not only a description of the action to perform but also
the address of the multisig contract and a counter that gets
incremented at each successful call to the contract.

The multisig commands of :ref:`Tezos command line client <client_manual_012>`
use this
smart contract. Moreover, `functional correctness of this contract has
been verified
<https://gitlab.com/nomadic-labs/mi-cho-coq/blob/master/src/contracts_coq/multisig.v>`__
using the Coq proof assistant.


.. code-block:: michelson

   parameter (pair
                (pair :payload
                   (nat %counter) # counter, used to prevent replay attacks
                   (or :action    # payload to sign, represents the requested action
                      (pair :transfer    # transfer tokens
                         (mutez %amount) # amount to transfer
                         (contract %dest unit)) # destination to transfer to
                      (or
                         (option %delegate key_hash) # change the delegate to this address
                         (pair %change_keys          # change the keys controlling the multisig
                            (nat %threshold)         # new threshold
                            (list %keys key)))))     # new list of keys
                (list %sigs (option signature)));    # signatures

   storage (pair (nat %stored_counter) (pair (nat %threshold) (list %keys key))) ;

   code
     {
       UNPAIR ; SWAP ; DUP ; DIP { SWAP } ;
       DIP
         {
           UNPAIR ;
           # pair the payload with the current contract address, to ensure signatures
           # can't be replayed across different contracts if a key is reused.
           DUP ; SELF ; ADDRESS ; CHAIN_ID ; PAIR ; PAIR ;
           PACK ; # form the binary payload that we expect to be signed
           DIP { UNPAIR @counter ; DIP { SWAP } } ; SWAP
         } ;

       # Check that the counters match
       UNPAIR @stored_counter; DIP { SWAP };
       ASSERT_CMPEQ ;

       # Compute the number of valid signatures
       DIP { SWAP } ; UNPAIR @threshold @keys;
       DIP
         {
           # Running count of valid signatures
           PUSH @valid nat 0; SWAP ;
           ITER
             {
               DIP { SWAP } ; SWAP ;
               IF_CONS
                 {
                   IF_SOME
                     { SWAP ;
                       DIP
                         {
                           SWAP ; DIIP { DIP { DUP } ; SWAP } ;
                           # Checks signatures, fails if invalid
                           CHECK_SIGNATURE ; ASSERT ;
                           PUSH nat 1 ; ADD @valid } }
                     { SWAP ; DROP }
                 }
                 {
                   # There were fewer signatures in the list
                   # than keys. Not all signatures must be present, but
                   # they should be marked as absent using the option type.
                   FAIL
                 } ;
               SWAP
             }
         } ;
       # Assert that the threshold is less than or equal to the
       # number of valid signatures.
       ASSERT_CMPLE ;
       DROP ; DROP ;

       # Increment counter and place in storage
       DIP { UNPAIR ; PUSH nat 1 ; ADD @new_counter ; PAIR} ;

       # We have now handled the signature verification part,
       # produce the operation requested by the signers.
       NIL operation ; SWAP ;
       IF_LEFT
         { # Transfer tokens
           UNPAIR ; UNIT ; TRANSFER_TOKENS ; CONS }
         { IF_LEFT {
                     # Change delegate
                     SET_DELEGATE ; CONS }
                   {
                     # Change set of signatures
                     DIP { SWAP ; CAR } ; SWAP ; PAIR ; SWAP }} ;
       PAIR }



Full grammar
------------

::

    <data> ::=
      | <int constant>
      | <string constant>
      | <byte sequence constant>
      | Unit
      | True
      | False
      | Pair <data> <data> ...
      | Left <data>
      | Right <data>
      | Some <data>
      | None
      | { <data> ; ... }
      | { Elt <data> <data> ; ... }
      | instruction
    <natural number constant> ::=
      | [0-9]+
    <int constant> ::=
      | <natural number constant>
      | -<natural number constant>
    <string constant> ::=
      | "<string content>*"
    <string content> ::=
      | \"
      | \r
      | \n
      | \t
      | \b
      | \\
      | [^"\]
    <byte sequence constant> ::=
      | 0x[0-9a-fA-F]+
    <instruction> ::=
      | { <instruction> ... }
      | DROP
      | DROP <natural number constant>
      | DUP
      | DUP <natural number constant>
      | SWAP
      | DIG <natural number constant>
      | DUG <natural number constant>
      | PUSH <type> <data>
      | SOME
      | NONE <type>
      | UNIT
      | NEVER
      | IF_NONE { <instruction> ... } { <instruction> ... }
      | PAIR
      | PAIR <natural number constant>
      | CAR
      | CDR
      | UNPAIR
      | UNPAIR <natural number constant>
      | LEFT <type>
      | RIGHT <type>
      | IF_LEFT { <instruction> ... } { <instruction> ... }
      | NIL <type>
      | CONS
      | IF_CONS { <instruction> ... } { <instruction> ... }
      | SIZE
      | EMPTY_SET <comparable type>
      | EMPTY_MAP <comparable type> <type>
      | EMPTY_BIG_MAP <comparable type> <type>
      | MAP { <instruction> ... }
      | ITER { <instruction> ... }
      | MEM
      | GET
      | GET <natural number constant>
      | UPDATE
      | UPDATE <natural number constant>
      | IF { <instruction> ... } { <instruction> ... }
      | LOOP { <instruction> ... }
      | LOOP_LEFT { <instruction> ... }
      | LAMBDA <type> <type> { <instruction> ... }
      | EXEC
      | APPLY
      | DIP { <instruction> ... }
      | DIP <natural number constant> { <instruction> ... }
      | FAILWITH
      | CAST
      | RENAME
      | CONCAT
      | SLICE
      | PACK
      | UNPACK <type>
      | ADD
      | SUB
      | MUL
      | EDIV
      | ABS
      | ISNAT
      | INT
      | NEG
      | LSL
      | LSR
      | OR
      | AND
      | XOR
      | NOT
      | COMPARE
      | EQ
      | NEQ
      | LT
      | GT
      | LE
      | GE
      | SELF
      | SELF_ADDRESS
      | CONTRACT <type>
      | TRANSFER_TOKENS
      | SET_DELEGATE
      | CREATE_CONTRACT { <instruction> ... }
      | IMPLICIT_ACCOUNT
      | VOTING_POWER
      | NOW
      | LEVEL
      | AMOUNT
      | BALANCE
      | CHECK_SIGNATURE
      | BLAKE2B
      | KECCAK
      | SHA3
      | SHA256
      | SHA512
      | HASH_KEY
      | SOURCE
      | SENDER
      | ADDRESS
      | CHAIN_ID
      | TOTAL_VOTING_POWER
      | PAIRING_CHECK
      | SAPLING_EMPTY_STATE <natural number constant>
      | SAPLING_VERIFY_UPDATE
      | TICKET
      | READ_TICKET
      | SPLIT_TICKET
      | JOIN_TICKETS
      | OPEN_CHEST
    <type> ::=
      | <comparable type>
      | option <type>
      | list <type>
      | set <comparable type>
      | operation
      | contract <type>
      | ticket <comparable type>
      | pair <type> <type> ...
      | or <type> <type>
      | lambda <type> <type>
      | map <comparable type> <type>
      | big_map <comparable type> <type>
      | bls12_381_g1
      | bls12_381_g2
      | bls12_381_fr
      | sapling_transaction <natural number constant>
      | sapling_state <natural number constant>
      | chest
      | chest_key
    <comparable type> ::=
      | unit
      | never
      | bool
      | int
      | nat
      | string
      | chain_id
      | bytes
      | mutez
      | key_hash
      | key
      | signature
      | timestamp
      | address
      | option <comparable type>
      | or <comparable type> <comparable type>
      | pair <comparable type> <comparable type> ...


Reference implementation
------------------------

The language is implemented in OCaml as follows:

-  The lower internal representation is written as a GADT whose type
   parameters encode exactly the typing rules given in this
   specification. In other words, if a program written in this
   representation is accepted by OCaml's typechecker, it is guaranteed
   type-safe. This is of course also valid for programs not
   handwritten but generated by OCaml code, so we are sure that any
   manipulated code is type-safe.

   In the end, what remains to be checked is the encoding of the typing
   rules as OCaml types, which boils down to half a line of code for
   each instruction. Everything else is left to the venerable and well
   trusted OCaml.

-  The interpreter is basically the direct transcription of the
   rewriting rules presented above. It takes an instruction, a stack and
   transforms it. OCaml's typechecker ensures that the transformation
   respects the pre and post stack types declared by the GADT case for
   each instruction.

   The only things that remain to be reviewed are value dependent
   choices, such as we did not swap true and false when
   interpreting the IF instruction.

-  The input, untyped internal representation is an OCaml ADT with
   only 5 grammar constructions: ``String``, ``Int``, ``Bytes``, ``Seq`` and
   ``Prim``. It is the target language for the parser, since not all
   parsable programs are well typed, and thus could simply not be
   constructed using the GADT.

-  The typechecker is a simple function that recognizes the abstract
   grammar described in section X by pattern matching, producing the
   well-typed, corresponding GADT expressions. It is mostly a checker,
   not a full inferrer, and thus takes some annotations (basically the
   input and output of the program, of lambdas and of uninitialized maps
   and sets). It works by performing a symbolic evaluation of the
   program, transforming a symbolic stack. It only needs one pass over
   the whole program.

   Here again, OCaml does most of the checking, the structure of the
   function is very simple, what we have to check is that we transform a
   ``Prim ("If", ...)`` into an ``If``, a ``Prim ("Dup", ...)`` into a
   ``Dup``, etc.
