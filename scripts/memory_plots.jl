using CairoMakie
using JSON3
using Printf
using Statistics

include(joinpath(@__DIR__, "constants.jl"))

const INPUT_FILE = joinpath(@__DIR__, "benchmarks.json")
const OUTPUT_DIR = joinpath(@__DIR__, "plots")
const OUTPUT_FILE_MEMORY_FULL = joinpath(OUTPUT_DIR, "memory_full.svg")
const OUTPUT_FILE_BLOCKSIZE = joinpath(OUTPUT_DIR, "memory_vs_blocksize_big_no_full_block.svg")
const OUTPUT_FILE_NOBLOCK = joinpath(OUTPUT_DIR, "memory_full_block_all_datasets.svg")
const OUTPUT_FILE_BLOCK1000 = joinpath(OUTPUT_DIR, "memory_block_1000_all_datasets.svg")
const OUTPUT_FILE_NOBLOCK_BIG = joinpath(OUTPUT_DIR, "memory_full_block_eeg_eye_tracking.svg")
const OUTPUT_FILE_BLOCK1000_BIG = joinpath(OUTPUT_DIR, "memory_block_1000_eeg_eye_tracking.svg")
const BLOCK_KEY = "params.block_size"

const BASE_FILTERS = Dict(
    "params.n_iter" => "40",
    "params.threads" => "1",
)
const ALLOWED_THREADS = Set([1, 64])

const DATASETS = ["small", "memorize", "big"]
const DATASET_LABEL = Dict(
    "small" => "Cognitive Workload",
    "memorize" => "Memorize",
    "big" => "EEG Eye Tracking",
)

const ALLOWED_BLOCK_SIZES = Dict(
    "small" => Set([100, 1_000, 10_000, 100_000, 172_704]),
    "memorize" => Set([100, 1_000, 10_000, 100_000, 200_000, 300_000, 319_500]),
    "big" => Set([100, 1_000, 10_000, 100_000, 200_000, 300_000, 1_260_379]),
)
const EXCLUDED_BLOCK_SIZES = Set{Int}()
const FULL_BLOCK_SIZE = Dict(
    "small" => 172_704,
    "memorize" => 319_500,
    "big" => 1_260_379,
)

const GROUP_ORDER = Dict(
    "Fortran CPU F64" => 1,
    "Fortran CPU F64 × 64" => 2,
    "Julia CPU F32" => 3,
    "Julia CPU F64" => 4,
    "Julia CPU F32 × 64" => 5,
    "Julia CPU F64 × 64" => 6,
    "Julia GPU F32" => 7,
    "Julia GPU F64" => 8,
)
const FORTRAN_COLOR = colorant"#4E79A7"
const JULIA_CPU_FLOAT32_COLOR = colorant"#59A14F"
const JULIA_CPU_FLOAT64_COLOR = colorant"#F28E2B"
const JULIA_GPU_FLOAT32_COLOR = colorant"#E15759"
const JULIA_GPU_FLOAT64_COLOR = colorant"#76B7B2"

get_nested(v, path) = foldl(
    (x, key) -> x isa AbstractDict && haskey(x, key) ? x[key] : nothing,
    split(path, '.');
    init=v,
)

to_int(v) = v isa Integer ? Int(v) : tryparse(Int, string(v))
to_float(v) = v isa Number ? Float64(v) : tryparse(Float64, string(v))
lighten(c, t=GPU_MEMORY_LIGHTEN_FACTOR) = RGBAf(c.r + (1 - c.r) * t, c.g + (1 - c.g) * t, c.b + (1 - c.b) * t, 1.0)
function darken(c, t=0.3)
    cc = RGBAf(c)
    return RGBAf(cc.r * (1 - t), cc.g * (1 - t), cc.b * (1 - t), 1.0)
end
with_alpha(c, a) = begin
    cc = RGBAf(c)
    RGBAf(cc.r, cc.g, cc.b, a)
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

function style_axis_title!(ax::Axis)
    ax.titlecolor = AXIS_TEXT_COLOR
    ax.titlegap = AXIS_TITLE_GAP
    ax.xlabelcolor = AXIS_TEXT_COLOR
    ax.ylabelcolor = AXIS_TEXT_COLOR
    ax.xticklabelcolor = AXIS_TEXT_COLOR
    ax.yticklabelcolor = AXIS_TEXT_COLOR
end

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

function load_sample_entries(path::String)
    data = JSON3.read(read(path, String), Dict{String,Any})
    entries = Any[]
    for (key, raw_value) in pairs(data)
        samples = normalize_samples(raw_value)
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

function keep_entry(entry, filters)
    for (k, expected) in filters
        actual = get_nested(entry, k)
        actual === nothing && return false
        lowercase(strip(string(actual))) == lowercase(strip(string(expected))) || return false
    end
    return true
end

function impl_group(entry)
    impl = lowercase(strip(string(get_nested(entry, "implementation"))))
    dev = lowercase(strip(string(get_nested(entry, "params.device"))))
    prec = lowercase(strip(string(get_nested(entry, "params.precision"))))
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

function group_base_color(group::AbstractString)
    g = lowercase(group)
    base = if startswith(g, "fortran cpu f64")
        FORTRAN_COLOR
    elseif startswith(g, "julia cpu f32")
        JULIA_CPU_FLOAT32_COLOR
    elseif startswith(g, "julia cpu f64")
        JULIA_CPU_FLOAT64_COLOR
    elseif startswith(g, "julia gpu f32")
        JULIA_GPU_FLOAT32_COLOR
    elseif startswith(g, "julia gpu f64")
        JULIA_GPU_FLOAT64_COLOR
    elseif occursin("julia cpu", g)
        JULIA_CPU_FLOAT32_COLOR
    elseif occursin("julia gpu", g)
        JULIA_GPU_FLOAT32_COLOR
    else
        colorant"#999999"
    end
    occursin("× 64", group) ? lighten(base, 0.3) : base
end

function impl_tick_label(group::String)
    return group
end

function group_base_rank(group::String)
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

function group_thread_count(group::String)
    m = match(r"×\s*(\d+)", group)
    m === nothing && return 1
    return parse(Int, m.captures[1])
end

group_sort_key(group::String) = (
    group_base_rank(group),
    group_thread_count(group),
    lowercase(group),
)

function groups_for_dict(values_by_key)
    isempty(values_by_key) && return String[]
    groups = unique(first(k) for k in keys(values_by_key))
    return sort(groups; by=group_sort_key)
end

is_gpu_group(group::AbstractString) = occursin("gpu", lowercase(group))
function ordered_groups(values...)
    groups = String[]
    for values_dict in values
        values_dict === nothing && continue
        append!(groups, unique(first(k) for k in keys(values_dict)))
    end
    unique!(groups)
    return sort(groups; by=group_sort_key)
end

function collect_values_by_group_block(entries, filters; allowed_block_sizes=nothing, excluded_block_sizes=Set{Int}(), allowed_threads=nothing)
    values_tmp = Dict{Tuple{String,Int},Tuple{Vector{Float64},Vector{Float64}}}()

    for entry in entries
        keep_entry(entry, filters) || continue
        threads = to_int(get_nested(entry, "params.threads"))
        if allowed_threads !== nothing
            (threads === nothing || !(threads in allowed_threads)) && continue
        end
        group = impl_group(entry)
        block = to_int(get_nested(entry, BLOCK_KEY))
        cpu = to_float(get_nested(entry, "max_cpu_rss_mib"))
        gpu = to_float(get_nested(entry, "max_gpu_memory_mib"))
        (block === nothing || cpu === nothing) && continue

        dataset = lowercase(strip(string(get_nested(entry, "params.dataset"))))
        if allowed_block_sizes !== nothing && haskey(allowed_block_sizes, dataset)
            block in allowed_block_sizes[dataset] || continue
        end
        block in excluded_block_sizes && continue

        gpu = gpu === nothing ? 0.0 : gpu
        key = (group, block)
        if !haskey(values_tmp, key)
            values_tmp[key] = (Float64[], Float64[])
        end
        push!(values_tmp[key][1], cpu)
        push!(values_tmp[key][2], gpu)
    end

    values_by_group_block = Dict{Tuple{String,Int},Any}()
    for (key, (cpu_samples, gpu_samples)) in values_tmp
        isempty(cpu_samples) && continue
        values_by_group_block[key] = (
            cpu_median=median(cpu_samples),
            gpu_median=isempty(gpu_samples) ? 0.0 : median(gpu_samples),
            cpu_samples=cpu_samples,
            gpu_samples=gpu_samples,
        )
    end
    return values_by_group_block
end

function collect_values_by_group(entries, filters; allowed_threads=nothing)
    values_tmp = Dict{String,Tuple{Vector{Float64},Vector{Float64}}}()

    for entry in entries
        keep_entry(entry, filters) || continue
        threads = to_int(get_nested(entry, "params.threads"))
        if allowed_threads !== nothing
            (threads === nothing || !(threads in allowed_threads)) && continue
        end
        group = impl_group(entry)
        cpu = to_float(get_nested(entry, "max_cpu_rss_mib"))
        gpu = to_float(get_nested(entry, "max_gpu_memory_mib"))
        cpu === nothing && continue
        gpu = gpu === nothing ? 0.0 : gpu
        if !haskey(values_tmp, group)
            values_tmp[group] = (Float64[], Float64[])
        end
        push!(values_tmp[group][1], cpu)
        push!(values_tmp[group][2], gpu)
    end

    values_by_group = Dict{String,Any}()
    for (group, (cpu_samples, gpu_samples)) in values_tmp
        isempty(cpu_samples) && continue
        values_by_group[group] = (
            cpu_median=median(cpu_samples),
            gpu_median=isempty(gpu_samples) ? 0.0 : median(gpu_samples),
            cpu_samples=cpu_samples,
            gpu_samples=gpu_samples,
        )
    end
    return values_by_group
end

function bars_for_blocksize(values_by_group_block, group_color)
    groups = groups_for_dict(values_by_group_block)
    x_centers = Float64[]
    x_labels = String[]
    xs_cpu_big = Float64[]
    ys_cpu_big = Float64[]
    colors_cpu_big = Any[]
    cpu_big_samples = Vector{Vector{Float64}}()
    xs_gpu_cpu = Float64[]
    ys_gpu_cpu = Float64[]
    colors_gpu_cpu = Any[]
    gpu_cpu_samples = Vector{Vector{Float64}}()
    xs_gpu_mem = Float64[]
    ys_gpu_mem = Float64[]
    colors_gpu_mem = Any[]
    gpu_mem_samples = Vector{Vector{Float64}}()
    group_labels = String[]
    group_centers = Float64[]

    x = 1.0
    blocks = sort(unique(last(k) for k in keys(values_by_group_block)))
    for g in groups
        group_xs = Float64[]
        for b in blocks
            push!(x_centers, x)
            push!(group_xs, x)
            push!(x_labels, format_int_commas(b))

            key = (g, b)
            if haskey(values_by_group_block, key)
                vals = values_by_group_block[key]
                cpu_gib = vals.cpu_median / 1024.0
                gpu_gib = vals.gpu_median / 1024.0
                cpu_samples_gib = [v / 1024.0 for v in vals.cpu_samples]
                gpu_samples_gib = [v / 1024.0 for v in vals.gpu_samples]

                if is_gpu_group(g)
                    push!(xs_gpu_cpu, x - GPU_PAIR_OFFSET)
                    push!(ys_gpu_cpu, cpu_gib)
                    push!(colors_gpu_cpu, group_color[g])
                    push!(gpu_cpu_samples, cpu_samples_gib)

                    push!(xs_gpu_mem, x + GPU_PAIR_OFFSET)
                    push!(ys_gpu_mem, gpu_gib)
                    push!(colors_gpu_mem, lighten(group_color[g], 0.45))
                    push!(gpu_mem_samples, gpu_samples_gib)
                else
                    push!(xs_cpu_big, x)
                    push!(ys_cpu_big, cpu_gib)
                    push!(colors_cpu_big, group_color[g])
                    push!(cpu_big_samples, cpu_samples_gib)
                end
            end
            x += 1.0
        end
        if !isempty(group_xs)
            push!(group_centers, (first(group_xs) + last(group_xs)) / 2)
            push!(group_labels, impl_tick_label(g))
        end
        x += 1.4
    end

    return (
        x_centers=x_centers,
        x_labels=x_labels,
        xs_cpu_big=xs_cpu_big,
        ys_cpu_big=ys_cpu_big,
        colors_cpu_big=colors_cpu_big,
        cpu_big_samples=cpu_big_samples,
        xs_gpu_cpu=xs_gpu_cpu,
        ys_gpu_cpu=ys_gpu_cpu,
        colors_gpu_cpu=colors_gpu_cpu,
        gpu_cpu_samples=gpu_cpu_samples,
        xs_gpu_mem=xs_gpu_mem,
        ys_gpu_mem=ys_gpu_mem,
        colors_gpu_mem=colors_gpu_mem,
        gpu_mem_samples=gpu_mem_samples,
        group_labels=group_labels,
        group_centers=group_centers,
    )
end

function overlay_samples!(ax, xs::Vector{Float64}, samples::Vector{Vector{Float64}}, colors::Vector)
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

function overlay_samples_horizontal!(ax, ys::Vector{Float64}, samples::Vector{Vector{Float64}}, colors::Vector)
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

function plot_blocksize_dataset!(ax, bars, dataset_label; ytick_step=nothing)
    if isempty(bars.x_centers)
        return
    end

    cpu_max = max(
        isempty(bars.ys_cpu_big) ? 0.0 : maximum(bars.ys_cpu_big),
        isempty(bars.ys_gpu_cpu) ? 0.0 : maximum(bars.ys_gpu_cpu),
    )
    gpu_max = isempty(bars.ys_gpu_mem) ? 0.0 : maximum(bars.ys_gpu_mem)
    sample_max = max(
        max_from_samples(bars.cpu_big_samples),
        max_from_samples(bars.gpu_cpu_samples),
        max_from_samples(bars.gpu_mem_samples),
    )
    ymax = max(cpu_max, gpu_max, sample_max, 1e-6)
    ytop = TOP_FACTOR * ymax

    if !isempty(bars.xs_cpu_big)
        barplot!(ax, bars.xs_cpu_big, bars.ys_cpu_big; fillto=0.0, color=bars.colors_cpu_big, width=MEMORY_SINGLE_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(bars.xs_gpu_cpu)
        barplot!(ax, bars.xs_gpu_cpu, bars.ys_gpu_cpu; fillto=0.0, color=bars.colors_gpu_cpu, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(bars.xs_gpu_mem)
        barplot!(ax, bars.xs_gpu_mem, bars.ys_gpu_mem; fillto=0.0, color=bars.colors_gpu_mem, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end

    overlay_samples!(ax, bars.xs_cpu_big, bars.cpu_big_samples, bars.colors_cpu_big)
    overlay_samples!(ax, bars.xs_gpu_cpu, bars.gpu_cpu_samples, bars.colors_gpu_cpu)
    overlay_samples!(ax, bars.xs_gpu_mem, bars.gpu_mem_samples, bars.colors_gpu_mem)

    label_y_offset = VALUE_LABEL_OFFSET_RATIO * ytop
    for (bx, by) in zip(bars.xs_cpu_big, bars.ys_cpu_big)
        text!(ax, bx, by + label_y_offset; text=@sprintf("%.2f GB", by), align=(:left, :center), rotation=π / 2, fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(bars.xs_gpu_cpu, bars.ys_gpu_cpu)
        text!(ax, bx, by + label_y_offset; text=@sprintf("%.2f GB", by), align=(:left, :center), rotation=π / 2, fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(bars.xs_gpu_mem, bars.ys_gpu_mem)
        text!(ax, bx, by + label_y_offset; text=@sprintf("%.2f GB", by), align=(:left, :center), rotation=π / 2, fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end

    ax.xticks = (bars.x_centers, bars.x_labels)
    ax.xticklabelrotation = DIAGONAL_TICK_LABEL_ROTATION
    ylims!(ax, 0, ytop)
    if ytick_step !== nothing
        tick_top = max(1, ceil(Int, ytop))
        step = max(1, Int(ytick_step))
        yticks = collect(0:step:tick_top)
        ax.yticks = (yticks, string.(yticks))
    end
    ax.title = "Dataset: $dataset_label"
    style_axis_title!(ax)
    for (center, group_label) in zip(bars.group_centers, bars.group_labels)
        text!(ax, center, GROUP_HEADER_Y_RATIO * ytop; text=group_label, align=(:center, :top), color=SECONDARY_TEXT_COLOR)
    end
end

function bars_for_blocksize_horizontal(
    values_by_group_block,
    group_color;
    groups_override=nothing,
    blocks_override=nothing,
    group_blocks_override=nothing,
)
    groups = groups_override === nothing ? groups_for_dict(values_by_group_block) : collect(groups_override)
    y_positions = Float64[]
    y_labels = Any[]
    xs_cpu_big = Float64[]
    ys_cpu_big = Float64[]
    colors_cpu_big = Any[]
    cpu_big_samples = Vector{Vector{Float64}}()
    xs_gpu_cpu = Float64[]
    ys_gpu_cpu = Float64[]
    colors_gpu_cpu = Any[]
    gpu_cpu_samples = Vector{Vector{Float64}}()
    xs_gpu_mem = Float64[]
    ys_gpu_mem = Float64[]
    colors_gpu_mem = Any[]
    gpu_mem_samples = Vector{Vector{Float64}}()

    y = 1.8
    blocks = blocks_override === nothing ? sort(unique(last(k) for k in keys(values_by_group_block))) : collect(blocks_override)
    for g in groups
        group_blocks = group_blocks_override === nothing ? blocks : get(group_blocks_override, g, Int[])
        isempty(group_blocks) && continue

        push!(y_positions, y - 0.95)
        push!(y_labels, rich(impl_tick_label(g); font=:bold))

        for b in group_blocks
            push!(y_positions, y)
            push!(y_labels, format_int_commas(b))

            key = (g, b)
            if haskey(values_by_group_block, key)
                vals = values_by_group_block[key]
                cpu_gib = vals.cpu_median / 1024.0
                gpu_gib = vals.gpu_median / 1024.0
                cpu_samples_gib = [v / 1024.0 for v in vals.cpu_samples]
                gpu_samples_gib = [v / 1024.0 for v in vals.gpu_samples]

                if is_gpu_group(g)
                    push!(xs_gpu_cpu, cpu_gib)
                    push!(ys_gpu_cpu, y - GPU_PAIR_OFFSET)
                    push!(colors_gpu_cpu, group_color[g])
                    push!(gpu_cpu_samples, cpu_samples_gib)

                    push!(xs_gpu_mem, gpu_gib)
                    push!(ys_gpu_mem, y + GPU_PAIR_OFFSET)
                    push!(colors_gpu_mem, lighten(group_color[g], GPU_MEMORY_LIGHTEN_FACTOR))
                    push!(gpu_mem_samples, gpu_samples_gib)
                else
                    push!(xs_cpu_big, cpu_gib)
                    push!(ys_cpu_big, y)
                    push!(colors_cpu_big, group_color[g])
                    push!(cpu_big_samples, cpu_samples_gib)
                end
            end
            y += 1.0
        end
        y += 1.6
    end

    return (
        y_positions=y_positions,
        y_labels=y_labels,
        xs_cpu_big=xs_cpu_big,
        ys_cpu_big=ys_cpu_big,
        colors_cpu_big=colors_cpu_big,
        cpu_big_samples=cpu_big_samples,
        xs_gpu_cpu=xs_gpu_cpu,
        ys_gpu_cpu=ys_gpu_cpu,
        colors_gpu_cpu=colors_gpu_cpu,
        gpu_cpu_samples=gpu_cpu_samples,
        xs_gpu_mem=xs_gpu_mem,
        ys_gpu_mem=ys_gpu_mem,
        colors_gpu_mem=colors_gpu_mem,
        gpu_mem_samples=gpu_mem_samples,
    )
end

function plot_blocksize_dataset_horizontal!(ax, bars, dataset_label; ytick_step=nothing)
    ax.yreversed = true
    ax.xgridvisible = true
    ax.xgridcolor = GRID_COLOR
    ax.ygridvisible = false

    if isempty(bars.y_positions)
        return
    end

    cpu_max = max(
        isempty(bars.xs_cpu_big) ? 0.0 : maximum(bars.xs_cpu_big),
        isempty(bars.xs_gpu_cpu) ? 0.0 : maximum(bars.xs_gpu_cpu),
    )
    gpu_max = isempty(bars.xs_gpu_mem) ? 0.0 : maximum(bars.xs_gpu_mem)
    sample_max = max(
        max_from_samples(bars.cpu_big_samples),
        max_from_samples(bars.gpu_cpu_samples),
        max_from_samples(bars.gpu_mem_samples),
    )
    xmax = max(cpu_max, gpu_max, sample_max, 1e-6)
    xtop = TOP_FACTOR * xmax
    label_x_offset = VALUE_LABEL_OFFSET_RATIO * xtop

    if !isempty(bars.xs_cpu_big)
        barplot!(ax, bars.ys_cpu_big, bars.xs_cpu_big; direction=:x, fillto=0.0, color=bars.colors_cpu_big, width=MEMORY_SINGLE_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(bars.xs_gpu_cpu)
        barplot!(ax, bars.ys_gpu_cpu, bars.xs_gpu_cpu; direction=:x, fillto=0.0, color=bars.colors_gpu_cpu, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(bars.xs_gpu_mem)
        barplot!(ax, bars.ys_gpu_mem, bars.xs_gpu_mem; direction=:x, fillto=0.0, color=bars.colors_gpu_mem, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end

    overlay_samples_horizontal!(ax, bars.ys_cpu_big, bars.cpu_big_samples, bars.colors_cpu_big)
    overlay_samples_horizontal!(ax, bars.ys_gpu_cpu, bars.gpu_cpu_samples, bars.colors_gpu_cpu)
    overlay_samples_horizontal!(ax, bars.ys_gpu_mem, bars.gpu_mem_samples, bars.colors_gpu_mem)

    for (bx, by) in zip(bars.xs_cpu_big, bars.ys_cpu_big)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(bars.xs_gpu_cpu, bars.ys_gpu_cpu)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(bars.xs_gpu_mem, bars.ys_gpu_mem)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end

    ax.yticks = (bars.y_positions, bars.y_labels)
    ax.yticklabelalign = (:right, :center)
    ax.yticksvisible = false
    y_values = vcat(bars.y_positions, bars.ys_cpu_big, bars.ys_gpu_cpu, bars.ys_gpu_mem)
    ypad = 0.8
    ylims!(ax, maximum(y_values) + ypad, minimum(y_values) - ypad)
    xlims!(ax, 0.0, xtop)
    if ytick_step !== nothing
        tick_top = max(1, ceil(Int, xtop))
        step = max(1, Int(ytick_step))
        xticks = collect(0:step:tick_top)
        ax.xticks = (xticks, string.(xticks))
    end
    ax.title = "Dataset: $dataset_label"
    style_axis_title!(ax)
end

function save_memory_full_plot(entries)
    values_per_dataset = Dict{String,Dict{Tuple{String,Int},Any}}()
    all_groups = String[]
    legend_has_samples = false
    for dataset in DATASETS
        filters = Dict(
            "params.n_iter" => "40",
            "params.dataset" => dataset,
        )
        values_by_group_block = collect_values_by_group_block(entries, filters)
        values_per_dataset[dataset] = values_by_group_block
        append!(all_groups, groups_for_dict(values_by_group_block))
        legend_has_samples |= any(!isempty(vals.cpu_samples) || !isempty(vals.gpu_samples) for vals in values(values_by_group_block))
    end
    unique!(all_groups)
    all_groups = sort(all_groups; by=group_sort_key)
    group_color = Dict(g => group_base_color(g) for g in all_groups)
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
    output_base, output_ext = splitext(OUTPUT_FILE_MEMORY_FULL)
    for (page_idx, page_group_blocks) in enumerate(page_blocks)
        isempty(page_group_blocks) && continue

        fig = Figure(size=(1092, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1))
        rowgap!(fig.layout, 16)
        add_supertitle!(
            fig[0, 1:length(DATASETS)],
            "Full Memory Benchmark Results";
            subtitle="Page $(page_idx) of $(length(page_blocks))",
        )
        axes = Axis[]
        for (col, _) in enumerate(DATASETS)
            ax = Axis(
                fig[1, col],
                backgroundcolor=AXIS_BACKGROUND_COLOR,
                xlabel="Max. Memory GB",
                ylabel=col == 1 ? "Block Size" : "",
                xgridvisible=true,
                ygridvisible=false,
                xgridcolor=GRID_COLOR,
                leftspinecolor=SPINE_COLOR,
                bottomspinecolor=SPINE_COLOR,
            )
            style_axis_title!(ax)
            col == 1 || (ax.yticklabelsvisible = false)
            push!(axes, ax)
        end

        page_groups = [group for group in all_groups if haskey(page_group_blocks, group)]
        for (i, dataset) in enumerate(DATASETS)
            bars = bars_for_blocksize_horizontal(
                values_per_dataset[dataset],
                group_color;
                groups_override=page_groups,
                group_blocks_override=page_group_blocks,
            )
            plot_blocksize_dataset_horizontal!(axes[i], bars, get(DATASET_LABEL, dataset, dataset))
        end

        text!(
            fig.scene,
            CAPTION_X,
            CAPTION_Y;
            text=MEMORY_CAPTION,
            space=:relative,
            align=(:left, :bottom),
            color=SECONDARY_TEXT_COLOR,
        )

        add_notation_legend!(fig[1, 3], all_groups; show_samples=legend_has_samples, group_colors=group_color)

        output_path = output_base * "_page$(page_idx)" * output_ext
        save(output_path, fig)
        println("Saved figure: $output_path")
    end
end

function save_memory_blocksize_plot(entries)
    dataset = "big"
    filters = copy(BASE_FILTERS)
    filters["params.dataset"] = dataset
    values_by_group_block = collect_values_by_group_block(
        entries,
        filters;
        allowed_block_sizes=ALLOWED_BLOCK_SIZES,
        excluded_block_sizes=EXCLUDED_BLOCK_SIZES,
        allowed_threads=ALLOWED_THREADS,
    )
    full_block = FULL_BLOCK_SIZE[dataset]
    values_by_group_block = Dict(
        k => v for (k, v) in values_by_group_block
        if k[2] != full_block
    )

    all_groups = groups_for_dict(values_by_group_block)
    group_color = Dict(g => group_base_color(g) for g in all_groups)
    bars = bars_for_blocksize_horizontal(values_by_group_block, group_color)

    fig_height = max(840, 16 * length(bars.y_positions) + 260) + 50
    fig = Figure(size=(FIGURE_WIDTH, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    rowgap!(fig.layout, 16)
    add_supertitle!(fig[0, 1], "Memory Use Across Block Size"; subtitle="Dataset: $(get(DATASET_LABEL, dataset, dataset))")
    ax = Axis(
        fig[1, 1],
        backgroundcolor=AXIS_BACKGROUND_COLOR,
        xlabel="Max. Memory GB",
        ylabel="Block Size",
        xgridvisible=true,
        ygridvisible=false,
        xgridcolor=GRID_COLOR,
        leftspinecolor=SPINE_COLOR,
        bottomspinecolor=SPINE_COLOR,
    )
    style_axis_title!(ax)
    plot_blocksize_dataset_horizontal!(ax, bars, get(DATASET_LABEL, dataset, dataset); ytick_step=2)
    ax.title = ""

    text!(
        fig.scene,
        CAPTION_X,
        CAPTION_Y;
        text=MEMORY_CAPTION,
        space=:relative,
        align=(:left, :bottom),
        color=SECONDARY_TEXT_COLOR,
    )

    add_notation_legend!(
        fig[1, 1],
        all_groups;
        show_samples=has_sample_data(bars.cpu_big_samples) || has_sample_data(bars.gpu_cpu_samples) || has_sample_data(bars.gpu_mem_samples),
        group_colors=group_color,
    )

    save(OUTPUT_FILE_BLOCKSIZE, fig)
    println("Saved figure: $OUTPUT_FILE_BLOCKSIZE")
end

function collect_full_block_values(entries; datasets=DATASETS)
    values = Dict{Tuple{String,String},Any}()
    for dataset in datasets
        filters = copy(BASE_FILTERS)
        filters["params.dataset"] = dataset
        filters["params.block_size"] = string(FULL_BLOCK_SIZE[dataset])
        by_group = collect_values_by_group(entries, filters; allowed_threads=ALLOWED_THREADS)
        for (group, vals) in by_group
            values[(group, dataset)] = vals
        end
    end
    return values
end

function collect_uniform_block_values(entries, block_size::Int; datasets=DATASETS)
    values = Dict{Tuple{String,String},Any}()
    for dataset in datasets
        filters = copy(BASE_FILTERS)
        filters["params.dataset"] = dataset
        filters["params.block_size"] = string(block_size)
        by_group = collect_values_by_group(entries, filters; allowed_threads=ALLOWED_THREADS)
        for (group, vals) in by_group
            values[(group, dataset)] = vals
        end
    end
    return values
end

function save_memory_dataset_group_plot(
    all_values,
    subtitle::String,
    output_path::String;
    reference_values=nothing,
    caption=MEMORY_CAPTION,
    datasets=DATASETS,
    show_heading::Bool=true,
    figure_padding=FIGURE_PADDING,
    show_legend::Bool=true,
)
    ytick_positions = Float64[]
    ytick_labels = Any[]
    xs_cpu_ref = Float64[]
    ys_cpu_ref = Float64[]
    colors_cpu_ref = Any[]
    xs_gpu_cpu_ref = Float64[]
    ys_gpu_cpu_ref = Float64[]
    colors_gpu_cpu_ref = Any[]
    xs_gpu_mem_ref = Float64[]
    ys_gpu_mem_ref = Float64[]
    colors_gpu_mem_ref = Any[]
    xs_cpu_big = Float64[]
    ys_cpu_big = Float64[]
    colors_cpu_big = Any[]
    cpu_big_samples = Vector{Vector{Float64}}()
    xs_gpu_cpu = Float64[]
    ys_gpu_cpu = Float64[]
    colors_gpu_cpu = Any[]
    gpu_cpu_samples = Vector{Vector{Float64}}()
    xs_gpu_mem = Float64[]
    ys_gpu_mem = Float64[]
    colors_gpu_mem = Any[]
    gpu_mem_samples = Vector{Vector{Float64}}()
    groups = ordered_groups(all_values, reference_values)
    legend_has_samples = false

    y = 1.8
    for dataset in datasets
        push!(ytick_positions, y - 0.95)
        push!(ytick_labels, rich(get(DATASET_LABEL, dataset, dataset); font=:bold))

        for group in groups
            push!(ytick_positions, y)
            push!(ytick_labels, impl_tick_label(group))
            key = (group, dataset)
            if haskey(all_values, key)
                vals = all_values[key]
                cpu_gib = vals.cpu_median / 1024.0
                gpu_gib = vals.gpu_median / 1024.0
                cpu_samples_gib = [v / 1024.0 for v in vals.cpu_samples]
                gpu_samples_gib = [v / 1024.0 for v in vals.gpu_samples]
                color = group_base_color(group)
                if is_gpu_group(group)
                    push!(xs_gpu_cpu, cpu_gib)
                    push!(ys_gpu_cpu, y - GPU_PAIR_OFFSET)
                    push!(colors_gpu_cpu, color)
                    push!(gpu_cpu_samples, cpu_samples_gib)

                    push!(xs_gpu_mem, gpu_gib)
                    push!(ys_gpu_mem, y + GPU_PAIR_OFFSET)
                    push!(colors_gpu_mem, lighten(color, GPU_MEMORY_LIGHTEN_FACTOR))
                    push!(gpu_mem_samples, gpu_samples_gib)
                else
                    push!(xs_cpu_big, cpu_gib)
                    push!(ys_cpu_big, y)
                    push!(colors_cpu_big, color)
                    push!(cpu_big_samples, cpu_samples_gib)
                end
                legend_has_samples |= !isempty(cpu_samples_gib) || !isempty(gpu_samples_gib)

                if reference_values !== nothing && haskey(reference_values, key)
                    ref_vals = reference_values[key]
                    ref_cpu_gib = ref_vals.cpu_median / 1024.0
                    ref_gpu_gib = ref_vals.gpu_median / 1024.0
                    ref_color = with_alpha(color, 0.18)
                    if is_gpu_group(group)
                        push!(xs_gpu_cpu_ref, ref_cpu_gib)
                        push!(ys_gpu_cpu_ref, y - GPU_PAIR_OFFSET)
                        push!(colors_gpu_cpu_ref, ref_color)

                        push!(xs_gpu_mem_ref, ref_gpu_gib)
                        push!(ys_gpu_mem_ref, y + GPU_PAIR_OFFSET)
                        push!(colors_gpu_mem_ref, with_alpha(lighten(color, GPU_MEMORY_LIGHTEN_FACTOR), 0.18))
                    else
                        push!(xs_cpu_ref, ref_cpu_gib)
                        push!(ys_cpu_ref, y)
                        push!(colors_cpu_ref, ref_color)
                    end
                end
            end
            y += 1.0
        end
        y += 1.6
    end

    x_cpu = max(
        isempty(xs_cpu_big) ? 0.0 : maximum(xs_cpu_big),
        isempty(xs_gpu_cpu) ? 0.0 : maximum(xs_gpu_cpu),
    )
    x_gpu = isempty(xs_gpu_mem) ? 0.0 : maximum(xs_gpu_mem)
    x_ref = max(
        isempty(xs_cpu_ref) ? 0.0 : maximum(xs_cpu_ref),
        isempty(xs_gpu_cpu_ref) ? 0.0 : maximum(xs_gpu_cpu_ref),
        isempty(xs_gpu_mem_ref) ? 0.0 : maximum(xs_gpu_mem_ref),
    )
    x_samples = max(
        max_from_samples(cpu_big_samples),
        max_from_samples(gpu_cpu_samples),
        max_from_samples(gpu_mem_samples),
    )
    xmax = max(x_cpu, x_gpu, x_ref, x_samples, 1e-6)
    xtop = TOP_FACTOR * xmax

    base_fig_height = max(760, 13 * length(ytick_positions) + 240) + 50
    fig_height = length(datasets) == 1 ? max(320, Int(round(base_fig_height * 0.42))) : base_fig_height
    fig = Figure(size=(FIGURE_WIDTH, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=figure_padding)
    rowgap!(fig.layout, show_heading ? 16 : 0)
    axis_slot = fig[1, 1]
    if show_heading
        supertitle = length(datasets) == 1 ? "Memory Use Across Implementations" : "Memory Use Across Datasets"
        add_supertitle!(fig[0, 1], supertitle; subtitle=subtitle)
    end
    ax = Axis(
        axis_slot,
        backgroundcolor=AXIS_BACKGROUND_COLOR,
        xlabel="Max. Memory GB",
        ylabel="",
        xgridvisible=true,
        ygridvisible=false,
        xgridcolor=GRID_COLOR,
        leftspinecolor=SPINE_COLOR,
        bottomspinecolor=SPINE_COLOR,
        title="",
    )
    style_axis_title!(ax)
    ax.yreversed = true

    if !isempty(xs_cpu_ref)
        barplot!(ax, ys_cpu_ref, xs_cpu_ref; direction=:x, fillto=0.0, color=colors_cpu_ref, width=MEMORY_SINGLE_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(xs_gpu_cpu_ref)
        barplot!(ax, ys_gpu_cpu_ref, xs_gpu_cpu_ref; direction=:x, fillto=0.0, color=colors_gpu_cpu_ref, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(xs_gpu_mem_ref)
        barplot!(ax, ys_gpu_mem_ref, xs_gpu_mem_ref; direction=:x, fillto=0.0, color=colors_gpu_mem_ref, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end

    if !isempty(xs_cpu_big)
        barplot!(ax, ys_cpu_big, xs_cpu_big; direction=:x, fillto=0.0, color=colors_cpu_big, width=MEMORY_SINGLE_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(xs_gpu_cpu)
        barplot!(ax, ys_gpu_cpu, xs_gpu_cpu; direction=:x, fillto=0.0, color=colors_gpu_cpu, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end
    if !isempty(xs_gpu_mem)
        barplot!(ax, ys_gpu_mem, xs_gpu_mem; direction=:x, fillto=0.0, color=colors_gpu_mem, width=MEMORY_PAIRED_BAR_WIDTH, strokewidth=0)
    end

    overlay_samples_horizontal!(ax, ys_cpu_big, cpu_big_samples, colors_cpu_big)
    overlay_samples_horizontal!(ax, ys_gpu_cpu, gpu_cpu_samples, colors_gpu_cpu)
    overlay_samples_horizontal!(ax, ys_gpu_mem, gpu_mem_samples, colors_gpu_mem)

    label_x_offset = VALUE_LABEL_OFFSET_RATIO * xtop
    for (bx, by) in zip(xs_cpu_big, ys_cpu_big)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(xs_gpu_cpu, ys_gpu_cpu)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end
    for (bx, by) in zip(xs_gpu_mem, ys_gpu_mem)
        text!(ax, bx + label_x_offset, by; text=@sprintf("%.2f GB", bx), align=(:left, :center), fontsize=BAR_LABEL_FONT_SIZE, color=PRIMARY_TEXT_COLOR)
    end

    xlims!(ax, 0.0, xtop)
    ax.yticks = (ytick_positions, ytick_labels)
    ax.yticklabelalign = (:right, :center)
    ax.yticksvisible = false

    if !isempty(caption)
        text!(
            fig.scene,
            CAPTION_X,
            CAPTION_Y;
            text=caption,
            space=:relative,
            align=(:left, :bottom),
            color=SECONDARY_TEXT_COLOR,
        )
    end

    if show_legend
        legend_colors = Dict(group => group_base_color(group) for group in groups)
        add_notation_legend!(axis_slot, groups; show_samples=legend_has_samples, group_colors=legend_colors)
    end

    save(output_path, fig)
    println("Saved figure: $output_path")
end

function save_memory_noblock_plot(entries)
    all_values = collect_full_block_values(entries)
    save_memory_dataset_group_plot(all_values, "Blockwise Processing Disabled", OUTPUT_FILE_NOBLOCK)
end

function save_memory_block1000_plot(entries)
    all_values = collect_uniform_block_values(entries, 1_000)
    full_values = collect_full_block_values(entries)
    save_memory_dataset_group_plot(
        all_values,
        "Block Size: 1000",
        OUTPUT_FILE_BLOCK1000;
        reference_values=full_values,
        caption=MEMORY_BLOCK1000_CAPTION
    )
end

function save_memory_noblock_big_plot(entries)
    datasets = ["big"]
    all_values = collect_full_block_values(entries; datasets=datasets)
    save_memory_dataset_group_plot(
        all_values,
        "Dataset: $(DATASET_LABEL["big"]), Blockwise Processing Disabled",
        OUTPUT_FILE_NOBLOCK_BIG;
        datasets=datasets,
        show_heading=false,
        caption="",
        figure_padding=(4, 4, 4, 4),
        show_legend=false,
    )
end

function save_memory_block1000_big_plot(entries)
    datasets = ["big"]
    all_values = collect_uniform_block_values(entries, 1_000; datasets=datasets)
    full_values = collect_full_block_values(entries; datasets=datasets)
    save_memory_dataset_group_plot(
        all_values,
        "Dataset: $(DATASET_LABEL["big"]), Block Size: 1000",
        OUTPUT_FILE_BLOCK1000_BIG;
        reference_values=full_values,
        datasets=datasets,
        show_heading=false,
        caption="",
        figure_padding=(4, 4, 4, 4),
        show_legend=false,
    )
end

function memory_main(args=ARGS)
    mode = isempty(args) ? "all" : lowercase(strip(args[1]))
    entries = load_sample_entries(INPUT_FILE)
    mkpath(OUTPUT_DIR)

    if mode == "all"
        save_memory_full_plot(entries)
        save_memory_blocksize_plot(entries)
        save_memory_noblock_plot(entries)
        save_memory_block1000_plot(entries)
        save_memory_noblock_big_plot(entries)
        save_memory_block1000_big_plot(entries)
    elseif mode == "full"
        save_memory_full_plot(entries)
    elseif mode == "blocksize"
        save_memory_blocksize_plot(entries)
    elseif mode == "noblock"
        save_memory_noblock_plot(entries)
    elseif mode == "block1000"
        save_memory_block1000_plot(entries)
    elseif mode == "noblock-big"
        save_memory_noblock_big_plot(entries)
    elseif mode == "block1000-big"
        save_memory_block1000_big_plot(entries)
    else
        println("Unknown mode '$mode'. Use one of: all, full, blocksize, noblock, block1000, noblock-big, block1000-big")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    memory_main()
end
