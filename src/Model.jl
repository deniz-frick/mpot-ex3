using JuMP, Gurobi, Graphs, SimpleWeightedGraphs

mutable struct State
    model::Model
    graph::SimpleWeightedGraph
    constraint_added_by_callback::Int
end
State(model::Model, graph::SimpleWeightedGraph) = State(model, graph, 0)

function create_model(graph::SimpleWeightedGraph, formulation)
    env = Gurobi.Env(
        Dict{String,Any}(
            "OutputFlag" => 0,
        ),
    )

    model = Model(() -> Gurobi.Optimizer(env))

    state = State(model, graph)

    # nv = number of vertices
    n = nv(graph)

    # General Constraints
    @variable(model, x[1:n, 1:n], Bin)
    @objective(model, Min, sum(x[i, j] for i in 1:n for j in 1:n if i != j))

    if formulation == "cec"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> cec_callback(cb_data, state))

        # Cycle Elimination Constraints



    elseif formulation == "dcc"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> dcc_callback(cb_data, state))

        # Directed Cutset Constraints


    else
        error("Invalid formulation")
    end

    return state
end


function cec_callback(cb_data::Gurobi.CallbackData, state::State)
    @show typeof(cb_data)
    @show state.graph

    state.constraint_added_by_callback += 1
end

function dcc_callback(cb_data::Gurobi.CallbackData, state::State)
    @show typeof(cb_data)
    @show state.graph

    state.constraint_added_by_callback += 1
end
