function benchmark_suite_specs()
    specs = NamedTuple{(:config, :runs),Tuple{String,Int}}[]

    add_spec(config::String, runs::Int) = push!(specs, (config=config, runs=runs))

    # memory benchmarks

    fsd = Dict(
        "small" => 172704,
        "memorize" => 319500,
        "big" => 1260379,
    )

    function add_specs(;
        datasets,
        block_sizes,
        precisions,
        threads,
        n_iters,
        runs,
        implementations=["julia", "fortran"],
        devices=["cpu", "gpu"],
    )
        for dataset in datasets,
            implementation in implementations,
            device in devices,
            raw_block_size in block_sizes,
            precision in precisions,
            thread in threads,
            n_iter in n_iters

            full_size = fsd[dataset]
            block_size = raw_block_size == "full" ? full_size : raw_block_size

            if block_size > full_size
                continue
            end

            if block_size * thread > full_size
                continue
            end

            if (precision == "float32" || device == "gpu") && implementation == "fortran"
                continue
            end

            if thread > 1 && device == "gpu"
                continue
            end

            add_spec("$dataset $implementation $device $block_size $precision $thread $n_iter", runs)
        end
    end

    add_specs(
        datasets=["small", "memorize", "big"],
        block_sizes=[100, 1000, 10000, 100000, 200000, 300000, 600000, "full"],
        precisions=["float32", "float64"],
        threads=[1, 4, 8, 16, 24, 32, 64],
        n_iters=[40],
        runs=6,
    )



    return specs
end
