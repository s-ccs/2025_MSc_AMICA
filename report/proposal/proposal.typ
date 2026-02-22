// A central place where libraries are imported (or macros are defined)
// which are used within all the chapters:
#import "utils/global.typ": *


// Fill me with the Abstract
#let abstract = [#lorem(150)]

// Fill me with acknowledgments
#let acknowledgements = [#lorem(50)]


// if you have appendices, add them here
#let appendix = [
  = Appendices
  //#include "./chapters/appendix.typ"
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
    key:"pdf",
    short:"PDF",
    long: "Probability Density Function"
  ),
  (
    key:"mgg",
    short:"MGG",
    long:"Mixture of Generalized Gaussian distribution"
  ),
  (
    key:"gsms",
    short: "GSMs",
    long: "Gaussian Scale Mixtures"
  ), 
  (
    key:"em",
    short: "EM",
    long: "Expectation Maximization"
  )
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
    // (
    //   title: "Second Supervisor",
    //   name: "Max Mustermann",
    //   affiliation: [Computational Cognitive Science \
    //     Faculty of Electrical Engineering and Computer Science, \
    //     Department of Computer Science
    //   ],
    // ),
  ),
  epigraph: none,
  // abstract: abstract,
  // appendix: appendix,
  // acknowledgements: acknowledgements,
  preface: none,
  figure-index: false,
  table-index: false,
  listing-index: false,
  abbreviations: abbreviations,
  date: datetime(year: 2025, month: 9, day: 1),
  bibliography: bibliography("refs.bib", title: "Bibliography", style: "ieee"),
)

// Code blocks
#codly(
  zebra-fill: none,

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

// If you wish to use lining figures rather than old-style figures, uncomment this line.
#set text(number-type: "lining")

// Main Content starts here

// Proposal Phase:
= Introduction <chp:introduction>
== Motivation
@ica is a method for decomposing mixed source signals (mixtures) into their additive components, a problem category known as @bss. @stone2004independent

An example, named the "cocktail party problem", is a room with people speaking, recorded by multiple microphones. As the microphones are placed in different positions, the intensity of the recorded voices varies by recording. @ica can be used to decompose those mixed signals back into the source signals, the distinct speakers. @stone2002independent

The algorithm @amica as introduced by #cite(<palmer2012amica>, form: "prose") is a popular implementation of @ica, especially in the area of @eeg signal processing, where it's used to isolate signals measured by electrodes attached to a skull. It extends previous @ica implementations in two aspects, by including support for non-stationary signals and by using a @mgg to estimate the density of the source signals.

There are currently multiple implementations of @amica, the reference implementation in Fortran developed by Jason Palmer @amicaweb as well as implementations in Matlab @amicamatlab and Julia @lulkin. The implementation in Fortran performs well - however, it's difficult to maintain, compile and extend and lacks compatibility with programming languages commonly used in science like Python or Julia. The implementation in Matlab is more approachable, but has worse performance in terms of convergence quality and computational efficiency. The implementation in Julia, modeled after the Matlab version, suffers from those same issues.

This planned work aims to improve and extend the Julia implementation of the @amica algorithm, with the goal to reach convergence and performance similar to the reference implementation. In addition to that, it's planned to explore adding GPU support to better exploit the capabilities of modern hardware. Aside those technical aspects, documentation of AMICA.jl shall be improved throughout the project.

== Other work

=== Independent Component Analysis

@ica is a "method for extracting individual signals from mixtures of signals" @stone2002independent, a specific type of @bss. While several algorithms to solve @ica have been proposed over the years, they share the ideas that (a) the source signals are independent of each other while the recorded mixtures are not and (b) all but one source signal have a non-gaussian @pdf. @stone2002independent@naik2011overview@lee1998independent

More formally, a linear transformation from source signals $s$ to mixtures $x$ using the (unknown) mixing matrix $A$ is assumed:

$ x = A*s $

Which in turn enables an estimate of the source signals $s$ (sometimes denoted as approximated source signals $hat(s)$) using the unmixing matrix $W=A^(-1)$:


$ s = x*W $

The goal of the @ica algorithm is to approximate the unmixing matrix $W$, and thereby the source signals $s$ and the mixing matrix $A$. This process can be visualized as _rotating_ the mixtures versus the sources. Different approaches exist. Some work by maximizing the entropy of the signal while others, like @amica, maximize the likelihood of the unmixed data. @pearlmutter1996maximum @stone2004independent

=== AMICA

@amica is an @ica algorithm based on maximum likelihood estimation, which extends other maximum likelihood based @ica approaches in the following two ways.

First, instead of assuming a fixed @pdf for the source signals, @amica models the (assumed) density of the source signals $q_(i)(s_i (t))$ as a mixture of $m$ @gsms $q_(i j)$ parametrized by $rho_(i j)$. The mixing of the @gsms is defined by @mixing which additionally includes a shift of the components by $mu_(i j)$ and scaling by $sqrt(beta_(i j))$ where $0 < beta < 2$. @palmer2012amica

$ q_(i)(s_i (t)) = sum_(j=1)^m alpha_(i j) sqrt(beta_(i j)) q_(i j)(sqrt(beta_(i j))(s_i (t) - mu_(i j)); rho_(i j)) $ <mixing>


Based on the estimated source $y_t = W x_t$ and the density model (defined above) $q_i (y_i)$, the algorithm computes the negative log-likelihood $L(W)$ of the observed data under the current $W$ and the current source density model, which is then minimized. @palmer2012amica

$
  // q(y_t) &= product_i q_i(y_(i t)) \
   f(y_t) &= sum_i (-log q_i (y_(i t))) \
   L(W) &= sum_(t=1)^N -log | det W| +f(y_t)
$ <loglikelihood>

Therefore, the single model @amica estimates ${W, alpha_(i j), mu_(i j), beta_(i j), rho_(i j)}$.

Second, @amica includes support for estimating multiple models which improves unmixing in scenarios where the source signals are non-stationary. A model index $h in {1..M}$ is added to the parameters of the source density model and to the unmixing matrix $W$. $gamma_h$ indicates the probability that a model is active at time $t$, and exactly one model is active for each $t$. Each model is centered by $c_h$. @palmer2012amica

This extends these estimated parameters to ${W_h, c_h, gamma_h, alpha_(h i j), mu_(h i j), beta_(h i j), rho_(h i j)}$ where

$ x(t) = A_h s(t) + c_h $

To optimize those parameters, the @amica algorithm uses @em to iteratively assign samples to models and source-mixture components and then updates the unmixing matrix and density-parameters.

In addition to the algorithmic improvements, the @amica implementation provides advanced features like distributed execution on clusters of Linux machines. @amicaweb

=== AMICA.jl
AMICA.jl first implemented by #cite(<lulkin>, form: "prose") is an implementation of the AMICA algorithm modelled after the Matlab implementation @amicamatlab. Both implement the basic @amica algorithm and contain multi model functionality.

Compared to the reference fortran implementation, they perform around 10x slower and omit block based learning as well as parallelization across nodes. Convergence has shown to lack compared to the fortran algorithm.

=== GPU Programming in Julia
While Julia code runs on the CPU by default, several Julia packages provide powerful abstractions to port existing code to the GPU. Broadly speaking, there's two levels of abstraction:

1. *High level* abstractions provided by libraries like CUDA.jl @cudajl or AMDGPU.jl @amdjl expose custom array types such as `CuArray` which behave like regular Julia arrays but store data in the GPU memory and run operations performed on those data types on the GPU. This allows using common Julia operations like vector or matrix multiplications, broadcasts, map, reduce etc. on the GPU. In addition to that, vendor provided libaries for AMD and Nvidia GPUs expose precompiled GPU kernels for common operations like matrix multiplication, which work with the aforementioned array types. While simple to implement, this GPU integrations might be limited in which computations are supported. @juliaforhpc


#figure(caption: [High level gpu abstraction in julia, adapted from @juliaforhpc], kind: raw)[
```jl
using CUDA

A = CuArray([0,1,2,3,4,5,6])
A .+= 1 # runs on GPU
```
]


2. *Lower level* abstractions provide more control on how computations are executed on the GPU by writing custom kernels in Julia. The CUDA.jl packages provides a `@cuda` macro which runs arbitrary code on the GPU, however, work needs to be split across GPU threads manually, by calling the `threadIdx` function to obtain the index of the current GPU thread and then perform work on the right block of data. To simplify this, the KernelAbstractions.jl @kernelAbstractions package provides utilities to efficiently parallelize work on the GPU without manually managing blockwise computations. @juliaforhpc


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

//
// NOTE:
// It's important to have explicit pagebreaks between each chapter,
// otherwise header stylings from the template might break
#pagebreak()
= Planned Project
Goal of this project is to improve the AMICA.jl implementation in different dimensions and to bring its quality closer to the reference implementation in Fortran.
== Research Question
Based on the previous explanations, the research question of the planned work can therefore be formulated as follows:

#quote[
  To what extent can an optimized Julia implementation of AMICA match the Fortran reference, measured by convergence quality and runtime efficiency, and which algorithmic changes, like block-based learning and GPU acceleration, most strongly contribute to closing this gap?
]

== Approach <approach>
The following steps are planned to address this research question:

+ A comprehensive test suite shall be added to be able to continuously assess the impact of changes throughout the development process. The test suite shall assess computational efficiency as well as convergence quality. Research on reasonable assessment approaches has to be conducted first.
+ Blockwise learning will be investigated by first assessing the performance impact on the original fortran implementation and then, if shown to be effective, implementing blockwise learning in Julia.
+ GPU support shall be added. This will most likely involve refactoring certain critical code regions to take use of broadcasts, and migrating data structures to use GPU based array types like `CuArray`.
+ Documentation shall be improved and extended and tutorials will be added.


== Goals
=== Main Goals
+ Add a comprehensive testing suite
+ Implement significant improvements in computational efficiency as well as quality of convergence, e.g. by
  + Adding GPU support
  + Implementing blockwise learning
+ Improve overall code-quality and maintainability along the way
+ Improve documentation and add tutorials

=== Stretch Goals
+ Improve learning rules
+ Attempt an implementation based on autodiff

#pagebreak()
= Plan

The work is planned to be executed roughly in the order outlined in @approach, further detailed in @timeline. Each implementation phase is preceded by an according research phase. General refactorings and improvements are scheduled throughout the whole implementation phase. Writing the thesis is scheduled for the last 2.5 months, where the last two of them are solely reserved for writing and incorporating feedback.

#import "@preview/timeliney:0.3.0"

#figure(caption: [Implementation timeline])[

#timeliney.timeline(
  show-grid: true,
  {
    import timeliney: *

    headerline(group(([*2025*], 4)), group(([*2026*], 2)))
    headerline(
      strong("Sep"),
      strong("Okt"),
      strong("Nov"),
      strong("Dez"),
      strong("Jan"),
      strong("Feb"),
    )

    taskgroup(title: [*Research*], {
      task("Familiarize with AMICA", (0,0.5), style: (stroke: 2pt + gray))
      task("Investigate blockwise learning", (1,2), style: (stroke: 2pt + gray))
      task("Investigate GPU support", (2,3), style: (stroke: 2pt + gray))
    })

    taskgroup(title: [*Implementation*], {
      task("Implement testing suite", (0, 2), style: (stroke: 2pt + gray))
      task("Implement blockwise learning", (1.5, 3), style: (stroke: 2pt + gray))
      task("Implement GPU support", (2.5, 4), style: (stroke: 2pt + gray))
      task("General refactoring, improvements", (1.5, 5), style: (stroke: 2pt + gray))
      task("Improve documentation", (3.5, 4.5), style: (stroke: 2pt + gray))
    })

    taskgroup(title: [*Thesis*], {
      task("Related work", (3.5, 4.5), style: (stroke: 2pt + gray))
      task("Method", (4, 5), style: (stroke: 2pt + gray))
      task("Results", (4.5, 5.5), style: (stroke: 2pt + gray))
    })

    milestone(
      at: 1.5,
      style: (stroke: (dash: "dashed")),
      align(center, [
        *Start implementation*
      ])
    )

    milestone(
      at: 3.5,
      style: (stroke: (dash: "dashed")),
      align(center, [
        *Start thesis writing*
      ])
    )
  }
)
] <timeline>
