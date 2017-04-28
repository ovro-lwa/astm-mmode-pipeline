function fitrfi(spw, dataset, target)
    dir = getdir(spw)
    times, data, flags = load(joinpath(dir, "$target-$dataset-visibilities.jld"),
                              "times", "data", "flags")
    if spw == 4
        fitrfi_spw04(times, data, flags, dataset, target)
    elseif spw == 6
        fitrfi_spw06(times, data, flags, dataset, target)
    elseif spw == 8
        fitrfi_spw08(times, data, flags, dataset, target)
    elseif spw == 10
        fitrfi_spw10(times, data, flags, dataset, target)
    elseif spw == 12
        fitrfi_spw12(times, data, flags, dataset, target)
    elseif spw == 14
        fitrfi_spw14(times, data, flags, dataset, target)
    elseif spw == 16
        fitrfi_spw16(times, data, flags, dataset, target)
    elseif spw == 18
        fitrfi_spw18(times, data, flags, dataset, target)
    end
    nothing
end

macro fitrfi_preamble(spw)
    output = quote
        spw = $spw
        dadas = listdadas(spw, dataset)
        ms, ms_path = dada2ms(dadas[1], dataset)
        finalize(ms)

        output_sources = Source[]
        output_calibrations = GainCalibration[]
    end
    esc(output)
end

macro fitrfi_pick_an_integration(idx)
    quote
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, dataset, $idx)
    end |> esc
end

function fitrfi_pick_an_integration(spw, times, data, flags, dataset, idx)
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw, dataset)
    meta.channels = meta.channels[55:55]
    meta.time = Epoch(epoch"UTC", times[idx]*seconds)
    meta.phase_center = Direction(dir"AZEL", 0degrees, 90degrees)
    beam = ConstantBeam()
    visibilities = Visibilities(Nbase, 1)
    visibilities.flags[:] = true
    for α = 1:Nbase
        xx = data[1, α, idx]
        yy = data[2, α, idx]
        visibilities.data[α, 1] = JonesMatrix(xx, 0, 0, yy)
        visibilities.flags[α, 1] = flags[α, idx]
    end
    TTCal.flag_short_baselines!(visibilities, meta, 15.0)
    meta, visibilities
end

macro fitrfi_sum_over_integrations(range)
    quote
        meta, visibilities = fitrfi_sum_over_integrations(spw, times, data, flags, dataset, $range)
    end |> esc
end

function fitrfi_sum_over_integrations(spw, times, data, flags, dataset, range)
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw, dataset)
    meta.channels = meta.channels[55:55]
    meta.time = Epoch(epoch"UTC", times[range[1]]*seconds)
    meta.phase_center = Direction(dir"AZEL", 0degrees, 90degrees)
    beam = ConstantBeam()
    visibilities = Visibilities(Nbase, 1)
    visibilities.flags[:] = true
    for idx in range, α = 1:Nbase
        if !flags[α, idx]
            xx = data[1, α, idx]
            yy = data[2, α, idx]
            visibilities.data[α, 1] += JonesMatrix(xx, 0, 0, yy)
            visibilities.flags[α, 1] = false
        end
    end
    TTCal.flag_short_baselines!(visibilities, meta, 15.0)
    meta, visibilities
end

macro fitrfi_sum_over_integrations_with_subtraction(range, sources...)
    quote
        meta, visibilities = fitrfi_sum_over_integrations_with_subtraction(spw, times, data, flags,
                                                                           dataset, $range, $sources)
    end |> esc
end

function fitrfi_sum_over_integrations_with_subtraction(spw, times, data, flags, dataset, range, sources)
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw, dataset)
    meta.channels = meta.channels[55:55]
    meta.phase_center = Direction(dir"AZEL", 0degrees, 90degrees)
    beam = ConstantBeam()
    visibilities = Visibilities(Nbase, 1)
    visibilities.flags[:] = true
    for idx in range
        all(flags[:, idx]) && continue
        meta.time = Epoch(epoch"UTC", times[idx]*seconds)
        temp = Visibilities(Nbase, 1)
        temp.flags[:] = true
        for α = 1:Nbase
            xx = data[1, α, idx]
            yy = data[2, α, idx]
            temp.data[α, 1] = JonesMatrix(xx, 0, 0, yy)
            temp.flags[α, 1] = flags[α, idx]
        end
        for name in sources
            source = fitrfi_getdata_source(name, temp, meta)
            subsrc!(temp, meta, ConstantBeam(), source)
        end
        for α = 1:Nbase
            if !flags[α, idx]
                visibilities.data[α, 1] += temp.data[α, 1]
                visibilities.flags[α, 1] = false
            end
        end
    end
    TTCal.flag_short_baselines!(visibilities, meta, 15.0)
    meta, visibilities
end

function fitrfi_getdata_source(name, visibilities, meta)
    getdata_sources = readsources(joinpath(dirname(@__FILE__), "..", "..", "workspace", "source-lists",
                                           "getdata-sources.json"))
    source = filter(source -> source.name == name, getdata_sources)[1]
    source, I, Q, dir = update(visibilities, meta, source)
    source
end

macro fitrfi_test_start_image()
    quote
        fitrfi_image_visibilities(spw, ms_path, "fitrfi-test-start-$target-$dataset", meta, visibilities)
    end |> esc
end

macro fitrfi_test_finish_image()
    quote
        fitrfi_image_visibilities(spw, ms_path, "fitrfi-test-finish-$target-$dataset", meta, visibilities)
        fitrfi_image_corrupted_models(spw, ms_path, meta, sources, calibrations,
                                      "fitrfi-test-component-$target-$dataset")
    end |> esc
end

const fitrfi_source_dictionary = Dict(
    :A => (37.145402389570144, -118.3147833410907,  1226.7091391887516), # Big Pine
    :B => (37.3078474772316,   -118.3852914162684,  1214.248326037079),  # Bishop
    :C => (37.24861167954518,  -118.36229648059934, 1232.6294581335637), # Keough's Hot Springs
    :D => (37.06249388547446,  -118.23417138204732, 1608.21583019197),
    # the following locations were eye-balled by Marin
    :A2 => (37.143397, -118.322727, 1226.709), # another Big Pine source
    :B2 => (37.323000, -118.401953, 1214.248326037079), # the northern most source in the triplet
    :B3 => (37.320125, -118.377464, 1214.248326037079), # the middle source in the triplet
    # fit for with the position fitting routine
    :A3 => (37.17025133416173,  -118.32196666958995, 1895.923202819064),
    :B4 => (37.712871601687155, -118.92190463586564, 1647.8143169306663),
    :E => (37.27751649756355, -118.37534090029699, 726.6254751399765)
)

function fitrfi_known_source(visibilities, meta, lat, lon, el)
    position = Position(pos"WGS84", el*meters, lon*degrees, lat*degrees)
    spectrum = RFISpectrum(meta.channels, ones(StokesVector, 1))
    rfi = RFISource("RFI", position, spectrum)
    stokes = StokesVector(getspec(visibilities, meta, rfi)[1])
    spectrum = RFISpectrum(meta.channels, [stokes])
    RFISource("RFI", position, spectrum)
end

function fitrfi_unknown_source()
    direction = Direction(dir"AZEL", 0degrees, 90degrees)
    spectrum = PowerLaw(0.1, 0, 0, 0, 1e6, [0.0])
    PointSource("RFI", direction, spectrum)
end

macro fitrfi_construct_sources(args...)
    output = quote
        sources = TTCal.Source[]
    end
    for arg in args
        if haskey(fitrfi_source_dictionary, arg)
            lat, lon, el = fitrfi_source_dictionary[arg]
            expr = :(push!(sources, fitrfi_known_source(visibilities, meta, $lat, $lon, $el)))
            push!(output.args, expr)
        elseif isa(arg, String)
            expr = :(push!(sources, fitrfi_getdata_source($arg, visibilities, meta)))
            push!(output.args, expr)
        elseif isa(arg, Integer)
            unknown_sources = fill(fitrfi_unknown_source(), arg)
            expr = :(sources = [sources; $unknown_sources])
            push!(output.args, expr)
        end
    end
    esc(output)
end

macro fitrfi_peel_sources()
    output = quote
        calibrations = fitrfi_peel(meta, visibilities, sources)
    end
    esc(output)
end

function fitrfi_peel(meta, visibilities, sources)
    for source in sources
        println(source)
    end
    beam = ConstantBeam()
    peel!(visibilities, meta, beam, sources, peeliter=10, maxiter=200, tolerance=1e-5)
end

macro fitrfi_select_components(range)
    output = quote
        for idx in $range
            push!(output_sources, sources[idx])
            push!(output_calibrations, calibrations[idx])
        end
    end
    esc(output)
end

macro rm_rfi_so_far()
    output = quote
        rm_rfi(meta, visibilities, output_sources, output_calibrations)
    end
    esc(output)
end

macro fitrfi_finish()
    output = quote
        fitrfi_image_corrupted_models(spw, ms_path, meta, output_sources, output_calibrations,
                                      "fitrfi-$target-$dataset")
        xx, yy = fitrfi_output(spw, meta, sources, calibrations, "fitrfi-$target-$dataset")
    end
    esc(output)
end

function fitrfi_output(spw, meta, sources, calibrations, filename)
    N = length(sources)
    xx = zeros(Complex128, Nbase(meta), N)
    yy = zeros(Complex128, Nbase(meta), N)
    beam = ConstantBeam()
    for idx = 1:N
        model = genvis(meta, beam, sources[idx])
        corrupt!(model, meta, calibrations[idx])
        for α = 1:Nbase(meta)
            xx[α, idx] = model.data[α, 1].xx
            yy[α, idx] = model.data[α, 1].yy
        end
    end
    dir = getdir(spw)
    save(joinpath(dir, "$filename.jld"), "xx", xx, "yy", yy)
    xx, yy
end

function fitrfi_image_visibilities(spw, ms_path, image_name, meta, visibilities)
    beam = ConstantBeam()
    dir = getdir(spw)
    output_visibilities = Visibilities(Nbase(meta), 109)
    output_visibilities.flags[:] = true
    output_visibilities.flags[:, 55] = visibilities.flags[:, 1]
    output_visibilities.data[:, 55] = visibilities.data[:, 1]
    ms = Table(ms_path)
    TTCal.write(ms, "DATA", output_visibilities)
    finalize(ms)
    wsclean(ms_path, joinpath(dir, "tmp", image_name), j=8)
end

function fitrfi_image_corrupted_models(spw, ms_path, meta, sources, calibrations, image_name)
    beam = ConstantBeam()
    dir = getdir(spw)
    output_visibilities = Visibilities(Nbase(meta), 109)
    output_visibilities.flags[:] = true
    output_visibilities.flags[:, 55] = false
    for idx = 1:length(sources)
        model = genvis(meta, beam, sources[idx])
        corrupt!(model, meta, calibrations[idx])
        output_visibilities.data[:, 55] = model.data[:, 1]
        ms = Table(ms_path)
        TTCal.write(ms, "DATA", output_visibilities)
        finalize(ms)
        wsclean(ms_path, joinpath(dir, "tmp", image_name*"-$idx"), j=8)
    end
end

#function fitrfi_spw04(data, flags, target)
#    @fitrfi_start 4
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources B
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 0
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw06(data, flags, target)
#    @fitrfi_start 6
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources B A
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 0
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw08(data, flags, target)
#    @fitrfi_start 8
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources A B
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 1
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw10(data, flags, target)
#    @fitrfi_start 10
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources B 1 A 1 C
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 2
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw12(data, flags, target)
#    @fitrfi_start 12
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources 2 B
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 3
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw14(data, flags, target)
#    @fitrfi_start 14
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources A C 2 B
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 2 E
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end
#
#function fitrfi_spw16(data, flags, target)
#    @fitrfi_start 16
#    if target == "calibrated-100hr-visibilities"
#        @fitrfi_construct_sources 1 A 1 B
#    elseif target == "calibrated-rainy-visibilities"
#        @fitrfi_construct_sources 2
#    else
#        Lumberjack.error("unknown target")
#    end
#    @fitrfi_peel_sources
#    @fitrfi_finish
#end

function fitrfi_spw18(times, data, flags, dataset, target)
    @fitrfi_preamble 18
    if dataset == "100hr"
        if target == "calibrated"
            #@fitrfi_construct_sources C A B 2
        elseif target == "peeled"
        else
            error("unknown target")
        end
    elseif dataset == "rainy"
        if target == "calibrated"
            @fitrfi_sum_over_integrations 1:7756
            @fitrfi_construct_sources 3
            @fitrfi_peel_sources
            @fitrfi_select_components 1:3

            # this component causes peeling to choke on Cas A
            @fitrfi_sum_over_integrations_with_subtraction 745:785 "Cyg A" "Cas A"
            @rm_rfi_so_far
            @fitrfi_construct_sources 1
            @fitrfi_peel_sources
            @fitrfi_select_components 1

            # this component causes peeling to choke on Vir A
            @fitrfi_pick_an_integration 6419
            @rm_rfi_so_far
            @fitrfi_construct_sources "Cyg A" 1 "Vir A" "Cas A"
            @fitrfi_peel_sources
            @fitrfi_select_components 2
        elseif target == "peeled"
        else
            error("unknown target")
        end
    else
        error("unknown dataset")
    end
    @fitrfi_finish
end

"""
    fitrfi_get_new_coordinates(spw, data, flags, lat, lon, el)

Fit for the coordinates of a new RFI source in the given data.
"""
function fitrfi_get_new_coordinates(spw, data, flags, lat, lon, el)
    meta, visibilities = fitrfi_sum_the_visibilities(spw, data, flags)

    opt = Opt(:LN_SBPLX, 3)
    max_objective!(opt, (x, g)->fitrfi_objective_function(visibilities, meta, x[1], x[2], x[3]))
    lower_bounds!(opt, [lat-1, lon-1, 0])
    upper_bounds!(opt, [lat+1, lon+1, 3000])
    xtol_rel!(opt, 1e-15)
    ftol_rel!(opt, 1e-10)
    minf, x, ret = optimize(opt, [lat, lon, el])

    lat = x[1]
    lon = x[2]
    el = x[3]
    @show minf lat lon el ret
end

function fitrfi_objective_function(visibilities, meta, lat, lon, el)
    position = Position(pos"WGS84", el*meters, lon*degrees, lat*degrees)
    spectrum = RFISpectrum(meta.channels, [one(StokesVector)])
    rfi = RFISource("RFI", position, spectrum)
    flux = StokesVector(getspec(visibilities, meta, rfi)[1]).I
    flux
end

