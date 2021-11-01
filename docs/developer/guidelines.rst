Coding guidelines
=================

This document provides guidelines that should be observed by all the contributors to the Tezos codebase. It first presents documentation guidelines, and then rules more specific to coding (e.g., logging levels, code formatting, naming conventions, etc.).

License
-------

The Tezos software is distributed under the MIT license. Every OCaml source file should start with a header comment instantiating the following template (use appropriate comment syntax for other languages):

.. literalinclude:: LICENSE.ml

Note that:

- The holder, on the copyright line, is the name of the company which hires the employee or the sub-contractor.
- For sub-contractors, check your specific contract terms. They sometimes allow to include, as an additional copyright holder, the name of a particular developer, but consider that this may end up with bloated license headers.
- When adding a significant new contribution to a file (i.e. more like whole new features, rather than simple fixes), check whether there already is a copyright for your copyright holder (see above).

  + If there is one, mentioning any year, it is not required to add the current year (but this is allowed). In no case should you *replace* the existing year with the current one.
  + If there is no line for your copyright holder, you should add one, with the current year.

- Old source files may contain on the first line `Open Source License` instead of `MIT License`. When touching such a file, please replace the former with the latter, correct form.

For example, for a source file with multiple contributors spanning several years, the copyright lines may look as follows::

  (* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
  (* Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>           *)
  (* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)


.. _in_code_comments:

Comments in the code
--------------------

The OCaml code should include comments facilitating the comprehension and the maintenance. In particular, the main syntactic constructs in the code should be commented as follows.

Modules:

- One-line comment explaining the purpose of the module
- If needed: More detailed description

Types:

- One-line comment explaining what the type represents, typically the invariants satisfied by its inhabitants

Functions and methods:

- Purpose of the function, brief description of the returned value
- If needed: How and why to use this function
- If needed: Pre-conditions for calling the function
- If needed: Conditions under which the function will return an error
- If needed: Any special behavior that is not obvious

Constants and struct fields:

- Purpose and definition of this data. If the unit is a measurement of time, include it, e.g., TIMEOUT_MS for timeout in milliseconds.

.. _todo_fixme:

TODO/FIXME comments
~~~~~~~~~~~~~~~~~~~

During the :ref:`code review process <code_review>`, follow-up issues may be created to improve some piece of code that already implement its specification (e.g., optimize, refactor, or bring a potentially useful generalization).
When the place of the future evolution is known in advance (e.g. a given function), you should mark it with a ``TODO`` comment of the form::

    (* TODO: <reference to issue>
       <one-line explanation>
       <Add long explanation if the issue description is not the right place.>
    *)

If the evolution is needed to fix some code that does *not* fully implement its specification, (e.g., a known bug detected but not yet fixed, or a temporary implementation handling only some particular cases), rather than to merely improve the code, you should use a ``FIXME`` tag instead of the ``TODO``, adhering to the same syntax for the rest.

Thus, the difference between ``TODO`` and ``FIXME`` tags is a semantic one,  reflecting the full/partial implementation of the specification.
Consequently, when the specification evolves to become more demanding, some ``TODO`` tags corresponding to *potential* evolutions may have to be recasted as ``FIXME`` tags, corresponding to *required* evolutions.

Note that the reference to an existing issue on the first line is mandatory, to facilitate searches of evolutions corresponding to given issues, and might be checked automatically by the :ref:`Merge-Request Bot <merge_bot>`.
The reference to an issue may be one of:

- a URL such as ``https://gitlab.com/tezos/tezos/-/issues/1377``
- a GitLab notation such as ``#123`` (implicitly under ``tezos/tezos``), ``michelson-reference#123`` (implicitly under ``tezos/michelson-reference``),
  or ``oxheadalpha/merbocop#123`` (fully qualified).

Documenting interfaces and implementations
------------------------------------------

At the granularity of OCaml files, it is essential to document the interface implemented by each file.
In many cases, it is useful to also document the implementation, but *separately* from the interface.

Implementation (``.ml``) files:

- Document the interface:

  + In the common case where there is a corresponding interface (``.mli``) file,
    document the interface file instead, as detailed below.
  + In the less common case where there is no corresponding interface (``.mli``)
    file, document the exported elements directly in the implementation
    (``.ml``) file.

- Document the implementation: For many non-trivial implementations, it is most useful to document the design principles, code structure, internal invariants, and so on.
  Such information should be placed in a comment block at the top of the file.

Interface (``.mli``) file comments:

- One-line description
- Brief description of the library, introducing the needed concepts
- Brief description of each module, type, function, data, as described for :ref:`comments in the code<in_code_comments>`
- If applicable, external invariants (i.e., visible to the user).

README files
------------

At coarser levels, source file directories should be documented by Markdown files called ``README.md``. Such files are mandatory in top-level directories of the Tezos codebase (such as ``src/`` and ``docs/``), and at least in immediate sub-directories of the source directory (``src/*/``).

Source directories must instantiate the following ``README.md`` template::

  # Component Name
  <!-- Summary line: One sentence about this component. -->

  ## Overview
  <!--
  - Describe the purpose of this component and how the code in this directory
    works. If needed, design rationale for its API.
  - Describe the interaction of the code in this directory with the other
    components. This includes dependencies on other components, for instance.
  - Describe the security model and assumptions about the crates in this
    directory.
  -->

  ## Implementation Details
  <!--
  - Describe how the component is modeled.
  - Describe the code structure and implementation design rationale.
  - Other relevant implementation details (e.g. global invariants).
  - Testing specifics, if needed.
  -->

  ## API Documentation
  <!--
  - Link to the external API.
  - For the top-level source directory, link to the most important APIs within.
  -->

The rationale of this template is that a README file addresses two different kinds of developers:

#. the users of the module, which are concerned only about the component
   concepts and API, and not about its implementations details, and
#. the developers and maintainers of the module, which are also concerned about
   implementation details.

When filling in the template, you should keep untouched the guidelines within
HTML comments (which are visible to the document maintainers but invisible to
end-users), so that any maintainer can check how well the README instantiates
the template, and address any gap if needed.

Logging Levels
--------------

The Tezos libraries use an logging library with 5 different verbosity `levels`
defined in ``src/lib_event_logging/internal_event.mli`` for shell and
``src/lib_protocol_environment/sigs/v3/logging.mli`` for protocol code.

It is important to choose the appropriate level for each event in the code to
avoid flooding the node administrator with too much information.

These are the rules-of-thumb that we use in the code to decide the appropriate
level (here listed from most to least verbose) for each event:

- ``Debug`` level -- the most verbose -- it is used by developers to follow
  the flow of execution of the node at the lowest granularity.
- ``Info`` level is about all the additional information that you might want to
  have, but they are not important to have if your node is running OK
  (and definitely do not require any action).
- ``Notice`` level (the default) should be about things that the node
  admin should be concerned, but that does not require any action.

The two following levels are used to provide information to the node
administrator of possible problems and errors:

- ``Warning`` level are all those events that might require the attention of
  the node administrator, and can reveal potential anomalies in the workings of
  the node.
- ``Error`` level are all those events that require an intervention of the node
  administrator or that signal some exceptional circumstance.

There is another level ``Fatal`` with the highest priority but it is rarely
relevant. Specifically, ``Fatal`` should be reserved for errors that can
absolutely not be recovered. All logging at the ``Fatal`` level should be
immediately followed by a call to ``Lwt_exit.exit_and_raise``.

Note that a library is never able to decide whether a certain condition is fatal
or not. Indeed, the application that calls into the library may not consider the
function call as essential to the continuation of the application's main
purpose. Consequently, ``Fatal`` should never be used within libraries.


Code formatting
---------------

To ensure that your OCaml code is well formatted, set up correctly your editor:

+ automatically run `ocamlformat` when saving a file
+ no tabs, use whitespaces
+ no trailing whitespaces
+ indent correctly (e.g. use lisp-mode for dune files)

Many of these checks can be run with ``make check-python-linting``.

Some of these checks can be executed with a `pre-commit <https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks>`_
which is installed with
``ln -sr scripts/pre_commit/pre_commit.py .git/hooks/pre-commit``
(see the header of `./scripts/pre_commit/pre_commit.py` and its `--help`
for additional options).

Exposing internals
------------------

Sometimes you want to expose some internal functions, types or sub-modules of a module: usually it is for testing part of the module logic, but it may also be to let some power users access internals (for performance, extra-functionality, or any other reason).

A first question you should ask yourself is: "Is this a hint that my module has too many responsibilities?".

If the answer is yes: consider splitting your module per responsibility and see if you still need to expose internals.

If the answer is no: the guideline is to expose an internal module as part of your API:

+ ``Internal_for_tests`` for internal types, functions and sub-modules that are only meant to be accessed by tests
+ ``Internal`` for internal types, functions and sub-modules that are meant to be accessed by production code (but may also be accessed by tests)

Additionally you should add the ``(**/**)`` `Stop special comment <https://ocaml.org/manual/ocamldoc.html#ss:ocamldoc-stop>`_ so that this module is
not displayed in the public module documentation.

The rationale of ``Internal_for_tests`` is to make it explicit both for developers writing code and for reviewers that this module must not be used in production code.

Example:

.. code-block:: ocaml
  :emphasize-lines: 6,8-20,35-43

   (* mli *)
   type t

   val f : t -> u

   (**/**)

   module Internal_for_tests : sig
     (** The actual representation of [t] *)
     type t_raw = {bar : string; baz : int}

     (** Access inner fields of a value of type [t] *)
     val unwrap : t -> t_raw

     (** An internal function that we want to test in isolation *)
     val g : t -> v

     (** You can also expose internal modules, e.g. the inner cache *)
     module Mycache : Cache.S
   end

   (* ml *)
   module Mycache = Cache.Make ...

   type t = {bar : string; baz : int}

   (* [g] is an internal function, not part of the public API *)
   let g t = ...

   (* [f] uses internal function [g] *)
   let f t =
     let w = g t in
     ...

   module Internal_for_tests = struct
     type t_raw = t = {bar : string; baz : int}

     let unwrap t = t

     let g = g

     module Mycache = Mycache
   end

Exceptions and errors
---------------------

The following pieces of advice should be applied in general, although exceptions apply (pun intended).

- Only use exceptions locally and don't let them escape: raise them and catch them within the same function or the same module.

  - If a function that is exported can fail, return a ``result`` or a ``tzresult``.

  - If you cannot (or for another reason do not) handle an exception and it may escape you **must** document it.

- Never catch ``Stack_overflow`` nor ``Out_of_memory`` which are exceptions from
  the OCaml runtime rather than the code itself. In other words, when one of
  these exception is raised in one process, the same exception may or may not be
  raised in another process executing the same code on other machines. When you
  catch this exception, you make a branching in the code that is decided not
  based on properties of the code, but properties of the process executing the
  code. Consequently, the same branching may differ on two distinct runs of the
  same code. This is, in essence, non-determinism.

  - If you are in one of the small cases where non-determinism is ok and you
    have a compelling reason to catch either ``Stack_overflow`` or
    ``Out_of_memory``, you **must** include a comment explaining why.

  - Note that catch-all patterns (such as wildcard (`| _ ->`) and variable
    (`| exn ->`) include ``Stack_overflow`` and ``Out_of_memory``.

- Do not let low-level, implementation-dependent exceptions and errors bubble up
  to high-level code. For example, you should catch ``Unix_error`` near the
  syscall sites (ideally, within the same module) and handle it there. If you
  cannot handle it (e.g., if the error is non-recoverable) you should translate
  it into an error that is more relevant to the high-level code.

  - E.g., If a file-writing call to a library function raises
    ``Unix_error(ENOSPC, _, _)``, the caller of that library function should

    - catch the exception,

    - attempt to recover (if possible; e.g., by removing other old files before attempting it again),

    - and if the recovery does not work (e.g., does not release sufficient
      space) or is impossible (e.g., there are no references to old files in
      scope) then it should fail in a more meaningful way than by forwarding the
      exception (e.g., indicating what operation it was trying to carry).

  - In the rare case that the underlying exception/error is satisfactory to the
    higher level code, then you may propagate it as is.

The ``Lwtreslib`` and the ``Error_monad`` libraries provide functions that can
help you follow these guidelines. Notably, ``traces`` allow callers to
contextualise the errors produced by its callees.

.. _rpc_security:

RPC security
------------

During the development of the codebase a lot of RPC endpoints were created, some
of which are responsible for delicate or computationally intense tasks like
validating blocks or executing Michelson scripts. While some of them are
necessary for the node's users to interact with the blockchain, others are there
to expose API to processes responsible for baking and endorsing, for
configuration or debugging purposes or to facilitate development of smart
contracts.

In order to mitigate risks related to exposing these endpoints, Access Control
Lists (ACL for short) were introduced to limit the scope of the API exposed to
public networks (see also :ref:`configure_rpc`). While node administrators are
free to configure these ACLs however they like, there is :ref:`the default ACL
<default_acl>`, which lists all the endpoints that are **exposed by default**.

When adding a new RPC endpoint, please consider whether or not there is a reason
to call it over a public network. If the answer is yes, you should probably
consider adding the new endpoint to the ACL. If there are also risks related to
calling the endpoint by a potentially malicious user, they should be weighed
when making the decision too. There are no simple answers here. Remember that
all new endpoints are **blocked by default** unless explicitly added to the ACL.

When changing an existing public RPC endpoint it is also important to consider,
how does the change impact possible risks related to calling the endpoint.
Should it be removed from the ACL?

.. _RPC-versioning-dev:

RPC Versioning
--------------

General information about RPC versioning can be found in
:doc:`../user/versioning`.

How to Version an RPC
~~~~~~~~~~~~~~~~~~~~~

If an RPC already has a query parameter ``version``, just add a
variant to the corresponding type ``t_with_version`` (see
:ref:`RPC-versioning-dev-adding-an-rpc`). Otherwise, the ``version``
query parameter should be added (a natural number starting from
``0``). See example `here
<https://gitlab.com/tezos/tezos/-/merge_requests/3480>`_.

For versioning an RPC which returns a type ``t``, you have to write in
the service module of the RPC a type ``t_with_version`` which has one
constructor by version. The encoding of ``t_with_version`` is simply
constructed using the ``Data_encoding.union`` function.

To ensure that the implementation of the RPC (the directory module)
uses the version parameter we recommend that ``t_with_version`` is
abstract and a dispatcher is written in the service file. This way,
when a new version is added, only the dispatcher function needs to be
updated. In general, the type for this dispatcher will be:

.. code-block:: ocaml

   val t_dispatcher : t -> ~version:int -> t_with_version

A similar process can be followed to modify the input of an RPC.
However, in that case, the semantics of ``union`` makes the parameter
``version`` optional (all versions are supported by default). It is
still interesting to version RPCs to allow removing older versions in the
future.

Notice that we use only one version number for both input and output
of an RPC.

.. _RPC-versioning-dev-adding-an-rpc:

When to Add a New Version to an RPC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you modify the input or the output of an RPC, it is not always
necessary to create a new version for the RPC. A new version should be
brought in when a **breaking change** is introduced. Assume that an
RPC returns the following JSON value:

.. code-block:: json

    {
      "foo": 5,
      "bar": {
        "baz": 10
      }
    }

If you introduce a new field ``foobar`` like this:

.. code-block:: json

    {
      "foo": 5,
      "bar": {
        "baz": 10,
        "foobar" : 5
      }
    }

it should not be considered a breaking change. Indeed, many
decoders which accept the former value also accept the latter.

However, if you remove a field or change the encoding of a field in a
non-extensible way as above, it should be considered a breaking change
like the two examples below.

.. code-block:: json

    {
      "foo": "bar",
      "bar": {
        "baz": 10
      }
    }

.. code-block:: json

    {
      "bar": {
        "baz": 10
      }
    }

Coding conventions
------------------

Other than the guidelines above, there are currently no coding
conventions enforced in the codebase. However, Tezos developers should be aware
of general `OCaml programming guidelines <https://caml.inria.fr/resources/doc/guides/guidelines.en.html>`_, which recommend formatting, naming conventions,
and more.
