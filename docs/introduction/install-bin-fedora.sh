#!/bin/sh

# TODO tezos/tezos#2170: search shifted protocol name/number & adapt
set -e
set -x
# [install prerequisites]
dnf install -y dnf-plugins-core
# [setup repository]
dnf copr enable -y @Serokell/Tezos && dnf update -y
# [install tezos]
dnf install -y tezos-client
dnf install -y tezos-node
dnf install -y tezos-baker-011-PtHangz2
dnf install -y tezos-endorser-011-PtHangz2
dnf install -y tezos-accuser-011-PtHangz2
