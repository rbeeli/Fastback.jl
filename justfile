docs-build:
	julia --project=docs docs/makedocs.jl

docs-serve:
	#!/usr/bin/env bash
	set -euo pipefail
	cleanup() {
		kill "$server_pid" 2>/dev/null || true
	}
	if [ ! -f docs/build/1/index.html ]; then
		just build-docs
	fi
	docs/node_modules/.bin/vitepress preview docs/build/.documenter --host 127.0.0.1 --port 8000 >/tmp/fastback-docs-server.log 2>&1 &
	server_pid=$!
	trap cleanup EXIT
	trap 'cleanup; exit 0' INT TERM
	sleep 1
	if command -v open >/dev/null 2>&1; then
		open "http://127.0.0.1:8000/"
	elif command -v xdg-open >/dev/null 2>&1; then
		xdg-open "http://127.0.0.1:8000/"
	fi
	echo "Serving docs at http://127.0.0.1:8000/"
	wait "$server_pid" || true
