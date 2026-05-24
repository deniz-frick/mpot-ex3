using JuMP, Gurobi, Graphs, SimpleWeightedGraphs

function create_model(graph::SimpleWeightedGraph, formulation)
    env = Gurobi.Env(
        Dict{String,Any}(
            "OutputFlag" => 0,
        ),
    )

    model = Model(() -> Gurobi.Optimizer(env))

    # nv = number of vertices
    n = nv(graph)

    # General Constraints
    @variable(model, x[1:n, 1:n], Bin)
    @objective(model, Min, sum(x[i, j] for i in 1:n for j in 1:n if i != j))

    if formulation == "cec"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> cec_callback(cb_data, graph))

        # Cycle Elimination Constraints



    elseif formulation == "dcc"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> dcc_callback(cb_data, graph))

        # Directed Cutset Constraints


    else
        error("Invalid formulation")
    end

    return model
end


function cec_callback(cb_data::Gurobi.CallbackData, graph::SimpleWeightedGraph)
    @show typeof(cb_data)
    @show graph
end

function dcc_callback(cb_data::Gurobi.CallbackData, graph::SimpleWeightedGraph)
    @show typeof(cb_data)
    @show graph
end
