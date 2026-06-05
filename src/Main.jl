using Colors: default_brettel_neutral
using ArgParse, Graphs, SimpleWeightedGraphs, GraphPlot, Compose, Colors

include("Model.jl")
include("Util.jl")


function run(input=ARGS)
    settings = ArgParseSettings()

    @add_arg_table settings begin
        "--plot"
        help = "Enable plotting the resulting graph"
        action = :store_true
        "--csv", "-c"
        help = "path to a csv file, run data will be saved to"
        arg_type = String
        "--time", "-t"
        help = "time limit in seconds"
        arg_type = Int
        "--mem", "-m"
        help = "memory limit in seconds"
        arg_type = Float64
        "--threads"
        help = "number of threads to use"
        arg_type = Int
        default = 1
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

    instance_file = args["instance"]
    graph = read_instance(instance_file)
    formulation = args["%COMMAND%"]
    k = args["k"]
    state = create_model(graph, k, formulation, threads=args["threads"], mem_limit=args["mem"])
    model = state.model
    start_num_cons = num_constraints(model, count_variable_in_set_constraints=true)

    !isnothing(args["time"]) && set_time_limit_sec(model, args["time"])


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
    obj_val = 0
    try
        obj_val = objective_value(model)
    catch
    end

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
    if !isnothing(args["csv"])
        open(args["csv"], "a"; lock=true) do csv
            file_name = split(split(instance_file, "/")[end], ".")[1]
            print(csv, "$file_name, $k, $num_total, $num_cont, $num_int, $num_bin, $start_num_cons, $runtime, $max_mem, $node_count, $(state.constraint_added_by_callback), $obj_val, $gap\n")
        end
    end

    x_val = value.(model[:x])
    y_val = value.(model[:y])

    n = nv(graph)
    args["plot"] && (nodecolor = [colorant"lightgray" for _ in 1:n])

    translate = Dict{Int,Int}()
    checklist = []
    for (idx, val) in zip(axes(y_val, 1), y_val)
        if val > 0.5
            println(idx, " => ", val)

            if !haskey(translate, idx[1])
                translate[idx[1]] = length(translate) + 1
            end
            if !haskey(translate, idx[2])
                translate[idx[2]] = length(translate) + 1
            end

            push!(checklist, Edge(translate[idx[1]], translate[idx[2]]))
            if args["plot"] && idx[1] * idx[2] > 0
                nodecolor[idx[1]] = nodecolor[idx[2]] = colorant"orange"
            end

        end
    end

    check = SimpleGraphFromIterator(checklist)
    correct = is_tree(check)
    if correct
        println("Solution is a tree")
    else
        println("Solution IS NOT A TREE")
    end

    #println(x_val)

    # Plotting

    if args["plot"]
        nodelabel = collect(1:n)
        edgecolor = map(x -> x > 0 ? colorant"orange" : colorant"lightgray", x_val)
        edgelabelcolor = map(x -> x > 0 ? colorant"red" : colorant"black", x_val)
        edgesize = map(x -> x > 0 ? 1.0 : 0.2, x_val)
        plot = gplot(graph,
            background_color=colorant"white",
            nodelabel=nodelabel,
            nodefillc=nodecolor,
            edgelabel=[e.weight for e in edges(graph)],
            edgelabelc=edgelabelcolor,
            edgelabelsize=edgesize,
            edgestrokec=edgecolor)
        draw(SVG("plots/graph_$(nv(graph))_$(formulation)_$(k).svg", sqrt(nv(graph)) * 5cm, sqrt(nv(graph)) * 5cm), plot)
    end
end

function run(input::String)
    run([String(s) for s in split(input, " ")])
end


function (@main)(ARGS)
    run(ARGS)
    return 0
end
