# Exercise 3: k-MST

Deniz Frick (52109950)  
Felix Odelga (12025985)

## Run Instructions
This project requires Julia.

### Running from the command prompt
```sh
julia --project src/Main.jl instance-file k formulation-type
```

### Running from Julia code / REPL
Project needs to be activated with `Pkg or `--project` first.
```jl
include("src/Main.jl")
run("instance-file k formulation-type")
```

### Arguments
```
usage: julia --project src/Main.jl [-h] instance k {cec|dcc}

commands:
  cec         Model k-MST using cycle elimination constraints
  dcc         Model k-MST using directed cutset constraints

positional arguments:
  instance    Path to the graph instance file
  k           Number of nodes in the minimal spanning tree (type:
              Int64)

optional arguments:
  -h, --help  show this help message and exit
```
