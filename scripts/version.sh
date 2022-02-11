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
export full_opam_repository_tag=1c55af16c8ffc84a4dfc35b256be9818f7dbe21a

## opam_repository is an additional, tezos-specific opam repository.
## This value MUST be the same as `build_deps_image_version` in `.gitlab-ci.yml
export opam_repository_url=https://github.com/ocaml-multicore/tezos-opam-repository
export opam_repository_tag=a1545517aa61be25303cd4e8731dc22f000887f8
export opam_repository_git=$opam_repository_url.git
export opam_repository=$opam_repository_git\#update-24-01


## for sapling param, fork is on github, url convention not the same in install_sapling_parameters
raw_opam_repository_url=https://raw.githubusercontent.com/ocaml-multicore/tezos-opam-repository/4.12.0%2Bdomains

## Other variables, used both in Makefile and scripts
export COVERAGE_OUTPUT=_coverage_output
