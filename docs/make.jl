push!(LOAD_PATH,"../src/")

using Documenter
using fastback

makedocs(
    sitename = "fastback",
    format = Documenter.HTML(prettyurls=false),
    modules = [fastback]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
