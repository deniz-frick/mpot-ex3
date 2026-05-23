import networkx as nx


def read_instance(filename: str) -> nx.Graph:
    with open(filename, "r", encoding="utf-8") as f:
        n_nodes = int(f.readline())
        n_edges = int(f.readline())

        graph = nx.Graph()
        graph.add_nodes_from(range(1, n_nodes + 1))

        for line in f:
            values = [int(i) for i in line.split()]
            if len(values) == 4:
                graph.add_edge(values[1], values[2], id=values[0], cost=values[3])

        return graph
