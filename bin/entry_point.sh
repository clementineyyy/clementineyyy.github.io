#!/bin/bash
set -euo pipefail

echo "Entry point script running"

CONFIG_FILE=_config.yml
WATCH_DIRS=("_config.yml" "_posts" "_pages" "_projects" "_news" "_data" "_includes" "_bibliography" "_books" "_teachings")

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

get_latest_mtime() {
    local latest=0
    local mtime
    for dir in "${WATCH_DIRS[@]}"; do
        if [ -f "/srv/jekyll/$dir" ]; then
            mtime=$(stat -c %Y "/srv/jekyll/$dir" 2>/dev/null || echo 0)
        elif [ -d "/srv/jekyll/$dir" ]; then
            mtime=$(find "/srv/jekyll/$dir" -type f -exec stat -c %Y {} + 2>/dev/null | sort -rn | head -1 || echo 0)
        else
            mtime=0
        fi
        [ "$mtime" -gt "$latest" ] && latest=$mtime
    done
    echo "$latest"
}

# Initial setup
manage_gemfile_lock
ensure_bundle_deps

# Initial build + purge (production-matching)
build_and_purge

# Start the static server
start_server

echo "Serving at http://localhost:8080"
echo "Watching source files for changes (polling every 3s)..."
echo "Edit files in VSCode, save, and refresh browser to see changes."

# Poll for source file changes -> full rebuild + purge
last_mtime=$(get_latest_mtime)
while true; do
    sleep 3
    current_mtime=$(get_latest_mtime)
    if [ "$current_mtime" -gt "$last_mtime" ]; then
        echo "Source file change detected, rebuilding..."
        kill $SERVER_PID 2>/dev/null || true
        last_mtime=$current_mtime
        build_and_purge
        start_server
        echo "Rebuild complete, serving at http://localhost:8080"
    fi
done