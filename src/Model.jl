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
    e = ne(graph)

    # General Constraints

    # 13f 14e
    @variable(model, x[1:e] ≥ 0)
    # 13g 14f
    arc_idxs = Iterators.flatten([[(edge.src, edge.dst), (edge.dst, edge.src)] for edge in edges(graph)])
    @variable(model, y[arc_idxs], Bin)
    # 13e 14d
    @constraint(model, [(e, edge) in enumerate(edges(graph))], x[e] == y[(edge.src, edge.dst)] + y[(edge.dst, edge.src)])

    # 13d 14c
    @constraint(model, sum(y[idx] for idx in arc_idxs) == n - 1)

    # 13a 14a
    @objective(model, Min, sum(edge.weight * x[e] for (e, edge) in enumerate(edges(graph))))


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
