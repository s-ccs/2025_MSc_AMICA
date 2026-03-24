using ArgParse
using CairoMakie
using Random
using Statistics

const OUTPUT_PATH = "plots/exemplary_mixtures.svg"

function setup_signal_axis!(ax::Axis; title::String, xlabel::String="", ylabel::String="")
    ax.backgroundcolor = colorant"#FAFCFF"
    ax.title = title
    ax.titlecolor = :gray25
    ax.titlegap = 12
    ax.xlabel = xlabel
    ax.ylabel = ylabel
    ax.xlabelcolor = :gray20
    ax.ylabelcolor = :gray20
    ax.xlabelsize = 18
    ax.ylabelsize = 18
    ax.xticklabelcolor = :gray20
    ax.yticklabelcolor = :gray20
    ax.xticklabelsize = 14
    ax.yticklabelsize = 14
    ax.titlesize = 18
    ax.xgridvisible = false
    ax.ygridcolor = RGBAf(0.4, 0.4, 0.4, 0.20)
    ax.leftspinecolor = :gray35
    ax.bottomspinecolor = :gray35
end

function add_panel_header!(slot, title::String)
    Label(
        slot,
        title;
        halign=:center,
        valign=:center,
        fontsize=18,
        color=:gray20,
        font=:bold,
        tellwidth=false,
    )
end


n = 2_000
sample_idx = collect(1:n)

rng = MersenneTwister(42)
t = range(0.0, 8.0; length=n)

# s1 is Gaussian by construction.
s1 = randn(rng, n)
s2 = sin.(2π * 1.3 .* t) .+ 0.35 .* sin.(2π * 3.7 .* t .+ 0.6)
s3 = sin.(2π * 0.45 .* t .+ 1.1) .+ 0.25 .* sin.(2π * 0.9 .* t .- 0.2)

sources = [s1 s2 s3]'
for i in 1:size(sources, 1)
    sources[i, :] ./= std(sources[i, :])
end

mixing = [
    1.0 0.6 -0.4
    -0.3 1.2 0.5
    0.7 -0.2 1.0
]
mixtures = mixing * sources

data = (sources=sources, mixtures=mixtures)


mix_colors = [colorant"#4E79A7", colorant"#F28E2B", colorant"#59A14F"]
src_colors = [colorant"#E15759", colorant"#76B7B2", colorant"#EDC948"]

fig = Figure(size=(1400, 960), backgroundcolor=RGBAf(1, 1, 1, 1))

colgap!(fig.layout, 30)
rowgap!(fig.layout, 16)

for i in 1:3
    ax_mix = Axis(fig[i, 1])
    ax_src = Axis(fig[i, 2])

    setup_signal_axis!(ax_mix; title="Mixture x$i", xlabel=(i == 3 ? "Sample index" : ""), ylabel="Amplitude")
    setup_signal_axis!(ax_src; title="Source s$i", xlabel=(i == 3 ? "Sample index" : ""), ylabel="Amplitude")

    lines!(ax_mix, sample_idx, data.mixtures[i, :]; color=mix_colors[i], linewidth=1.8)
    lines!(ax_src, sample_idx, data.sources[i, :]; color=src_colors[i], linewidth=1.8)
end

add_panel_header!(fig[0, 1], "Observed Mixtures")
add_panel_header!(fig[0, 2], "Unmixed Sources")

save(OUTPUT_PATH, fig)
println("Saved plot: $OUTPUT_PATH")

