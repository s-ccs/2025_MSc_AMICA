`benchmark_summary.jl` standalone script to continuously sample a process for cpu and gpu memory, using the same approach as benchmark.jl

`benchmark.jl` runs all benchmark configurations defined in `testsuite.jl`, which are not yet present in `benchmarks.json`, and stores the results in `benchmarks.json`

`fortran_runner.jl`, `julia_runner.jl` scripts to run AMICA.jl and AMICA Fortran with a given configuration, used by benchmark.jl

`convert.jl` script to convert the "EEG Eye Tracking" and "Cognitive Workload" to the format expected by AMICA Fortran

`exemplary_mixtures.jl` plot the exemplary signal mixing used in the thesis

`gaussian_mixture.jl` plot the exemplary Gaussian Mixtures used in the thesis

`ll_compare_memorize_big.jl` runs all AMICA implementations for 40 iterations, stores the results in `ll_compare_memorize_big_backup.json` and creates a plot of the results

`memory_plots.jl` & `runtime_plots.jl` all other plots used in the thesis and presentation, reads data from benchmarks.json

`Makefile` a makefile to build AMICA Fortran
