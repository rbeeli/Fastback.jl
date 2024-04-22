push!(LOAD_PATH,"../src/")

using Documenter
using Fastback

makedocs(
    sitename = "Fastback.jl",
    # format = Documenter.HTML(prettyurls=false),
    # modules = [Fastback]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
