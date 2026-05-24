using JuMP, Gurobi, Graphs, SimpleWeightedGraphs

mutable struct State
    model::Model
    graph::SimpleWeightedGraph
    constraint_added_by_callback::Int
end
State(model::Model, graph::SimpleWeightedGraph) = State(model, graph, 0)

function create_model(graph::SimpleWeightedGraph, k, formulation)
    env = Gurobi.Env(
        Dict{String,Any}(
            "OutputFlag" => 0,
        ),
    )


    model = Model(() -> Gurobi.Optimizer(env))



    # nv = number of vertices
    n = nv(graph)
    e = ne(graph)

    state = State(model, graph)

    # General Constraints

    # 13f 14e
    @variable(model, x[1:e] ≥ 0)

    # 13g 14f
    artificial_arc_idxs = [(0, node) for node in 1:n]
    arc_idxs = Iterators.flatten([[(edge.src, edge.dst), (edge.dst, edge.src)] for edge in edges(graph)])
    @variable(model, y[Iterators.flatten((arc_idxs, artificial_arc_idxs))], Bin)
    # ensure only one of the artifical ones is chosen
    @constraint(model, sum(y[idx] for idx in artificial_arc_idxs) == 1)

    # 13e 14d
    @constraint(model, [(e, edge) in enumerate(edges(graph))], x[e] == y[(edge.src, edge.dst)] + y[(edge.dst, edge.src)])

    # 13d 14c
    @constraint(model, sum(y[idx] for idx in arc_idxs) == k - 1)

    # 13a 14a
    @objective(model, Min, sum(edge.weight * x[e] for (e, edge) in enumerate(edges(graph))))


    if formulation == "cec"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> cec_callback(cb_data, state))

        # 13c with a twist for kmeans
        @constraint(model, [j in 1:n], sum(y[(i, j)] for i in inneighbors(graph, j)) ≤ 1)




    elseif formulation == "dcc"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> dcc_callback(cb_data, state))

        # Directed Cutset Constraints


    else
        error("Invalid formulation")
    end

    return state
end


function cec_callback(cb_data::Gurobi.CallbackData, state::State)
    graph = state.graph
    model = state.model
    y = model[:y]

    y_val = callback_value.(cb_data, y)
    edges = [idx for (idx, val) in zip(axes(y_val)[1], y_val) if val > 0]
    @show edges
    minigraph = SimpleDiGraphFromIterator(Edge.(edges))
    for cycle in simplecycles(minigraph)
        edges = zip(cycle, vcat(cycle[2:end], cycle[1]))
        # would be better to use x instead of y to block the other direction aswell
        con = @build_constraint(
            sum(y[edge] for edge in edges) <= length(edges) - 1
        )
        println("Adding $(con)")
        MOI.submit(model, MOI.LazyConstraint(cb_data), con)
        state.constraint_added_by_callback += 1
    end
end

function dcc_callback(cb_data::Gurobi.CallbackData, state::State)
    @show typeof(cb_data)
    @show state.graph

    state.constraint_added_by_callback += 1
end
