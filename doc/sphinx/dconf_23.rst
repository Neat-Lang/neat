=============================
The Neat Programming Language
=============================

.. image:: https://img.shields.io/badge/license-BSD-blue.svg
    :target: https://github.com/neat-lang/neat/blob/master/LICENSE

.. image:: https://img.shields.io/badge/platform-Linux%2064--bit-brightgreen.svg

Links
-----

`Documentation <https://neat-lang.github.io>`_

`Github <https://github.com/neat-lang/neat>`_

`IRC: #neat on libera.chat <https://web.libera.chat/#neat>`_

Installation
------------

To set up Neat on Ubuntu 22.04 from source, follow these steps:

.. code-block:: bash

    apt-get update
    apt-get install -y --no-install-recommends \
      ca-certificates clang-15 curl file gcc git llvm-15 llvm-15-dev unzip
    git clone https://github.com/neat-lang/neat
    cd neat
    ./build.sh
    export PATH=$(pwd)/build:$PATH

Note that copying the binary to `/usr/local/bin` will *not* work at present,
as `neat` looks for configuration and compiler source relative to the binary.

Sample
------

To run a sample:

.. code-block:: bash

   neat demos/longestline.nt
   ./longestline demos/longestline.nt

Check the other files in `demos/` as well, but note that they may need various `-dev` packages installed.

Help, things stopped working!
-----------------------------

If compiles are randomly failing with linker errors or weird problems, delete the `.obj/` folder,
which caches compilation artifacts.

This should not happen, and yet...
