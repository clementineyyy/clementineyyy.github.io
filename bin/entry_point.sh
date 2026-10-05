#!/bin/bash
set -euo pipefail

echo "Entry point script running"

CONFIG_FILE=_config.yml

# Function to manage Gemfile.lock
manage_gemfile_lock() {
    git config --global --add safe.directory /srv/jekyll
    if command -v git &> /dev/null && [ -f Gemfile.lock ]; then
        if git ls-files --error-unmatch Gemfile.lock &> /dev/null; then
            echo "Gemfile.lock is tracked by git, keeping it intact"
            git restore Gemfile.lock 2>/dev/null || true
        else
            echo "Gemfile.lock is not tracked by git, removing it"
            rm Gemfile.lock
        fi
    fi
}

ensure_bundle_deps() {
    if bundle check >/dev/null 2>&1; then
        echo "Bundler dependencies already satisfied"
        return
    fi

    echo "Installing missing bundler dependencies"
    bundle install --jobs 4 --retry 3
}

build_and_purge() {
    echo "Building Jekyll site..."
    bundle exec jekyll build --config "$CONFIG_FILE" --verbose --trace || echo "WARNING: Jekyll build had non-fatal errors"

    echo "Purging unused CSS (matching GitHub Actions workflow)..."
    purgecss -c purgecss.config.js

    echo "Build + PurgeCSS complete"
}

start_server() {
    mkdir -p /srv/jekyll/_site
    cd /srv/jekyll/_site
    python3 -m http.server 8080 &
    SERVER_PID=$!
    cd /srv/jekyll
}

# Initial setup
manage_gemfile_lock
ensure_bundle_deps

# Full build + purge (identical to GitHub Actions deploy.yml)
build_and_purge

# Serve the purged site
start_server
echo "Serving at http://localhost:8080"

# Watch for config changes -> full rebuild + purge
while true; do
    inotifywait -q -e modify,move,create,delete "$CONFIG_FILE"
    if [ $? -eq 0 ]; then
        echo "Change detected to $CONFIG_FILE, rebuilding..."
        kill $SERVER_PID 2>/dev/null || true
        build_and_purge
        start_server
        echo "Rebuild complete, serving at http://localhost:8080"
    fi
done