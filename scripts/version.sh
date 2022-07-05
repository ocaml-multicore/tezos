#!/bin/sh

## This script is not meant to be executed interactively. Instead it is meant to
## be used in other scripts to provide common variables for version numbers and
## hashes.
##
## Typical use:
## . "$script_dir"/version.sh

## `ocaml-version` should be in sync with `README.rst` and
## `lib.protocol-compiler/tezos-protocol-compiler.opam`
##
## This script is also sourced in the Makefile, as such it should be compatible
## with both the make and sh syntax

export ocaml_version=5.0.0~alpha0
export opam_version=2
export recommended_rust_version=1.52.1
export recommended_node_version=14.12.0

## full_opam_repository is a commit hash of the public OPAM repository, i.e.
## https://github.com/ocaml/opam-repository
export full_opam_repository_tag=1e2c428e84d3ab514163688b396de0fea01e224a

## opam_repository is an additional, tezos-specific opam repository.
## This value MUST be the same as `build_deps_image_version` in `.gitlab/ci/templates.ym
export opam_repository_url=https://github.com/ocaml-multicore/tezos-opam-repository
export opam_repository_tag=latest-alpha0
export opam_repository_git=$opam_repository_url.git
export opam_repository=$opam_repository_git\#$opam_repository_tag

## Other variables, used both in Makefile and scripts
export COVERAGE_OUTPUT=_coverage_output

export sapling_output_parameters_sha256=2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4
export sapling_spend_parameters_sha256=8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13
