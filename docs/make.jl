push!(LOAD_PATH, "../src/")

using Documenter
using Literate
using Fastback

function postprocess_md(md)
    replace(md, "\"data/" => "\"../data/")
end

function postprocess_nb(nb)
    for cell in nb["cells"]
        if cell["cell_type"] == "code"
            for (i, line) in enumerate(cell["source"])
                cell["source"][i] = replace(line, "\"data/" => "\"../data/")
            end
        end
    end
    nb
end

# generate example markdown and notebook files
Literate.markdown("src/examples/1_random_trading.jl", "src/examples/gen/";
    postprocess=postprocess_md, credit=false)
Literate.markdown("src/examples/2_portfolio_trading.jl", "src/examples/gen/";
    postprocess=postprocess_md, credit=false)

Literate.notebook("src/examples/1_random_trading.jl", "src/examples/gen/";
    postprocess=postprocess_nb, credit=false)
Literate.notebook("src/examples/2_portfolio_trading.jl", "src/examples/gen/";
    postprocess=postprocess_nb, credit=false)

makedocs(
    sitename="Fastback.jl",
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", nothing) == "true",
        sidebar_sitename=false,
        assets=["assets/styles.css"]
    ),
    pages=[
        "Home" => "index.md",
        "Examples" => [
            "Basic Setup" => "examples/0_setup.md",
            "1\\. Random Trading" => "examples/gen/1_random_trading.md",
            "2\\. Portfolio Trading" => "examples/gen/2_portfolio_trading.md",
        ]
    ]
)
