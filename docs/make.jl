push!(LOAD_PATH, "../src/")

using Documenter
using Literate
using Fastback

function postprocess_md(md)
    # fix data folder path
    md = replace(md, "\"data/" => "\"../data/")
    md
end

function postprocess_nb(nb)
    for cell in nb["cells"]
        if cell["cell_type"] == "code"
            for (i, line) in enumerate(cell["source"])
                # fix data folder path
                line = replace(line, "\"data/" => "\"../data/")
                cell["source"][i] = line
            end
        end
    end
    nb
end

function gen_markdown(path)
    Literate.markdown(
        path,
        "src/examples/gen/";
        postprocess=postprocess_md,
        credit=false)
end

function gen_notebook(path)
    Literate.notebook(
        path,
        "src/examples/gen/";
        postprocess=postprocess_nb,
        credit=false)
end

# generate markdown files
gen_markdown("src/examples/1_random_trading.jl");
gen_markdown("src/examples/2_portfolio_trading.jl");
gen_markdown("src/examples/3_multi_currency.jl");

# generate notebook files
gen_notebook("src/examples/1_random_trading.jl");
gen_notebook("src/examples/2_portfolio_trading.jl");
gen_notebook("src/examples/3_multi_currency.jl");

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
            "3\\. Multi-Currency Trading" => "examples/gen/3_multi_currency.md",
        ]
    ]
)
