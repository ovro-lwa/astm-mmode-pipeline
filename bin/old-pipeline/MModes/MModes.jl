module MModes

using JLD
using StaticArrays
using Unitful, UnitfulAstro
using ProgressMeter
using CasaCore.Measures
using LibHealpix
using TTCal
using BPJSpec
using ..Common

include("gettransfermatrix.jl")

#include("folddata.jl")
#include("getmmodes.jl")
#include("getalm.jl")
#include("lcurve.jl")
#include("interpolate.jl")
#include("wiener.jl")
#include("observation-matrix.jl")
#include("makemap.jl")
##include("powerlaw.jl")
#include("glamour-image.jl")

end

