#! /bin/sh

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

export ocaml_version=4.12.0+domains
export opam_version=2
export recommended_rust_version=1.52.1
export recommended_node_version=14.12.0

## full_opam_repository is a commit hash of the public OPAM repository, i.e.
## https://github.com/ocaml/opam-repository
export full_opam_repository_tag=b0287f75170afa0e21bf5a38e0ff0e90e0244c49

## opam_repository is an additional, tezos-specific opam repository.

## This value MUST be the same as `build_deps_image_version` in `.gitlab-ci.yml
export opam_repository_url=https://github.com/ocaml-multicore/tezos-opam-repository
export opam_repository_tag=4138659057683d257e65ba887dd2e65cee9e37dc
export opam_repository_git=$opam_repository_url.git
export opam_repository=$opam_repository_git\#$opam_repository_tag


## for sapling param, fork is on github, url convention not the same in install_sapling_parameters
raw_opam_repository_url=https://raw.githubusercontent.com/ocaml-multicore/tezos-opam-repository/4.12.0%2Bdomains

## Other variables, used both in Makefile and scripts
export COVERAGE_OUTPUT=_coverage_output

## for sapling param, fork is on github, url convention not the same in install_sapling_parameters
raw_opam_repository_url=https://raw.githubusercontent.com/ocaml-multicore/tezos-opam-repository/4.12.0%2Bdomains