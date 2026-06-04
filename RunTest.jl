instances = [
        ("instances/g01.dat",   10)
        ("instances/g02.dat",   20)
        ("instances/g03.dat",   50)
        ("instances/g04.dat",   70)
        ("instances/g05.dat",  100)
        ("instances/g06.dat",  200)
        ("instances/g07.dat",  300)
        ("instances/g08.dat",  400)
        ("instances/g09.dat", 1000)
        ("instances/g10.dat", 2000)
    ]

denominators = [5,2]
formulations = ["cec", "dcc"]
formulations = ["cec"]

time_limit = 60 * 60 * 2  # 2 hours
mem_limit = 8.0           # 8 gb
threads = 1

include("src/Main.jl")

function (@main)(ARGS)
    println("=================== Warmup ===================")
    for (denominator, (instance, k), formulation) in Iterators.product(
        denominators, instances[1:2], formulations
    )
        @show (formulation, (instance, k), denominator)
        command = (
            "--time $time_limit " *
            "--mem $mem_limit " *
            "--threads $threads " *
            "$instance $(Int(ceil(k/denominator))) $formulation"
        )
        @show command
        run(command)
    end

    println("=================== Test Runs ===================")
    for (denominator, (instance, k), formulation) in Iterators.product(
        denominators, instances, formulations
    )
        @show (formulation, (instance, k), denominator)
        command = (
            "--csv results/$formulation.csv " *
            "--time $time_limit " *
            "--mem $mem_limit " *
            "--threads $threads " *
            "$instance $(Int(ceil(k/denominator))) $formulation"
        )
        @show command
        run(command)
    end
end
