== Parameterizations to be Benchmarked<appendix:paramalgo>
We ran benchmarks for the combination of the following parameters:

- Implementation: Fortran, Julia
- Backend: CPU, GPU
- Datasets: "Cognitive Workload", "Memorize", "EEG Eye Tracking"
- Block sizes: 100, 1000, 10000, 100000, 200000, 300000, 600000, "full dataset"
- Precision: 32-bit, 64-bit
- Thread count: 1, 4, 8, 16, 24, 32, 64
- Number of iterations: 40
- Number of runs: 6

We exclude all parameterizations which match one of the following conditions:
- $"Block size" > "Problem size"$
- $"Block size" * "Thread count" > "Problem size"$
- $"Precision" = "float32"$ and $"Implementation" = "fortran"$
- $"Backend" = "GPU"$ and $"Implementation" = "fortran"$

== Full Results of the Runtime Benchmarks <appendix:fullitertime>
#figure(caption: [Runtime by AMICA implementation and parametrization (1/2)])[
  #image("figures/runtime_full_page1.svg")
]
#figure(caption: [Runtime by AMICA implementation and parametrization (2/2)])[
  #image("figures/runtime_full_page2.svg")
]
== Full Results of the Memory Benchmarks <appendix:fullmem>
#figure(caption: [Memory by AMICA implementation and parametrization (1/2)])[
  #image("figures/memory_full_page1.svg")
]
#figure(caption: [Memory by AMICA implementation and parametrization (2/2)])[
  #image("figures/memory_full_page2.svg")

]
