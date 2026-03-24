using ArgParse

const SCRIPT_DIR = @__DIR__
const DEFAULT_PARAM = joinpath(SCRIPT_DIR, "default.param")
const TMP_PARAM = joinpath(SCRIPT_DIR, "tmp.param")
const DEFAULT_OUTDIR = joinpath(SCRIPT_DIR, "amicaout")
const DEFAULT_AMICA_BIN = "/home/fapra_morlock/amica/amica"

const MPI_LIB = "/home/fapra_morlock/mpich-install/lib/"
const ONEAPI_LIB = "/home/fapra_morlock/intel/oneapi/2025.2/lib/"

function parse_dataset(value::AbstractString)
    v = lowercase(String(value))
    v in ("memorize", "big", "small") || error("Invalid dataset '$value' (expected memorize, big, or small)")
    return v
end

function as_int(name::String, value)
    iv = if value isa Integer
        Int(value)
    elseif value isa AbstractString
        try
            parse(Int, String(value))
        catch
            error("Expected '$name' to be an integer, got: $value")
        end
    elseif value isa AbstractFloat && isinteger(value)
        Int(value)
    else
        error("Expected '$name' to be an integer, got: $value")
    end
    iv > 0 || error("Expected '$name' to be > 0, got: $iv")
    return iv
end

function parse_precision(value::AbstractString)
    v = lowercase(String(value))
    if v in ("float64", "f64")
        return "float64"
    end
    error("Invalid precision '$value' for fortran runner (expected float64)")
end

function parse_config(args::Vector{String})
    settings = ArgParseSettings(autofix_names=true)
    @add_arg_table! settings begin
        "--amica-bin"
        help = "Path to Fortran AMICA executable"
        arg_type = String
        default = DEFAULT_AMICA_BIN
        "--param-template"
        help = "Template .param file"
        arg_type = String
        default = DEFAULT_PARAM
        "--param-output"
        help = "Generated .param output file"
        arg_type = String
        default = TMP_PARAM
        "--outdir"
        help = "Output directory used in generated .param file"
        arg_type = String
        default = DEFAULT_OUTDIR
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
    implementation == "fortran" || error("fortran_runner expects implementation=fortran, got '$implementation'")
    device = lowercase(tokens[3])
    device in ("cpu", "gpu") || error("Invalid device '$device' (expected cpu or gpu)")

    block_size = as_int("block_size", tokens[4])
    precision_raw = tokens[5]
    threads = as_int("threads", tokens[6])
    n_iter = as_int("n_iter", tokens[7])

    precision = parse_precision(precision_raw)

    amica_bin = String(parsed[:amica_bin])
    param_template = String(parsed[:param_template])
    param_output = String(parsed[:param_output])
    outdir = String(parsed[:outdir])

    dataset_path, data_dim, field_dim = if dataset == "memorize"
        (joinpath(SCRIPT_DIR, "..", "integration_tests", "input", "Memorize.fdt"), 71, 319500)
    elseif dataset == "big"
        (joinpath(SCRIPT_DIR, "big.bin"), 128, 1260379)
    else
        (joinpath(SCRIPT_DIR, "small.bin"), 19, 172704)
    end

    return (
        dataset=dataset,
        dataset_path=abspath(dataset_path),
        data_dim=data_dim,
        field_dim=field_dim,
        block_size=block_size,
        threads=threads,
        n_iter=n_iter,
        precision=precision,
        amica_bin=amica_bin,
        param_template=param_template,
        param_output=param_output,
        outdir=outdir,
    )
end

function write_param_file(cfg)
    isfile(cfg.param_template) || error("Template param file not found: $(cfg.param_template)")

    lines = readlines(cfg.param_template)
    out = String[]
    set_files = false
    set_data_dim = false
    set_field_dim = false
    set_pcakeep = false
    set_threads = false
    set_block = false
    set_iter = false
    set_outdir = false

    for line in lines
        if occursin(r"^[[:space:]]*files[[:space:]]+", line)
            push!(out, "files $(cfg.dataset_path)")
            set_files = true
        elseif occursin(r"^[[:space:]]*outdir[[:space:]]+", line)
            push!(out, "outdir $(cfg.outdir)")
            set_outdir = true
        elseif occursin(r"^[[:space:]]*data_dim[[:space:]]+", line)
            push!(out, "data_dim $(cfg.data_dim)")
            set_data_dim = true
        elseif occursin(r"^[[:space:]]*field_dim[[:space:]]+", line)
            push!(out, "field_dim $(cfg.field_dim)")
            set_field_dim = true
        elseif occursin(r"^[[:space:]]*pcakeep[[:space:]]+", line)
            # Keep all channels for a fair comparison with Julia runs.
            push!(out, "pcakeep $(cfg.data_dim)")
            set_pcakeep = true
        elseif occursin(r"^[[:space:]]*max_threads[[:space:]]+", line)
            push!(out, "max_threads $(cfg.threads)")
            set_threads = true
        elseif occursin(r"^[[:space:]]*block_size[[:space:]]+", line)
            push!(out, "block_size $(cfg.block_size)")
            set_block = true
        elseif occursin(r"^[[:space:]]*max_iter[[:space:]]+", line)
            push!(out, "max_iter $(cfg.n_iter)")
            set_iter = true
        else
            push!(out, line)
        end
    end

    !set_files && push!(out, "files $(cfg.dataset_path)")
    !set_outdir && push!(out, "outdir $(cfg.outdir)")
    !set_data_dim && push!(out, "data_dim $(cfg.data_dim)")
    !set_field_dim && push!(out, "field_dim $(cfg.field_dim)")
    !set_pcakeep && push!(out, "pcakeep $(cfg.data_dim)")
    !set_threads && push!(out, "max_threads $(cfg.threads)")
    !set_block && push!(out, "block_size $(cfg.block_size)")
    !set_iter && push!(out, "max_iter $(cfg.n_iter)")

    mkpath(dirname(cfg.param_output))
    mkpath(cfg.outdir)
    open(cfg.param_output, "w") do io
        for line in out
            println(io, line)
        end
    end
end

function run_amica(cfg)
    isfile(cfg.amica_bin) || error("AMICA binary not found: $(cfg.amica_bin)")
    isexecutable(cfg.amica_bin) || error("AMICA binary is not executable: $(cfg.amica_bin)")

    existing = get(ENV, "LD_LIBRARY_PATH", "")
    ld = isempty(existing) ? "$(MPI_LIB):$(ONEAPI_LIB)" : "$(MPI_LIB):$(ONEAPI_LIB):$(existing)"

    cmd = setenv(`$(cfg.amica_bin) $(cfg.param_output)`, "LD_LIBRARY_PATH" => ld)
    println("Generated param file: $(cfg.param_output)")
    println("Running: $(cfg.amica_bin) $(cfg.param_output)")
    run(cmd)
end

function main(args::Vector{String})
    cfg = parse_config(args)
    isfile(cfg.dataset_path) || error("Dataset file not found: $(cfg.dataset_path)")
    println("Dataset: $(cfg.dataset) -> $(cfg.dataset_path) (field_dim=$(cfg.field_dim), data_dim=$(cfg.data_dim))")
    write_param_file(cfg)
    run_amica(cfg)
    return 0
end

exit(main(ARGS))
