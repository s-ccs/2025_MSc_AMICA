// A central place where libraries are imported (or macros are defined)
// which are used within all the chapters:
#import "utils/global.typ": *


// Fill me with the Abstract
#let abstract = [
  #include "./abstract.typ"
]

// Fill me with acknowledgments
#let acknowledgements = [
  #include "./acknowledgements.typ"
]

// Fill me with the declaration
#let declaration = [
  #include "./declaration.typ"
]

// if you have appendices, add them here
#let appendix = [
  = Appendices
  #include "./appendix.typ"
]

// Put your abbreviations/acronyms here.
// 'key' is what you will reference in the typst code
// 'short' is the abbreviation (what will be shown in the pdf on all references except the first)
// 'long' is the full acronym expansion (what will be shown in the first reference of the document)
//
// In the text, call @eeg or @uniS to reference  the shortcode
#let abbreviations = (
  (
    key: "eeg",
    short: "EEG",
    long: "Electroencephalography",
  ),
  (
    key: "uniS",
    short: "UoS",
    long: "University of Stuttgart",
  ),
  (
    key: "ica",
    short: "ICA",
    long: "Independent Component Analysis",
  ),
  (
    key: "amica",
    short: "AMICA",
    long: "Adaptive Mixture of Independent Component Analyzers",
  ),
  (
    key: "bss",
    short: "BSS",
    long: "Blind Source Separation",
  ),
  (
    key: "pdf",
    short: "PDF",
    long: "Probability Density Function",
  ),
  (
    key: "mgg",
    short: "MGG",
    long: "Mixture of Generalized Gaussian distribution",
  ),
  (
    key: "gsms",
    short: "GSMs",
    long: "Gaussian Scale Mixtures",
  ),
  (
    key: "em",
    short: "EM",
    long: "Expectation Maximization",
  ),
  (
    key: "ll",
    short: "LL",
    long: "Logarithmic Likelihood",
  ),
  (
    key: "llm",
    short: "LLM",
    long: "Large Language Model",
  ),
  (
    key: "rss",
    short: "RSS",
    long: "Resident Set Size",
  ),
)

#show: thesis.with(
  author: "Valentin Morlock",
  title: "Toward Fortran Level AMICA in Julia: Block Based Learning and GPU Acceleration",
  degree: "Master of Science",
  faculty: "Faculty of Electrical Engineering and Computer Science",
  department: "Computational Cognitive Science",
  major: "Software Engineering",
  supervisors: (
    (
      title: "Main Supervisor",
      name: "Benedikt Ehinger",
      affiliation: [Computational Cognitive Science \
        Faculty of Electrical Engineering and Computer Science, \
        Department of Computer Science
      ],
    ),
  ),
  epigraph: none,
  abstract: abstract,
  appendix: appendix,
  declaration: declaration,
  acknowledgements: acknowledgements,
  preface: none,
  figure-index: false,
  table-index: false,
  listing-index: false,
  abbreviations: abbreviations,
  date: datetime(year: 2026, month: 3, day: 16),
  bibliography: bibliography("refs.bib", title: "Bibliography", style: "american-psychological-association"),
)

// Code blocks
#codly(
  languages: (
    rust: (
      name: "Rust",
      color: rgb("#CE412B"),
    ),
    // NOTE: Hacky, but 'fs' doesn't syntax highlight
    fsi: (
      name: "F#",
      color: rgb("#6a0dad"),
    ),
  ),
)


#let badge(body, fill) = {
  table.cell(inset: 0mm, align: center + horizon, rect(
    radius: 0.5mm,
    inset: (x: 0.7mm, y: 0.8mm),
    fill: fill,
    text(body, size: 6pt, fill: white),
  ))
};

// blocksize = 1000
// dataset = memorize
#let sidebar_rows = (
  ("CPU", rgb("#00A2FF"), "7.5 GB", "6.0 s/iter"),
  ("CPU", rgb("#00A2FF"), "3.5 GB", "7.1 s/iter"),
  ("GPU", rgb("#D31976"), "15.6 GB", "0.1 s/iter"),
  ("CPU", rgb("#00A2FF"), "3.6 GB", "6.6 s/iter"),
  ("GPU", rgb("#D31976"), "0.9 GB", "0.5 s/iter"),
  ("CPU", rgb("#00A2FF"), "1.1 GB", "4.9 s/iter"),
  ("CPU*64", rgb("#00A2FF"), "2.8 GB", "0.6 s/iter"),
)

#let perf_sidebar(rows_to_show, rows_to_gray) = {
  let row_count = sidebar_rows.len()
  let visible_rows = if rows_to_show < 0 {
    0
  } else if rows_to_show > row_count {
    row_count
  } else {
    rows_to_show
  }

  let gray_rows = if rows_to_gray < 0 {
    0
  } else if rows_to_gray > visible_rows {
    visible_rows
  } else {
    rows_to_gray
  }

  context {
    let side = if calc.rem(here().page(), 2) == 0 { left } else { right }
    let side_dx = if side == left { -3.6cm } else { +3.6cm }

    place(
      side,
      dx: side_dx,
      {
        show table.cell: set text(size: 7pt)

        table(
          columns: (auto, auto, auto),
          stroke: (x, y) => if y == 0 {
            (bottom: 0.1pt + black)
          },
          inset: 1.5mm,
          align: start,
          [],
          [Memory],
          [Time],
          ..range(visible_rows)
            .map(i => {
              let row = sidebar_rows.at(i)
              let is_gray = i < gray_rows
              (
                badge(row.at(0), if is_gray { luma(170) } else { row.at(1) }),
                text(row.at(2), fill: if is_gray { luma(140) } else { black }),
                text(row.at(3), fill: if is_gray { luma(140) } else { black }),
              )
            })
            .flatten(),
        )
      },
    )
  }
}


// If you wish to use lining figures rather than old-style figures, uncomment this line.
// #set text(number-type: "lining")

// import custom utilities
#import "utils/general-utils.typ": *

// Main Content starts here
= Introduction <chp:introduction>

When engaging in a conversation within a room full of other people speaking, the human brain can effortlessly separate the voice of the conversation partner from auxiliary sounds in real time. However, achieving the same separation using digital signal processing is surprisingly complicated. An often cited exemplary scenario, named the "cocktail party problem", is the aforementioned room of multiple speakers, recorded by several microphones. Each microphone records a mixture of the individual sound sources present in the observed room, at varying sound levels. @naik2011overview

Separating the unknown source signals within the room given the signal mixtures is called @bss. An exemplary problem is shown in @fig:icaviz, where the left three graphs represent the mixed source signals $x$, as recorded by the microphones, which can be unmixed to the unmixed source signals displayed on the right, as originally emitted by the sound sources. The graphs make it visible how the three sources influence the mixtures by varying degrees. @bss finds application in various fields of signal processing, for example in medical imaging, sound processing or @eeg artifact removal. @choi2005blind@naik2011overview

#figure(caption: [Schematic visualization of observed mixtures $x$ and unmixed sources $s$])[
  #image("figures/exemplary_mixtures.svg")
] <fig:icaviz>



== EEG Artifact Removal

#figure(caption: [Active scalp areas by separated source, created by the EEGLAB software @eeglabtutorial])[
  #image("figures/92ICA_topo.jpg", width: 60%)
] <fig:eeglabica>
@eeg recordings are extensively used in scientific research as well as clinical diagnostics. The goal of an @eeg usually is to create a recording of the signals emitted by certain areas of the subject's brain. The subject has electrodes attached to their scalp, and each electrode is capturing a separate recording of the electrical signals observed on the scalp, often called a channel. Different sources might emit these electric signals, and therefore each electrode's recording consists of a distinct mixture of these source signals.

A recording typically does not contain only the signals emitted by the brain but also other unwanted signals, e.g. caused by the blinks or movements of an eye. The distortions caused by this are called artifacts. @eeg artifact removal is a class of approaches to remove such artifacts from the @eeg recordings. Artifact removal can be seen as a @bss problem where the recorded channels contain mixtures of neural activity and undesired sources. After separating the recording's sources using @bss, sources with relevant information are kept and sources with artifacts are discarded.  @uriguen2015eeg


== Independent Component Analysis

Several classes of algorithms to solve @bss are successfully employed in scientific and industrial applications, one of the most popular classes being @ica.

@bss is called blind as very little or no prior knowledge about the sources or the mixing process is known. The problem is therefore highly under-determined and separation is only possible by imposing additional assumptions like statistical independence, sparseness or non-gaussianity that constrain the solution space. @yu2013blind

@ica assumes the mixtures to be a linear combination of the source signals and unmixes the signals such that they are as statistically independent from each other as possible. Formally speaking, the observations $x$ are modelled as linear mixtures $x = A*s$ and an optimal unmixing matrix $W = A^(-1)$ is being determined. @yu2013blind @choi2005blind @lee1998ica_book

The process of @ica can be visualized as _rotating_ the mixtures versus the sources. Different specific approaches on how to determine the optimal unmixing exist. Some algorithms maximize the entropy of the signal while others, like @amica, maximize the likelihood of the unmixed data. @pearlmutter1996maximum @stone2004independent

== AMICA
The algorithm @amica as introduced by #cite(<palmer2012amica>, form: "prose") is a popular variant of @ica, especially in the area of @eeg signal processing. It has been shown to be one of the best-performing ICA algorithms in the field of artifact removal on @eeg sources @delorme2012independent. @amica is an @ica algorithm based on maximum likelihood estimation, which extends other maximum likelihood based @ica approaches (e.g., Infomax and extended Infomax) in the following two ways.

Following #cite(<palmer2012amica>, form: "prose"), instead of assuming a fixed @pdf for the source signals, @amica estimates the density of the source signals $q_(i)(s_i (t))$, where $i$ indexes the source component, as a mixture of $m$ @gsms $q_(i j)$ parametrized by location $mu_(i j)$, scale $beta_(i j)$ and shape $rho_(i j)$, where $j$ indexes the mixture component for source $i$.

The mixing of the @gsms is defined by @mixing which additionally includes a shift of the components by $mu_(i j)$ and scaling by $sqrt(beta_(i j))$ where $0 < beta_(i j) < 2$, which is required to ensure non-gaussianity. A visualization can be seen in @fig:mgg.

$
  q_(i)(s_i (t)) = sum_(j=1)^m alpha_(i j) sqrt(beta_(i j)) q_(i j)(sqrt(beta_(i j))(s_i (t) - mu_(i j)); rho_(i j))
$ <mixing>


#figure(caption: [Visualization of how multiple gaussians are combined to a @pdf])[
  #image("figures/gaussian_mixture.svg", width: 80%)
] <fig:mgg>

Based on the estimated source $y_t = W x_t$ and the density model (defined above) $q_i (y_i)$, the algorithm computes the negative @ll $L(W)$ of the observed data under the current $W$ and the current source density model. The @ll is then minimized. @palmer2012amica

$
  // q(y_t) &= product_i q_i(y_(i t)) \
  f(y_t) & = sum_i (-log q_i (y_(i t))) \
    L(W) & = sum_(t=1)^N -log | det W| +f(y_t)
$ <loglikelihood>

Therefore, the single model @amica estimates ${W, alpha_(i j), mu_(i j), beta_(i j), rho_(i j)}$.

Second, @amica includes support for estimating multiple models which improves unmixing in scenarios where the source signals are non-stationary. A model index $h in {1..M}$ is added to the parameters of the source density model and to the unmixing matrix $W$. $gamma_h$ indicates the probability that a model is active at time $t$, and exactly one model is active for each $t$. Each model is centered by $c_h$. @palmer2012amica

This extends these estimated parameters to ${W_h, c_h, gamma_h, alpha_(h i j), mu_(h i j), beta_(h i j), rho_(h i j)}$ where

$ x(t) = A_h s(t) + c_h $

To optimize those parameters, the @amica algorithm uses @em to iteratively assign samples to models and source-mixture components and then updates the unmixing matrix and density-parameters.

There are currently multiple implementations of @amica. #cite(<amicaweb>, form: "prose") initially implemented it in Matlab @amicamatlab, and later added the current de facto standard implementation in Fortran. #cite(<lulkin2023thesis>, form: "prose") created the initial version of AMICA.jl, an AMICA implementation written in Julia. AMICA Fortran performs well and has advanced features like multithreading or distributed processing. However, it is difficult to maintain, compile and extend and lacks compatibility with programming languages commonly used in science like Python or Julia. The implementation in Matlab is more approachable, but has worse performance in terms of convergence quality and computational efficiency. The implementation in Julia, modeled after the Matlab version, suffers from those same issues.

=== AMICA.jl
AMICA.jl, initially implemented by #cite(<lulkin2023thesis>, form: "prose"), is an implementation of the AMICA algorithm modelled after the Matlab implementation @amicamatlab. Both implement the basic @amica algorithm as well as multi-model functionality.

Compared to the multi threaded Fortran implementation, AMICA.jl, as present at the start of this project, solves the @amica algorithm around 25x slower on a single thread and omits block based learning as well as parallelization across cores or nodes. Convergence and numerical stability are inferior compared to the reference implementation. As visualized in @fig:nan, before this project, AMICA.jl computed significantly different results and aborted after 5 iterations.


#figure(
  caption: [@ll of AMICA.jl and AMICA Fortran on the "Memorize" reference dataset. We plot the absolute value on a logarithmic scale to show the large deviation before AMICA.jl aborts with `NaN`.],
)[
  #image("figures/amicajl_nan.svg", width: 60%)
] <fig:nan>

Despite the aforementioned issues, AMICA.jl remains promising because it is implemented in a more approachable programming language and in a significantly more compact and better structured codebase. This would allow a wider audience to work with, understand, and extend the AMICA algorithm.

The logical next step would therefore be to align the results to the Fortran code, and to achieve performance that is on par with or surpasses the reference. One obvious step to achieve similar performance is adding parallel processing on multiple cores of a CPU. The Fortran code implements this by dividing the dataset into blocks which are then processed in parallel.

GPUs offer significantly more effective parallelization than CPUs. Running AMICA on a GPU would therefore present a viable way to surpass the performance of all currently existing implementations. Since applying AMICA to large datasets can currently take several hours, this could substantially improve its practical usefulness.

=== GPU Programming in Julia
While Julia code runs on the CPU by default, several Julia packages provide powerful abstractions to port existing code to the GPU. Broadly speaking, there are two levels of abstraction:

1. *High level* abstractions provided by libraries like CUDA.jl @cudajl or AMDGPU.jl @amdjl expose custom array types such as `CuArray` which behave like regular Julia arrays but store data in the GPU memory and run operations performed on those data types on the GPU. This allows using common Julia operations like vector or matrix multiplications, broadcasts, map, reduce etc. on the GPU. In addition to that, vendor provided libraries for AMD and Nvidia GPUs expose precompiled GPU kernels for common operations like matrix multiplication, which work with the aforementioned array types. While simple to implement, these GPU integrations are limited in terms of which computations are supported. @juliaforhpc


#figure(caption: [High level gpu abstraction in julia, adapted from @juliaforhpc], kind: raw)[
  ```jl
  using CUDA

  A = CuArray([0,1,2,3,4,5,6])
  A .+= 1 # runs on GPU
  ```
]

An important benefit of this approach is that the implementation is independent of the GPU backend: the same computation could work with a CPU array or a GPU array of another backend.

2. *Lower level* abstractions provide more control on how computations are executed on the GPU by writing custom kernels in Julia. The CUDA.jl package provides a `@cuda` macro which runs arbitrary code on the GPU, however, work needs to be split across GPU threads manually, by calling the `threadIdx` function to obtain the index of the current GPU thread and then perform work on the right block of data. Similar abstractions exist for other GPU backends, e.g. Metal.jl for Apple Silicon GPUs or AMDGPU.jl for AMD GPUs. This method of writing custom kernels implies writing a separate kernel per GPU backend, which increases implementation effort and limits reusing code. To simplify this, the KernelAbstractions.jl @kernelAbstractions package provides utilities to efficiently parallelize work on the GPU without manually managing blockwise computations. @juliaforhpc


#figure(caption: [Lower level gpu abstraction in julia @juliaforhpc], kind: raw)[
  ```jl
  using KernelAbstractions

  @kernel function vadd!(C, @Const(A), @Const(B))
      i = @index(Global)
      @inbounds C[i] = A[i] + B[i]
  end

  function my_vadd!(C, A, B)
      backend = get_backend(A)
      kernel! = vadd!(backend)
      kernel!(C,A,B, ndrange = size(C))
  end
  ```
]

To summarize, Julia offers two backend agnostic ways to implement computations on the GPU: using broadcasts or a custom KernelAbstractions kernel. #cite(<raimondo2012cudaica>, form: "prose") have demonstrated that it is possible to run Infomax-ICA on a GPU, and the AMICA Fortran implementation shows that the AMICA algorithm can also be parallelized across threads and nodes. Since AMICA, similar to Infomax-ICA, calculates expensive operations such as matrix multiplications or exponents on each sample of the dataset, we expect AMICA to make good use of the massive parallelization of a GPU. Combined with the GPU programming capabilities in Julia, this suggests that adding GPU support to AMICA.jl is a feasible direction for further work.

== Summary

@ica is a class of algorithms to solve @bss problems, with AMICA being the currently best performing algorithm in the area of @eeg artifact removal. AMICA.jl is an implementation of the algorithm in the Julia programming language, which tries to make AMICA more approachable, but currently suffers from inferior accuracy, numerical stability and performance. All implementations existing before this work require extensive compute and, on large @eeg datasets, exhibit runtimes up to several hours, which makes running AMICA intensive in time and cost.

This work therefore explores how an optimized Julia implementation of AMICA can match the Fortran reference, measured by convergence quality and runtime efficiency, and which algorithmic changes, like block-based learning and GPU acceleration, most strongly improve performance.

#pagebreak()
= Results

Throughout the implementation phase of this work, we iteratively updated, tested and benchmarked the AMICA.jl implementation. The following chapter describes the approach we took, the results we obtained, the conclusions we draw, and the final version of AMICA.jl at which we arrived.

== Approach
=== Benchmarking <chapter:benchmark>

To improve performance and correctness, an appropriate benchmarking methodology had to be established first. Throughout the implementation phase of this work, we performed benchmarks on the 71 channel, 319,500 sample reference @eeg dataset "Memorize" as published on the #cite(<amicaweb>, form: "prose") page. For the final benchmarks we also use a roughly 7x smaller 19 channel, 172,704 sample @eeg dataset from #cite(<barras_booth_2026_ds007262>, form: "prose"), subject 1, which we call "Cognitive Workload" as well as an around 7x larger 128 channel, 1,260,379 sample "EEG Eye Tracking" dataset from #cite(<scheppers>, form: "prose").

All benchmarks were run on the same machine with specifications as shown in @fig:specs and, unless specified otherwise, the algorithm was executed for 40 iterations with the Newton Method enabled in all iterations.

#figure(caption: [Specification of the server used for benchmarking AMICA.jl])[
  #table(
    columns: (auto, auto),
    align: start,
    [CPU], [2x AMD EPYC 7452 32-Core Processor, 354GB Memory],
    [GPU], [1x NVIDIA RTX A6000, 49GB Memory],
  )
]<fig:specs>

To evaluate performance of the implementations, we measured (1) time spent per iteration, i.e. total runtime divided by the number of iterations, (2) peak CPU memory and (3) peak GPU memory used.

We defined the CPU memory as the @rss reported as `VmRSS` in `/proc/<pid>/status` and GPU memory as the value reported by the function `nvml_gpu_mem_for_pid` of the NVIDIA NVML library. For both values, we captured the whole process tree to avoid missing subprocesses e.g. launched by the MPI library used in Fortran. We continuously sampled both memory values every 100ms using a Julia script and took the maximum observed value. In theory, this approach might miss very short memory spikes, but due to the high number of samples, we considered it robust enough to compare different AMICA variants.

The first iteration of the AMICA algorithm takes longer than all subsequent iterations, particularly in the Julia implementation. Furthermore, both implementations perform various preprocessing steps before the first iteration begins. In our benchmarks over 40 iterations, this initial time significantly distorts the average iteration time. Real-world scenarios often involve 1,000 or more iterations, so this factor is negligible for practical use. Therefore, we measure the iteration time in all runtime benchmarks starting from iteration 1 as $"time_after_iter_1" / ("n_iter" - 1)$.


#perf_sidebar(1, 0)
Where relevant, we show the performance of the current implementation step in a sidebar table. The table alongside this paragraph shows the initial performance numbers measured for AMICA.jl upon the start of the project.

To find performance bottlenecks and make targeted improvements, we additionally implemented fine grained benchmarks using the `TimerOutputs.jl` library @timeroutputs. As shown in @fig:timeroutputs and @fig:timeroutputs_usage, the macro `@timeit` allows measuring the time spent and memory allocated in a certain code area and hierarchically visualizes total and average measurements.
#figure(caption: [Sample usage of the TimerOutputs.jl package])[
  ```jl
  @timeit to "initialize_shape_parameter!" initialize_shape_parameter!(myAmica, lrate)

  @timeit to "removeMean" if remove_mean
      removed_mean = removeMean!(data)
  end

  @timeit to "sphering" if do_sphering
      S = sphering!(data)
      myAmica.S = S
      myAmica.LLdetS = logabsdet(S ⊳ Array)[1]
  else
      myAmica.S = I
      myAmica.LLdetS = 0
  end
  ```
] <fig:timeroutputs_usage>

#figure(caption: [Sample output of the TimerOutputs.jl package, ordered by average allocation])[
  #image("figures/timeroutputs.png", width: 80%)
] <fig:timeroutputs>


=== Testing
The first step of this work was to achieve algorithmic correctness with the AMICA Fortran implementation as baseline. The AMICA algorithm computes the @ll of the current unmixing for each iteration. As it is simpler to compare the single @ll value instead of the whole unmixing matrix, we chose to use the @ll as a proxy to validate whether two implementations of AMICA compute matching results. While it is theoretically possible that two different unmixings result in the exact same @ll, we consider that highly unlikely and therefore a limitation we accepted.

However, comparing just the algorithm's output makes it hard to identify and fix errors in the implementation. We therefore added a test suite which compares not only the output but also intermediary values, allowing us to identify the root cause of mismatching results.
To do so, we created a modified Fortran implementation which runs for one iteration and writes a set of intermediary values to binary files. This version is built and executed within a Julia test suite, which then runs AMICA.jl and compares the binary files to the Julia implementation.

We have also set up a GitHub Actions pipeline that runs the test suite every time a commit is pushed to the repository, so that every contributor can run the tests without having to install Fortran dependencies on their local computer. This also makes it immediately clear if a pull request fails the tests.

This proved helpful during the initial bug fixing of AMICA.jl and also during the implementation of performance improvements, as regressions could be identified early.

== Implementation
=== Aligning results of AMICA.jl to AMICA Fortran
At the beginning of this project, AMICA.jl returned results which didn't match the output of AMICA Fortran, and took more iterations to converge. In addition to that, `NaN` values caused frequent early termination and hinted that there might be issues with numerical stability. The goal of this phase was therefore to identify which parts of the algorithm are implemented differently in AMICA.jl.

Comparing the two implementations can be tedious, especially given that variables are named differently and the Fortran code can be rather cryptic. To support that process, we made use of @llm:pl, specifically "Claude 4.5 Sonnet" using the "Claude Code" tool, to identify where in the Fortran code a specific value is computed and to extract a mathematical representation of the computation implemented in Fortran. As we checked all changes using the aforementioned test suite, the @llm output could be readily verified for correctness.

We iteratively changed AMICA.jl to pass the test suite, which resulted in a @ll that closely tracks AMICA Fortran, as shown in @fig:ll_matching.

#figure(caption: [AMICA.jl @ll closely tracking AMICA Fortran over 40 iterations])[
  #image("figures/ll_matching.svg", width: 80%)
] <fig:ll_matching>


Around 15 algorithmic changes were required to align results with version 17 of the Fortran implementation. Some were small changes to the implementation of the algorithm, e.g. removing a square root, subtracting $1.0$ from an exponent or flipping a sign in the newton update logic, while other areas like the update of parameter $beta$ required a complete rewrite. Some of those issues reflected bugs and inconsistencies within the AMICA.jl implementation, whereas others reflect inconsistencies between the Matlab and Fortran reference implementations.

#perf_sidebar(2, 1)

The fixes we made slightly increased iteration times but already cut the memory usage in half compared to the initial AMICA.jl, as shown in the sidebar.

In addition to that, we made improvements to numerical stability not present in AMICA Fortran, for example clamping certain values to a small $epsilon$ to avoid division by zero. In our tests, this enables AMICA.jl to reliably operate on `Float32` data - a significant performance improvement not present in the Fortran implementation.

=== GPU Support

Broadly speaking, there are two approaches to perform computations on the GPU in Julia - either by using custom kernels or by using broadcast operations, both having distinct advantages and disadvantages. Both, however, require using the array type specific to the GPU backend.

To allow computing AMICA on the GPU while still working on the CPU, we had to make the `SingleModelAmica` struct generic over the kind of array being used. An excerpt of the adjusted code can be seen in @fig:generic. A notable limitation of Julia is that a type parameter can't be further parametrized, so a separate parameter was required for each distinct number of dimensions used within `SingleModelAmica`.

#figure(caption: [Adaptation of `SingleModelAmica` to support different array types])[
  ```jl
  # before
  mutable struct SingleModelAmica{T} <:AbstractAmica
    location::Array{T, 2}
    shape::Array{T, 2}
    Lt::Array{T, 1}
    # ... further fields ...
  end

  # after
  mutable struct SingleModelAmica{
    T,
    Array1<:DenseArray{T,1},
    Array2<:DenseArray{T,2},
    Array3<:DenseArray{T,3}
  } <: AbstractAmica
    location::Array2
    shape::Array2
    Lt::Array1
    # ... further fields ...
  end
  ```
] <fig:generic>


==== Tradeoffs of Broadcasts versus Custom Kernels

Given the adjusted type, many broadcast operations within AMICA.jl work with GPU vectors without further changes. However, all places using scalar indexing had to be replaced by either broadcasts or custom kernels. Similarly, certain library functions are not supported by some or all GPU backends. For example, the `Base.inv` function works with CUDAs `CuArray` type but fails when passed Metal's `MtlArray` type. In cases where no alternatives could be found, we temporarily move data to the CPU memory and perform the computation on the CPU.

#figure(caption: [The `logabsdet` function does not support GPU arrays])[
  ```jl
  ldet = -logabsdet(A |> Array)[1]
  ```
]

While implementing GPU support, we noticed that the main tradeoff between broadcasts and custom kernels lies in the reuse of intermediary values and in undesired allocations. A broadcast is simple to understand and implement, but it usually operates on the whole dataset. Therefore, using a result in more than one subsequent calculation requires either computing it twice or allocating the intermediary value.

We illustrate this tradeoff using the example in @fig:reuse-cpu, which implements a computation using scalar indexing and a `for` loop. It computes the value `fp` once and reuses it to compute `dlambda_numer` and `g`. As `fp` is written to a scalar stack variable, no heap memory is allocated. Summation happens by incrementing both result variables.

#figure(caption: [Computing `g` and `dlambda_numer` in a `for` loop])[
  ```jl
  g .= zero(T)
  dlambda_numer .= zero(T)
  for k, i, j in size(y)
    fp = y_rho[k, i, j] * sign(y[k, i, j]) * shape[i, j]
    dlambda_numer[i, j] += z[k, i, j] * (fp * y[k, i, j] - T(1.0))^2
    g[k, i, j] += scale[i, j] * z[k, i, j] * fp
  end
  ```
]<fig:reuse-cpu>

One way to run this computation on the GPU is to use broadcasts as in @fig:reuse. `fp` is calculated for all data points and stored in a three dimensional array. The accumulation in the loop is replaced by the `sum` function.

#figure(caption: [Computing `g` and `dlambda_numer` using broadcasts])[
  ```jl
    fp = y_rho .* sign.(y) .* push_dimension(shape)
    dlambda_numer = sum(z .* (fp .* y .- T(1.0)) .^ 2, dims=1)[1, :, :]
    g .= sum(push_dimension(scale) .* z .* fp, dims=3)[:, :, 1]
  ```
]<fig:reuse>

In addition to `fp`, Julia implicitly allocates the values passed to the `sum` function. This approach therefore causes three allocations of size $"samples" * "mixtures" * "m"$, which consumes significant time and memory. This can be improved by reusing a `temporary`/`scratch` array as shown in @fig:reuse-scratch, but peak memory consumption is still $2 * "samples" * "mixtures" * "m"$ higher than in the initial version from @fig:reuse-cpu.

#figure(caption: [Computing `g` and `dlambda_numer` using broadcasts and a scratch array])[
  ```jl
    fp = y_rho .* sign.(y) .* push_dimension(shape)
    scratch = similar(y)
    scratch .= z .* (fp .* y .- T(1.0)) .^ 2
    dlambda_numer = sum(scratch, dims=1)[1, :, :]
    scratch .= push_dimension(scale) .* z .* fp
    g .= sum(scratch, dims=3)[:, :, 1]
  ```
]<fig:reuse-scratch>

This shows that implementing such computations with loop-like semantics is beneficial in terms of memory consumption. The tool to operate on individual datapoints, comparable to a loop, on a GPU is a custom kernel, which leads to the question whether such operations would be better implemented as a custom kernel. The critical part here is the two summing operations. As the kernel is started within hundreds or thousands of parallel GPU threads, it is no longer possible to simply add to the output variables as in @fig:reuse-cpu. Instead, some kind of synchronization logic is required to avoid data corruption when multiple threads operate on the same variable, which is commonly implemented using the Atomix.jl package @atomix.

#figure(caption: [Computing `g` and `dlambda_numer` using a custom KernelAbstractions.jl kernel])[
  ```jl
  @kernel function g_dlambda_kernel!(
      g, dlambda_numer,
      @Const(y_rho), @Const(y), @Const(shape), @Const(scale), @Const(z), @Const(T)
  )
      k, i, j = @index(Global, NTuple)
      fp = y_rho[k, i, j] * sign(y[k, i, j]) * shape[i, j]
      Atomix.@atomic dlambda_numer[i, j] += z[k, i, j] * (fp * y[k, i, j] - T(1.0))^2
      Atomix.@atomic g[k, i, 1] += scale[i, j] * z[k, i, j] * fp
  end
  g .= zero(T)
  dlambda_numer .= zero(T)
  kernel! = g_dlambda_kernel!(get_backend(y))
  kernel!(g, dlambda_numer, y_rho, y, shape, scale, z, T, ndrange=size(y))
  ```
]<fig:reuse-kernel>

In terms of memory efficiency, the kernel implementation (@fig:reuse-kernel) shares the benefits of the loop implementation. However, the two atomic operations negate most of the performance benefits of GPU parallelization, as the high number of locking operations is rather inefficient. In addition to that, the order of summing is no longer deterministic, which causes inconsistent results due to floating point inaccuracies and decreases numerical stability. Practically speaking, that can result in `NaN` values within the accumulated values.

One might ask how the built-in `sum` operation handles summing in an efficient and deterministic way on the GPU. CUDA.jl implements accumulation using a hierarchical summing algorithm. The algorithm roughly works as follows:

1. Within each GPU processing block, one thread loads a batch of data to a block local variable
2. The threads of the block hierarchically accumulate the local data as shown in @fig:hierarchic-sum, until the local sum is found in `scratch[1]`. Due to the `thread <= d` condition, each loop iteration halves the number of threads that perform the summing
3. `scratch[1]` is written to another vector, with one element per GPU block, and a second kernel is launched which sums over the outputs of the former step.

#figure(caption: [Schematic representation of the hierarchic summing step])[
  ```jl
  while d > 0
    @synchronize()
    if thread <= d
        ai = offset * (2 * thread - 1)
        bi = offset * (2 * thread)
        scratch[bi] += scratch[ai]
    end
    offset = offset * 2
    d = d ÷ 2
  end
  ```
]<fig:hierarchic-sum>


We considered implementing this algorithm in our custom kernels, but ultimately found that we were not able to match the performance of the built-in CUDA.jl implementation. As this approach significantly increases the complexity of our implementation, we decided it was not worth further investigation.

A further limitation of the kernel implementation is that CPU performance in our tests wasn't on par with a comparable broadcast or loop implementation, probably due to the overhead of dispatching a high number of tasks.

==== GPU port of AMICA.jl

Based on the discussed tradeoff between broadcasts and kernels, we chose the following design when adding GPU support to AMICA.jl.

The *initial preparation* logic, consisting of subtracting the means, sphering and parameter initialization, runs on the CPU. As those steps are executed only once and typically neither memory use nor duration is a bottleneck, porting them to the GPU was not a priority.

The main logic of the AMICA algorithm is computed on the GPU using broadcasts. There are two exceptions for which we decided to use custom kernels, which we discuss in more detail below.

*Updating `z` and `LL`* in a kernel has the advantage that `logsumexp_Q` can be used to update `z` and `LL` without allocating `logsumexp_Q`, `Qmax` or `z_sum`, all of them having the number of samples as one of their dimensions. As the only accumulation is for the per sample likelihood `LL`, only $"m" * "mixtures"$ locking operations happen for each sample and lock congestion thus is not as much of an issue compared to other accumulations.

*Computing the newton method parameter `B`* in a kernel has two advantages. First, `B` is defined differently for diagonal vs non diagonal elements, which is difficult to implement using broadcasts. Second, the `posdef` value is based on an intermediary computation used to calculate `B`, which would be hard to access when implemented as broadcast. As no summing happens and `posdef` is only ever flipped from `true` to `false`, no locking is required.


#perf_sidebar(4, 2)
Benchmarks of this implementation are promising. Time per iteration is reduced by around a factor of 70, but memory usage is still lagging behind the Fortran implementation, especially when running on GPU. The test suite still passes and the resulting @ll matches Fortran.

=== Blockwise Processing

After adding GPU acceleration, we found that the high memory use of AMICA.jl might be a prohibitive factor in running it on larger datasets, as especially GPU memory is often constrained. To improve on this, we implemented a pattern also found in AMICA Fortran, called blockwise processing.

Accumulation is critical to the AMICA algorithm. Several steps follow a similar pattern: First, a value is computed for each sample, component and mixture. The results of this computation are then accumulated per component and mixture.

As discussed before and shown in @fig:reuse-cpu, the most memory efficient way of implementing such computations is a loop, which however is hard to implement in a performant way on GPU or to parallelize in general.

Blockwise processing is a compromise between full dataset broadcasts and a single loop. The dataset is divided into a number of blocks, which are then processed independently. Each block is transformed and accumulated. The result of the accumulation is then added to the final result. If blocks are processed in sequence, this theoretically reduces the required amount of memory relative to block size versus full problem size.

#figure(caption: [Schematic representation of blockwise processing])[
  ```jl
  # without blocks
  scratch .= (z .* (y_rho .* sign.(y) .* shape))
  dmu_numer .= sum(scratch, dims=1)[1, :, :]

  # with blocks
  dmu_numer .= zero(T)

  for blocks in 1:num_blocks
    range = ((block-1)*block_size+1):(block*block_size)
    scratch .= (z[range] .* (y_rho[range] .* sign.(y[range]) .* shape[range]))
    dmu_numer .+= sum(scratch, dims=1)[1, :, :]
  end
  ```
]<fig:blockwise>

To implement blockwise processing in AMICA.jl, we first had to change the code structure to allow certain steps to run per block before using the results to update the gaussian parameters and the mixing matrix. To do that, we pulled the computation of `z`, `LL`, `y`, `y_rho` and `source_signals` into the method previously called `update_parameters`. This allows us to directly use the values computed for the current block, effectively making them local variables within the block loop body. We also reduced the dimensions of the corresponding fields in the `SingleModelAmica` to the configured block size.

#perf_sidebar(6, 4)

Using this approach and a block size of 1000 samples, memory consumption of the AMICA algorithm is reduced to around 1GB of memory. Compared to the previous benchmark, GPU performance suffers, which is expected given that the GPU can no longer parallelize over the whole dataset but is instead limited to a number of threads equal to the block size. The former 0.1 s iteration time for GPU executions is however still achievable using a block size of 10.000 (0.13 s / iteration), so introducing blockwise processing has not caused a regression of the optimal GPU performance. Setting an appropriate block size is, in the GPU case, a tradeoff between memory use and processing time.

=== Object Pool

Despite blockwise processing, a certain amount of memory has to be allocated to store intermediary results, before e.g. accumulating them. There are different approaches to handling this. The most trivial implementation would be to always allocate what's required and let Julia's garbage collector free memory once it is no longer needed. While this, given perfect garbage collection, shouldn't change peak memory use of the algorithm, it still brings an overhead of frequently allocating and freeing huge chunks of memory.

A way to optimize this is to preallocate arrays and reuse them across iterations. As most arrays are only required for a short time, it also makes sense to reuse them for different computations, as shown for the `scratch` array in @fig:reuse2. However, a single `scratch` array is not sufficient to implement the AMICA algorithm, as several arrays are written and released in an interleaving manner. Manually implementing this using a set of preallocated arrays was tedious and error-prone.

#{
  show figure: set block(breakable: true)
  [#figure(caption: [Different ways of managing temporary arrays])[
    ```jl
    # allocates "intermed" in each iteration
    for i in 1:100
      q = calc_q()
      sum_q = sum(q, dims=1)

      fp = calc_fp()
      sum_fp = sum(fp, dims=1)
    end

    # preallocate and reuse
    q = Array(undef, n, m)
    fp = Array(undef, n, m)
    for i in 1:100
      q .= calc_q()
      sum_q = sum(q, dims=1)

      fp .= calc_fp()
      sum_fp = sum(fp, dims=1)
    end

    # reuse scratch array
    scratch = Array(undef, n, m)
    for i in 1:100
      scratch .= calc_q()
      sum_q = sum(scratch, dims=1)

      scratch .= calc_fp()
      sum_fp = sum(scratch, dims=1)
    end

    ```
  ]<fig:reuse2>]
}

To simplify the management of temporary arrays while still avoiding excessive allocations, we implemented a concept called Object Pool. It consists of a struct holding a configurable number of temporary arrays, together with two methods to acquire and release them. When acquired, the array is reshaped to the requested proportion and then blocked for other acquirers. Once released, it is available to be acquired again. The user still needs to make sure that a released array is no longer used after releasing it. To debug such situations, we added a flag which "poisons" all released arrays by writing NaN to them, making it easier to spot operations which operate on a previously released array. While manually managing a scratch array would be simpler in the example shown in @fig:objectpool, AMICA.jl requires seven such arrays, and manually managing and reshaping them would require significant effort.

#figure(caption: [Using the object pool to manage temporary arrays])[
  ```jl
  pool = ObjectPool{T}(n * n, 1) # pool with capacity 1
  for i in 1:100
    q = pool_acquire!(pool, (n, n))
    q .= calc_q()
    sum_q = sum(q, dims=1)
    pool_release!(pool, q)

    fp = pool_acquire!(pool, (n, n))
    fp .= calc_fp()
    sum_fp = sum(fp, dims=1)
    pool_release!(pool, fp)
  end

  ```
]<fig:objectpool>

=== Multithreading

Without further adjustments, computations in Julia are not parallelized on the CPU but run within a single thread. In addition, parallelization needs to be structured differently on a CPU, compared to a GPU, as the number of concurrent tasks is significantly lower while the speed of execution is higher. Simply porting all GPU threads to the CPU would most likely lead to suboptimal results, as the per-thread overhead is higher on a CPU, and also the CPU wouldn't be able to apply optimizations like SIMD to the computations. It is therefore desirable to break the algorithm into larger chunks, e.g. equal to the number of processor cores, and run them in parallel.

Blockwise processing already splits the AMICA algorithm into work units of configurable size. It is therefore logical to leverage the block logic for CPU parallelization, by launching a number of threads where each thread independently processes a set of blocks and accumulates their results. As a second step, the per thread results are then accumulated to the final value.

To implement this, we add a thread count variable to the `SingleAmicaStruct` and initialize one Object Pool per thread. Additionally, we need to add a second layer of accumulation. To store the values to be accumulated, we define a new `BlockAccumulators` struct which is filled by each thread.

Finally, we spawn the threads and add accumulation of the resulting `BlockAccumulators`. A schematic example is shown in @fig:multithreading, with the variable `dmu_numer_acc` representing one field within the `BlockAccumulators` struct.

#figure(caption: [Schematic representation of multithreaded blockwise processing])[
  ```jl
  # accumulator with extra per thread dimension
  dmu_numer_acc = Array(undef, nthreads, n, m)

  # spawn threads
  Threads.@threads for tid in 1:nthreads
    for blocks in 1:num_blocks
      range = ((block-1)*block_size+1):(block*block_size)
      scratch .= (...) # some computation
      # accumulate to local accumulator
      dmu_numer_acc[tid, :, :] .+= sum(scratch, dims=1)[1, :, :]
    end
  end

  # accumulate results
  dmu_numer .= sum(dmu_numer_acc, dims=1)[1, :, :]
  ```
]<fig:multithreading>

#perf_sidebar(7, 4)

The introduction of multithreading has negligible impact on the single threaded benchmarks. However, parallelizing AMICA by 64 threads significantly cuts iteration times, roughly by a factor of 8 compared to the single threaded execution. As each thread requires its own object pool, memory consumption rises when the thread count is increased, a phenomenon that is similarly present in AMICA Fortran.

As the object pool represents only a part of the memory use of AMICA.jl, we still see a static part of memory usage and memory therefore does not increase linearly with thread count, but instead thread count can be seen as a multiplier to the block size, accompanied by some overhead due to the thread spawning and the `BlockAccumulators` struct.

#pagebreak()

== Benchmarks

To assess the effectiveness of our changes, we performed a series of AMICA executions with 259 distinct parameterizations, measuring iteration time after the first iteration, peak CPU memory and peak GPU memory. We ran all benchmarks six times with 40 iterations each, resulting in 1,554 total runs. Unless noted otherwise, we followed the benchmarking methodology described in @chapter:benchmark. The exact algorithm used to determine the set of parameters is shown in @appendix:paramalgo.

For all of the following benchmarks, we skipped configurations in which not every thread had at least one block (i.e., block size ≤ samples / threads), as otherwise some threads would be idle and the degree of parallelization would no longer be comparable. Additionally, we did not benchmark configurations with both multithreading and GPU acceleration enabled, as the GPU already parallelizes operations and there is no added benefit of starting those GPU operations in multiple threads.

Given these benchmark results, we first show that our final implementation is algorithmically correct. We then compare the memory use and runtime of AMICA.jl and AMICA Fortran across several datasets and configurations. Finally, we present an analysis of the performance bottlenecks in our AMICA.jl implementation.

=== Correctness

To verify correctness of our implementation, we execute AMICA.jl for all three datasets and compare the resulting log-likelihood to the output of AMICA Fortran. The graphs in @fig:correctness show that the likelihood closely tracks Fortran using both the CPU and GPU backend, with 32-bit and 64-bit precision. We conclude that AMICA.jl now reliably computes results that match the output of the Fortran implementation.

#figure(
  caption: [Per iteration log-likelihood by implementation: all implementations closely track the LL of AMICA Fortran],
)[
  #image("figures/ll_compare_memorize_big_iter40.svg")

]<fig:correctness>


=== Runtime
The execution time is a key factor in the practical usability of the AMICA algorithm. To achieve good unmixing, 1000 or more iterations often need to be performed, meaning the algorithm can take several hours to complete. Shortening runtime is therefore beneficial and directly reduces the time and, potentially, costs involved in using AMICA.

We present various influencing parameters and a comparison of the different implementations below. The full results of our runtime benchmarks can be found in @appendix:fullitertime.


#figure(
  caption: [Iteration time by block size. We omit configurations with a _block count_ smaller than thread count.],
)[
  #image("figures/runtime_vs_blocksize_big.svg")
]<fig:runtime_vs_blocksize_big>

In theory, block size (i.e. number of samples per processed block) should only play a minor role in execution time, as the same operations are performed in a different order. This was largely confirmed by our benchmarks as shown in @fig:runtime_vs_blocksize_big. Although there were minor differences in iteration times, we do not consider block size to be the decisive parameter for execution time.

Block size starts to significantly influence runtime once parallelization is enabled. If the block size is smaller than the maximum number of GPU threads, the GPU is not fully utilized and execution is therefore significantly slower, as shown by the benchmarks with block size 100 and 1000.

The same applies with multithreading on the CPU and $"block_size" > "n_samples" / "n_threads"$, which leads to a situation where there are fewer blocks than threads, effectively reducing the parallelism to the number of blocks. We exclude these configurations from the benchmarks because memory usage often prevents execution (since memory depends on $"thread_count" * "block_size"$). Furthermore, it is clear that an execution with a number of threads equal to the number of blocks will always perform as well or better.

Due to the minor role of block size, we will not list it as a separate dimension in the following benchmarks. Instead, we will select the optimal block size for each parameterization and display only its result.

#figure(
  caption: [Iteration time across datasets: Runtime increases significantly with problem size, but relative differences between parameterizations remain comparable],
)[
  #image("figures/runtime_best_impl_per_dataset.svg")
]<fig:runtime_best_impl_per_dataset>

In the following, we compare how the implementations react to different problem sizes and how runtime differs between implementations when using the optimal blocksize. @fig:runtime_best_impl_per_dataset shows a comparison of AMICA Fortran with one or 64 threads versus AMICA.jl with one thread, with 64 threads, or with GPU acceleration, each with Float32 data or Float64 data. The comparison reveals a similar picture regardless of dataset size: the fastest implementation is AMICA.jl on the GPU, with a speedup of between 2x and 6.6x compared to multithreaded Fortran. This is followed by the multi-threaded CPU implementations, where the results are mixed. In some cases, AMICA Fortran is faster, and in others, AMICA.jl is faster. However, switching to Float32 in AMICA.jl results in a speed advantage in all cases.
Overall, we conclude that AMICA.jl with GPU acceleration outperforms the multi-threaded Fortran implementation in all cases. Furthermore, our implementation of multithreading is effective and delivers similar results to the multi-threaded Fortran code. The runtime of all implementations increases comparably with the size of the dataset.


#figure(caption: [Iteration time by thread count])[
  #image("figures/runtime_per_iter_big_threads.svg")
]<fig:runtime_per_iter_big_threads>

To examine the effects of multithreading in more detail, we compare the results of AMICA Fortran and AMICA.jl with different numbers of threads in @fig:runtime_per_iter_big_threads. The results show that the greatest performance improvement is achieved between 16 and 24 threads and that further increases have diminishing returns. However, Fortran achieves a greater improvement than Julia when increasing from 16 to 24 threads. Multithreading therefore effectively reduces the runtime of the AMICA algorithm in all implementations, but the effects do not scale indefinitely.

From these results, we conclude that the CPU performance of AMICA.jl is similar to that of AMICA Fortran, multithreading effectively reduces the runtime of AMICA, and GPU acceleration is effective and outperforms all other implementations. The change from 64-bit to 32-bit precision in AMICA.jl is also an effective method of reducing execution time in all configurations.
In addition, we have shown that the choice of block size has only a minor effect on the iteration time as long as the block size is small enough to utilize all CPU threads or large enough to utilize all GPU threads.

=== Memory Usage


The @eeg datasets on which AMICA is typically applied can be many megabytes to gigabytes large. Since the algorithm must allocate the entire dataset and additional intermediary results, memory use can become a limiting factor. We thus compared the peak CPU and GPU memory use of the AMICA implementations along three dimensions: block size, problem size and implementation. We omit multithreaded runs from the following benchmarks as the number of threads basically acts as a multiplier to the block size (with some additional overhead).
The full memory usage results of our benchmark series can be found in @appendix:fullmem.

In order to draw a comparison between the different implementations and to demonstrate the effect of individual configuration parameters on memory consumption, we will now present several illustrative comparisons of these results.

To establish a baseline, we first benchmarked memory use with *blockwise processing disabled*. Looking at the results in @fig:memfullblock, we see that all implementations outperform the 7.5GB of memory AMICA.jl used on the Memorize dataset before this project.

#figure(caption: [Memory use across datasets without blockwise processing])[#image(
  "figures/memory_full_block_all_datasets.svg",
)]<fig:memfullblock>

Fortran is still among the most efficient implementations, only beaten by the Float32 Julia implementation for the two larger datasets. Comparing the Float64 CPU implementations, Fortran is noticeably more memory efficient than Julia, with the offset increasing for larger datasets, and the Julia GPU implementation requiring slightly more memory than the CPU version. When looking at combined CPU and GPU memory use, AMICA.jl requires more memory when running on the GPU than on the CPU. We suspect that the reason is the memory required to load the CUDA library, which already uses over 1GB of memory, as well as some overhead of loading the dataset to the CPU and then duplicating it to the GPU.

We implemented *blockwise processing* to reduce the memory consumption of our AMICA implementation. In @fig:mem1000block, we compare the memory used when blockwise processing is enabled, for all three datasets and block size 1000. The dim bars show the values without blockwise processing for comparison. Blockwise processing significantly reduced memory consumption, with the strongest reduction seen on the largest dataset. However, memory usage continues to be influenced by the size of the dataset, even though blocks of identical size are now used regardless of the problem size. We assume that this is due to the initial loading of the data and some computation steps that still operate on the full dataset.

#figure(
  caption: [Memory use across datasets with block size 1000, compared to blockwise processing disabled (dim bars)],
)[#image(
  "figures/memory_block_1000_all_datasets.svg",
)]<fig:mem1000block>

Setting the correct block size is an effective way to influence AMICA's memory usage. We have therefore evaluated the influence of different block sizes in more detail and show a comparison of different block sizes and the resulting memory usage in @fig:membyblock. It shows that the greatest savings are achieved when reducing the block size to 10,000, and that further reductions to 1,000 or 100 actually worsen the results for the Julia implementation. One possible reason for this is that the block loop runs extremely frequently with very small blocks, meaning that the garbage collector does not clean up often enough to free up memory after each iteration. Memory usage was largely consistent across samples, with the exception of CPU memory for GPU runs, where we saw occasional outliers. We suspect that the reason for those outliers is Julia's non-deterministic garbage collection, but cannot explain why they primarily occur in GPU runs.

Another finding of this analysis is that the CPU memory required for execution on the GPU does not increase with the size of the blocks, but remains constant. The benchmarks also demonstrate that switching to Float32, with or without blockwise processing, leads to a significant reduction in the amount of required memory.

#figure(caption: [Memory use across block sizes])[#image(
  "figures/memory_vs_blocksize_big_no_full_block.svg",
)]<fig:membyblock>


From these results, we conclude that the changes made to AMICA.jl, in particular the implementation of blockwise processing, have achieved a significant reduction in memory requirements. The memory requirements of AMICA.jl are slightly higher when using Float64 data, but lower than AMICA Fortran when using Float32 data. The required GPU memory is slightly lower than the memory required by the CPU implementations, but an additional static amount of CPU memory is required to load the dataset and the CUDA library.


#figure(caption: [Performance breakdown of a single threaded execution of AMICA.jl])[
  #image("figures/bottleneck.png", width: 80%)

]<fig:bottleneck>

=== Bottlenecks
In addition to the aforementioned performance benchmarks, we will now discuss the output of the fine-grained benchmarks obtained by integrating the `TimerOutputs.jl` library. @fig:bottleneck shows the evaluation of four single-threaded iterations of AMICA.jl with block size 5000.


The output shows that most of the runtime is spent in the `update_parameters` function and, within that, in the `process_blocks` function. This is relevant because it is the part parallelized by our implementation of multithreading. When analyzing the top four areas (`y_rho`, `source_signals`, `drho_numer`, `expQ`), we see that the dominant operations perform `log`, `exp` and `mul` operations on arrays with large dimensions. We therefore conclude that we were able to eliminate most other overhead and that these operations are now the main limiting factor in further improving the implementation's runtime.

We additionally note that only around 8 percent of the memory is allocated within the measured areas, which means that most allocations happen outside of AMICA's main loop, most likely during construction of the `SingleModelAmica` object. This shows that we successfully reduced repeated allocations and instead pre-allocate the required memory.

#figure(caption: [Computations within the slowest operations (simplified)])[
  ```jl
  # y_rho
  y_rho .= exp.((myAmica.shape .- 1.0) .* log.(abs.(y)))

  # source_signals
  mul!(source_signals, data, W')

  # drho_numer -> log
  z .* log.(scratch) .* scratch

  # expQ
  expQ .= exp.(Q .- Qmax)
  ```
]<fig:bottlenecks>


= Discussion

We now discuss the practical and theoretical results of our work and address the research question of whether an optimized version of AMICA.jl can match the Fortran reference in terms of correctness and performance.


== Correctness and Convergence
By adding a comprehensive test suite and adjusting the AMICA.jl implementation in around 15 aspects, we aligned the results to AMICA Fortran and then verified that alignment by comparing the @ll for three different datasets. We regard the matching @ll as a clear proxy for correctness and consider this the most important achievement of our work, as it is the foundation of the practical usability of AMICA.jl and of all performance benchmarks, since only a benchmark of a correct algorithm allows for a meaningful comparison with the reference.

The delayed convergence and problems with numerical stability indicated that there were not only minor bugs in AMICA.jl, but also fundamental differences in the implementation. We see this confirmed in the number and scope of the changes we made, which required us to completely rewrite entire functions. At the same time, this also shows that AMICA's results are sensitive to small differences in implementation, and that maintaining a correct implementation is therefore important. The test suite can also ensure this for future adjustments.

== Runtime

Our implementation of GPU support and multithreading, as well as the benchmarks discussed above, show that AMICA contains sufficient parallel work to be effectively parallelized across multiple processor cores or even a GPU. We thus demonstrated that implementing GPU support in AMICA is possible and effective, and that this can achieve iteration times that surpass AMICA Fortran.

When comparing the impact of different measures, our benchmarks show that parallelization on the GPU is the strongest contributor to runtime improvement. Multithreading on the CPU also proved effective, but showed diminishing returns beyond 16 threads and could not match the performance of the GPU implementation.

Comparing our implementation with AMICA Fortran, we therefore conclude that AMICA.jl is competitive on the CPU and measurably exceeds the reference implementation's performance when running on the GPU.

By improving numerical stability in some areas, we have ensured that AMICA.jl reliably calculates the same results as AMICA Fortran, even when using Float32 data types. This provides an additional performance advantage without noticeable downsides. However, we cannot rule out with certainty that certain data sets, such as very small problems, might still result in numerical issues. Therefore, it should be determined on a case-by-case basis whether using 32-bit precision is sufficient.


== Memory


In addition to runtime, memory consumption is the other constraining factor for AMICA. Memory is typically limited, especially on the GPU, so economical memory usage provides a significant advantage in the practical usability of AMICA.jl.

By implementing blockwise processing, we were able to achieve a drastic reduction in the memory requirements of AMICA.jl, especially for larger datasets. Memory usage is now no longer only determined by the size of the dataset, but can be influenced by choosing an appropriate block size. However, the size of the dataset continues to play a role in memory consumption, suggesting that some parts of the implementation still operate on the entire dataset or incur a fixed overhead.

We have shown that block size generally plays a minor role in runtime, but in combination with parallelization on the CPU or GPU, there can be a trade-off between runtime and block size, and thus memory consumption. When running AMICA.jl on the CPU, we found that large block sizes can result in not every thread having a block to compute, thereby reducing the effective parallelism to the number of blocks. When running on the GPU, small block sizes reduce parallelism because there is not enough data being processed simultaneously to utilize all GPU threads. Finally, very small block sizes can always cause a certain amount of overhead, which is a disadvantage compared to larger blocks.

Compared to Julia, AMICA Fortran remains the most memory efficient implementation when working with 64-bit data. Julia became more competitive by our changes, and surpassed Fortran when working with 32-bit precision. The GPU acceleration requires a similar amount of GPU memory compared to CPU only executions, but also allocates a static overhead of CPU memory.


== Practical implications
Our improvements are not only theoretical but make a significant difference in the practical applicability of AMICA.jl, for example in @eeg workflows. The correctness of the implementation ensures an unmixing of the data that is comparable to the Fortran reference implementation and thus forms the basis for the practical applicability.

Shorter iteration times lead to a noticeable reduction in evaluation time, and potentially cost, especially since AMICA is typically executed for hundreds or thousands of iterations. For example, 1000 iterations on the "EEG Eye Tracking" dataset require about 4:10 minutes using GPU acceleration and 32-bit precision, compared to 25 minutes required in the fastest AMICA Fortran configuration. Since typical consumer PCs often have significantly fewer than 64 cores, we believe it is likely that the practical difference will be even greater.

In @eeg studies, it is common to analyze not just a single EEG recording but several subjects. A common approach is to run several AMICA processes simultaneously, as this results in significantly more efficient parallelization than multithreading within the implementation can offer. In those settings, memory can be a key factor in scalability, and therefore our improvements in memory usage can increase the practically achievable degree of parallelization. For example, when running AMICA.jl (32-bit precision) on 16 subjects, given sufficient memory available, we could run all 16 subjects in parallel with four threads on our 64 core machine. This would result in a theoretical runtime of around 9:25 minutes per AMICA, which significantly beats the 43 minutes required for a single 64 thread AMICA. This example shows that efficient memory use can enable significantly more efficient parallelism on the CPU compared to multithreading within the implementation, but GPU acceleration is still twice as fast as the given example.

Our implementation, however, is attractive not only because of its speed, but also because it is easier to understand, maintain, and extend than the Fortran code. AMICA.jl therefore provides a useful compromise between accessibility and high performance.

== Limitations

=== Gaps in the Implementation
While we believe this work made significant improvements to AMICA.jl, we also want to recognize the following limitations of our findings.

First, we would like to note that although AMICA.jl implements the basic algorithm, it currently omits some notable features. AMICA Fortran offers multi-model functionality, where different models are active for each sample, which provides the benefit of supporting non-stationary settings. This feature used to be present in AMICA.jl but remains to be re-implemented with appropriate unit-tests. AMICA Fortran also includes functionality to choose the optimal block size, a helpful feature that makes it easier to find the optimal parametrization, and likelihood-based data-rejection which automatically rejects samples of low likelihood. AMICA.jl currently also omits the multi-node processing that Fortran implements using the MPI library, and which allows splitting larger chunks of work across multiple machines, possibly increasing the amount of usable compute.

With regards to performance, while we are able to match AMICA Fortran performance using GPU acceleration or 32-bit precision, AMICA.jl is still slightly behind Fortran in regular single- or multi-threaded executions. We see no systematic reason why a Julia implementation couldn't exactly match the Fortran performance, so future work might explore how those remaining gaps might be closed.

Our bottleneck analysis showed that we were able to mitigate most overheads in AMICA.jl, so the current constraining factors are certain mathematical operations like `log`, `exp` or `mul`. Future work could focus on ways to specifically improve those parts, for example by implementing the Intel Vector Math library, previously called Intel MKL, as supported by the Fortran implementation.

The first iteration of AMICA.jl continues to be considerably slower than the subsequent iterations; we typically saw static offsets of around 10s for GPU runs and around 0.1s for CPU runs, a fact that we omit in our benchmarks. We suspect this might be due to Julia's just-in-time compilation and type inference, and thus it is unclear to which degree this could be improved. In addition, we tested GPU acceleration only on the CUDA and Metal backend and have to acknowledge that support is much more limited on Metal, primarily restricted by the feature set of the Metal.jl library.

While our test suite compares several intermediary variables and outputs, and runs with and without Newton Method, we acknowledge that it currently does not cover all code paths; for example, it does not test a fallback from the Newton Method to the natural gradient.

=== Gaps in the Benchmark
While we ran a large number of distinct benchmark configurations, and repeated each benchmark six times to determine the median result, we still covered only a limited number of influencing factors and parameters. The selection of data sets was limited to three, we only tested AMICA Fortran in the MKL variant (recommended in private communication with Jason Palmer), and we also excluded multi-node support. In the analysis of our benchmarks we omitted the influence of multithreading on memory use, which mainly acts as a multiplier to the block size, but also brings some additional overhead which could be further explored. Since we ran all the benchmarks on an AMD CPU, we cannot rule out that the Intel MKL library used within the Fortran implementation would perform better on Intel CPUs.

Since all benchmarks were run on the same hardware setup, their results shouldn't be generalized without caution. Although comparisons between different implementations are feasible, comparisons between CPU and GPU are only of limited meaning, as their relationship is highly dependent on the respective hardware: For example, the acceleration provided by the GPU compared to the CPU could vary significantly with a different GPU model. It should also be noted that we used a shared server, so the influence of other users' workloads cannot be ruled out.

#pagebreak()

= Summary


// - AMICA.jl now is not only correct but also practically fast enough to be competitive in a realistic setting

// - the project substantially improved the scalability of AMICA.jl, even if memory efficiency is not uniformly better than Fortran in all configurations

// - could reduce computational cost and broaden access to AMICA in research environments without very large compute resources

Our work evolved AMICA.jl from a promising but unreliable re-implementation into a credible alternative that is competitive in terms of computational performance. We achieved this improvement through a combination of algorithmic correctness, improvements to numerical stability, restructuring to improve memory usage, and two forms of parallelization.

By adding a comprehensive test suite, we ensured that regressions introduced during our work or by future changes are identified quickly. Extensive benchmarks allow performance to be measured in terms of timing and memory allocation on a per-function basis.

We showed that adding GPU acceleration to the AMICA algorithm is feasible and that it significantly improves runtime. We implemented blockwise processing as a measure to reduce memory usage and added multithreaded CPU execution. These new features specifically lower the barrier to running AMICA.jl on large @eeg datasets.

By increasing numerical stability, mainly by clamping very small intermediate values to a small epsilon, AMICA.jl can now work with 32-bit precision while still reliably computing a comparable unmixing, further lowering resource usage and offering a capability not present in AMICA Fortran.

Our work therefore substantially improves the practical usability of AMICA.jl and positions it as a more accessible high-performance alternative to the reference Fortran implementation.
