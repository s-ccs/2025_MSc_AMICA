using CairoMakie
using SpecialFunctions

const FILENAME = "plots/gaussian_mixture.svg"

function setup_axis!(ax::Axis; xlabel::String, ylabel::String)
    ax.backgroundcolor = colorant"#FAFCFF"
    ax.xlabel = xlabel
    ax.ylabel = ylabel
    ax.xlabelsize = 20
    ax.ylabelsize = 20
    ax.xticklabelsize = 18
    ax.yticklabelsize = 18
    ax.xgridvisible = false
    ax.ygridcolor = RGBAf(0.4, 0.4, 0.4, 0.20)
    ax.leftspinecolor = :gray35
    ax.bottomspinecolor = :gray35
end

function gsm_base_pdf(u::AbstractArray, ρ::Float64)
    c = ρ / (2.0 * gamma(1.0 / ρ))
    return c .* exp.(-(abs.(u) .^ ρ))
end

alphas = [0.35, 0.40, 0.25]
mus = [-1.8, 0.4, 2.2]
betas = [0.45, 1.10, 1.75]
rhos = [2.0, 2.0, 2.0]

x = collect(range(-6.0, 6.0; length=1_200))

comp1 = alphas[1] .* sqrt(betas[1]) .* gsm_base_pdf(sqrt(betas[1]) .* (x .- mus[1]), rhos[1])
comp2 = alphas[2] .* sqrt(betas[2]) .* gsm_base_pdf(sqrt(betas[2]) .* (x .- mus[2]), rhos[2])
comp3 = alphas[3] .* sqrt(betas[3]) .* gsm_base_pdf(sqrt(betas[3]) .* (x .- mus[3]), rhos[3])
mix = comp1 .+ comp2 .+ comp3

colors = [colorant"#4E79A7", colorant"#F28E2B", colorant"#59A14F"]

fig = Figure(size=(1200, 720), backgroundcolor=RGBAf(1, 1, 1, 1))
ax = Axis(fig[1, 1])
setup_axis!(ax; xlabel="x", ylabel="Density")

l1 = lines!(ax, x, comp1; color=colors[1], linewidth=3.0, label="Component 1")
l2 = lines!(ax, x, comp2; color=colors[2], linewidth=3.0, label="Component 2")
l3 = lines!(ax, x, comp3; color=colors[3], linewidth=3.0, label="Component 3")
lmix = lines!(ax, x, mix; color=:black, linewidth=3.0, linestyle=:dash, label="Mixture Density")

axislegend(
    ax,
    [l1, l2, l3, lmix],
    ["Component 1", "Component 2", "Component 3", "Mixture Density"];
    position=:rt,
    labelsize=15,
    framecolor=RGBAf(0.3, 0.3, 0.3, 0.4),
    backgroundcolor=RGBAf(1, 1, 1, 0.85),
)

save(FILENAME, fig)
println("Saved plot: $FILENAME")

