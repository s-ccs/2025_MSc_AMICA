using ArgParse
using CairoMakie
using JSON3
using Printf
using Statistics

include(joinpath(@__DIR__, "constants.jl"))

const DEFAULT_INPUT = joinpath(@__DIR__, "benchmarks.json")
const DEFAULT_OUTDIR = joinpath(@__DIR__, "plots")

const IMPL_COLORS = Dict(
    "Fortran CPU F64" => colorant"#4E79A7",
    "Julia CPU" => colorant"#59A14F",
    "Julia CPU F32" => colorant"#59A14F",
    "Julia CPU F64" => colorant"#F28E2B",
    "Julia GPU" => colorant"#E15759",
)
const DATASET_LABEL = Dict(
    "small" => "Cognitive Workload",
    "memorize" => "Memorize",
    "big" => "EEG Eye Tracking",
)
const DATASETS = ["small", "memorize", "big"]
const BLOCK_SIZE_KEY = "params.block_size"
const BLOCKSIZE_PLOT_BASE_SIZES = Set([100, 1_000, 10_000, 100_000, 200_000, 300_000])
const BLOCKSIZE_ALLOWED_THREADS = Set([1, 64])
const BLOCKSIZE_GROUP_ORDER = Dict(
    "Fortran CPU F64" => 1,
    "Fortran CPU F64 × 64" => 2,
    "Julia CPU F32" => 3,
    "Julia CPU F64" => 4,
    "Julia CPU F32 × 64" => 5,
    "Julia CPU F64 × 64" => 6,
    "Julia GPU F32" => 7,
    "Julia GPU F64" => 8,
)
const IMPLEMENTATION_COMPARE_GROUPS = [
    "Fortran CPU F64",
    "Fortran CPU F64 × 64",
    "Julia CPU F32",
    "Julia CPU F64",
    "Julia CPU F32 × 64",
    "Julia CPU F64 × 64",
    "Julia GPU F32",
    "Julia GPU F64",
]
const IMPLEMENTATION_COMPARE_N_ITER = 40

get_nested(v, path) = foldl(
    (x, key) -> x isa AbstractDict && haskey(x, key) ? x[key] : nothing,
    split(path, '.');
    init=v,
)

normalize(v) = lowercase(strip(string(v)))
to_float(v) = v isa Number ? Float64(v) : tryparse(Float64, string(v))
to_int(v) = v isa Integer ? Int(v) : tryparse(Int, string(v))
median_or_nothing(vals::Vector{Float64}) = isempty(vals) ? nothing : median(vals)

function normalize_samples(value)
    if value isa AbstractVector
        out = Any[]
        for sample in value
            sample isa AbstractDict || continue
            push!(out, sample)
        end
        return out
    elseif value isa AbstractDict
        return Any[value]
    end
    return Any[]
end

function median_entry(key::String, samples)
    first_sample = samples[1]
    entry = Dict{String,Any}()
    for (k, v) in pairs(first_sample)
        entry[String(k)] = v
    end

    runtime_vals = Float64[]
    runtime_after_iter1_vals = Float64[]
    runtime_per_iter_after_first_vals = Float64[]
    for sample in samples
        runtime = to_float(get_nested(sample, "runtime_s"))
        runtime === nothing || push!(runtime_vals, runtime)
        runtime_after_iter1 = to_float(get_nested(sample, "runtime_after_iter1_s"))
        runtime_after_iter1 === nothing || push!(runtime_after_iter1_vals, runtime_after_iter1)
        runtime_per_iter_after_first = to_float(get_nested(sample, "runtime_per_iter_after_first_s"))
        runtime_per_iter_after_first === nothing || push!(runtime_per_iter_after_first_vals, runtime_per_iter_after_first)
    end

    entry["key"] = key
    median_runtime = median_or_nothing(runtime_vals)
    median_runtime === nothing || (entry["runtime_s"] = median_runtime)
    median_runtime_after_iter1 = median_or_nothing(runtime_after_iter1_vals)
    median_runtime_after_iter1 === nothing || (entry["runtime_after_iter1_s"] = median_runtime_after_iter1)
    median_runtime_per_iter_after_first = median_or_nothing(runtime_per_iter_after_first_vals)
    median_runtime_per_iter_after_first === nothing || (entry["runtime_per_iter_after_first_s"] = median_runtime_per_iter_after_first)
    entry["sample_count"] = length(samples)
    return entry
end

function load_entries_with_medians(path::String)
    raw = JSON3.read(read(path, String), Dict{String,Any})
    entries = Any[]
    for (key, value) in pairs(raw)
        samples = normalize_samples(value)
        isempty(samples) && continue
        push!(entries, median_entry(String(key), samples))
    end
    return entries
end

function load_sample_entries(path::String)
    raw = JSON3.read(read(path, String), Dict{String,Any})
    entries = Any[]
    for (key, value) in pairs(raw)
        samples = normalize_samples(value)
        isempty(samples) && continue
        for sample in samples
            sample_dict = Dict{String,Any}()
            for (k, v) in pairs(sample)
                sample_dict[String(k)] = v
            end
            sample_dict["key"] = String(key)
            push!(entries, sample_dict)
        end
    end
    return entries
end

function format_int_commas(n::Int)
    s = string(n)
    out = IOBuffer()
    first_group = length(s) % 3
    first_group == 0 && (first_group = 3)
    print(out, s[1:first_group])
    i = first_group + 1
    while i <= lastindex(s)
        print(out, ",", s[i:i+2])
        i += 3
    end
    return String(take!(out))
end

function parse_invocation(args::Vector{String})
    settings = ArgParseSettings(autofix_names=true)
    @add_arg_table! settings begin
        "--input"
        help = "Benchmark JSON file"
        arg_type = String
        default = DEFAULT_INPUT
        "--outdir"
        help = "Output directory for generated plots"
        arg_type = String
        default = DEFAULT_OUTDIR
    end

    parsed = parse_args(args, settings; as_symbols=true)
    input_path = abspath(String(parsed[:input]))
    outdir = abspath(String(parsed[:outdir]))
    return (input_path, outdir)
end

function entry_matches(entry, filters::AbstractDict)
    for (k, expected) in filters
        actual = get_nested(entry, k)
        actual === nothing && return false
        normalize(actual) == normalize(expected) || return false
    end
    return true
end

function runtime_per_iter_value(entry)
    return to_float(get_nested(entry, "runtime_per_iter_after_first_s"))
end

function find_runtime_per_iter(entries, filters::AbstractDict)
    for entry in entries
        entry_matches(entry, filters) || continue
        runtime = runtime_per_iter_value(entry)
        runtime === nothing && continue
        return runtime
    end
    return nothing
end

function setup_axis!(ax::Axis; xlabel::String, title::String)
    ax.backgroundcolor = AXIS_BACKGROUND_COLOR
    ax.xlabel = xlabel
    ax.ylabel = "Runtime per iteration after iter 1 (s)"
    ax.title = title
    ax.titlegap = AXIS_TITLE_GAP
    ax.titlecolor = AXIS_TEXT_COLOR
    ax.xlabelcolor = AXIS_TEXT_COLOR
    ax.ylabelcolor = AXIS_TEXT_COLOR
    ax.xticklabelcolor = AXIS_TEXT_COLOR
    ax.yticklabelcolor = AXIS_TEXT_COLOR
    ax.xgridvisible = false
    ax.ygridcolor = GRID_COLOR
    ax.leftspinecolor = SPINE_COLOR
    ax.bottomspinecolor = SPINE_COLOR
end

function add_supertitle!(slot, title::String; subtitle::Union{Nothing,String}=nothing)
    text = subtitle === nothing ? title : rich(
        rich(title; fontsize=18, color=:gray20, font=:bold),
        "\n",
        rich(subtitle; fontsize=13, color=:gray35),
    )
    Label(
        slot,
        text;
        halign=:center,
        valign=:center,
        fontsize=18,
        color=:gray20,
        font=:bold,
        tellwidth=false,
    )
end

function style_subplot_subtitle!(ax::Axis)
    ax.titlecolor = colorant"#595959"
    ax.titlesize = 13
    ax.titlegap = 10
end

function darken(c, t=0.3)
    cc = RGBAf(c)
    return RGBAf(cc.r * (1 - t), cc.g * (1 - t), cc.b * (1 - t), 1.0)
end

function lighten(c, t=0.3)
    cc = RGBAf(c)
    return RGBAf(
        cc.r + (1 - cc.r) * t,
        cc.g + (1 - cc.g) * t,
        cc.b + (1 - cc.b) * t,
        1.0,
    )
end

function blocksize_impl_group(entry)
    impl = normalize(get_nested(entry, "implementation"))
    dev = normalize(get_nested(entry, "params.device"))
    prec = normalize(get_nested(entry, "params.precision"))
    threads = to_int(get_nested(entry, "params.threads"))
    thread_suffix = (dev == "cpu" && threads !== nothing && threads != 1) ? " × $(threads)" : ""
    impl == "fortran" && return "Fortran CPU F64$(thread_suffix)"
    if impl == "julia"
        if prec == "float32"
            return dev == "gpu" ? "Julia GPU F32" : "Julia CPU F32$(thread_suffix)"
        elseif prec == "float64"
            return dev == "gpu" ? "Julia GPU F64" : "Julia CPU F64$(thread_suffix)"
        end
        return dev == "gpu" ? "Julia GPU" : "Julia CPU$(thread_suffix)"
    end
    return string(uppercasefirst(impl), " ", uppercase(dev), " ", prec)
end

function blocksize_group_color(group::AbstractString)
    base = if startswith(group, "Fortran CPU F64")
        colorant"#4E79A7"
    elseif startswith(group, "Julia CPU F32")
        colorant"#59A14F"
    elseif startswith(group, "Julia CPU F64")
        colorant"#F28E2B"
    elseif startswith(group, "Julia GPU F32")
        colorant"#E15759"
    elseif startswith(group, "Julia GPU F64")
        colorant"#76B7B2"
    else
        colorant"#999999"
    end
    occursin("× 64", group) ? lighten(base, 0.3) : base
end

function blocksize_tick_label(group::String)
    return group
end

function blocksize_group_base_rank(group::String)
    if startswith(group, "Fortran CPU F64")
        return 1
    elseif startswith(group, "Julia CPU F32")
        return 2
    elseif startswith(group, "Julia CPU F64")
        return 3
    elseif startswith(group, "Julia GPU F32")
        return 4
    elseif startswith(group, "Julia GPU F64")
        return 5
    end
    return 99
end

function blocksize_group_thread_count(group::String)
    m = match(r"×\s*(\d+)", group)
    m === nothing && return 1
    return parse(Int, m.captures[1])
end

blocksize_group_sort_key(group::String) = (
    blocksize_group_base_rank(group),
    blocksize_group_thread_count(group),
    lowercase(group),
)

function blocksize_groups_for_dict(values_by_group_block)
    isempty(values_by_group_block) && return String[]
    groups = unique(first(k) for k in keys(values_by_group_block))
    return sort(groups; by=blocksize_group_sort_key)
end

function collect_runtime_values_by_group_block(entries, filters; allowed_block_sizes=Set{Int}(), allowed_threads=nothing)
    values_tmp = Dict{Tuple{String,Int},Vector{Float64}}()

    for entry in entries
        entry_matches(entry, filters) || continue

        threads = to_int(get_nested(entry, "params.threads"))
        if allowed_threads !== nothing
            (threads === nothing || !(threads in allowed_threads)) && continue
        end
        group = blocksize_impl_group(entry)
        block_size = to_int(get_nested(entry, BLOCK_SIZE_KEY))
        runtime_per_iter = runtime_per_iter_value(entry)
        (block_size === nothing || runtime_per_iter === nothing) && continue
        !isempty(allowed_block_sizes) && !(block_size in allowed_block_sizes) && continue

        key = (group, block_size)
        if !haskey(values_tmp, key)
            values_tmp[key] = Float64[]
        end
        push!(values_tmp[key], runtime_per_iter)
    end

    values_by_group_block = Dict{Tuple{String,Int},Any}()
    for (key, runtime_samples) in values_tmp
        isempty(runtime_samples) && continue
        values_by_group_block[key] = (
            runtime_median=median(runtime_samples),
            runtime_samples=runtime_samples,
        )
    end
    return values_by_group_block
end

function blocksize_plot_allowed_sizes(entries, filters; base_sizes=BLOCKSIZE_PLOT_BASE_SIZES)
    allowed = Set(base_sizes)
    block_sizes = Int[]
    for entry in entries
        entry_matches(entry, filters) || continue
        block_size = to_int(get_nested(entry, BLOCK_SIZE_KEY))
        block_size === nothing && continue
        push!(block_sizes, block_size)
    end
    isempty(block_sizes) || push!(allowed, maximum(block_sizes))
    return allowed
end

function bars_for_runtime_blocksize(
    values_by_group_block,
    group_color;
    groups_override=nothing,
    blocks_override=nothing,
    group_blocks_override=nothing,
)
    groups = groups_override === nothing ? blocksize_groups_for_dict(values_by_group_block) : collect(groups_override)
    y_positions = Float64[]
    y_labels = Any[]
    ys = Float64[]
    xs = Float64[]
    colors = Any[]
    runtime_samples = Vector{Vector{Float64}}()

    y = 1.8
    blocks = blocks_override === nothing ? sort(unique(last(k) for k in keys(values_by_group_block))) : collect(blocks_override)
    for group in groups
        group_blocks = group_blocks_override === nothing ? blocks : get(group_blocks_override, group, Int[])
        isempty(group_blocks) && continue

        push!(y_positions, y - 0.95)
        push!(y_labels, rich(blocksize_tick_label(group); font=:bold))

        for block_size in group_blocks
            push!(y_positions, y)
            push!(y_labels, format_int_commas(block_size))

            key = (group, block_size)
            if haskey(values_by_group_block, key)
                vals = values_by_group_block[key]
                push!(ys, y)
                push!(xs, vals.runtime_median)
                push!(colors, group_color[group])
                push!(runtime_samples, vals.runtime_samples)
            end
            y += 1.0
        end
        y += 1.6
    end

    return (
        ys=ys,
        xs=xs,
        y_positions=y_positions,
        y_labels=y_labels,
        colors=colors,
        runtime_samples=runtime_samples,
    )
end

function overlay_runtime_samples!(ax, xs::Vector{Float64}, samples::Vector{Vector{Float64}}, colors::Vector)
    for (i, x0) in enumerate(xs)
        vals = samples[i]
        isempty(vals) && continue
        n = length(vals)
        jitter = n == 1 ? [0.0] : collect(range(-SAMPLE_JITTER, SAMPLE_JITTER; length=n))
        scatter!(
            ax,
            x0 .+ jitter,
            vals;
            markersize=SAMPLE_MARKER_SIZE,
            marker=:xcross,
            color=darken(colors[i]),
            strokewidth=0,
        )
    end
end

function overlay_runtime_samples_horizontal!(ax, ys::Vector{Float64}, samples::Vector{Vector{Float64}}, colors::Vector)
    for (i, y0) in enumerate(ys)
        vals = samples[i]
        isempty(vals) && continue
        n = length(vals)
        jitter = n == 1 ? [0.0] : collect(range(-SAMPLE_JITTER, SAMPLE_JITTER; length=n))
        scatter!(
            ax,
            vals,
            y0 .+ jitter;
            markersize=SAMPLE_MARKER_SIZE,
            marker=:xcross,
            color=darken(colors[i]),
            strokewidth=0,
        )
    end
end

function max_from_samples(sample_vectors)
    sample_max = 0.0
    for sv in sample_vectors
        isempty(sv) || (sample_max = max(sample_max, maximum(sv)))
    end
    return sample_max
end

function has_sample_data(sample_vectors::Vector{Vector{Float64}})
    return any(!isempty(vals) for vals in sample_vectors)
end

function legend_thread_counts(groups::AbstractVector{<:AbstractString})
    counts = Set{Int}()
    for group in String.(groups)
        uppercase_group = uppercase(group)
        occursin("CPU", uppercase_group) || continue
        m = match(r"×\s*(\d+)", group)
        if m !== nothing
            push!(counts, parse(Int, m.captures[1]))
        end
    end
    return sort!(collect(counts))
end

function notation_legend_rows(
    groups::AbstractVector{<:AbstractString};
    show_samples::Bool=false,
    group_colors=nothing,
    thread_counts::Union{Nothing,AbstractVector{<:Integer}}=nothing,
    show_block_size::Bool=false,
)
    normalized_groups = uppercase.(String.(groups))
    rows = NamedTuple{(:kind, :token, :description, :color),Tuple{Symbol,String,String,Any}}[]

    if show_samples
        push!(rows, (kind=:sample, token="", description="individual sample", color=PRIMARY_TEXT_COLOR))
    end

    if any(group -> occursin("F64", group), normalized_groups)
        push!(rows, (kind=:text, token="F64", description="Float64 precision", color=PRIMARY_TEXT_COLOR))
    end

    if any(group -> occursin("F32", group), normalized_groups)
        push!(rows, (kind=:text, token="F32", description="Float32 precision", color=PRIMARY_TEXT_COLOR))
    end

    counts = thread_counts === nothing ? legend_thread_counts(groups) : sort!(filter(>(1), unique(Int.(thread_counts))))
    for count in counts
        push!(rows, (kind=:text, token="× $(count)", description="$(count) threads", color=PRIMARY_TEXT_COLOR))
    end

    if show_block_size
        push!(rows, (kind=:text, token="b", description="Block Size", color=PRIMARY_TEXT_COLOR))
    end

    return rows
end

function add_notation_legend!(
    slot,
    groups::AbstractVector{<:AbstractString};
    show_samples::Bool=false,
    group_colors=nothing,
    thread_counts::Union{Nothing,AbstractVector{<:Integer}}=nothing,
    show_block_size::Bool=false,
    valign::Symbol=:top,
)
    rows = notation_legend_rows(
        groups;
        show_samples=show_samples,
        group_colors=group_colors,
        thread_counts=thread_counts,
        show_block_size=show_block_size,
    )
    isempty(rows) && return nothing

    nrows = length(rows)
    row_step = 16
    row_height = 12
    top_pad = 8
    bottom_pad = 8
    legend_height = top_pad + bottom_pad + row_height + row_step * max(0, nrows - 1)
    legend_width = 134
    legend_ax = Axis(
        slot;
        width=legend_width,
        height=legend_height,
        tellwidth=false,
        tellheight=false,
        halign=:right,
        valign=valign,
        alignmode=Outside(10),
        backgroundcolor=:transparent,
    )
    hidedecorations!(legend_ax)
    hidespines!(legend_ax)
    xlims!(legend_ax, 0.0, 1.0)
    ylims!(legend_ax, 0.0, 1.0)

    poly!(
        legend_ax,
        Point2f[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
        color=RGBAf(1, 1, 1, 0.92),
        strokecolor=RGBAf(0.6, 0.6, 0.6, 0.9),
        strokewidth=1,
    )

    top_center = legend_height - top_pad - row_height / 2
    bottom_center = bottom_pad + row_height / 2
    ys_px = nrows == 1 ? [legend_height / 2] : collect(range(top_center, bottom_center; length=nrows))
    ys = ys_px ./ legend_height
    token_x = 0.125
    desc_x = 0.27
    for (row, y) in zip(rows, ys)
        if row.kind == :sample
            scatter!(
                legend_ax,
                [token_x],
                [y];
                marker=:xcross,
                markersize=SAMPLE_MARKER_SIZE + 1,
                color=row.color,
                strokewidth=0,
            )
        else
            text!(
                legend_ax,
                token_x,
                y;
                text=row.token,
                align=(:center, :center),
                color=row.color,
                fontsize=10,
            )
        end
        text!(
            legend_ax,
            desc_x,
            y;
            text=row.description,
            align=(:left, :center),
            color=PRIMARY_TEXT_COLOR,
            fontsize=10,
        )
    end

    return legend_ax
end

function plot_runtime_blocksize_dataset!(ax, bars, dataset_label)
    ax.yreversed = true
    ax.xgridvisible = true
    ax.xgridcolor = GRID_COLOR
    ax.ygridvisible = false

    if isempty(bars.y_positions)
        return
    end

    xmax = max(
        isempty(bars.xs) ? 0.0 : maximum(bars.xs),
        max_from_samples(bars.runtime_samples),
        1e-6,
    )
    xtop = TOP_FACTOR * xmax

    if !isempty(bars.ys)
        barplot!(ax, bars.ys, bars.xs; direction=:x, fillto=0.0, color=bars.colors, strokewidth=0)
    end

    for (x, y) in zip(bars.xs, bars.ys)
        text!(ax, x + RUNTIME_BEST_IMPL_LABEL_X_OFFSET_RATIO * xtop, y; text=@sprintf("%.2f s", x), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end

    overlay_runtime_samples_horizontal!(ax, bars.ys, bars.runtime_samples, bars.colors)

    ax.yticks = (bars.y_positions, bars.y_labels)
    ax.yticklabelalign = (:right, :center)
    ax.yticksvisible = false
    y_values = isempty(bars.ys) ? copy(bars.y_positions) : vcat(bars.y_positions, bars.ys)
    ypad = 0.8
    ylims!(ax, maximum(y_values) + ypad, minimum(y_values) - ypad)
    xlims!(ax, 0.0, xtop)
    ax.title = "Dataset: $dataset_label"
end

function plot_grouped_runtime(
    x_labels::Vector{String},
    impl_names::Vector{String},
    values::Dict{Tuple{Int,String},Float64};
    xlabel::String,
    title::String,
    output_base::String,
)
    fig = Figure(size=(FIGURE_WIDTH, 700), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    ax = Axis(fig[1, 1])
    setup_axis!(ax; xlabel=xlabel, title=title)

    n_x = length(x_labels)
    n_impl = length(impl_names)
    x_centers = collect(1:n_x)

    offsets = collect(range(-RUNTIME_GROUPED_BAR_OFFSET_SPAN, RUNTIME_GROUPED_BAR_OFFSET_SPAN; length=n_impl))

    for (impl_idx, impl_name) in enumerate(impl_names)
        xs = Float64[]
        ys = Float64[]
        for x_idx in 1:n_x
            key = (x_idx, impl_name)
            haskey(values, key) || continue
            push!(xs, x_centers[x_idx] + offsets[impl_idx])
            push!(ys, values[key])
        end

        if !isempty(xs)
            barplot!(
                ax,
                xs,
                ys;
                color=IMPL_COLORS[impl_name],
                strokecolor=RGBAf(1, 1, 1, 0.9),
                strokewidth=1.2,
            )
        end
    end

    ax.xticks = (x_centers, x_labels)

    svg_path = output_base * ".svg"
    save(svg_path, fig)
    println("Saved plot: $svg_path")
end

function build_blocksize_plot(
    entries,
    outdir,
    dataset::String;
    output_name::Union{Nothing,String}=nothing,
    group_filter::Function=group -> true,
)
    dataset_title = get(DATASET_LABEL, dataset, uppercasefirst(dataset))
    filters = Dict(
        "params.dataset" => dataset,
        "params.n_iter" => "40",
    )
    allowed_block_sizes = blocksize_plot_allowed_sizes(entries, filters)
    values_by_group_block = collect_runtime_values_by_group_block(
        entries,
        filters;
        allowed_block_sizes=allowed_block_sizes,
        allowed_threads=BLOCKSIZE_ALLOWED_THREADS,
    )
    values_by_group_block = Dict(
        key => vals for (key, vals) in values_by_group_block
        if !occursin("F32", key[1]) && group_filter(key[1])
    )
    all_groups = blocksize_groups_for_dict(values_by_group_block)
    group_color = Dict(g => blocksize_group_color(g) for g in all_groups)
    bars = bars_for_runtime_blocksize(values_by_group_block, group_color)

    fig_height = Int(round(0.7 * 1.2 * 1.3 * max(700, 10 * length(bars.y_positions) + 160))) + 50
    fig = Figure(size=(FIGURE_WIDTH, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    rowgap!(fig.layout, 16)
    add_supertitle!(fig[0, 1], "Runtime Across Block Size"; subtitle="Dataset: $(dataset_title), 40 Iterations")
    ax = Axis(fig[1, 1])
    setup_axis!(ax; xlabel="Runtime per iteration after iter 1 (s)", title="")
    ax.ylabel = "Block Size"
    plot_runtime_blocksize_dataset!(ax, bars, dataset_title)
    ax.title = ""

    text!(
        fig.scene,
        CAPTION_X,
        CAPTION_Y;
        text=RUNTIME_SAMPLES_CAPTION,
        space=:relative,
        align=(:left, :bottom),
        color=SECONDARY_TEXT_COLOR,
    )

    add_notation_legend!(fig[1, 1], all_groups; show_samples=has_sample_data(bars.runtime_samples), group_colors=group_color)

    basename = something(output_name, "runtime_vs_blocksize_$(dataset).svg")
    output_path = joinpath(outdir, basename)
    save(output_path, fig)
    println("Saved plot: $output_path")
end

function build_runtime_full_plot(entries, outdir)
    values_per_dataset = Dict{String,Dict{Tuple{String,Int},Any}}()
    all_groups = String[]
    legend_has_samples = false
    for dataset in DATASETS
        filters = Dict(
            "params.dataset" => dataset,
            "params.n_iter" => "40",
        )
        values_by_group_block = collect_runtime_values_by_group_block(
            entries,
            filters;
        )
        values_per_dataset[dataset] = values_by_group_block
        append!(all_groups, blocksize_groups_for_dict(values_by_group_block))
        legend_has_samples |= any(!isempty(vals.runtime_samples) for vals in values(values_by_group_block))
    end
    unique!(all_groups)
    all_groups = sort(all_groups; by=blocksize_group_sort_key)
    group_color = Dict(g => blocksize_group_color(g) for g in all_groups)

    all_blocks_by_group = Dict(
        group => sort(unique(last(k) for values_by_group_block in values(values_per_dataset) for k in keys(values_by_group_block) if first(k) == group))
        for group in all_groups
    )

    all_rows = [(group, block_size) for group in all_groups for block_size in get(all_blocks_by_group, group, Int[])]
    target_rows_per_page = max(1, ceil(Int, length(all_rows) / 2))
    page_blocks = [Dict{String,Vector{Int}}(), Dict{String,Vector{Int}}()]
    page = 1
    rows_on_page = 0
    for (group, block_size) in all_rows
        if page < 2 && rows_on_page >= target_rows_per_page
            page += 1
            rows_on_page = 0
        end
        push!(get!(() -> Int[], page_blocks[page], group), block_size)
        rows_on_page += 1
    end

    fig_height = 1530
    for (page_idx, page_group_blocks) in enumerate(page_blocks)
        isempty(page_group_blocks) && continue

        fig = Figure(size=(1092, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1))
        rowgap!(fig.layout, 16)
        add_supertitle!(
            fig[0, 1:length(DATASETS)],
            "Full Runtime Benchmark Results";
            subtitle="Page $(page_idx) of $(length(page_blocks))",
        )
        axes = Axis[]
        for (col, dataset) in enumerate(DATASETS)
            ax = Axis(fig[1, col])
            setup_axis!(ax; xlabel="Runtime per iteration after iter 1 (s)", title="Dataset: $(get(DATASET_LABEL, dataset, dataset))")
            style_subplot_subtitle!(ax)
            ax.ylabel = col == 1 ? "Block Size" : ""
            col == 1 || (ax.yticklabelsvisible = false)
            push!(axes, ax)
        end

        page_groups = [group for group in all_groups if haskey(page_group_blocks, group)]
        for (i, dataset) in enumerate(DATASETS)
            bars = bars_for_runtime_blocksize(
                values_per_dataset[dataset],
                group_color;
                groups_override=page_groups,
                group_blocks_override=page_group_blocks,
            )
            plot_runtime_blocksize_dataset!(axes[i], bars, get(DATASET_LABEL, dataset, dataset))
        end

        text!(
            fig.scene,
            CAPTION_X,
            CAPTION_Y;
            text=RUNTIME_SAMPLES_CAPTION,
            space=:relative,
            align=(:left, :bottom),
            color=SECONDARY_TEXT_COLOR,
        )

        add_notation_legend!(fig[1, 3], all_groups; show_samples=legend_has_samples, group_colors=group_color, valign=:bottom)

        output_path = joinpath(outdir, "runtime_full_page$(page_idx).svg")
        save(output_path, fig)
        println("Saved plot: $output_path")
    end
end

function collect_optimal_runtime_by_dataset_group(entries)
    best = Dict{Tuple{String,String},NamedTuple{(:runtime, :block_size),Tuple{Float64,Int}}}()

    for entry in entries
        dataset = normalize(get_nested(entry, "params.dataset"))
        dataset in DATASETS || continue

        n_iter = to_int(get_nested(entry, "params.n_iter"))
        n_iter == IMPLEMENTATION_COMPARE_N_ITER || continue

        runtime = runtime_per_iter_value(entry)
        runtime === nothing && continue

        block_size = to_int(get_nested(entry, BLOCK_SIZE_KEY))
        block_size === nothing && continue

        group = blocksize_impl_group(entry)
        group in IMPLEMENTATION_COMPARE_GROUPS || continue

        if occursin("× 64", group)
            to_int(get_nested(entry, "params.threads")) == 64 || continue
        else
            to_int(get_nested(entry, "params.threads")) == 1 || continue
        end

        key = (dataset, group)
        if !haskey(best, key) || runtime < best[key].runtime
            best[key] = (runtime=runtime, block_size=block_size)
        end
    end

    return best
end

function collect_runtime_samples_by_dataset_group_block(entries)
    samples = Dict{Tuple{String,String,Int},Vector{Float64}}()

    for entry in entries
        dataset = normalize(get_nested(entry, "params.dataset"))
        dataset in DATASETS || continue

        n_iter = to_int(get_nested(entry, "params.n_iter"))
        n_iter == IMPLEMENTATION_COMPARE_N_ITER || continue

        runtime = runtime_per_iter_value(entry)
        runtime === nothing && continue

        block_size = to_int(get_nested(entry, BLOCK_SIZE_KEY))
        block_size === nothing && continue

        group = blocksize_impl_group(entry)
        group in IMPLEMENTATION_COMPARE_GROUPS || continue

        if occursin("× 64", group)
            to_int(get_nested(entry, "params.threads")) == 64 || continue
        else
            to_int(get_nested(entry, "params.threads")) == 1 || continue
        end

        key = (dataset, group, block_size)
        if !haskey(samples, key)
            samples[key] = Float64[]
        end
        push!(samples[key], runtime)
    end

    return samples
end

function optimal_implementation_xmax(dataset::String, best_values, sample_values)
    xs = Float64[]
    runtime_samples = Vector{Vector{Float64}}()
    for group in IMPLEMENTATION_COMPARE_GROUPS
        key = (dataset, group)
        haskey(best_values, key) || continue
        push!(xs, best_values[key].runtime)
        best_block_size = best_values[key].block_size
        push!(runtime_samples, get(sample_values, (dataset, group, best_block_size), Float64[]))
    end
    return max(
        isempty(xs) ? 0.0 : maximum(xs),
        max_from_samples(runtime_samples),
        1e-6,
    )
end

function optimal_implementation_xtop(dataset::String, best_values, sample_values, row::Int, nrows::Int)
    xmax = optimal_implementation_xmax(dataset, best_values, sample_values)
    scale = if row == 1
        0.40
    elseif row == 2
        0.70
    else
        1.00
    end
    return (TOP_FACTOR * xmax) / scale
end

function plot_optimal_implementation_dataset!(ax, dataset::String, best_values, sample_values; xtop::Float64, show_xticklabels::Bool)
    dataset_label = get(DATASET_LABEL, dataset, uppercasefirst(dataset))
    setup_axis!(ax; xlabel="", title=dataset_label)
    style_subplot_subtitle!(ax)
    ax.ylabel = ""
    ax.xgridvisible = true
    ax.xgridcolor = GRID_COLOR
    ax.ygridvisible = false
    ax.yticksvisible = false
    ax.xticklabelsvisible = true
    ax.xticksvisible = true

    y_positions = Float64[]
    y_labels = Any[]
    ys = Float64[]
    xs = Float64[]
    colors = Any[]
    present_groups = String[]
    runtime_samples = Vector{Vector{Float64}}()

    n_groups = length(IMPLEMENTATION_COMPARE_GROUPS)
    for (idx, group) in enumerate(IMPLEMENTATION_COMPARE_GROUPS)
        y = Float64(n_groups - idx + 1)
        push!(y_positions, y)
        push!(y_labels, group)

        key = (dataset, group)
        if haskey(best_values, key)
            push!(ys, y)
            push!(xs, best_values[key].runtime)
            push!(colors, blocksize_group_color(group))
            push!(present_groups, group)
            best_block_size = best_values[key].block_size
            push!(runtime_samples, get(sample_values, (dataset, group, best_block_size), Float64[]))
        end
    end

    ax.yticks = (y_positions, y_labels)

    if isempty(xs)
        return
    end

    xlims!(ax, 0.0, xtop)
    ylims!(ax, minimum(y_positions) - 0.5, maximum(y_positions) + 0.5)
    barplot!(ax, ys, xs; direction=:x, fillto=0.0, color=colors, strokewidth=0)

    overlay_runtime_samples_horizontal!(ax, ys, runtime_samples, colors)

    for (x, y, group) in zip(xs, ys, present_groups)
        vals = best_values[(dataset, group)]
        label = @sprintf("%.2f s, b=%s", vals.runtime, format_int_commas(vals.block_size))
        text!(ax, x + RUNTIME_BEST_IMPL_LABEL_X_OFFSET_RATIO * xtop, y; text=label, align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
end

function build_optimal_implementation_plot(entries, sample_entries, outdir)
    best_values = collect_optimal_runtime_by_dataset_group(entries)
    sample_values = collect_runtime_samples_by_dataset_group_block(sample_entries)
    datasets_with_data = String[]
    legend_groups = String[]
    legend_has_samples = false
    for dataset in DATASETS
        has_data = any(haskey(best_values, (dataset, group)) for group in IMPLEMENTATION_COMPARE_GROUPS)
        has_data && push!(datasets_with_data, dataset)
        for group in IMPLEMENTATION_COMPARE_GROUPS
            key = (dataset, group)
            haskey(best_values, key) || continue
            push!(legend_groups, group)
            best_block_size = best_values[key].block_size
            legend_has_samples |= !isempty(get(sample_values, (dataset, group, best_block_size), Float64[]))
        end
    end
    isempty(datasets_with_data) && return
    unique!(legend_groups)

    fig_width = FIGURE_WIDTH
    chart_height = 260
    nrows = length(datasets_with_data)
    fig_height = chart_height * nrows + 110
    fig = Figure(size=(fig_width, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    rowgap!(fig.layout, 16)
    add_supertitle!(fig[0, 1], "Runtime Across Datasets")
    for (row, dataset) in enumerate(datasets_with_data)
        ax = Axis(fig[row, 1])
        plot_optimal_implementation_dataset!(
            ax,
            dataset,
            best_values,
            sample_values;
            xtop=optimal_implementation_xtop(dataset, best_values, sample_values, row, nrows),
            show_xticklabels=row == nrows,
        )
    end

    legend_colors = Dict(group => blocksize_group_color(group) for group in legend_groups)
    add_notation_legend!(fig[nrows, 1], legend_groups; show_samples=legend_has_samples, group_colors=legend_colors, show_block_size=true, valign=:bottom)

    output_path = joinpath(outdir, "runtime_best_impl_per_dataset.svg")
    save(output_path, fig)
    println("Saved plot: $output_path")
end

function best_runtime_with_blocksize(entries, filters::AbstractDict)
    best = nothing
    for entry in entries
        entry_matches(entry, filters) || continue
        runtime = runtime_per_iter_value(entry)
        runtime === nothing && continue
        block_size = to_int(get_nested(entry, BLOCK_SIZE_KEY))
        block_size === nothing && continue
        if best === nothing || runtime < best.runtime
            best = (runtime=runtime, block_size=block_size)
        end
    end
    return best
end

function sample_runtimes_for_config(sample_entries, filters::AbstractDict, block_size::Int)
    vals = Float64[]
    for entry in sample_entries
        entry_matches(entry, filters) || continue
        to_int(get_nested(entry, BLOCK_SIZE_KEY)) == block_size || continue
        runtime = runtime_per_iter_value(entry)
        runtime === nothing && continue
        push!(vals, runtime)
    end
    return vals
end

function build_big_threads_plot(
    entries,
    sample_entries,
    outdir;
    impls_override=nothing,
    output_name::String="runtime_per_iter_big_threads.svg",
    subtitle_suffix::Union{Nothing,String}=nothing,
)
    base_filters = Dict(
        "params.dataset" => "big",
        "params.device" => "cpu",
        "params.n_iter" => "40",
    )
    impls = impls_override === nothing ? [
        ("Fortran CPU F64", Dict("params.implementation" => "fortran", "params.precision" => "float64")),
        ("Julia CPU F32", Dict("params.implementation" => "julia", "params.precision" => "float32")),
        ("Julia CPU F64", Dict("params.implementation" => "julia", "params.precision" => "float64")),
    ] : impls_override

    thread_set = Set{Int}()
    for entry in entries
        entry_matches(entry, base_filters) || continue
        t = to_int(get_nested(entry, "params.threads"))
        t === nothing || push!(thread_set, t)
    end
    threads = sort(collect(thread_set))
    isempty(threads) && return

    y_positions = Float64[]
    y_labels = Any[]
    xs = Float64[]
    ys = Float64[]
    colors = Any[]
    runtime_samples = Vector{Vector{Float64}}()
    selected_block_sizes = Int[]

    y = 1.8
    legend_groups = String[]
    for (impl_label, impl_filters) in impls
        push!(y_positions, y - 0.95)
        push!(y_labels, rich(impl_label; font=:bold))
        push!(legend_groups, impl_label)

        for thread_count in threads
            push!(y_positions, y)
            push!(y_labels, string(thread_count))

            filters = merge(copy(base_filters), impl_filters, Dict("params.threads" => string(thread_count)))
            best = best_runtime_with_blocksize(entries, filters)
            if best !== nothing
                push!(ys, y)
                push!(xs, best.runtime)
                push!(colors, IMPL_COLORS[impl_label])
                push!(runtime_samples, sample_runtimes_for_config(sample_entries, filters, best.block_size))
                push!(selected_block_sizes, best.block_size)
            end
            y += 1.0
        end
        y += 1.6
    end

    dataset_title = get(DATASET_LABEL, "big", "Big")
    fig_height = Int(round(0.7 * max(760, 12 * length(y_positions) + 180))) + 50
    fig = Figure(size=(FIGURE_WIDTH, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    rowgap!(fig.layout, 16)
    subtitle = "Dataset: $dataset_title"
    subtitle_suffix === nothing || (subtitle *= ", $subtitle_suffix")
    add_supertitle!(fig[0, 1], "Runtime Across Thread Count"; subtitle=subtitle)
    ax = Axis(fig[1, 1])
    setup_axis!(ax; xlabel="Runtime per iteration after iter 1 (s)", title="")
    ax.ylabel = "Thread Count"
    ax.yreversed = true
    ax.xgridvisible = true
    ax.xgridcolor = GRID_COLOR
    ax.ygridvisible = false

    if !isempty(xs)
        xmax = max(
            maximum(xs),
            max_from_samples(runtime_samples),
            1e-6,
        )
        xtop = TOP_FACTOR * xmax
        xlims!(ax, 0.0, xtop)
        barplot!(ax, ys, xs; direction=:x, fillto=0.0, color=colors, strokewidth=0)
        overlay_runtime_samples_horizontal!(ax, ys, runtime_samples, colors)

        for (x, y, block_size) in zip(xs, ys, selected_block_sizes)
            text!(
                ax,
                x + RUNTIME_BEST_IMPL_LABEL_X_OFFSET_RATIO * xtop,
                y;
                text=@sprintf("%.2f s, b=%s", x, format_int_commas(block_size)),
                align=(:left, :center),
                fontsize=BAR_LABEL_FONT_SIZE,
                color=PRIMARY_TEXT_COLOR,
            )
        end
    end

    ax.yticks = (y_positions, y_labels)
    ax.yticklabelalign = (:right, :center)
    ax.yticksvisible = false

    legend_colors = Dict(label => IMPL_COLORS[label] for label in legend_groups if haskey(IMPL_COLORS, label))
    add_notation_legend!(
        fig[1, 1],
        legend_groups;
        show_samples=has_sample_data(runtime_samples),
        group_colors=legend_colors,
        show_block_size=true,
        valign=:bottom,
    )

    output_path = joinpath(outdir, output_name)
    save(output_path, fig)
    println("Saved plot: $output_path")
end

function build_threads_plot(entries, outdir)
    dataset_title = get(DATASET_LABEL, "memorize", "Memorize")
    shared = Dict(
        "params.dataset" => "memorize",
        "params.precision" => "float64",
        "params.block_size" => "2000",
        "params.n_iter" => "40",
        "params.device" => "cpu",
    )
    x_vals = [1, 32, 64]
    x_labels = [string(v) for v in x_vals]

    impls = [
        ("Fortran CPU F64", Dict("params.implementation" => "fortran")),
        ("Julia CPU F64", Dict("params.implementation" => "julia")),
    ]

    values = Dict{Tuple{Int,String},Float64}()
    for (x_idx, threads) in enumerate(x_vals)
        for (label, impl_filters) in impls
            filters = merge(copy(shared), impl_filters, Dict("params.threads" => string(threads)))
            runtime = find_runtime_per_iter(entries, filters)
            if runtime === nothing
                @warn "Missing benchmark entry" category = "threads" threads label filters
            else
                values[(x_idx, label)] = runtime
            end
        end
    end

    plot_grouped_runtime(
        x_labels,
        [x[1] for x in impls],
        values;
        xlabel="Threads",
        title="Influence of Thread Count on Per-Iteration Runtime ($(dataset_title))",
        output_base=joinpath(outdir, "runtime_per_iter_memorize_threads"),
    )
end

function build_precision_plot(entries, outdir)
    dataset_title = get(DATASET_LABEL, "memorize", "Memorize")
    shared = Dict(
        "params.dataset" => "memorize",
        "params.block_size" => "2000",
        "params.threads" => "1",
        "params.n_iter" => "40",
    )
    x_vals = ["float32", "float64"]
    x_labels = ["F32", "F64"]

    impls = [
        ("Julia CPU", Dict("params.implementation" => "julia", "params.device" => "cpu")),
        ("Julia GPU", Dict("params.implementation" => "julia", "params.device" => "gpu")),
    ]

    values = Dict{Tuple{Int,String},Float64}()
    for (x_idx, precision) in enumerate(x_vals)
        for (label, impl_filters) in impls
            filters = merge(copy(shared), impl_filters, Dict("params.precision" => precision))
            runtime = find_runtime_per_iter(entries, filters)
            if runtime === nothing
                @warn "Missing benchmark entry" category = "precision" precision label filters
            else
                values[(x_idx, label)] = runtime
            end
        end
    end

    plot_grouped_runtime(
        x_labels,
        [x[1] for x in impls],
        values;
        xlabel="Precision",
        title="Influence of Data Type on Per-Iteration Runtime ($(dataset_title))",
        output_base=joinpath(outdir, "runtime_per_iter_memorize_precision"),
    )
end

function runtime_main(args::Vector{String})
    input_path, outdir = parse_invocation(args)
    isfile(input_path) || error("Input file not found: $input_path")

    sample_entries = load_sample_entries(input_path)
    entries = load_entries_with_medians(input_path)
    mkpath(outdir)

    build_runtime_full_plot(sample_entries, outdir)
    build_blocksize_plot(sample_entries, outdir, "big")
    build_blocksize_plot(
        sample_entries,
        outdir,
        "big";
        output_name="runtime_vs_blocksize_big_julia.svg",
        group_filter=group -> startswith(group, "Julia "),
    )
    build_blocksize_plot(sample_entries, outdir, "memorize")
    build_optimal_implementation_plot(entries, sample_entries, outdir)
    build_big_threads_plot(entries, sample_entries, outdir)
    build_big_threads_plot(
        entries,
        sample_entries,
        outdir;
        impls_override=[
            ("Fortran CPU F64", Dict("params.implementation" => "fortran", "params.precision" => "float64")),
            ("Julia CPU F64", Dict("params.implementation" => "julia", "params.precision" => "float64")),
        ],
        output_name="runtime_per_iter_big_threads_f64.svg",
        subtitle_suffix="64-bit only",
    )
end
if abspath(PROGRAM_FILE) == @__FILE__
    runtime_main(ARGS)
end
