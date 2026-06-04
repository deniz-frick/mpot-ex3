using Graphs, SimpleWeightedGraphs, DataFrames
import CSV

function read_instance(filename::String)
    data = CSV.read(filename, DataFrame, delim=' ', header=[:id, :src, :dst, :weight], skipto=3)
    return SimpleWeightedGraph(data.src, data.dst, data.weight)
end
