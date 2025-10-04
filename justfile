build-docs:
	julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate(); include("docs/make.jl")'

serve-docs:
	(npx live-server docs/build/ &) && sleep 1 && xdg-open http://localhost:8080
