using Pkg

const DOCS_ROOT = @__DIR__
const PROJECT_ROOT = normpath(joinpath(DOCS_ROOT, ".."))

cd(DOCS_ROOT)
Pkg.activate(DOCS_ROOT)
# Local docs manifests from the old workflow may pin a custom Documenter fork.
try
    Pkg.free("Documenter")
catch
    nothing
end
Pkg.develop(; path=PROJECT_ROOT)
Pkg.resolve()
Pkg.instantiate()

# GR render offscreen (avoid window popups during docs build)
ENV["GKS_WSTYPE"] = "100"

# Use a wider virtual terminal for @example/@repl output so wide tables
# (DataFrames/PrettyTables) are not horizontally cropped in rendered docs.
ENV["COLUMNS"] = "160"
ENV["LINES"] = "80"

using Documenter: Documenter
using DocumenterVitepress
using Literate
using Fastback

const DOCS_REPO = "github.com/rbeeli/Fastback.jl"
const DEPLOY_REPO = "github.com/rbeeli/Fastback.jl.git"

function postprocess_md(md, data_dir)
    # fix data folder path
    md = replace(md, "\"data/" => "\"$(data_dir)")

    md
end

const EXAMPLES_ROOT = joinpath(DOCS_ROOT, "src", "examples")
const INTEGRATIONS_ROOT = joinpath(DOCS_ROOT, "src", "integrations")
const PLOTTING_ROOT = joinpath(DOCS_ROOT, "src", "plotting")
const GENERATED_EXAMPLES_ROOT = joinpath(EXAMPLES_ROOT, "gen")
const GENERATED_INTEGRATIONS_ROOT = joinpath(INTEGRATIONS_ROOT, "gen")
const GENERATED_PLOTTING_ROOT = joinpath(PLOTTING_ROOT, "gen")

for dir in (GENERATED_EXAMPLES_ROOT, GENERATED_INTEGRATIONS_ROOT, GENERATED_PLOTTING_ROOT)
    rm(dir; recursive=true, force=true)
    mkpath(dir)
end

function gen_markdown(path;
        name=nothing,
        source_root::String=EXAMPLES_ROOT,
        generated_root::String=GENERATED_EXAMPLES_ROOT,
        data_dir::String="../data/")
    kwargs = (
        postprocess=(md -> postprocess_md(md, data_dir)),
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

function deploy_decision()
    decision = Documenter.deploy_folder(
        Documenter.auto_detect_deploy_system();
        repo=DOCS_REPO,
        devbranch="main",
        devurl="dev",
        push_preview=true,
    )

    if decision.all_ok && !decision.is_preview && decision.subfolder == "dev"
        return Documenter.DeployDecision(;
            all_ok=decision.all_ok,
            branch=decision.branch,
            is_preview=decision.is_preview,
            repo=decision.repo,
            subfolder="",
        )
    end

    return decision
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

deployment = deploy_decision()

Documenter.makedocs(
    sitename="Fastback.jl",
    format=DocumenterVitepress.MarkdownVitepress(;
        repo=DOCS_REPO,
        devurl="dev",
        devbranch="main",
        description="Event-driven backtesting library for quantitative trading in Julia.",
        deploy_decision=deployment,
    ),
    pages=[
        "Home" => "index.md",
        "Getting started" => "getting_started.md",
        "Basic setup" => "basic_setup.md",
        "Accounting model and event loop" => "concepts.md",
        "Execution and errors" => "execution_errors.md",
        "Pitfalls and gotchas" => "pitfalls.md",
        "How-to" => "how_to.md",
        "Analytics" => "analytics.md",
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
    ],
    warnonly=get(ENV, "CI", "false") != "true",
    pagesonly=true,
)

Documenter.deploydocs(
    repo=DEPLOY_REPO,
    target=joinpath("build", "1"),
    versions=nothing,
    push_preview=true,
    devbranch="main",
)
