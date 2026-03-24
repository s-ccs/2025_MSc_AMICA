using ArgParse
using CairoMakie
using Dates
using JSON3

const SCRIPT_DIR = @__DIR__
include(joinpath(SCRIPT_DIR, "constants.jl"))

const PLOTS_DIR = joinpath(SCRIPT_DIR, "plots")
const JULIA_RUNNER = joinpath(SCRIPT_DIR, "julia_runner.jl")
const FORTRAN_RUNNER = joinpath(SCRIPT_DIR, "fortran_runner.jl")
const DEFAULT_PARAM = joinpath(SCRIPT_DIR, "default.param")
const DEFAULT_CACHE_FILE = joinpath(SCRIPT_DIR, "ll_compare_memorize_big_backup.json")
const DATASETS = ["small", "memorize", "big"]
const DATASET_LABEL = Dict(
    "small" => "Cognitive Workload",
    "memorize" => "Memorize",
    "big" => "EEG Eye Tracking",
)

const FORTRAN_BLOCK_SIZE = 1_000
const FORTRAN_THREADS = 64
const JULIA_GPU_BLOCK_SIZE = 100_000
const JULIA_GPU_THREADS = 1
const JULIA_CPU_BLOCK_SIZE = 1_000
const JULIA_CPU_THREADS = 64

const FORTRAN_COLOR = colorant"#4E79A7"
const JULIA_CPU_FLOAT32_COLOR = colorant"#59A14F"
const JULIA_CPU_FLOAT64_COLOR = colorant"#F28E2B"
const JULIA_GPU_FLOAT32_COLOR = colorant"#E15759"
const JULIA_GPU_FLOAT64_COLOR = colorant"#76B7B2"
const PLOT_ALPHA = 0.70

const FORTRAN_STYLE = (label="Fortran Float64", color=FORTRAN_COLOR, linestyle=:solid)
const JULIA_STYLE = (
    (label="Julia GPU", device="gpu", block_size=JULIA_GPU_BLOCK_SIZE, threads=JULIA_GPU_THREADS),
    (label="Julia CPU", device="cpu", block_size=JULIA_CPU_BLOCK_SIZE, threads=JULIA_CPU_THREADS),
)
const PRECISION_STYLE = (
    (token="float32", label="Float32", linestyle=:dash),
    (token="float64", label="Float64", linestyle=:solid),
)

function parse_invocation()
    settings = ArgParseSettings(autofix_names=true)
    @add_arg_table! settings begin
        "--output"
        help = "output path"
        arg_type = String
        default = ""
        "--cache-file"
        help = "path to backup file"
        arg_type = String
        default = DEFAULT_CACHE_FILE
        "--refresh-cache"
        help = ""
        action = :store_true
        "--show-output"
        help = ""
        action = :store_true
        "--keep-temp"
        help = ""
        action = :store_true
        "n_iter"
        help = "number of iterations"
        arg_type = Int
    end

    parsed = parse_args(ARGS, settings; as_symbols=true)

    parsed[:n_iter] === nothing && error("Missing required argument: n_iter")
    n_iter = Int(parsed[:n_iter])

    output = String(parsed[:output])
    if isempty(strip(output))
        output = joinpath(PLOTS_DIR, "ll_compare_memorize_big_iter$(n_iter).svg")
    end

    output = abspath(output)
    cache_file = abspath(String(parsed[:cache_file]))

    return (
        n_iter=n_iter,
        output=output,
        cache_file=cache_file,
        refresh_cache=Bool(parsed[:refresh_cache]),
        show_output=Bool(parsed[:show_output]),
        keep_temp=Bool(parsed[:keep_temp]),
    )
end

function run_and_capture(cmd::Cmd; show_output::Bool=false)
    pipe = Pipe()
    proc = run(pipeline(ignorestatus(cmd), stdout=pipe, stderr=pipe); wait=false)
    close(pipe.in)

    io = IOBuffer()
    reader = @async begin
        while !eof(pipe)
            chunk = readavailable(pipe)
            if !isempty(chunk)
                write(io, chunk)
                if show_output
                    write(stdout, chunk)
                    flush(stdout)
                end
            else
                sleep(0.01)
            end
        end
    end

    wait(proc)
    wait(reader)
    out = String(take!(io))
    return (success(proc), out)
end

function parse_julia_ll(stdout_text::String)
    vals = Float64[]
    for m in eachmatch(r"LL\s*=\s*([\-+0-9.eE]+)", stdout_text)
        push!(vals, parse(Float64, m.captures[1]))
    end
    return vals
end

function read_fortran_ll(ll_path::String, n_iter::Int)
    isfile(ll_path) || error("Fortran LL file not found: $ll_path")
    raw = read(ll_path)
    length(raw) % sizeof(Float64) == 0 || error("Unexpected LL file size for '$ll_path'")
    vals = collect(reinterpret(Float64, raw))
    length(vals) >= n_iter || error("Fortran LL file has $(length(vals)) entries, expected at least $n_iter")
    return vals[1:n_iter]
end

function load_cache_entries(cache_path::String)
    entries = Dict{String,Any}()
    if isfile(cache_path)
        raw = strip(read(cache_path, String))
        if !isempty(raw)
            parsed = try
                JSON3.read(raw)
            catch err
                error("Cache file is not valid JSON: $cache_path\n$(sprint(showerror, err))")
            end
            parsed isa AbstractDict || error("Cache JSON must be an object/map keyed by config string: $cache_path")
            for (k, v) in pairs(parsed)
                entries[String(k)] = v
            end
        end
    end
    return entries
end

function save_cache_entries(cache_path::String, entries::Dict{String,Any})
    mkpath(dirname(cache_path))
    open(cache_path, "w") do io
        write(io, JSON3.write(entries))
        write(io, '\n')
    end
end

function cached_ll(entries::Dict{String,Any}, key::String, n_iter::Int)
    haskey(entries, key) || return nothing
    entry = entries[key]
    entry isa AbstractDict || return nothing
    haskey(entry, "ll") || return nothing
    ll_raw = entry["ll"]
    ll_raw isa AbstractVector || return nothing

    vals = Float64[]
    for v in ll_raw
        push!(vals, Float64(v))
    end
    length(vals) >= n_iter || return nothing
    return vals[1:n_iter]
end

function update_cache_entry!(entries::Dict{String,Any}, key::String, ll::Vector{Float64}, params::Dict{String,Any})
    entries[key] = Dict(
        "key" => key,
        "params" => params,
        "ll" => ll,
        "n_iter" => length(ll),
        "updated_at" => Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS"),
    )
end

function write_template_with_outdir(src_template::String, dst_template::String, outdir::String)
    isfile(src_template) || error("Template param file not found: $src_template")
    lines = readlines(src_template)
    out = String[]
    replaced = false
    for line in lines
        if occursin(r"^[[:space:]]*outdir[[:space:]]+", line)
            push!(out, "outdir $outdir")
            replaced = true
        else
            push!(out, line)
        end
    end
    !replaced && push!(out, "outdir $outdir")
    open(dst_template, "w") do io
        for line in out
            println(io, line)
        end
    end
end

function config_string(dataset::String, impl::String, device::String, block_size::Int, precision::String, threads::Int, n_iter::Int)
    return string(dataset, " ", impl, " ", device, " ", block_size, " ", precision, " ", threads, " ", n_iter)
end

function run_or_error(cmd::Cmd, label::String; show_output::Bool=false)
    ok, out = run_and_capture(cmd; show_output=show_output)
    ok && return out
    cmd_str = join(cmd.exec, ' ')
    error("$label failed.\n\nCommand:\n$cmd_str\n\nOutput:\n$out")
end

function require_ll(ll::Vector{Float64}, n_iter::Int, label::String)
    length(ll) >= n_iter || error("$label produced $(length(ll)) LL values, expected at least $n_iter.")
    return ll[1:n_iter]
end

function series_color(device::String, precision::String)
    if device == "cpu"
        precision == "float64" && return JULIA_CPU_FLOAT64_COLOR
        return JULIA_CPU_FLOAT32_COLOR
    end
    if device == "gpu"
        precision == "float64" && return JULIA_GPU_FLOAT64_COLOR
        return JULIA_GPU_FLOAT32_COLOR
    end
    return colorant"#999999"
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

function plot_dataset!(ax::Axis, series, dataset_label::String)
    for s in series
        x = 1:length(s.ll)
        lines!(ax, x, s.ll; color=s.color, alpha=PLOT_ALPHA, linestyle=s.linestyle, linewidth=3, label=s.label)
        scatter!(ax, x, s.ll; color=s.color, alpha=PLOT_ALPHA, markersize=6)
    end

    ax.title = "Dataset: $dataset_label"
    ax.titlecolor = :gray25
    ax.titlegap = 12
    ax.xlabelcolor = :gray20
    ax.ylabelcolor = :gray20
    ax.xticklabelcolor = :gray20
    ax.yticklabelcolor = :gray20
    axislegend(
        ax;
        position=:rb,
        title="Implementation / Precision",
        nbanks=1,
        framevisible=true,
        backgroundcolor=RGBAf(1, 1, 1, 0.85),
        patchsize=(18, 12),
        rowgap=4,
    )
end

function make_plot(dataset_results, output_path::String; title::String)
    mkpath(dirname(output_path))
    fig_height = 270 * length(dataset_results) + 170
    fig = Figure(size=(FIGURE_WIDTH, fig_height), backgroundcolor=RGBAf(1, 1, 1, 1), figure_padding=FIGURE_PADDING)
    add_supertitle!(fig[0, 1], title)

    for (row, (dataset, series)) in enumerate(dataset_results)
        ax = Axis(
            fig[row, 1],
            xlabel="Iteration",
            ylabel="Log-likelihood",
            xgridvisible=false,
            ygridcolor=GRID_COLOR,
            leftspinecolor=SPINE_COLOR,
            bottomspinecolor=SPINE_COLOR,
            backgroundcolor=AXIS_BACKGROUND_COLOR,
        )
        plot_dataset!(ax, series, get(DATASET_LABEL, dataset, dataset))
    end

    rowgap!(fig.layout, 16)
    save(output_path, fig)
end

cfg = parse_invocation()
project_path = abspath(joinpath(SCRIPT_DIR, ".."))
cache_entries = load_cache_entries(cfg.cache_file)
dataset_results = Tuple{String,Any}[]

tmpdir = mktempdir(prefix="ll_compare_")

for dataset in DATASETS
    series = NamedTuple{(:label, :ll, :color, :linestyle),Tuple{String,Vector{Float64},Any,Any}}[]
    fortran_cfg = config_string(dataset, "fortran", "cpu", FORTRAN_BLOCK_SIZE, "float64", FORTRAN_THREADS, cfg.n_iter)

    dataset_tmpdir = joinpath(tmpdir, dataset)
    mkpath(dataset_tmpdir)
    tmp_template = joinpath(dataset_tmpdir, "template.param")
    tmp_param = joinpath(dataset_tmpdir, "tmp.param")
    outdir = joinpath(dataset_tmpdir, "amicaout")
    mkpath(outdir)
    write_template_with_outdir(DEFAULT_PARAM, tmp_template, outdir)

    fortran_cmd = `julia --project=$project_path $FORTRAN_RUNNER --param-template $tmp_template --param-output $tmp_param $fortran_cfg`

    fortran_ll = cfg.refresh_cache ? nothing : cached_ll(cache_entries, fortran_cfg, cfg.n_iter)
    if fortran_ll === nothing
        println("Running $(FORTRAN_STYLE.label) ($dataset)...")
        _ = run_or_error(fortran_cmd, "$(FORTRAN_STYLE.label) ($dataset)"; show_output=cfg.show_output)
        fortran_ll = read_fortran_ll(joinpath(outdir, "LL"), cfg.n_iter)
        update_cache_entry!(
            cache_entries,
            fortran_cfg,
            fortran_ll,
            Dict(
                "dataset" => dataset,
                "implementation" => "fortran",
                "device" => "cpu",
                "precision" => "float64",
                "block_size" => FORTRAN_BLOCK_SIZE,
                "threads" => FORTRAN_THREADS,
                "n_iter" => cfg.n_iter,
            ),
        )
        save_cache_entries(cfg.cache_file, cache_entries)
    else
        println("Using cached $(FORTRAN_STYLE.label) ($dataset)")
    end
    push!(series, (label=FORTRAN_STYLE.label, ll=require_ll(fortran_ll, cfg.n_iter, FORTRAN_STYLE.label), color=FORTRAN_STYLE.color, linestyle=FORTRAN_STYLE.linestyle))

    for julia_style in JULIA_STYLE
        for precision_style in PRECISION_STYLE
            julia_cfg = config_string(
                dataset,
                "julia",
                julia_style.device,
                julia_style.block_size,
                precision_style.token,
                julia_style.threads,
                cfg.n_iter,
            )
            run_label = "$(julia_style.label) $(precision_style.label)"
            julia_ll = cfg.refresh_cache ? nothing : cached_ll(cache_entries, julia_cfg, cfg.n_iter)
            if julia_ll === nothing
                println("Running $run_label ($dataset)...")
                julia_cmd = `julia --project=$project_path $JULIA_RUNNER $julia_cfg`
                julia_out = run_or_error(julia_cmd, "$run_label ($dataset)"; show_output=cfg.show_output)
                julia_ll = parse_julia_ll(julia_out)
                isempty(julia_ll) && error("Could not parse LL values from runner output for $run_label on dataset '$dataset'.")
                julia_ll = require_ll(julia_ll, cfg.n_iter, run_label)

                update_cache_entry!(
                    cache_entries,
                    julia_cfg,
                    julia_ll,
                    Dict(
                        "dataset" => dataset,
                        "implementation" => "julia",
                        "device" => julia_style.device,
                        "precision" => precision_style.token,
                        "block_size" => julia_style.block_size,
                        "threads" => julia_style.threads,
                        "n_iter" => cfg.n_iter,
                    ),
                )
                save_cache_entries(cfg.cache_file, cache_entries)
            else
                println("Using cached $run_label ($dataset)")
                julia_ll = require_ll(julia_ll, cfg.n_iter, run_label)
            end

            push!(
                series,
                (
                    label=run_label,
                    ll=julia_ll,
                    color=series_color(julia_style.device, precision_style.token),
                    linestyle=precision_style.linestyle,
                ),
            )
        end
    end

    push!(dataset_results, (dataset, series))
end

make_plot(dataset_results, cfg.output; title="Log Likelihood Across $(cfg.n_iter) Iterations")
println("Saved LL comparison plot: $(cfg.output)")

if !cfg.keep_temp
    rm(tmpdir; recursive=true, force=true)
end

