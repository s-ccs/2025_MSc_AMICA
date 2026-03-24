using Amica
using ArgParse

include(joinpath(@__DIR__, "..", "integration_tests", "util.jl"))

const JULIA_RUNNER_PATH = abspath(@__FILE__)

function parse_device(value::AbstractString)
    v = lowercase(String(value))
    if v == "cpu"
        return :cpu
    elseif v == "gpu"
        return :gpu
    end
    error("Invalid value for device: $value (expected cpu or gpu)")
end

function parse_precision(value::AbstractString)
    v = lowercase(String(value))
    if v in ("float32", "f32")
        return Float32
    elseif v in ("float64", "f64")
        return Float64
    end
    error("Invalid value for precision: $value (expected float32, or float64)")
end

function parse_dataset(value::AbstractString)
    v = lowercase(String(value))
    v in ("memorize", "big", "small") || error("Invalid dataset '$value' (expected memorize, big, or small)")
    return v
end

function positive_int(name::String, value)
    if value isa Integer
        iv = Int(value)
    elseif value isa AbstractString
        try
            iv = parse(Int, String(value))
        catch
            error("Invalid value for $name: $value (expected positive integer)")
        end
    elseif value isa AbstractFloat && isinteger(value)
        iv = Int(value)
    else
        error("Invalid value for $name: $value (expected positive integer)")
    end
    iv > 0 || error("Invalid value for $name: $value (expected positive integer)")
    return iv
end

function parse_config(args::Vector{String})
    settings = ArgParseSettings()
    @add_arg_table! settings begin
        "config"
        help = "Config format: dataset implementation device block_size precision threads n_iter"
        arg_type = String
    end

    parsed = parse_args(args, settings; as_symbols=true)
    tokens = split(strip(String(parsed[:config])))
    length(tokens) == 7 || error(
        "Invalid config format. Expected 7 fields: dataset implementation device block_size precision threads n_iter",
    )

    dataset = parse_dataset(tokens[1])
    implementation = lowercase(tokens[2])
    implementation == "julia" || error("julia_runner expects implementation=julia, got '$implementation'")
    device = parse_device(tokens[3])
    block_size = positive_int("block_size", tokens[4])
    precision = parse_precision(tokens[5])
    num_threads = positive_int("threads", tokens[6])
    n_iter = positive_int("n_iter", tokens[7])

    config = join(
        (dataset, "julia", device == :gpu ? "gpu" : "cpu", string(block_size), lowercase(string(precision)), string(num_threads), string(n_iter)),
        " ",
    )

    return (dataset, device, block_size, precision, num_threads, n_iter, config)
end

function resolve_array_type(device::Symbol)
    if device == :cpu
        return Array
    end

    isdefined(Main, :CUDA) || error("CUDA device requested, but CUDA.jl is not loaded")
    return getfield(Main, :CUDA).CuArray
end

function ensure_cuda_loaded!()
    if !isdefined(Main, :CUDA)
        @eval import CUDA
    end
    return nothing
end

function dataset_spec(dataset::String)
    if dataset == "memorize"
        return (path=integration_test_path("input", "Memorize.fdt"), ncols=71)
    elseif dataset == "big"
        return (path=joinpath(@__DIR__, "big.bin"), ncols=128)
    else
        return (path=joinpath(@__DIR__, "small.bin"), ncols=19)
    end
end

function run_benchmark(dataset, device, block_size, precision, num_threads, n_iter)
    Threads.nthreads() == num_threads || error(
        "Julia process has $(Threads.nthreads()) threads, but config requested $num_threads. ")

    array_type = resolve_array_type(device)

    spec = dataset_spec(dataset)
    isfile(spec.path) || error("Dataset file not found: $(spec.path)")
    data = read_fdt(spec.path; ncols=spec.ncols, T=Float32, transpose=true, OutType=precision)
    N, n = size(data)

    println(
        "Configuration: dataset=$(dataset), device=$(device), precision=$(precision), block_size=$(block_size), threads=$(num_threads), n_iter=$(n_iter)"
    )

    lrate = Amica.LearningRate{precision}(newtrate=precision(1.0))
    myAmica = SingleModelAmica(
        precision,
        ncomps=n,
        nsamples=N,
        m=3,
        ArrayType=array_type,
        block_size=block_size,
        num_threads=num_threads,
    )

    Amica.amica!(myAmica, data, maxiter=n_iter, newt_start_iter=0, lrate=lrate)
    return nothing
end

function ensure_julia_threads!(num_threads::Int, config::String)
    Threads.nthreads() == num_threads && return false

    if get(ENV, "AMICA_JULIA_RUNNER_REEXEC", "0") == "1"
        error(
            "Requested $num_threads Julia threads, but process still has $(Threads.nthreads()) " *
            "after re-exec attempt."
        )
    end

    julia_bin = joinpath(Sys.BINDIR, Base.julia_exename())
    project_path = abspath(joinpath(@__DIR__, ".."))
    cmd = `$julia_bin --threads=$num_threads --project=$project_path $JULIA_RUNNER_PATH $config`

    println("Re-launching julia_runner with threads=$num_threads (current=$(Threads.nthreads()))")
    run(setenv(cmd, "AMICA_JULIA_RUNNER_REEXEC" => "1"))
    return true
end

function main(args::Vector{String})
    dataset, device, block_size, precision, num_threads, n_iter, config = parse_config(args)

    if ensure_julia_threads!(num_threads, config)
        return nothing
    end

    if device == :gpu
        try
            ensure_cuda_loaded!()
        catch err
            error("Failed to load CUDA: $(sprint(showerror, err))")
        end
        return Base.invokelatest(run_benchmark, dataset, device, block_size, precision, num_threads, n_iter)
    end

    return run_benchmark(dataset, device, block_size, precision, num_threads, n_iter)
end

main(ARGS)
