# This file simply contains a number of routines that I should think about adding to TTCal that
# make it a little easier to work with source models.

function update_source_list(data, meta, sources)
    N = length(sources)
    I = zeros(N)
    Q = zeros(N)
    directions = Vector{Direction}(N)
    update_source_list_in_place(data, meta, deepcopy(sources), I, Q, directions)
end

function update_source_list_in_place(data, meta, sources, I, Q, directions)
    for (idx, source) in enumerate(sources)
        _source, _I, _Q, _dir = update(data, meta, source)
        sources[idx] = _source
        I[idx] = _I
        Q[idx] = _Q
        directions[idx] = _dir
    end
    sources, I, Q, directions
end

function getflux(data, meta, source)
    spec = getspec(data, meta, source)
    stokes = StokesVector.(spec)
    I = getfield.(stokes, 1)
    mean(I)
end

function update(data, meta, source)
    source = deepcopy(source)
    direction = updatedirection!(data, meta, TTCal.unwrap(source))
    spectrum = updateflux!(data, meta, TTCal.unwrap(source))
    stokes = StokesVector.(spectrum)
    I = getfield.(stokes, 1)
    Q = getfield.(stokes, 2)
    source, mean(I), mean(Q), direction
end

function updateflux!(data::Visibilities, meta, source)
    spec = getspec(data, meta, source)
    updateflux!(spec, meta, source)
    spec
end

function updateflux!(spec::Vector{HermitianJonesMatrix}, meta, source)
    model_spec = [TTCal.get_total_flux(source, ν) for ν in meta.channels]
    model_stokes = StokesVector.(model_spec)
    model_I = getfield.(model_stokes, 1)
    stokes = StokesVector.(spec)
    I = getfield.(stokes, 1)
    Q = getfield.(stokes, 2)
    scale = (model_I \ I)[1]
    if I[1] == 0
        polarization_fraction = 0.0
    else
        polarization_fraction = (I \ Q)[1]
    end
    #polarization_fraction *= -1 # THIS SIGN FLIP IS NECESSARY TO MATCH WSCLEAN
    scaleflux!(source, scale, polarization_fraction)
end

function updateflux!(spec::Vector{HermitianJonesMatrix}, meta, source::RFISource)
    stokes = StokesVector.(spec)
    spectrum = TTCal.RFISpectrum(meta.channels, stokes)
    source.spectrum = spectrum
end

function scaleflux!(source, scale, polarization_fraction)
    I = source.spectrum.stokes.I
    source.spectrum.stokes = StokesVector(I*scale, I*scale*polarization_fraction, 0, 0)
end

function scaleflux!(source::RFISource, scale, polarization_fraction)
    stokes = source.spectrum.stokes
    stokes = [StokesVector(s.I*scale, s.I*polarization_fraction, 0, 0) for s in stokes]
    source.spectrum.stokes = stokes
end

function scaleflux!(source::MultiSource, scale, polarization_fraction)
    for component in source.components
        scaleflux!(component, scale, polarization_fraction)
    end
end

function updatedirection!(data::Visibilities, meta, source) :: Direction
    if source.name == "Sun"
        return Direction(dir"SUN") :: Direction
    else
        direction = fitvis(data, meta, source, tolerance=1e-5) :: Direction
        frame = TTCal.reference_frame(meta)
        changedirection!(source, frame, direction)
        return direction
    end
end

function updatedirection!(data::Visibilities, meta, source::RFISource) :: Direction
    # RFI sources are fixed, so return a sentinal
    Direction(dir"AZEL", 0degrees, 90degrees)
end

changedirection!(source, frame, direction) = source.direction = direction
function changedirection!(source::MultiSource, frame, direction)
    original = measure(frame, TTCal.get_mean_direction(frame, source), dir"J2000")
    Δx = direction.x - original.x
    Δy = direction.y - original.y
    Δz = direction.z - original.z
    for component in source.components
        mydirection = component.direction
        x = mydirection.x + Δx
        y = mydirection.y + Δy
        z = mydirection.z + Δz
        norm = sqrt(x^2 + y^2 + z^2)
        component.direction = Direction(dir"J2000", x/norm, y/norm, z/norm)
    end
end

function is_rising(frame, source)
    direction = _get_source_direction(source)
    azel = measure(frame, direction, dir"AZEL")
    az = longitude(azel) # ∈ (-π/2, π/2)
    az > 0
end

_get_source_direction(source) = source.direction
_get_source_direction(source::MultiSource) = _get_source_direction(source.components[1])

