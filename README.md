# **MSc-Thesis:** Toward Fortran Level AMICA in Julia: Block Based Learning and GPU Acceleration

**Author:** _Valentin Morlock_

**Supervisor:** _Benedikt V. Ehinger_

**Year:** _2026_

## Project Description

Adaptive Mixture of Independent Component Analyzers (AMICA) is a powerful maximum-likelihood based method for Independent Component Analysis (ICA) and is widely used in EEG artifact removal. AMICA.jl is a promising re-implementation of the Fortran reference in the Julia programming language that improves the accessibility of the algorithm's implementation but cannot yet match the convergence behavior, performance, and numerical stability of the reference.

Our work examines whether AMICA.jl can be improved to match the Fortran reference in correctness and performance while still offering a more accessible and extensible code base. By exporting intermediate values from a modified Fortran implementation and comparing them against Julia, multiple implementation differences were identified and corrected, resulting in closely matching outputs. Numerical stability was improved, allowing AMICA.jl to reliably work with 32-bit precision. To improve performance and potentially outperform AMICA Fortran, we added GPU acceleration, introduced blockwise processing, and implemented multithreading in AMICA.jl.

We performed an extensive benchmark series measuring memory use and runtime, and showed that our improved Julia implementation substantially improved both metrics. When compared to the Fortran reference, AMICA.jl is now competitive in terms of memory use and CPU runtime, and achieves faster runtimes when using GPU acceleration.

Our work therefore positions AMICA.jl as a correct, practically viable and more accessible alternative to the Fortran reference implementation.

## Instruction for a new student

The main artifact of this work can be found in the [AMICA.jl repo](https://github.com/s-ccs/Amica.jl). The final commit during this project was [177aa2cd5510d8e5c86e1b080cc18f88a401c10a](https://github.com/s-ccs/Amica.jl/commit/177aa2cd5510d8e5c86e1b080cc18f88a401c10a). To reproduce the benchmarks of this work, run the `benchmark.jl` script, this will run all benchmarks as defined in `testsuite.jl` and write the outputs to `benchmarks.json`. The plotting scripts `runtime_plots.jl` and `memory_plots.jl` consume this file and create a set of plots used within the thesis.

To run the benchmarks, certain system dependencies have to be available, and paths need to be adjusted:

- Download and install the [MPICH](https://www.mpich.org/static/downloads/5.0.0/mpich-5.0.0-installguide.pdf) library
- Download and install [Intel MKL](https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl-download.html) to compile and run the Fortran implementation
- A checkout of the [AMICA repository](https://github.com/sccn/amica). Add the `scripts/Makefile` to the checkout.
- Adjust paths: the location of Intel MKL and MPI are hardcoded within the `Makefile` and `scripts/fortran_runner.jl`, adjust those to match your installation
- Build AMICA Fortran: run `make` in the checked-out directory
- Adjust the AMICA path in `fortran_runner`'s `DEFAULT_AMICA_BIN` variable
- Acquire datasets: download the `Memorize` dataset from the [AMICA Website](https://sccn.ucsd.edu/~jason/amica_web.html). The small dataset is checked in to the AMICA.jl repository, but you will have to acquire the large dataset and convert it using `convert.jl`. Adjust paths in `default.param`,`fortran_runner.jl` and `julia_runner.jl`.

You should now be able to run the benchmark: remove or rename the current `benchmarks.json` and run `benchmark.jl`. As this can take multiple days, it's best to run it within a `tmux` session. Afterwards you might want to run the plotting scripts `memory_plots.jl` or `runtime_plots.jl`.
