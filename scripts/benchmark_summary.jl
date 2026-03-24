#!/usr/bin/env julia

const libnvml = "libnvidia-ml.so.1"
const NVML_SUCCESS = 0
const NVML_ERROR_INSUFFICIENT_SIZE = 7
const NVML_VALUE_NOT_AVAILABLE = typemax(Culonglong)
const SAMPLE_S = 0.1

struct NvmlProcessInfo
    pid::Cuint
    usedGpuMemory::Culonglong
    gpuInstanceId::Cuint
    computeInstanceId::Cuint
end

function nvml_init()
    r = ccall((:nvmlInit_v2, libnvml), Cint, ())
    r == NVML_SUCCESS || error("nvmlInit failed: $r")
end

nvml_shutdown() = ccall((:nvmlShutdown, libnvml), Cint, ())

function nvml_device_count()
    count = Ref{Cuint}()
    r = ccall((:nvmlDeviceGetCount_v2, libnvml), Cint, (Ref{Cuint},), count)
    r == NVML_SUCCESS || error("nvmlDeviceGetCount failed: $r")
    return Int(count[])
end

function nvml_device_handle(index::Integer)
    handle = Ref{Ptr{Cvoid}}()
    r = ccall((:nvmlDeviceGetHandleByIndex_v2, libnvml), Cint, (Cuint, Ref{Ptr{Cvoid}}), Cuint(index), handle)
    r == NVML_SUCCESS || error("nvmlDeviceGetHandleByIndex failed: $r")
    return handle[]
end

function nvml_gpu_mem_for_pid(handle::Ptr{Cvoid}, pid::Integer)
    count = Ref{Cuint}(0)
    r = ccall((:nvmlDeviceGetComputeRunningProcesses_v2, libnvml),
        Cint,
        (Ptr{Cvoid}, Ref{Cuint}, Ptr{NvmlProcessInfo}),
        handle, count, C_NULL)
    if r != NVML_SUCCESS && r != NVML_ERROR_INSUFFICIENT_SIZE
        return 0
    end

    n = Int(count[])
    n > 0 || return 0

    for _ in 1:3
        buf = Vector{NvmlProcessInfo}(undef, n)
        r = ccall((:nvmlDeviceGetComputeRunningProcesses_v2, libnvml),
            Cint,
            (Ptr{Cvoid}, Ref{Cuint}, Ptr{NvmlProcessInfo}),
            handle, count, pointer(buf))
        if r == NVML_SUCCESS
            total = 0
            for i in 1:Int(count[])
                if Int(buf[i].pid) == pid && buf[i].usedGpuMemory != NVML_VALUE_NOT_AVAILABLE
                    total += Int(buf[i].usedGpuMemory)
                end
            end
            return total
        end
        r == NVML_ERROR_INSUFFICIENT_SIZE || return 0
        n = Int(count[])
        n > 0 || return 0
    end

    return 0
end

function read_rss_kib(pid::Integer)
    rss_kib = 0
    open("/proc/$pid/status", "r") do io
        for line in eachline(io)
            if startswith(line, "VmRSS:")
                rss_kib = parse(Int, split(strip(line))[2])
                break
            end
        end
    end
    return rss_kib
end

function read_child_pids(pid::Integer)
    path = "/proc/$pid/task/$pid/children"
    isfile(path) || return Int[]
    raw = try
        strip(read(path, String))
    catch
        return Int[]
    end
    isempty(raw) && return Int[]

    out = Int[]
    for tok in split(raw)
        child = tryparse(Int, tok)
        child === nothing || push!(out, child)
    end
    return out
end

function process_tree_pids(root_pid::Integer)
    seen = Set{Int}()
    stack = Int[root_pid]
    while !isempty(stack)
        pid = pop!(stack)
        pid in seen && continue
        push!(seen, pid)
        for child in read_child_pids(pid)
            child in seen || push!(stack, child)
        end
    end
    return collect(seen)
end

function line_buffered_cmd(cmd::Cmd)
    stdbuf = Sys.which("stdbuf")
    stdbuf === nothing && return cmd
    return `$stdbuf -oL -eL $cmd`
end

function cmd_to_shell_string(cmd::Cmd)
    return join((Base.shell_escape(String(arg)) for arg in cmd.exec), " ")
end

function realtime_output_cmd(cmd::Cmd)
    buffered = line_buffered_cmd(cmd)
    script_cmd = Sys.which("script")
    script_cmd === nothing && return buffered
    return `$script_cmd -qefc $(cmd_to_shell_string(buffered)) /dev/null`
end

function poll_log_output!(
    log_path::String,
    read_offset::Base.RefValue{Int},
    show_output::Bool,
)
    isfile(log_path) || return

    file_size = try
        filesize(log_path)
    catch
        return
    end
    file_size > read_offset[] || return

    chunk = open(log_path, "r") do io
        seek(io, read_offset[])
        read(io, String)
    end
    read_offset[] = file_size
    isempty(chunk) && return

    if show_output
        print(chunk)
        flush(stdout)
    end
end

function benchmark_command(cmd::Cmd; show_output::Bool)
    log_path, log_io = mktemp()
    read_offset = Ref(0)

    t0 = time()
    proc = run(pipeline(ignorestatus(realtime_output_cmd(cmd)); stdout=log_io, stderr=log_io); wait=false)
    close(log_io)
    pid = Int(getpid(proc))

    nvml_ok = true
    devs = Ptr{Cvoid}[]
    try
        nvml_init()
        for i in 0:nvml_device_count()-1
            push!(devs, nvml_device_handle(i))
        end
    catch err
        nvml_ok = false
        @warn "NVML unavailable, GPU sampling disabled" exception = err
    end

    max_gpu_mib = 0
    max_rss_mib = 0

    while true
        poll_log_output!(log_path, read_offset, show_output)

        tracked_pids = process_tree_pids(pid)

        rss_kib = 0
        for tracked_pid in tracked_pids
            rss_kib += try
                read_rss_kib(tracked_pid)
            catch
                0
            end
        end
        max_rss_mib = max(max_rss_mib, rss_kib ÷ 1024)

        if nvml_ok
            total_bytes = 0
            for tracked_pid in tracked_pids
                for d in devs
                    total_bytes += nvml_gpu_mem_for_pid(d, tracked_pid)
                end
            end
            max_gpu_mib = max(max_gpu_mib, total_bytes ÷ (1024 * 1024))
        end

        !process_running(proc) && break
        sleep(SAMPLE_S)
    end

    wait(proc)
    poll_log_output!(log_path, read_offset, show_output)

    t_done = time()
    runtime = t_done - t0
    exit_code = proc.exitcode

    if nvml_ok
        nvml_shutdown()
    end
    rm(log_path; force=true)

    println("\n========== Benchmark Summary ==========")
    println("Command: " * join(cmd.exec, " "))
    println("Root PID: $pid")
    println("Exit code: $exit_code")
    println("Runtime: $(round(runtime; digits=3)) s")
    println("Max CPU RSS: $max_rss_mib MiB")
    println("Max GPU memory: $max_gpu_mib MiB")
    println("=======================================")

    return exit_code
end

function main(args::Vector{String})
    isempty(args) && error("Missing command to benchmark")
    cmd = Cmd(args)
    return benchmark_command(cmd; show_output=true)
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
