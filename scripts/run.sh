#!/usr/bin/env bash
# Run step of cc-openfront, run by the `run` Mise task (see mise.toml).
#
# It starts openfront-light from app/ as one Node process tree (master +
# NUM_WORKERS workers) on $PORT, with defaults.env for everything the platform
# does not set.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[cc-openfront] $*"; }
die() {
	echo "[cc-openfront] ERROR: $*" >&2
	exit 1
}

[[ -n "${DOMAIN:-}" ]] ||
	die "DOMAIN is not set. Set it to the host name players use (e.g. my-app.cleverapps.io), then restart."

# A plain restart reuses the build cache, so a changed OPENFRONT_VERSION (or
# mode, repository, maps) would silently keep running the old build. A release
# is quick to fetch again, so do it here. A source build is too heavy for the
# run instance: fail with the command that rebuilds without the cache.
if ! bash "$root/scripts/build.sh" --check; then
	if [[ "${OPENFRONT_BUILD:-release}" == "release" ]]; then
		log "app/ was built from other settings (OPENFRONT_VERSION changed?): fetching the release again."
		bash "$root/scripts/build.sh"
	else
		die "app/ was built from other settings (OPENFRONT_VERSION, OPENFRONT_REPO or OPENFRONT_MAPS changed) and a source build cannot run here. Rebuild without the cache: \`clever restart --without-cache\` (Console: \"Re-build and restart\")."
	fi
fi

cd "$root/app"

# The server refuses to start without GIT_COMMIT; report the built version.
GIT_COMMIT="${GIT_COMMIT:-$(cat static/commit.txt)}"
export GIT_COMMIT

# Heap cap per process. A command-line flag wins over NODE_OPTIONS, so only
# add the default when NODE_OPTIONS does not set one: that way NODE_OPTIONS
# can raise (or lower) it. Workers inherit the flag.
heap=(--max-old-space-size=384)
case " ${NODE_OPTIONS:-} " in
*--max-old-space-size* | *--max_old_space_size*) heap=() ;;
esac

log "starting openfront-light $GIT_COMMIT for $DOMAIN on port ${PORT:-8080}"
# ${heap[@]+...}: bash < 4.4 (macOS) calls an empty array unbound under set -u.
exec node ${heap[@]+"${heap[@]}"} --env-file=defaults.env dist/server/Server.mjs
