build-docs:
	julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate(); include("docs/make.jl")'

serve-docs:
	(python3 -m http.server 8080 --directory docs/build &) && sleep 1 && (command -v xdg-open >/dev/null && xdg-open http://localhost:8080 || command -v open >/dev/null && open http://localhost:8080 || echo "Open http://localhost:8080 in your browser")
