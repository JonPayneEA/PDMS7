# Using the PDM core outside R

The PDM time loop is written once, in `src/pdm_core.cpp`, behind the C interface in
`src/pdm_core.h`. The core has no R dependency. Any language that can call C functions can
use it: R does so through `src/pdm_engine.cpp`, and Python, Scala, Julia, MATLAB or Fortran
can do the same through their foreign function interfaces.

The header is the reference for every function, struct field and array layout. This file
covers building and checking.

## What the core covers

Simulation only, for Pareto capacity, standard recharge, two-store cascade surface routing and
power-law groundwater routing (cubic when `m = 3`). Configuration files, calibration and
metrics stay in each host language. A calibration in another language will therefore agree
closely with R's, not exactly, because optimisers differ between languages.

## Building

The core needs a C++11 compiler and nothing else. From the package root:

```
# Linux or macOS: a shared library for other languages
g++ -std=c++11 -O2 -shared -fPIC src/pdm_core.cpp -o libpdmcore.so      # Linux
clang++ -std=c++11 -O2 -dynamiclib src/pdm_core.cpp -o libpdmcore.dylib # macOS

# Windows, with the Rtools or MinGW toolchain
g++ -std=c++11 -O2 -shared -DPDM_CORE_BUILD_SHARED src/pdm_core.cpp -o pdmcore.dll ^
    -static-libgcc -static-libstdc++
```

On Windows, `PDM_CORE_BUILD_SHARED` exports the functions from the DLL, and the two static
flags make the DLL independent of the compiler's runtime libraries.

Only the Linux commands have been run so far. The macOS and Windows commands are standard, but
have not been run yet; run `check_golden` after the first build on each.

## Checking against the golden files

`check_golden.c` is a plain C program. It proves that the interface works from C, and so
from any language with a C foreign function interface, and it checks every golden case:

```
g++ -std=c++11 -O2 -c src/pdm_core.cpp -o pdm_core.o
gcc -std=c99 -O2 -I src -c tools/core/check_golden.c -o check_golden.o
g++ check_golden.o pdm_core.o -o check_golden
./check_golden inst/golden
```

It prints one line per case and exits with status 0 only if every case passes. A new binding
in any language should repeat the same checks; `inst/golden/README.md` gives the rules.

## Calling from other languages

The interface uses only fixed-width integers, doubles, arrays of doubles and a character
buffer for error messages. The caller allocates every array. The core allocates nothing the
caller must free, holds no global state, and is safe to call from several threads at once.

- **Python:** load the shared library with `ctypes.CDLL`. Declare `pdm_params` as a
  `ctypes.Structure` with 18 `c_double` fields and two `c_int32` fields, in header order.
  Pass NumPy arrays with `numpy.ctypeslib.as_ctypes` or `arr.ctypes.data_as(...)`. No
  compilation is needed on the Python side.
- **Scala and Java:** use the Java Foreign Function and Memory API (standard from Java 22),
  or JNA on older JVMs. `pdm_params` is 152 bytes: 18 doubles followed by two 32-bit
  integers, with no padding. Scala Native can call the core directly with `@extern`.
- **Julia:** `ccall` with a `struct` matching `pdm_params`.

Read the struct size back and compare it with 152 bytes, and check `pdm_core_abi_version()`
against `PDM_CORE_ABI_VERSION`, before trusting a new binding.

## Errors

Every function that can fail returns `PDM_OK` (0), `PDM_ERR_ARGUMENT` (1) or
`PDM_ERR_NUMERICAL` (2), and writes a message into the caller's buffer. On failure the
caller's state array is left unchanged, so a failed run can be retried or reported without
corrupting the model state.
