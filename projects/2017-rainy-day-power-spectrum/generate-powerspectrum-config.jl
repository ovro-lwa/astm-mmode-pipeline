#! /usr/bin/env julia-0.6

# There are so many different configurations that I would like to use while estimating the power
# spectrum that manually managing the config files is getting out of hand. All of these files are
# therefore now generated by this script.

const temp = "/dev/shm/mweastwood"
isdir(temp) || mkpath(temp)

function main()
    # "calibrated"   => only initial gain calibration, no source removal
    # "peeled"       => initial calibration with source removal
    # "recalibrated" => recalibrated and interpolated visibilities (with source removal)
    processing = ("calibrated", "peeled", "recalibrated")

    # "all"  => all visibilities are used to estimate the m-modes
    # "odd"  => only odd-numbered visibilities are used to estimate the m-modes
    # "even" => only even-numbered visibilities are used to estimate the m-modes
    sampling   = ("all", "odd", "even")

    # "extreme"  => filter modes with (foregrounds) > 0.1 × (signal)
    # "moderate" => filter modes with (foregrounds) > (signal)
    # "mild"     => filter modes with (foregrounds) > 10 × (signal)
    # "none"     => filter modes with (foregrounds) > ∞ × (signal)
    filtering  = ("extreme", "moderate", "mild", "none")

    # "spherical"   => spherically averaged power spectrum P(k)
    # "cylindrical" => cylindrically averaged power spectrum P(k⟂, k∥)
    # "angular"     => multi-frequency angular power spectrum Cl(ν1, ν2)
    estimator  = ("spherical", "cylindrical", "angular")

    open(joinpath(@__DIR__, "AutoGenerated.mk"), "w") do makefile
        write_header(makefile)
        newline(makefile)
        for process in processing
            for sample in sampling
                create_030_getmmodes_yml(makefile, process, sample)
                create_030_getmmodes_interpolated_yml(makefile, process, sample)
                create_031_tikhonov_yml(makefile, process, sample)
                create_031_tikhonov_channels_yml(makefile, process, sample)
                create_031_tikhonov_interpolated_yml(makefile, process, sample)
                create_031_tikhonov_channels_interpolated_yml(makefile, process, sample)
                create_101_average_channels_yml(makefile, process, sample)
                create_103_full_rank_compress_yml(makefile, process, sample)
                for filter in filtering
                    create_112_foreground_filter_yml(makefile, process, sample, filter)
                    for estimate in estimator
                        if process == "peeled"
                            create_121_fisher_matrix_yml(makefile, sample, filter, estimate)
                        end
                        create_122_quadratic_estimator_yml(makefile, process, sample, filter, estimate)
                    end
                end
            end
            create_032_predict_visibilities_yml(makefile, process)
        end
    end

    N = length(processing) * length(sampling) * length(filtering) * length(estimator)
    println("Generated $N power spectrum configurations.")
end

function replace_if_different(filename)
    # don't overwrite a file if it hasn't changed so that we're not triggering Makefile rules all
    # over the place
    file1 = joinpath(temp, filename)
    file2 = joinpath(@__DIR__, filename)
    if isfile(file2)
        hash1 = Base.crc32c(read(file1))
        hash2 = Base.crc32c(read(file2))
        if hash1 == hash2
            # files are equal, discard changes
            rm(file1)
        else
            # file has changed, accept changes
            info("File $filename has changed")
            mv(file1, file2, remove_destination=true)
        end
    else
        info("File $filename is new")
        mv(file1, file2)
    end
end

const HEADER = "# This file was auto-generated. Do not edit directly!"

function write_header(file)
    println(file, HEADER)
end

function newline(file)
    print(file, '\n')
end

function create_030_getmmodes_yml(makefile, process, sample)
    filename = "030-getmmodes-$process-$sample.yml"
    if process == "recalibrated"
        warn("SPECIAL CASE: recalibrated data is inheriting flags from peeled data")
        process_flags = "peeled"
    else
        process_flags = process
    end

    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 001-$process-transposed-data
                input-flags: 002-$process_flags-data-flags
                output: 030-m-modes-$process-$sample
                metadata: metadata
                hierarchy: hierarchy
                integrations-per-day: 6628
                delete-input: false
                option: $sample
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/030-m-modes-$process-$sample: \\
            \t\t\$(LIB)/030-getmmodes.jl project.yml $filename \\
            \t\t.pipeline/001-$process-transposed-data \\
            \t\t.pipeline/002-flagged-$process_flags-data \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_030_getmmodes_interpolated_yml(makefile, process, sample)
    filename = "030-getmmodes-interpolated-$process-$sample.yml"
    if process == "recalibrated"
        warn("SPECIAL CASE: recalibrated data is inheriting flags from peeled data")
        process_flags = "peeled"
    else
        process_flags = process
    end

    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 001-$process-transposed-data
                input-flags: 002-$process_flags-data-flags
                output: 030-m-modes-interpolated-$process-$sample
                metadata: metadata
                hierarchy: hierarchy
                interpolating-visibilities: 032-predicted-visibilities-$process
                replacement-threshold: 5
                integrations-per-day: 6628
                delete-input: false
                option: $sample
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/030-m-modes-interpolated-$process-$sample: \\
            \t\t\$(LIB)/030-getmmodes.jl project.yml $filename \\
            \t\t.pipeline/001-$process-transposed-data \\
            \t\t.pipeline/002-flagged-$process_flags-data \\
            \t\t.pipeline/032-predicted-visibilities-$process \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_031_tikhonov_yml(makefile, process, sample)
    filename = "031-tikhonov-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 030-m-modes-$process-$sample
                output-alm: 031-dirty-alm-$process-$sample
                output-map: 031-dirty-map-$process-$sample
                metadata: metadata
                transfer-matrix: 100-transfer-matrix
                regularization: 100
                nside: 512
                mfs: true
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/031-dirty-map-$process-$sample: \\
            \t\t\$(LIB)/031-tikhonov.jl project.yml $filename \\
            \t\t.pipeline/030-m-modes-$process-$sample \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_031_tikhonov_channels_yml(makefile, process, sample)
    filename = "031-tikhonov-channels-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 030-m-modes-$process-$sample
                output-alm: 031-dirty-channel-alm-$process-$sample
                output-map: 031-dirty-channel-map-$process-$sample
                output-directory: 031-dirty-channel-maps-$process-$sample
                metadata: metadata
                transfer-matrix: 100-transfer-matrix
                regularization: 100
                nside: 512
                mfs: false
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/031-dirty-channel-maps-$process-$sample: \\
            \t\t\$(LIB)/031-tikhonov.jl project.yml $filename \\
            \t\t.pipeline/030-m-modes-$process-$sample \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_031_tikhonov_interpolated_yml(makefile, process, sample)
    filename = "031-tikhonov-interpolated-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 030-m-modes-interpolated-$process-$sample
                output-alm: 031-dirty-alm-interpolated-$process-$sample
                output-map: 031-dirty-map-interpolated-$process-$sample
                metadata: metadata
                transfer-matrix: 100-transfer-matrix
                regularization: 100
                nside: 512
                mfs: true
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/031-dirty-map-interpolated-$process-$sample: \\
            \t\t\$(LIB)/031-tikhonov.jl project.yml $filename \\
            \t\t.pipeline/030-m-modes-interpolated-$process-$sample \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_031_tikhonov_channels_interpolated_yml(makefile, process, sample)
    filename = "031-tikhonov-channels-interpolated-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 030-m-modes-interpolated-$process-$sample
                output-alm: 031-dirty-channel-alm-interpolated-$process-$sample
                output-map: 031-dirty-channel-map-interpolated-$process-$sample
                output-directory: 031-dirty-channel-maps-interpolated-$process-$sample
                metadata: metadata
                transfer-matrix: 100-transfer-matrix
                regularization: 100
                nside: 512
                mfs: false
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/031-dirty-channel-maps-interpolated-$process-$sample: \\
            \t\t\$(LIB)/031-tikhonov.jl project.yml $filename \\
            \t\t.pipeline/030-m-modes-interpolated-$process-$sample \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_032_predict_visibilities_yml(makefile, process)
    # (we'll only do this with this with the sky maps constructed from all available data)
    filename = "032-predict-visibilities-$process.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 031-dirty-alm-$process-all
                output-alm: 032-predicted-alm-$process
                output-mmodes: 032-predicted-m-modes-$process
                output-visibilities: 032-predicted-visibilities-$process
                metadata: metadata
                hierarchy: hierarchy
                transfer-matrix: 100-transfer-matrix
                spectral-index: -2.3
                integrations-per-day: 6628
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/032-predicted-visibilities-$process: \\
            \t\t\$(LIB)/032-predict-visibilities.jl project.yml $filename \\
            \t\t.pipeline/031-dirty-map-$process-all \\
            \t\t.pipeline/100-transfer-matrix
            \t\$(call launch-remote,1)
            """)
end

function create_101_average_channels_yml(makefile, process, sample)
    filename = "101-average-channels-m-modes-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input: 030-m-modes-interpolated-$process-$sample
                output: 101-averaged-m-modes-$process-$sample
                Navg: 10
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/101-averaged-m-modes-$process-$sample: \\
            \t\t\$(LIB)/101-average-channels.jl project.yml $filename \\
            \t\t.pipeline/030-m-modes-interpolated-$process-$sample
            \t\$(call launch-remote,1)
            """)
end

function create_103_full_rank_compress_yml(makefile, process, sample)
    filename = "103-full-rank-compress-$process-$sample.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input-m-modes: 101-averaged-m-modes-$process-$sample
                input-transfer-matrix: 101-averaged-transfer-matrix
                input-noise-matrix: 102-noise-covariance-matrix-$sample
                output-m-modes: 103-compressed-m-modes-$process-$sample
                output-transfer-matrix: 103-compressed-transfer-matrix-$process-$sample
                output-noise-matrix: 103-compressed-noise-covariance-matrix-$process-$sample
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/103-full-rank-compression-$process-$sample: \\
            \t\t\$(LIB)/103-full-rank-compress.jl project.yml $filename \\
            \t\t.pipeline/101-averaged-m-modes-$process-$sample \\
            \t\t.pipeline/101-averaged-transfer-matrix \\
            \t\t.pipeline/102-noise-covariance-matrix-$sample
            \t\$(call launch-remote,1)
            """)
end

function create_112_foreground_filter_yml(makefile, process, sample, filter)
    filename = "112-foreground-filter-$process-$sample-$filter.yml"
    if filter == "extreme"
        value = 0.1
    elseif filter == "moderate"
        value = 1.0
    elseif filter == "mild"
        value = 10.0
    elseif filter == "none"
        value = Inf
    else
        error("unknown filter")
    end

    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input-m-modes: 103-compressed-m-modes-$process-$sample
                input-transfer-matrix: 103-compressed-transfer-matrix-$process-$sample
                input-noise-matrix: 103-compressed-noise-covariance-matrix-$process-$sample
                input-foreground-matrix: 110-foreground-covariance-matrix
                input-signal-matrix: 111-signal-covariance-matrix
                output-m-modes: 112-filtered-m-modes-$process-$sample-$filter
                output-transfer-matrix: 112-filtered-transfer-matrix-$process-$sample-$filter
                output-covariance-matrix: 112-filtered-covariance-matrix-$process-$sample-$filter
                output-foreground-filter: 112-foreground-filter-$process-$sample-$filter
                output-noise-whitener: 112-noise-whitener-$process-$sample-$filter
                threshold: $value
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/112-foreground-filter-$process-$sample-$filter: \\
            \t\t\$(LIB)/112-foreground-filter.jl project.yml $filename \\
            \t\t.pipeline/103-full-rank-compression-$process-$sample \\
            \t\t.pipeline/110-foreground-covariance-matrix \\
            \t\t.pipeline/111-signal-covariance-matrix
            \t\$(call launch-remote,2)
            """)
end

function create_121_fisher_matrix_yml(makefile, sample, filter, estimate)
    filename = "121-fisher-matrix-$sample-$filter-$estimate.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input-basis: 120-basis-covariance-matrices-$estimate
                input-transfer-matrix: 112-filtered-transfer-matrix-peeled-$sample-$filter
                input-covariance-matrix: 112-filtered-covariance-matrix-peeled-$sample-$filter
                output: 121-fisher-matrix-$sample-$filter-$estimate
                iterations: 1000
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/121-fisher-matrix-$sample-$filter-$estimate: \\
            \t\t\$(LIB)/121-fisher-matrix.jl project.yml $filename \\
            \t\t.pipeline/112-foreground-filter-peeled-$sample-$filter \\
            \t\t.pipeline/120-basis-covariance-matrices-$estimate
            \t\$(call launch-remote,4)
            """)
end

function create_122_quadratic_estimator_yml(makefile, process, sample, filter, estimate)
    filename = "122-quadratic-estimator-$process-$sample-$filter-$estimate.yml"
    open(joinpath(temp, filename), "w") do file
        println(file,
                """$HEADER
                input-basis: 120-basis-covariance-matrices-$estimate
                input-m-modes: 112-filtered-m-modes-$process-$sample-$filter
                input-transfer-matrix: 112-filtered-transfer-matrix-$process-$sample-$filter
                input-covariance-matrix: 112-filtered-covariance-matrix-$process-$sample-$filter
                input-fisher-matrix: 121-fisher-matrix-$sample-$filter-$estimate
                output: 122-quadratic-estimator-$process-$sample-$filter-$estimate
                iterations: 1000
                """)
    end
    replace_if_different(filename)

    println(makefile,
            """.pipeline/122-quadratic-estimator-$process-$sample-$filter-$estimate: \\
            \t\t\$(LIB)/122-quadratic-estimator.jl project.yml $filename \\
            \t\t.pipeline/112-foreground-filter-$process-$sample-$filter \\
            \t\t.pipeline/120-basis-covariance-matrices-$estimate \\
            \t\t.pipeline/121-fisher-matrix-$sample-$filter-$estimate
            \t\$(call launch-remote,4)
            """)
end

main()

