# The essential goal of `fitrfi` is to remove as much of the horizon RFI and stationary correlated
# noise as possible in order to facilitate the peeling of bright sources from the data. Without
# removing the RFI, peeling may elect to remove these components instead of Cas A or Cyg A. Now the
# regular `fitrfi` operates by picking out the brightest components in the time smeared
# visibilities. Occasionally this is not enough and there is a component we need to subtract that is
# not picked out by the regular `fitrfi`. Therefore we will use `fitrfi_special` to try and pick out
# these special cases.


function fitrfi_special(spw, target="rfi-subtracted-calibrated-visibilities")
    dir = getdir(spw)
    times, data, flags = load(joinpath(dir, target*".jld"), "times", "data", "flags")
    if spw == 4
        fitrfi_special_spw04(times, data, flags, target)
    elseif spw == 6
        fitrfi_special_spw06(times, data, flags, target)
    elseif spw == 8
        fitrfi_special_spw08(times, data, flags, target)
    elseif spw == 10
        fitrfi_special_spw10(times, data, flags, target)
    elseif spw == 12
        fitrfi_special_spw12(times, data, flags, target)
    elseif spw == 14
        fitrfi_special_spw14(times, data, flags, target)
    elseif spw == 16
        fitrfi_special_spw16(times, data, flags, target)
    elseif spw == 18
        fitrfi_special_spw18(times, data, flags, target)
    end
    nothing
end

macro fitrfi_pick_an_integration(idx)
    quote
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, $idx)
    end |> esc
end

function fitrfi_pick_an_integration(spw, times, data, flags, idx)
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw)
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
        meta, visibilities = fitrfi_sum_over_integrations(spw, times, data, flags, $range)
    end |> esc
end

function fitrfi_sum_over_integrations(spw, times, data, flags, range)
    @show range
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw)
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
                                                                           $range, $sources)
    end |> esc
end

function fitrfi_sum_over_integrations_with_subtraction(spw, times, data, flags, range, sources)
    @show range
    _, Nbase, Ntime = size(data)
    meta = getmeta(spw)
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
            source = fitrfi_special_getdata_source(name, temp, meta)
            subsrc!(temp, meta, ConstantBeam(), source)
        end
        for α = 1:Nbase
            if !flags[α, idx]
                visibilities.data[α, 1] += temp.data[α, 1]
                visibilities.flags[α, 1] = false
            end
        end
    end
    #TTCal.flag_short_baselines!(visibilities, meta, 15.0)
    meta, visibilities
end

function fitrfi_special_getdata_source(name, visibilities, meta)
    getdata_sources = readsources(joinpath(sourcelists, "getdata-sources.json"))
    source = filter(source -> source.name == name, getdata_sources)[1]
    source, I, Q, dir = update(visibilities, meta, source)
    source
end

macro fitrfi_special_start_image()
    quote
        fitrfi_image_visibilities(spw, ms_path, "fitrfi-special-start-"*target, meta, visibilities)
    end |> esc
end

macro fitrfi_special_finish_image()
    quote
        fitrfi_image_visibilities(spw, ms_path, "fitrfi-special-finish-"*target, meta, visibilities)
        fitrfi_image_corrupted_models(spw, ms_path, meta, sources, calibrations,
                                      target, "fitrfi-special")
    end |> esc
end

function fitrfi_special_spw04(times, data, flags, target)
    @fitrfi_preamble 4
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
        # this piece of RFI shows up and dominates over Cyg A
        idx = 6646
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, idx)
        cyg = fitrfi_special_getdata_source("Cyg A", visibilities, meta)
        @fitrfi_construct_sources A3
        sources = [sources; cyg]
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])

        # this piece of RFI is the same as the previous one, but the subtraction doesn't seem to be
        # working very well, so we're going to add another component to try and improve the
        # situation
        idx = 7119
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, idx)
        cyg = fitrfi_special_getdata_source("Cyg A", visibilities, meta)
        @fitrfi_construct_sources A3
        sources = [sources; cyg]
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])
    end
    fitrfi_image_corrupted_models(spw, ms_path, meta, output_sources, output_calibrations, target)
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw06(times, data, flags, target)
    @fitrfi_preamble 6
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
    elseif target == "peeled-rainy-visibilities"
        @fitrfi_sum_over_integrations 1:7756
        @fitrfi_construct_sources 1
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])
    elseif target == "test"
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw08(times, data, flags, target)
    @fitrfi_preamble 8
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
        # this piece of RFI shows up and dominates over Cyg A
        idx = 6652
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, idx)
        getdata_sources = readsources(joinpath(sourcelists, "getdata-sources.json"))
        cyg = filter(source -> source.name == "Cyg A", getdata_sources)[1]
        cyg, I, Q, dir = update(visibilities, meta, cyg)
        @fitrfi_construct_sources A3
        sources = [sources; cyg]
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])

    end
    fitrfi_image_corrupted_models(spw, ms_path, meta, output_sources, output_calibrations, target)
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw10(times, data, flags, target)
    @fitrfi_preamble 10
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw12(times, data, flags, target)
    @fitrfi_preamble 12
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
        @fitrfi_pick_an_integration 6327
        cas = fitrfi_special_getdata_source("Cas A", visibilities, meta)
        vir = fitrfi_special_getdata_source("Vir A", visibilities, meta)
        @fitrfi_construct_sources 1
        sources = [sources; vir; cas]
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])

    elseif target == "peeled-rainy-visibilities"

    elseif target == "test"
        @fitrfi_pick_an_integration 6327
        @fitrfi_special_start_image
        cas = fitrfi_special_getdata_source("Cas A", visibilities, meta)
        vir = fitrfi_special_getdata_source("Vir A", visibilities, meta)
        @fitrfi_construct_sources 2
        sources = [sources[1]; vir; cas]
        @fitrfi_peel_sources
        @fitrfi_special_finish_image
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw14(times, data, flags, target)
    @fitrfi_preamble 14
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw16(times, data, flags, target)
    @fitrfi_preamble 16
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end

function fitrfi_special_spw18(times, data, flags, target)
    @fitrfi_preamble 18
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    meta = getmeta(spw)
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
        # this component causes peeling to choke on Cas A
        @fitrfi_sum_over_integrations_with_subtraction 625:925 "Cyg A" "Cas A"
        @fitrfi_construct_sources 1
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])

        # this component causes peeling to choke on Vir A
        @fitrfi_pick_an_integration 6419
        cyg = fitrfi_special_getdata_source("Cyg A", visibilities, meta)
        vir = fitrfi_special_getdata_source("Vir A", visibilities, meta)
        cas = fitrfi_special_getdata_source("Cas A", visibilities, meta)
        @fitrfi_construct_sources 1
        sources = [cyg; sources; vir; cas]
        @fitrfi_peel_sources
        push!(output_sources, sources[2])
        push!(output_calibrations, calibrations[2])

        @fitrfi_sum_over_integrations_with_subtraction 5876:6250 "Cyg A" "Cas A" "Vir A"
        @fitrfi_construct_sources 1
        @fitrfi_peel_sources
        push!(output_sources, sources[1])
        push!(output_calibrations, calibrations[1])

    elseif target == "peeled-rainy-visibilities"
        #@fitrfi_sum_over_integrations 1:1500
        #@fitrfi_construct_sources 3
        #@fitrfi_peel_sources
        #push!(output_sources, sources[1])
        #push!(output_calibrations, calibrations[1])

        #@fitrfi_sum_over_integrations 4000:5000
        #@fitrfi_construct_sources 3
        #@fitrfi_peel_sources
        #push!(output_sources, sources[1])
        #push!(output_calibrations, calibrations[1])
        for idx = 1:500:4501
            @fitrfi_sum_over_integrations idx:idx+500
            @fitrfi_construct_sources 1
            @fitrfi_peel_sources
            push!(output_sources, sources[1])
            push!(output_calibrations, calibrations[1])
        end

    elseif target == "test"
        # Example
        # =======
        #@fitrfi_pick_an_integration 1
        #@fitrfi_special_start_image
        #cyg = fitrfi_special_getdata_source("Cyg A", visibilities, meta)
        #@fitrfi_construct_sources 1
        #sources = [cyg; sources]
        #@fitrfi_peel_sources
        #@fitrfi_special_finish_image
    end
    if target != "test"
        fitrfi_image_corrupted_models(spw, ms_path, meta, output_sources, output_calibrations,
                                      target, "fitrfi-special")
        fitrfi_output(spw, meta, output_sources, output_calibrations, target)
    end
end

