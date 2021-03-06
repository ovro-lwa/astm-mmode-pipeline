function fold(spw, dataset, target)
    dir = getdir(spw)
    data, flags = load(joinpath(dir, "$target-$dataset-visibilities.jld"), "data", "flags")
    fold(spw, data, flags, dataset, target)
end

function fold(spw, data, flags, dataset, target)
    output_data, output_flags = _fold(spw, data, flags, dataset, target)
    save(joinpath(getdir(spw), "folded-$target-$dataset-visibilities.jld"),
         "data", output_data, "flags", output_flags, compress=true)
    output_data, output_flags
end

function _fold(spw, data, flags, dataset, target)
    _, Nbase, Ntime = size(data)
    sidereal_day = 6628 # number of integrations in one sidereal day
    normalization = zeros(Int, Nbase, sidereal_day)
    output_data = zeros(Complex128, Nbase, sidereal_day)
    output_flags = trues(Nbase, sidereal_day)
    flags = apply_special_case_flags(spw, flags, dataset)
    for idx = 1:Ntime, α = 1:Nbase
        if !flags[α, idx]
            jdx = mod1(idx, sidereal_day)
            stokesI = 0.5*(data[1, α, idx] + data[2, α, idx])
            normalization[α, jdx] += 1
            output_data[α, jdx] += stokesI
            output_flags[α, jdx] = false
        end
    end
    for jdx = 1:sidereal_day, α = 1:Nbase
        if normalization[α, jdx] != 0
            output_data[α, jdx] /= normalization[α, jdx]
        end
    end
    output_data, output_flags
end

function apply_special_case_flags(spw, flags, dataset)
    myflags = copy(flags)
    if dataset == "100hr"
        if spw == 18
            myflags[:, 3807] = true # Sun
            myflags[:, 3828] = true # Sun
            myflags[:, 8590] = true # Vir A
            myflags[:, 8593] = true # Vir A
        end
    end
    myflags
end

# ODD INTEGRATIONS ONLY

function fold_odd(spw, dataset, target)
    dir = getdir(spw)
    data, flags = load(joinpath(dir, "$target-$dataset-visibilities.jld"), "data", "flags")
    fold_odd(spw, data, flags, dataset, target)
end

function fold_odd(spw, data, flags, dataset, target)
    output_data, output_flags = _fold(spw, data, flags, dataset, target)
    output_data = output_data[:, 1:2:end]
    output_flags = output_flags[:, 1:2:end]
    save(joinpath(getdir(spw), "odd-folded-$target-$dataset-visibilities.jld"),
         "data", output_data, "flags", output_flags, compress=true)
    output_data, output_flags
end

# EVEN INTEGRATIONS ONLY

function fold_even(spw, dataset, target)
    dir = getdir(spw)
    data, flags = load(joinpath(dir, "$target-$dataset-visibilities.jld"), "data", "flags")
    fold_even(spw, data, flags, dataset, target)
end

function fold_even(spw, data, flags, dataset, target)
    output_data, output_flags = _fold(spw, data, flags, dataset, target)
    output_data = output_data[:, 2:2:end]
    output_flags = output_flags[:, 2:2:end]
    save(joinpath(getdir(spw), "even-folded-$target-$dataset-visibilities.jld"),
         "data", output_data, "flags", output_flags, compress=true)
    output_data, output_flags
end

