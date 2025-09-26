const DOCS_ROOT = @__DIR__
const PROJECT_ROOT = normpath(joinpath(DOCS_ROOT, ".."))

push!(LOAD_PATH, joinpath(PROJECT_ROOT, "src"))

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

const EXAMPLES_ROOT = joinpath(DOCS_ROOT, "src", "examples")
const GENERATED_EXAMPLES_ROOT = joinpath(EXAMPLES_ROOT, "gen")

if isdir(GENERATED_EXAMPLES_ROOT)
    rm(GENERATED_EXAMPLES_ROOT; recursive=true)
end

mkpath(GENERATED_EXAMPLES_ROOT)

function gen_markdown(path)
    Literate.markdown(
        joinpath(EXAMPLES_ROOT, path),
        GENERATED_EXAMPLES_ROOT;
        postprocess=postprocess_md,
        credit=false)
end

function gen_notebook(path)
    Literate.notebook(
        joinpath(EXAMPLES_ROOT, path),
        GENERATED_EXAMPLES_ROOT;
        postprocess=postprocess_nb,
        credit=false)
end

# generate markdown files
gen_markdown("1_random_trading.jl");
gen_markdown("2_portfolio_trading.jl");
gen_markdown("3_multi_currency.jl");
gen_markdown("4_metadata.jl");
gen_markdown("5_Tables_integration.jl");
gen_markdown("6_NanoDates_integration.jl");
gen_markdown("7_Timestamps64_integration.jl");

# generate notebook files
gen_notebook("1_random_trading.jl");
gen_notebook("2_portfolio_trading.jl");
gen_notebook("3_multi_currency.jl");
gen_notebook("4_metadata.jl");
gen_notebook("5_Tables_integration.jl");
gen_notebook("6_NanoDates_integration.jl");
gen_notebook("7_Timestamps64_integration.jl");

makedocs(
    sitename="Fastback.jl",
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", nothing) == "true",
        sidebar_sitename=false,
        assets=["assets/styles.css"],
        edit_link="main"
    ),
    pages=[
        "Home" => "index.md",
        "Basic setup" => "basic_setup.md",
        "Examples" => [
            "1\\. Random trading" => "examples/gen/1_random_trading.md",
            "2\\. Portfolio trading" => "examples/gen/2_portfolio_trading.md",
            "3\\. Multi-Currency trading" => "examples/gen/3_multi_currency.md",
            "4\\. Attach metadata" => "examples/gen/4_metadata.md",
            "5\\. Tables.jl integration" => "examples/gen/5_Tables_integration.md",
            "6\\. NanoDates.jl integration" => "examples/gen/6_NanoDates_integration.md",
            "7\\. Timestamps64.jl integration" => "examples/gen/7_Timestamps64_integration.md",
        ],
        "Integrations" => "integrations.md",
        "Glossary" => "glossary.md",
    ]
)
