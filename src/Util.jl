using Graphs, SimpleWeightedGraphs

function read_instance(filename::String)
    open(filename, "r") do f
        n_nodes = parse(Int, readline(f))
        n_edges = parse(Int, readline(f))

        graph = SimpleWeightedGraph(n_nodes)

        for line in eachline(f)
            values = parse.(Int, split(line))
            if length(values) == 4
                # values: [id, u, v, cost]
                add_edge!(graph, values[2], values[3], values[4])
            end
        end

        return graph
    end
end
