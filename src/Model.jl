using JuMP, Gurobi, Graphs, SimpleWeightedGraphs

function create_model(graph::SimpleWeightedGraph, formulation)
    env = Gurobi.Env(
        Dict{String,Any}(
            "OutputFlag" => 0,
        ),
    )

    model = Model(() -> Gurobi.Optimizer(env))
    set_attribute(model, MOI.LazyConstraintCallback(), cb_data -> lazy_constraint_callback(cb_data, graph))


    @show graph
    # nv = number of vertices
    n = nv(graph)
    @show n

    # selects traveled edges
    @variable(model, x[1:n, 1:n], Bin)
    @objective(model, Min, sum(x[i, j] for i in 1:n for j in 1:n if i != j))

    return model
end


function lazy_constraint_callback(cb_data::Gurobi.CallbackData, graph::SimpleWeightedGraph)
    @show typeof(cb_data)
    @show graph

end
