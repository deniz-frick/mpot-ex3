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

    env = Gurobi.Env()
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
        @constraint(model, [v in 1:n], z[v] ≥ y[(0, v)] + sum(y[(u, v)] for u in inneighbors(graph, v)))


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
    # lazy constraints are of the form
    # ∀ S ⊂ V with 0 ∈ S, ∀ v ∉ S
    # ∑ x_e exiting cut ≥ indegree(v)
    # @constraint(model, sum(y[(i, j)] for (i, j) in cut ≥ sum(y[(u, v)] for u in inneighbors(graph, v))))

    graph = state.graph
    model = state.model
    status = callback_node_status(cb_data, model)

    if status == MOI.CALLBACK_NODE_STATUS_INTEGER || status == MOI.CALLBACK_NODE_STATUS_FRACTIONAL
        # build graph
        y = model[:y]
        z = model[:z]
        y_val = callback_value.(cb_data, y)

        n = nv(graph)
        # for mincut, we 'remap' 0 to n+1
        source = n + 1
        artificial_arc_idxs = [(source, node) for node in 1:n]
        arc_idxs = Iterators.flatten([[(edge.src, edge.dst), (edge.dst, edge.src)] for edge in edges(graph)])
        digra = SimpleDiGraphFromIterator(Edge.(Iterators.flatten([arc_idxs, artificial_arc_idxs])))

        capacity = zeros(Float64, n + 1, n + 1)

        for (u, v) in Iterators.flatten([arc_idxs, artificial_arc_idxs])
            if u == source
                uvar = 0
            else
                uvar = u
            end
            capacity[u, v] = y_val[(uvar, v)]
        end

        epsilon = 1e-5
        capacity_clean = max.(capacity, 0.0)
        capacity_clean[capacity_clean.<epsilon] .= 0.0
        capacity_clean[abs.(capacity_clean .- 1.0).<epsilon] .= 1.0

        for target in 1:n
            part_a, part_b, flow = GraphsFlows.mincut(digra, source, target, capacity_clean, EdmondsKarpAlgorithm())

            if flow < 1
                cut_edges = [(u, v) for (u, v) in Iterators.flatten([arc_idxs, artificial_arc_idxs])
                             if u in part_a && v in part_b]

                if isempty(cut_edges)
                    @error "graph seemingly not connected"
                end

                cut_edges = [(u == source ? 0 : u, v) for (u, v) in cut_edges]

                con = @build_constraint(
                    sum(y[(u, v)] for (u, v) in cut_edges) >= z[target]
                )

                state.constraint_added_by_callback += 1
                MOI.submit(model, MOI.LazyConstraint(cb_data), con)
            end
        end
    end
end
