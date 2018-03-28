module Driver

using BPJSpec
using FileIO, JLD2
using YAML

include("Project.jl")

struct Config
    input_basis :: String
    input_mmodes :: String
    input_transfermatrix :: String
    input_covariancematrix :: String
    input_fishermatrix :: String
    input_noisebias :: String
    output :: String
end

function load(file)
    dict = YAML.load(open(file))
    Config(dict["input-basis"], dict["input-mmodes"], dict["input-transfer-matrix"],
           dict["input-covariance-matrix"], dict["input-fisher-matrix"],
           dict["input-noise-bias"], dict["output"])
end

function go(project_file, config_file)
    project = Project.load(project_file)
    config  = load(config_file)
    quadratic_estimator(project, config)
end

function quadratic_estimator(project, config)
    path  = Project.workspace(project)
    path′ = joinpath(path, config.input_basis)

    mmodes           = BPJSpec.load(joinpath(path, config.input_mmodes))
    transfermatrix   = BPJSpec.load(joinpath(path, config.input_transfermatrix))
    covariancematrix = BPJSpec.load(joinpath(path, config.input_covariancematrix))

    model = FileIO.load(joinpath(path′, "FIDUCIAL.jld2"), "model")
    basis = [BPJSpec.load(joinpath(path′, @sprintf("%03d", idx))) for idx = 1:length(model.power)]

    F = Project.load(project, config.input_fishermatrix, "matrix")
    b = Project.load(project, config.input_noisebias,    "bias")

    println("Computing q")
    @time q = q_estimator(mmodes, transfermatrix, covariancematrix, basis)

    λ = minimum(eigvals(F))
    if λ < 0
        F -= 1.1*λ*I
    end

    println("Computing everything else")
    M⁻¹ = BPJSpec.inverse_mixing_matrix(F, strategy=:uncorrelated)
    W   = BPJSpec.window_functions(F, M⁻¹)
    Σ   = BPJSpec.windowed_covariance(F, M⁻¹)
    σ   = sqrt.(diag(Σ))
    p   = M⁻¹\(q-b)

    save(joinpath(path, config.output*".jld2"),
         "21-cm-signal-model", model,
         "fisher-information", F,
         "inverse-mixing-matrix", M⁻¹,
         "window-functions", W,
         "standard-errors", σ,
         "bias", b,
         "q", q,
         "p", p)
end

end

