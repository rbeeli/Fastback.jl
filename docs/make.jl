const DOCS_ROOT = @__DIR__
const PROJECT_ROOT = normpath(joinpath(DOCS_ROOT, ".."))

# GR render offscreen (avoid window popups during docs build)
ENV["GKS_WSTYPE"] = "100"

# Use a wider virtual terminal for @example/@repl output so wide tables
# (DataFrames/PrettyTables) are not horizontally cropped in rendered docs.
ENV["COLUMNS"] = "160"
ENV["LINES"] = "80"

using Pkg
Pkg.activate(DOCS_ROOT)
Pkg.develop(path=PROJECT_ROOT)
Pkg.instantiate()

using Documenter
using Literate
using Fastback

function postprocess_md(md, data_dir, notebook_name)
    # fix data folder path
    md = replace(md, "\"data/" => "\"$(data_dir)")

    # add a direct link to the generated notebook near the top of the page
    notebook_link = "**Jupyter Notebook:** [`$(notebook_name).ipynb`]($(notebook_name).ipynb)\n\n"
    if startswith(md, "```@meta\n")
        new_md = replace(md, "```\n\n" => "```\n\n$(notebook_link)", count=1)
        md = new_md == md ? notebook_link * md : new_md
    else
        md = notebook_link * md
    end

    md
end

function postprocess_nb(nb, data_dir)
    for cell in nb["cells"]
        if cell["cell_type"] == "code"
            for (i, line) in enumerate(cell["source"])
                # fix data folder path
                line = replace(line, "\"data/" => "\"$(data_dir)")
                cell["source"][i] = line
            end
        end
    end
    nb
end

const EXAMPLES_ROOT = joinpath(DOCS_ROOT, "src", "examples")
const INTEGRATIONS_ROOT = joinpath(DOCS_ROOT, "src", "integrations")
const PLOTTING_ROOT = joinpath(DOCS_ROOT, "src", "plotting")
const GENERATED_EXAMPLES_ROOT = joinpath(EXAMPLES_ROOT, "gen")
const GENERATED_INTEGRATIONS_ROOT = joinpath(INTEGRATIONS_ROOT, "gen")
const GENERATED_PLOTTING_ROOT = joinpath(PLOTTING_ROOT, "gen")

if isdir(GENERATED_EXAMPLES_ROOT)
    rm(GENERATED_EXAMPLES_ROOT; recursive=true)
end

mkpath(GENERATED_EXAMPLES_ROOT)

if isdir(GENERATED_INTEGRATIONS_ROOT)
    rm(GENERATED_INTEGRATIONS_ROOT; recursive=true)
end

mkpath(GENERATED_INTEGRATIONS_ROOT)

if isdir(GENERATED_PLOTTING_ROOT)
    rm(GENERATED_PLOTTING_ROOT; recursive=true)
end

mkpath(GENERATED_PLOTTING_ROOT)

function gen_markdown(path;
        name=nothing,
        source_root::String=EXAMPLES_ROOT,
        generated_root::String=GENERATED_EXAMPLES_ROOT,
        data_dir::String="../data/")
    notebook_name = name === nothing ? splitext(basename(path))[1] : name
    kwargs = (
        postprocess=(md -> postprocess_md(md, data_dir, notebook_name)),
        credit=false,
    )
    if name === nothing
        Literate.markdown(
            joinpath(source_root, path),
            generated_root;
            kwargs...)
    else
        Literate.markdown(
            joinpath(source_root, path),
            generated_root;
            kwargs...,
            name=name)
    end
end

function gen_notebook(path;
        name=nothing,
        source_root::String=EXAMPLES_ROOT,
        generated_root::String=GENERATED_EXAMPLES_ROOT,
        data_dir::String="../data/")
    kwargs = (
        postprocess=(nb -> postprocess_nb(nb, data_dir)),
        credit=false,
    )
    if name === nothing
        Literate.notebook(
            joinpath(source_root, path),
            generated_root;
            kwargs...)
    else
        Literate.notebook(
            joinpath(source_root, path),
            generated_root;
            kwargs...,
            name=name)
    end
end

# generate markdown files
gen_markdown("1_random_trading.jl");
gen_markdown("2_portfolio_trading.jl");
gen_markdown("3_multi_currency.jl");
gen_markdown("4_USDm_perp_trading.jl");
gen_markdown("5_VOO_vs_MES_comparison/main.jl"; name="5_VOO_vs_MES_comparison");
gen_markdown(
    "1_Tables_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_markdown(
    "2_NanoDates_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_markdown(
    "3_Timestamps64_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_markdown(
    "1_plots_extension.jl";
    source_root=PLOTTING_ROOT,
    generated_root=GENERATED_PLOTTING_ROOT);

# generate notebook files
gen_notebook("1_random_trading.jl");
gen_notebook("2_portfolio_trading.jl");
gen_notebook("3_multi_currency.jl");
gen_notebook("4_USDm_perp_trading.jl");
gen_notebook("5_VOO_vs_MES_comparison/main.jl"; name="5_VOO_vs_MES_comparison");
gen_notebook(
    "1_Tables_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_notebook(
    "2_NanoDates_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_notebook(
    "3_Timestamps64_integration.jl";
    source_root=INTEGRATIONS_ROOT,
    generated_root=GENERATED_INTEGRATIONS_ROOT);
gen_notebook(
    "1_plots_extension.jl";
    source_root=PLOTTING_ROOT,
    generated_root=GENERATED_PLOTTING_ROOT);

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
            "Random trading" => "examples/gen/1_random_trading.md",
            "Portfolio trading" => "examples/gen/2_portfolio_trading.md",
            "Multi-Currency trading" => "examples/gen/3_multi_currency.md",
            "USD-M perpetual trading" => "examples/gen/4_USDm_perp_trading.md",
            "VOO vs MES cost comparison" => "examples/gen/5_VOO_vs_MES_comparison.md",
        ],
        "Plotting" => [
            "Plots extensions" => "plotting/gen/1_plots_extension.md",
        ],
        "Integrations" => [
            "Overview" => "integrations/index.md",
            "Tables.jl" => "integrations/gen/1_Tables_integration.md",
            "NanoDates.jl" => "integrations/gen/2_NanoDates_integration.md",
            "Timestamps64.jl" => "integrations/gen/3_Timestamps64_integration.md",
        ],
        "API index" => "api_index.md",
        "Glossary" => "glossary.md",
    ]
)
