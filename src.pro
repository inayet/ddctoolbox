# Top-level qmake project for the repository.
# This project simply delegates to the vendored `src/` subdirectory
# which contains the actual application project file `src/src.pro`.
#
# The build system (nix/flake) looks for `./src.pro` at the repository root
# and runs qmake on it. This file allows that invocation to pick up the
# vendored `src/src.pro` and keep the upstream layout intact.

TEMPLATE = subdirs

# Ensure subprojects are built in the declared order (src first).
CONFIG += ordered

# Point qmake to the vendored source directory.
# qmake will run on src/src.pro automatically.
SUBDIRS += src

# Optionally propagate CONFIG flags from the top-level to subdirs.
# (The flake/CI usually passes CONFIG+=release and c++17 on the qmake command line.)
QMAKE_SUBSTITUTES += CONFIG
