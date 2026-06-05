using JuMP, Gurobi, Graphs, SimpleWeightedGraphs, GraphsFlows

mutable struct State
    model::Model
    graph::SimpleWeightedGraph
    constraint_added_by_callback::Int
end
State(model::Model, graph::SimpleWeightedGraph) = State(model, graph, 0)

function create_model(graph::SimpleWeightedGraph, k, formulation; threads::Union{Int,Nothing}=Nothing, mem_limit::Union{Float64,Nothing}=Nothing)
    settings = Dict{String,Any}()

    if !isnothing(threads)
        settings["Threads"] = threads
    end
    if !isnothing(mem_limit)
        settings["SoftMemLimit"] = mem_limit
    end

    env = Gurobi.Env(settings)
    model = Model(() -> Gurobi.Optimizer(env))



    # nv = number of vertices
    n = nv(graph)
    e = ne(graph)

    state = State(model, graph)

    # General Constraints

    # 13f 14e
    @variable(model, x[1:e], Bin)

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

        # 13c in spirit
        #only one incoming
        @constraint(model, [b in 1:n], sum(y[(a, b)] for a in inneighbors(graph, b)) + y[(0, b)] <= 1)
        # need to have an inneighbour to have outneigbours
        @constraint(model, [b in 1:n], (sum(y[(a, b)] for a in inneighbors(graph, b)) + y[(0, b)]) * k >= sum(y[(b, c)] for c in outneighbors(graph, b)))




    elseif formulation == "dcc"
        set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> dcc_callback(cb_data, state))

        # Directed Cutset Constraints
        @variable(model, z[1:n], Bin)
        @constraint(model, sum(z[i] for i in 1:n) == k)
        @constraint(model, [v in 1:n], sum(y[(v, w)] for w in outneighbors(graph, v)) <= (k - 1) * z[v])
        @constraint(model, [v in 1:n], z[v] ≥ y[(0, v)] + sum(y[(u, v)] for u in inneighbors(graph, v)))
        @constraint(model, [v in 1:n], z[v] ≤ y[(0, v)] + sum(y[(u, v)] for u in inneighbors(graph, v)))


        @constraint(model, [j in 1:n], y[(0, j)] + sum(y[(i, j)] for i in inneighbors(graph, j)) ≤ 1)
    else
        error("Invalid formulation")
    end

    return state
end


function cec_callback(cb_data::Gurobi.CallbackData, state::State)
    graph = state.graph
    model = state.model
    status = callback_node_status(cb_data, model)

    y = model[:y]

    y_val = callback_value.(cb_data, y)
    edges = [idx for (idx, val) in zip(axes(y_val)[1], y_val) if val > 0]

    minigraph = SimpleDiGraphFromIterator(Edge.(edges))
    for cycle in simplecycles(minigraph)
        edges = zip(cycle, vcat(cycle[2:end], cycle[1]))

        if status == MOI.CALLBACK_NODE_STATUS_FRACTIONAL
            activation_sum = sum(y_val[edge] for edge in edges)
            if activation_sum <= length(edges) - 1
                #println("Refrained from adding unviolated cut")
                continue
            end
        end

        # would be better to use x instead of y to block the other direction aswell
        con = @build_constraint(
            sum(y[edge] for edge in edges) <= length(edges) - 1
        )
        #println("Adding $(con)")
        MOI.submit(model, MOI.LazyConstraint(cb_data), con)
        state.constraint_added_by_callback += 1
    end
end

function dcc_callback(cb_data::Gurobi.CallbackData, state::State)
    status = callback_node_status(cb_data, state.model)
    if !(status in (MOI.CALLBACK_NODE_STATUS_INTEGER, MOI.CALLBACK_NODE_STATUS_FRACTIONAL))
        return
    end

    graph = state.graph
    model = state.model
    y = model[:y]
    z = model[:z]

    y_val = callback_value.(cb_data, y)
    z_val = callback_value.(cb_data, z)

    eps = 1e-4
    n = nv(graph)
    artificial_root = n + 1

    flow_graph = SimpleDiGraph(n + 1)
    capacity_matrix = zeros(Float64, n + 1, n + 1)

    for j in 1:n
        add_edge!(flow_graph, artificial_root, j)
        capacity_matrix[artificial_root, j] = max(0.0, y_val[(0, j)])
    end

    for edge in edges(graph)
        add_edge!(flow_graph, edge.src, edge.dst)
        add_edge!(flow_graph, edge.dst, edge.src)
        capacity_matrix[edge.src, edge.dst] = max(0.0, y_val[(edge.src, edge.dst)])
        capacity_matrix[edge.dst, edge.src] = max(0.0, y_val[(edge.dst, edge.src)])
    end

    for representative in 1:n
        z_val[representative] > eps || continue

        _, sink_partition, cut_value = GraphsFlows.mincut(
            flow_graph,
            artificial_root,
            representative,
            capacity_matrix,
            GraphsFlows.EdmondsKarpAlgorithm(),
        )
        cut_value >= z_val[representative] - eps && continue

        S = Set(v for v in sink_partition if v <= n)
        isempty(S) && continue

        incoming = [(u, j) for j in S for u in [0; inneighbors(graph, j)] if !(u in S)]
        isempty(incoming) && continue

        lhs_val = sum(y_val[(u, v)] for (u, v) in incoming)
        lhs_val >= z_val[representative] - eps && continue

        con = @build_constraint(sum(y[(u, v)] for (u, v) in incoming) >= z[representative])
        MOI.submit(model, MOI.LazyConstraint(cb_data), con)
        state.constraint_added_by_callback += 1
    end
end
