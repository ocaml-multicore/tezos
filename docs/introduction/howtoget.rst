.. TODO tezos/tezos#2170: search shifted protocol name/number & adapt

.. _howtoget:

How to get Tezos
================

In this how-to we explain how to get up-to-date binaries to run Tezos
(more precisely, the "Octez" implementation of Tezos software)
on any network (either on the mainnet or on one of the test networks).
Tezos consists of :ref:`several binaries <tezos_binaries>` (i.e., executable files), including: a client, a node, a baker, and an endorser.

There are several options for getting the binaries, depending on how you plan to use Tezos:

- :ref:`getting static binaries <getting_static_binaries>`.
  This is the easiest way to get native binaries for the latest stable release,
  requiring no dependencies, under Linux.
- :ref:`installing binaries <installing_binaries>`.
  This is the easiest way to install native binaries for the latest stable release, together with their dependencies, using a package manager.
- :ref:`using docker images <using_docker_images>`.
  This is the easiest way to run the latest stable release of the binaries in
  Docker containers, on any OS supported by Docker.
- :ref:`building the binaries via the OPAM source package manager <building_with_opam>`.
  Take this way to install the latest stable release in your native OS
  environment, automatically built from sources.
- :ref:`setting up a complete development environment <compiling_with_make>` by
  compiling the sources like developers do.
  This is the way to take if you plan to contribute to the source code.
  It allows to install any version you want (typically, the current
  development version on the master branch) by compiling it yourself from the
  sources.


These different options are described in the following sections.

Note that some of the packaged distributions are not only available for the latest stable release. For instance, static binaries are also available for release candidates, and Docker images are also available for the current development version (see :doc:`../releases/releases` for more information).

When choosing between the installation options, you may take into account the
convenience of the installation step (and of upgrading steps), but also
efficiency and security considerations. For instance, static binaries have a
different memory footprint compared to dynamically-linked binaries. Also,
compiling the sources in the official Tezos
repository is more secure than installing OPAM packages from a repository that
is not under Tezos control. In particular, compiling from sources enforces a fixed set of dependencies; when compiling via OPAM, this set of dependencies may change, which may or may not be compatible with your security practices.

All our installation scenarios are tested daily, including by automated means, to ensure that they are correct and up to date.
These tests are performed by applying scenarios in several standard environments, from scratch.
However, if you encounter problems when performing one of the installation scenarios in your own environment, you may want to take a look at :doc:`get_troubleshooting`.

.. _getting_static_binaries:

Getting static binaries
-----------------------

You can get static Linux binaries from the
`latest release in the tezos-packaging repository <https://github.com/serokell/tezos-packaging/releases/latest>`__.

This repository provides static binaries for x86_64 and arm64 architectures. Since these binaries
are static, they can be used on any Linux distribution without any additional prerequisites.
However, note that, by embedding all dependencies, static binary executables are typically much larger than dynamically-linked executables.

For upgrading to a newer release, you just have to download and run the new
versions of the binaries.

.. _installing_binaries:

Installing binaries
-------------------

Depending on your operating system, you may install Tezos (dynamically-linked)
binaries and their dependencies using a package manager, as follows.

Ubuntu Launchpad PPA with Tezos packages
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you're using Ubuntu, you can install packages with Tezos binaries from a Launchpad PPA.
Currently it supports Focal and Bionic versions.

In order to add the stable release PPA repository to your machine, run:

.. literalinclude:: install-bin-ubuntu.sh
   :language: shell
   :start-after: [setup repository]
   :end-before: [install tezos]

Alternatively, to add the release candidates PPA instead, run:

.. literalinclude:: install-bin-rc-ubuntu.sh
   :language: shell
   :start-after: [setup repository]
   :end-before: [install tezos]

Then, to install the binaries, run the following commands:

.. literalinclude:: install-bin-ubuntu.sh
   :language: shell
   :start-after: [install tezos]

Upgrading to a newer release is made easy by the APT package manager, using
commands such as ``apt-get update``, ``apt-get upgrade <package>``, and
``apt-get install <new-package>``. Indeed, as the names of some packages (e.g.
the baker) depend on their version, you may have to also install new packages.
You may take a look at the available packages in the Tezos PPA repository listed
by ``apt-get update``.

Fedora Copr repository with Tezos packages
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you're using Fedora, you can install packages with Tezos binaries from a Copr repository.
Currently it supports Fedora 34.

In order to add the stable Copr repository to your machine, run:

.. literalinclude:: install-bin-fedora.sh
   :language: shell
   :start-after: [setup repository]
   :end-before: [install tezos]

Alternatively, to add the release candidates Copr repository instead, run:

.. literalinclude:: install-bin-rc-fedora.sh
   :language: shell
   :start-after: [setup repository]
   :end-before: [install tezos]

Then, to install the binaries, run the following commands:

.. literalinclude:: install-bin-fedora.sh
   :language: shell
   :start-after: [install tezos]

Upgrading to a newer release is made easy by the DNF package manager, using
commands such as ``dnf upgrade <package>``, and
``dnf install <new-package>``. Indeed, as the names of some packages (e.g.
the baker) depend on their version, you may have to also install new packages.
You may take a look at the available packages in the Tezos Copr repository
listed by ``dnf repoinfo``.

.. _using_docker_images:

Using Docker images
-------------------

For every change committed in the GitLab repository, Docker images are
automatically generated and published on `DockerHub
<https://hub.docker.com/r/tezos/tezos/>`_. This provides a convenient
way to run an always up-to-date ``tezos-node``.  The script
``tezos-docker-manager.sh`` (formally known as ``alphanet.sh``) is
provided to download the right image for each network and run a
simple node.  Its only requirement is a working installation of
`Docker <https://www.docker.com/>`__ (including both Docker Engine and Docker Compose) on a machine
with architecture **x86_64**.  Although we only officially support
Linux, the script has been tested with success in the past on
Windows, OS X, and Linux.

The same script can be used to run Tezos on Mainnet, on Hangzhounet, or on other network: it
suffices to rename it as it downloads a different image based on its
name.
For example, to run Tezos on the Hangzhounet test network with the latest release:

.. literalinclude:: use-docker-hangzhounet.sh
   :language: shell
   :start-after: [get testnet]
   :end-before: [start testnet]

Alternatively, to run on Mainnet::

   wget -O mainnet.sh https://gitlab.com/tezos/tezos/raw/latest-release/scripts/tezos-docker-manager.sh
   chmod +x mainnet.sh

In the following we assume you are running on the Hangzhounet test network.
You are now one step away from a working node:

.. literalinclude:: use-docker-hangzhounet.sh
   :language: shell
   :start-after: [start testnet]

This will download the right Docker image for your chosen network, launch 3
Docker containers running the node, the baker and the endorser. Keep in mind
that when a Tezos node is launched, it needs to connect to new peers and
synchronize the chain. This can be *lengthy* on the first launch
considering that the chain takes up several gigabytes of data. See
:ref:`how to use Tezos<howtouse>` for more details.

Every call to ``hangzhounet.sh`` will check for updates of the node and
will fail if your node is not up-to-date. For updating the node, simply
run::

    ./hangzhounet.sh restart

If you prefer to temporarily disable automatic updates, you just have to
set an environment variable::

   export TEZOS_ALPHANET_DO_NOT_PULL=yes

See ``./hangzhounet.sh --help`` for more information about the
script. In particular see ``./hangzhounet.sh client --help`` or the
:ref:`online manual<client_manual>` for more information about
the client. Every command to the ``tezos-client`` can be equivalently
executed by using ``./hangzhounet.sh client``, passing the needed arguments. Similarly, ``tezos-admin-client``
can be executed using ``./hangzhounet.sh admin-client``.


.. _building_with_opam:

Building from sources via OPAM
------------------------------

The easiest way to build the binaries from the source code is to use the OPAM
source package manager for OCaml.

This is easier than :ref:`setting up a complete development environment <build_from_sources>`, like developers do.
However, this method is recommended for expert users as it requires basic
knowledge of the OPAM package manager and the OCaml packages
workflow. In particular, upgrading Tezos from release to
release might require tinkering with different options of the OPAM
package manager to adjust the local environment for the new
dependencies.


.. _build_environment:

Environment
~~~~~~~~~~~

Currently Tezos is being developed for Linux x86_64, mostly for
Debian/Ubuntu and Arch Linux. The following OSes are also reported to
work: macOS (x86_64), Arch Linux ARM (aarch64), Debian Linux (buster),
Ubuntu Linux (focal). A Windows port is feasible and might be
developed in the future.

.. note::

    If you build the binaries by using the following instructions inside a
    Docker container, you have to give extended privileges to this container,
    by passing option ``--privileged`` to the ``docker run`` command.


Install OPAM
~~~~~~~~~~~~

First, you need to install the `OPAM <https://opam.ocaml.org/>`__
package manager, at least version 2.0, that you can get by following the `install instructions <https://opam.ocaml.org/doc/Install.html>`__.

After the first install of OPAM, use ``opam init --bare`` to set it up
while avoiding to compile an OCaml compiler now, as this will be done in
the next step.

.. _install_opam_packages:

Install Tezos OPAM packages
~~~~~~~~~~~~~~~~~~~~~~~~~~~

The latest Tezos release is available (as soon as possible after the
release) directly as OPAM packages.

.. note::

   Every file related to OPAM is (by default) in ``$HOME/.opam`` which
   means that, first, OPAM installs are user-specific and, second, you
   can get rid of everything by removing this directory (+ updating
   your rc files (``$HOME/.bashrc``, ``$HOME/.profile``,
   ``$HOME/.zshrc``, ``$HOME/.emacs``, ...) if you asked/allowed OPAM
   to add some lines in them).

The binaries need a specific version of the OCaml compiler (see the value
of variable ``$ocaml_version`` in file ``scripts/version.sh``). To get an environment with it do:

.. literalinclude:: install-opam.sh
  :language: shell
  :start-after: [install ocaml compiler]
  :end-before: [get system dependencies]

.. note::

   The ``opam switch create`` command may fail if the switch already exists;
   you are probably re-installing or upgrading an existing installation.
   If the required compiler version has not changed since the last time, you
   may simply ignore this error. Otherwise, you are upgrading to a new compiler,
   so look at the :ref:`relevant section below <updating_with_opam>`.

   The command ``eval $(opam env)`` sets up required environment
   variables. OPAM will suggest to add it in your rc file. If, at any
   point, you get an error like ``tezos-something: command not
   found``, first thing to try is to (re)run ``eval $(opam
   env --switch $ocaml_version)`` (replace ``$ocaml_version`` with its value
   in ``scripts/version.sh``) to see if it fixes the problem.

In order to get the system dependencies of the binaries, do:

.. literalinclude:: install-opam.sh
  :language: shell
  :start-after: [get system dependencies]
  :end-before: [install tezos]

.. note::

   If an OPAM commands times out, you may allocate it more time for its
   computation by setting the OPAMSOLVERTIMEOUT environment variable (to a
   number of seconds), e.g. by adding ``OPAMSOLVERTIMEOUT=1200`` before the
   command. If no timeout occurs, you may omit this part.

Now, install all the binaries by:

.. literalinclude:: install-opam.sh
  :language: shell
  :start-after: [install tezos]

You can be more specific and only ``opam install tezos-node``, ``opam
install tezos-endorser-alpha``, ... In that case, it is enough to install the system dependencies of this package only by running ``opam depext tezos-node`` for example instead of ``opam depext tezos``.

.. warning::

   Note that ``opam install tezos-client`` and ``opam install
   tezos-signer`` are "minimal" and do not install the support for
   Ledger Nano devices. To enable it, run ``opam install
   ledgerwallet-tezos`` in addition to installing the binaries. (The
   macro meta-package ``tezos`` installs ``ledgerwallet-tezos``.)

.. _updating_with_opam:

Updating via OPAM
~~~~~~~~~~~~~~~~~

Installation via OPAM is especially convenient for updating to newer
versions. Once some libraries/binaries are installed and new versions
released, you can update by:

::

   opam update
   opam depext
   opam upgrade

It is recommended to also run the command ``opam remove -a`` in order
to remove the dependencies installed automatically and not needed
anymore. Beware not uninstall too much though.

Identified situations where it will be more tricky are:

* When the OCaml compiler version requirement changes. In this case,
  you have several possibilities:

  - Be explicit about the "upgrade" and do ``opam upgrade --unlock-base
    ocaml.$new_version tezos``. Note that starting from OPAM version 2.1,
    this option is replaced by ``--update-invariant`` (see the `opam-switch
    manual <https://opam.ocaml.org/doc/man/opam-switch.html>`_).
  - Remove the existing switch (e.g., ``opam switch remove for_tezos``, but
    be aware that this will delete the previous installation), and replay
    :ref:`the installation instructions <install_opam_packages>`.
  - Replay :ref:`the installation instructions <install_opam_packages>` while
    creating a different switch (e.g. ``ocaml_${ocaml_version}_for_tezos``), but
    be aware that each switch consumes a significant amount of disk space.

* When there are Rust dependencies involved. The way to go is still
  unclear.
  The solution will be defined when delivering the first release with Rust
  dependencies.

.. _build_from_sources:
.. _compiling_with_make:

Setting up the development environment from scratch
---------------------------------------------------

If you plan to contribute to the Tezos codebase, the way to go is to set up a
complete development environment, by cloning the repository and compiling the
sources using the provided makefile.

**TL;DR**: From a fresh Debian Buster x86_64, you typically want to do:

.. literalinclude:: compile-sources.sh
  :language: shell
  :start-after: [install packages]
  :end-before: [test executable]


The following sections describe the individual steps above in more detail.

.. _setup_rust:

Install Rust
~~~~~~~~~~~~

Compiling Tezos requires the Rust compiler,
version 1.52.1, and the Cargo package manager to be installed. If you
have `rustup <https://rustup.rs/>`_ installed, it should work without
any additional steps on your side. You can use `rustup
<https://rustup.rs/>`_ to install both. If you do not have ``rustup``,
please avoid installing it from Snapcraft; you can rather follow the
simple installation process shown below:

.. literalinclude:: compile-sources.sh
  :language: shell
  :start-after: [install rust]
  :end-before: [source cargo]

Once Rust is installed, note that your ``PATH`` environment variable
(in ``.profile``) may be updated and you will need to restart your session
so that changes can be taken into account. Alternatively, you can do it
manually without restarting your session:

.. literalinclude:: compile-sources.sh
  :language: shell
  :start-after: [source cargo]
  :end-before: [get sources]

Note that the command line above assumes that rustup
installed Cargo in ``$HOME/.cargo``, but this may change depending on how
you installed rustup. See the documentation of your rustup distribution
if file ``.cargo`` does not exist in your home directory.

.. _setup_zcash_params:

Install Zcash Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

Tezos binaries require the Zcash parameter files to run.
Docker images come with those files, and the source distribution also
includes those files. But if you compile from source and move Tezos to
another location (such as ``/usr/local/bin``), the Tezos binaries may
prompt you to install the Zcash parameter files. The easiest way is to
download and run this script::

   https://raw.githubusercontent.com/zcash/zcash/master/zcutil/fetch-params.sh

The node will try to find Zcash parameters in the following directories,
in this order:

#. ``$XDG_DATA_HOME/.local/share/zcash-params``
#. ``$XDG_DATA_DIRS/zcash-params`` (if ``$XDG_DATA_DIRS`` contains
   several paths separated by colons ``:``, each path is considered)
#. ``$OPAM_SWITCH_PREFIX/share/zcash-params``
#. ``./_opam/share/zcash-params``
#. ``~/.zcash-params``
#. ``~/.local/share/zcash-params``
#. ``/usr/local/share/zcash-params``
#. ``/usr/share/zcash-params``

If the node complains that it cannot find Zcash parameters, check that
at least one of those directories contains both files ``sapling-spend.params``
and ``sapling-output.params``. Here is where you should expect to find those files:

* if you are compiling from source, parameters should be in
  ``_opam/share/zcash-params`` (you may need to run ``eval $(opam env)``
  before running the node);

* if you used ``fetch-params.sh``, parameters should be in ``~/.zcash-params``.

.. note::

   Some operating systems may not be covered by the list of directories above.
   If Zcash is located elsewhere on your system (typically, on MacOS X), you may try creating a symbolic link such as: ``ln -s ~/Library/Application\ Support/ZcashParams ~/.zcash-params``.

Get the sources
~~~~~~~~~~~~~~~

Tezos ``git`` repository is hosted at `GitLab
<https://gitlab.com/tezos/tezos/>`_. All development happens here. Do
**not** use our `GitHub mirror <https://github.com/tezos/tezos>`_
which we don't use anymore and only mirrors what happens on GitLab.

Checkout the ``latest-release`` branch to use the latest release.
Alternatively, you can checkout a specific version based on its tag.

Install Tezos dependencies
~~~~~~~~~~~~~~~~~~~~~~~~~~

Install the OCaml compiler and the libraries that Tezos depends on::

   make build-deps

Alternatively, if you want to install extra
development packages such as ``merlin``, you may use the following
command instead:

::

   make build-dev-deps

.. note::

   * These commands create a local OPAM switch (``_opam`` folder at the root
     of the repository) where the required version of OCaml and OCaml Tezos
     dependencies are compiled and installed (this takes a while but it's
     only done once).

   * Be sure to ``eval $(scripts/env.sh)`` when you ``cd``
     into the repository in order to be sure to load this local
     environment.

   * As the opam hook would overwrite the effects of ``eval $(scripts/env.sh)``
     the script will disable the opam hook temporarily.

   * OPAM is meant to handle correctly the OCaml libraries but it is
     not always able to handle all external C libraries we depend
     on. On most systems, it is able to suggest a call to the system
     package manager but it currently does not handle version checking.

   * As a last resort, removing the ``_opam`` folder (as part of a ``git
     clean -dxf`` for example) allows to restart in a fresh environment.

Compile
~~~~~~~

Once the dependencies are installed we can update OPAM's environment to
refer to the new switch and compile the project:

.. literalinclude:: compile-sources.sh
  :language: shell
  :start-after: [compile sources]
  :end-before: [optional setup]

Lastly, you can also add the Tezos binaries to your ``PATH`` variable,
and after reading the Disclaimer a few
hundred times you are allowed to disable it with
``TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y``.

You may also activate Bash autocompletion by executing::

  source ./src/bin_client/bash-completion.sh

.. warning::

  Note that if your shell is `zsh`, you may need extra configuration to customize shell
  completion (refer to the `zsh` documentation).

Update
~~~~~~

For updating to a new version, you typically have to
update the sources by doing ``git pull`` in the ``tezos/`` directory and replay
the compilation scenario starting from ``make build-deps``.
You may also use ``make clean`` (and ``rm -Rf _opam/`` if needed) before that, for restarting compilation in a
fresh state.
