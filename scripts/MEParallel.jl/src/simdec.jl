mutable struct SimDecTargets
    accuracy::Real
    regret::Real            # R_best - R_actual
    runtime::Real           # minutes
    bias::Real              # 𝔼[predicted volume - truth]
    variance::Real          # 𝔼[(predicted volume - 𝔼[predicted volume])²]
    mse::Real               # mean squared error = bias² + var
    number_of_drills::Int   # number of bore holes drilled
    discounted_return::Real # discounted return of POMDP
end


mutable struct SimDecHeader
    mainbody_model::String
    planning_iterations::Int
    grid_dims::Int
    targets::SimDecTargets
end


"""
    Distributions for SimDec parameters.
"""
@with_kw mutable struct SimDecParameters
    mainbody_model = [BlobNode, EllipseNode, CircleNode]
    planning_iterations = collect(100:10_000)
    grid_dims = collect(10:50)
end


Base.rand(p::SimDecParameters) = rand(Random.GLOBAL_RNG, p)
function Base.rand(rng::AbstractRNG, p::SimDecParameters)
    mainbody_model = rand(rng, p.mainbody_model)
    planning_iterations = rand(rng, p.planning_iterations)
    grid_dims = rand(rng, p.grid_dims)
    return SimDecParameters(mainbody_model, planning_iterations, grid_dims)
end


function sample_simdec_configurations(p::SimDecParameters, n::Int)
    params = MEJobParameters(name="simdec")
    configs = MEConfiguration[]
    for i in 1:n
        Random.seed!(i)
        simdec_params = rand(p)
        grid_dims = (simdec_params.grid_dims, simdec_params.grid_dims, 1)
        pomcpow_iters = simdec_params.planning_iterations
        mainbody_type = simdec_params.mainbody_model
        config = MEConfiguration(i, grid_dims, pomcpow_iters, mainbody_type, params)
        push!(configs, config)
    end
    return configs::Vector{<:Configuration}
end


function simdec_header()
    param_names = [String.(filter(s->s != :targets, fieldnames(SimDecHeader)))...]
    target_names = [String.(fieldnames(SimDecTargets))...]
    return join(vcat(param_names, target_names), ",")
end


function save_simdec_csv(results::Dict, results_dir; extraction_cost=150)
    runtime_fn(res) = mean(map(t->t.time/60, res[:timing]))
    f(res) = res[:r_massive]
    f̂(res) = f(res) .+ last.(res[:rel_errors])
    bias_fn(res) = mean(mean(f̂(res)) .- f(res))
    variance_fn(res) = mean((f̂(res) .- mean(f̂(res))).^2)
    mse_fn(res) = mean((f(res) - f̂(res)).^2)
    bores_fn(res) = mean(res[:n_drills])
    returns_fn(res) = mean(res[:discounted_return])

    name = basename(results_dir)
    header = simdec_header()
    csv_filename = joinpath(results_dir, "results_simdec_$name.csv")

    open(csv_filename, "w+") do f
        println(f, header)
        for (k,v) in results
            mainbody_model = String(k[1])
            planning_iterations = k[3]
            grid_dims = k[2][1]
            res = results[k]
            accuracy = MixedFidelityModelSelection.accuracy(res; extraction_cost)
            regret = mean(MixedFidelityModelSelection.regret(res; extraction_cost))
            runtime = runtime_fn(res)
            bias = bias_fn(res)
            variance = variance_fn(res)
            mse = mse_fn(res)
            number_of_drills = bores_fn(res)
            discounted_return = returns_fn(res)
            row = join([mainbody_model, planning_iterations, grid_dims, accuracy, regret, runtime, bias, variance, mse, number_of_drills, discounted_return], ",")
            println(f, row)
        end
    end
    return csv_filename
end