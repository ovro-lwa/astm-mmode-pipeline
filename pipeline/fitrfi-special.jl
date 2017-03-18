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

function fitrfi_special_spw04(times, data, flags, target)
end

function fitrfi_special_spw06(times, data, flags, target)
end

function fitrfi_special_spw08(times, data, flags, target)
end

function fitrfi_special_spw10(times, data, flags, target)
end

function fitrfi_special_spw12(times, data, flags, target)
end

function fitrfi_special_spw14(times, data, flags, target)
end

function fitrfi_special_spw16(times, data, flags, target)
end

function fitrfi_special_spw18(times, data, flags, target)
    @fitrfi_preamble 18
    output_sources = Source[]
    output_calibrations = GainCalibration[]
    if target == "rfi-subtracted-calibrated-rainy-visibilities"
        # this component causes peeling to choke on Cas A
        idx = 925
        meta, visibilities = fitrfi_pick_an_integration(spw, times, data, flags, idx)
        getdata_sources = readsources(joinpath(sourcelists, "getdata-sources.json"))
        cyg = filter(source -> source.name == "Cyg A", getdata_sources)[1]
        cyg, I, Q, dir = update(visibilities, meta, cyg)
        cas = filter(source -> source.name == "Cas A", getdata_sources)[1]
        cas, I, Q, dir = update(visibilities, meta, cas)
        @fitrfi_construct_sources 1
        sources = [cyg; sources; cas]
        @fitrfi_peel_sources
        push!(output_sources, sources[2])
        push!(output_calibrations, calibrations[2])
    end
    fitrfi_output(spw, meta, output_sources, output_calibrations, target)
end
