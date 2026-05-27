using ArgParse, Graphs, SimpleWeightedGraphs

include("Model.jl")
include("Util.jl")


function run(input=ARGS)
    settings = ArgParseSettings()

    @add_arg_table settings begin
        "instance"
        help = "Path to the graph instance file"
        required = true
        "k"
        help = "Number of nodes in the minimal spanning tree"
        arg_type = Int
        required = true
        "cec"
        help = "Model k-MST using cycle elimination constraints"
        action = :command
        "dcc"
        help = "Model k-MST using directed cutset constraints"
        action = :command
    end

    args = parse_args(input, settings)

    graph = read_instance(args["instance"])
    formulation = args["%COMMAND%"]
    state = create_model(graph, args["k"], formulation)
    model = state.model
    optimize!(model)

    # println("===== Kruskal MST =====")
    # mst_edges = kruskal_mst(graph)
    # @show mst_edges
    # W = weights(graph)
    # obj_val = sum(W[src(e), dst(e)] for e in mst_edges)
    # @show obj_val
    println("===== k-MST =====")
    # Solver Info:
    all_vars = all_variables(model)
    num_total = num_variables(model)
    num_cont = count(is_binary.(all_vars) .== false .&& is_integer.(all_vars) .== false)
    num_int = count(is_integer.(all_vars))
    num_bin = count(is_binary.(all_vars))
    num_cons = num_constraints(model, count_variable_in_set_constraints=true)
    runtime = solve_time(model)
    max_mem = MOI.get(model, Gurobi.ModelAttribute("MaxMemUsed"))
    node_count = MOI.get(model, MOI.NodeCount())
    gap = relative_gap(model)
    obj_val = objective_value(model)

    # --- Summary Output ---
    println("Model Statistics:")
    println("Variables: $num_total (Continuous: $num_cont, Integer: $num_int, Binary: $num_bin)")
    println("Constraints: $num_cons")
    println("Runtime: $(round(runtime, digits=2))s")
    println("Max Memory: $(max_mem) GB")
    println("B&B Nodes: $node_count")
    println("Lazy Constraints added: $(state.constraint_added_by_callback)")
    println("Gap: $gap")
    println("Objective Value: $obj_val")

    @show termination_status(model)
    @show primal_status(model)

    x_val = value.(model[:x])
    y_val = value.(model[:y])

    for (idx, val) in zip(axes(y_val, 1), y_val)
        if val > 0.5
            println(idx, " => ", val)
        end
    end
    # some plotting or something
end

function run(input::String)
    run([String(s) for s in split(input, " ")])
end


function (@main)(ARGS)
    run(ARGS)

    return 0
end
