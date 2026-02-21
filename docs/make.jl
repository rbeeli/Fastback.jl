const DOCS_ROOT = @__DIR__
const PROJECT_ROOT = normpath(joinpath(DOCS_ROOT, ".."))

# GR render offscreen (avoid window popups during docs build)
ENV["GKS_WSTYPE"] = "100"

# Use a wider virtual terminal for @example/@repl output so wide tables
# (DataFrames/PrettyTables) are not horizontally cropped in rendered docs.
ENV["COLUMNS"] = "220"
ENV["LINES"] = "80"

using Pkg
Pkg.activate(DOCS_ROOT)
Pkg.develop(path=PROJECT_ROOT)
Pkg.instantiate()

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

function gen_markdown(path; name=nothing)
    kwargs = (
        postprocess=postprocess_md,
        credit=false,
    )
    if name === nothing
        Literate.markdown(
            joinpath(EXAMPLES_ROOT, path),
            GENERATED_EXAMPLES_ROOT;
            kwargs...)
    else
        Literate.markdown(
            joinpath(EXAMPLES_ROOT, path),
            GENERATED_EXAMPLES_ROOT;
            kwargs...,
            name=name)
    end
end

function gen_notebook(path; name=nothing)
    kwargs = (
        postprocess=postprocess_nb,
        credit=false,
    )
    if name === nothing
        Literate.notebook(
            joinpath(EXAMPLES_ROOT, path),
            GENERATED_EXAMPLES_ROOT;
            kwargs...)
    else
        Literate.notebook(
            joinpath(EXAMPLES_ROOT, path),
            GENERATED_EXAMPLES_ROOT;
            kwargs...,
            name=name)
    end
end

# generate markdown files
gen_markdown("1_random_trading.jl");
gen_markdown("2_portfolio_trading.jl");
gen_markdown("3_multi_currency.jl");
gen_markdown("4_Tables_integration.jl");
gen_markdown("5_NanoDates_integration.jl");
gen_markdown("6_Timestamps64_integration.jl");
gen_markdown("7_USDm_perp_trading.jl");
gen_markdown("8_plots_extension.jl");
gen_markdown("9_VOO_vs_MES_comparison/main.jl"; name="9_VOO_vs_MES_comparison");

# generate notebook files
gen_notebook("1_random_trading.jl");
gen_notebook("2_portfolio_trading.jl");
gen_notebook("3_multi_currency.jl");
gen_notebook("4_Tables_integration.jl");
gen_notebook("5_NanoDates_integration.jl");
gen_notebook("6_Timestamps64_integration.jl");
gen_notebook("7_USDm_perp_trading.jl");
gen_notebook("8_plots_extension.jl");
gen_notebook("9_VOO_vs_MES_comparison/main.jl"; name="9_VOO_vs_MES_comparison");

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
        "Getting started" => "getting_started.md",
        "Basic setup" => "basic_setup.md",
        "Accounting model and event loop" => "concepts.md",
        "Execution and errors" => "execution_errors.md",
        "Pitfalls and gotchas" => "pitfalls.md",
        "How-to" => "how_to.md",
        "Examples" => [
            "Walkthroughs" => [
                "Random trading" => "examples/gen/1_random_trading.md",
                "Portfolio trading" => "examples/gen/2_portfolio_trading.md",
                "Multi-Currency trading" => "examples/gen/3_multi_currency.md",
                "USD-M perpetual trading" => "examples/gen/7_USDm_perp_trading.md",
                "VOO vs MES cost comparison" => "examples/gen/9_VOO_vs_MES_comparison.md",
            ],
            "Integrations" => [
                "Tables.jl" => "examples/gen/4_Tables_integration.md",
                "NanoDates.jl" => "examples/gen/5_NanoDates_integration.md",
                "Timestamps64.jl" => "examples/gen/6_Timestamps64_integration.md",
            ],
            "Plotting" => [
                "Plots extensions" => "examples/gen/8_plots_extension.md",
            ],
        ],
        "Integrations" => "integrations.md",
        "API index" => "api_index.md",
        "Glossary" => "glossary.md",
    ]
)
