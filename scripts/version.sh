#! /bin/sh

## `ocaml-version` should be in sync with `README.rst` and
## `lib.protocol-compiler/tezos-protocol-compiler.opam`

ocaml_version=4.12.0+multicore
opam_version=2.0
recommended_rust_version=1.44.0

## full_opam_repository is a commit hash of the public OPAM repository, i.e.
## https://github.com/ocaml/opam-repository
full_opam_repository_tag=7026cc03199e7315b5ec592610650ff85c21cd90

## opam_repository is an additional, tezos-specific opam repository.
## This value MUST be the same as `build_deps_image_version` in `.gitlab-ci.yml
opam_repository_url=https://github.com/Engil/tezos-opam-repository-412
opam_repository_git=$opam_repository_url.git
opam_repository=$opam_repository_git

## Other variables, used both in Makefile and scripts
COVERAGE_OUTPUT=_coverage_output
