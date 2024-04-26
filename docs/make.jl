push!(LOAD_PATH,"../src/")

using Documenter
using Fastback

makedocs(
    sitename = "Fastback.jl",
    format = Documenter.HTML(prettyurls=false, sidebar_sitename=false),
    pages = [
        "Home" => "index.md",
        "Examples" => [
            "Basic Setup" => "examples/0_setup.md",
            "1\\. Random Trading" => "examples/1_random_trading.md",
            "2\\. Portfolio Trading" => "examples/2_portfolio_trading.md",
        ]
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
