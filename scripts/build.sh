#!/usr/bin/env bash
# Build step of cc-openfront, run by the `build` Mise task (see mise.toml).
#
# It fills app/ with a runnable openfront-light: static/, dist/, defaults.env
# and the licenses. Two modes, picked with OPENFRONT_BUILD:
#
#   release (default)  download the prebuilt tarball of a GitHub release and
#                      check its .sha256 (fast, no npm);
#   source             clone the repository and build it (pick the maps with
#                      OPENFRONT_MAPS, or build your own fork). Needs a
#                      dedicated build instance, see docs/how-it-works.md.
#
# `build.sh --check` builds nothing: it exits 0 when app/ was built from the
# current settings, 1 otherwise. scripts/run.sh uses it to notice a changed
# OPENFRONT_VERSION after a restart that reused the build cache.
set -euo pipefail

readonly DEFAULT_REPO="https://github.com/TekMath/openfront-light"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/app"
marker="$app/.cc-openfront-build"

log() { echo "[cc-openfront] $*"; }
warn() { echo "[cc-openfront] WARNING: $*" >&2; }
die() {
	echo "[cc-openfront] ERROR: $*" >&2
	exit 1
}

mode="${OPENFRONT_BUILD:-release}"
version="${OPENFRONT_VERSION:-}"
maps="${OPENFRONT_MAPS:-}"
# Accept "https://github.com/o/r", ".../r/", ".../r.git" and ".../r.git/".
repo="${OPENFRONT_REPO:-$DEFAULT_REPO}"
repo="${repo%/}"
repo="${repo%.git}"
repo="${repo%/}"

# What app/ must have been built from. OPENFRONT_VERSION is recorded as given:
# empty ("latest") is not re-resolved on each restart.
wanted="mode=$mode repo=$repo version=$version maps=$maps"

if [[ "${1:-}" == "--check" ]]; then
	[[ -f "$marker" ]] && [[ "$(head -n 1 "$marker")" == "$wanted" ]]
	exit
fi

case "$mode" in
release | source) ;;
*) die "unknown OPENFRONT_BUILD=\"$mode\": use \"release\" or \"source\"." ;;
esac

if [[ "$mode" == "release" && -n "$maps" ]]; then
	die "OPENFRONT_MAPS only applies to OPENFRONT_BUILD=source (a release tarball has its maps built in). Unset OPENFRONT_MAPS, or set OPENFRONT_BUILD=source."
fi

if [[ -z "${DOMAIN:-}" ]]; then
	warn "DOMAIN is not set. The server will refuse to start until you set it to the host name players use (e.g. my-app.cleverapps.io)."
fi

# openfront-light needs Node >=24.15 <25. mise.toml asks for "24", which
# resolves to the newest 24.x; this catches an older pinned or cached one.
node_version="$(node -p 'process.versions.node')" || die "node is not on the PATH (Mise should install it from mise.toml)."
IFS=. read -r node_major node_minor _ <<<"$node_version"
if ((node_major != 24 || node_minor < 15)); then
	die "Node $node_version found, openfront-light needs >=24.15 <25."
fi

sha256() {
	if command -v sha256sum >/dev/null; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

# The tag of the latest stable release, from GitHub's /releases/latest
# redirect (no API call, so no rate limit). Prints nothing without a release.
latest_release() {
	local url
	url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$repo/releases/latest")" || return 0
	if [[ "$url" == */releases/tag/* ]]; then
		echo "${url##*/releases/tag/}"
	fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Build into app.new/ and swap at the end, so a failed build never leaves a
# half-filled app/.
next="$root/app.new"
rm -rf "$next"
mkdir -p "$next"

if [[ "$mode" == "release" ]]; then
	resolved="$version"
	if [[ -z "$resolved" ]]; then
		resolved="$(latest_release)"
		[[ -n "$resolved" ]] || die "no stable release found at $repo/releases/latest. Set OPENFRONT_VERSION to a release tag, or use OPENFRONT_BUILD=source."
		log "OPENFRONT_VERSION not set, using the latest release: $resolved"
	fi
	asset="openfront-light-$resolved.tar.gz"
	url="$repo/releases/download/$resolved/$asset"

	log "downloading $url"
	curl -fsSL --retry 3 -o "$tmp/$asset" "$url" ||
		die "cannot download $url. Check that release \"$resolved\" exists in $repo and carries $asset (releases made before the tarball existed do not; use OPENFRONT_BUILD=source for those)."
	curl -fsSL --retry 3 -o "$tmp/$asset.sha256" "$url.sha256" ||
		die "cannot download the checksum $url.sha256."

	expected="$(awk '{print $1; exit}' "$tmp/$asset.sha256")"
	actual="$(sha256 "$tmp/$asset")"
	[[ "$expected" == "$actual" ]] || die "checksum mismatch for $asset: expected $expected, got $actual."
	log "checksum OK ($actual)"

	tar -xzf "$tmp/$asset" -C "$next" --strip-components=1
else
	src="$root/src"
	rm -rf "$src"
	clone=(git clone --quiet --depth 1)
	resolved="$version"
	if [[ -z "$resolved" ]]; then
		resolved="$(latest_release)"
		if [[ -z "$resolved" ]]; then
			warn "OPENFRONT_VERSION not set and no stable release found in $repo: building its default branch."
		else
			log "OPENFRONT_VERSION not set, using the latest release: $resolved"
		fi
	fi
	if [[ -n "$resolved" ]]; then
		clone+=(--branch "$resolved")
	fi

	log "cloning $repo ${resolved:-(default branch)}"
	"${clone[@]}" "$repo" "$src" || die "cannot clone $repo at \"${resolved:-default branch}\" (OPENFRONT_VERSION must be a tag or a branch)."
	cd "$src"
	if [[ -z "$resolved" ]]; then
		resolved="$(git rev-parse --short HEAD)"
	fi
	[[ -f deploy/defaults.env ]] ||
		die "$repo at \"$resolved\" has no deploy/defaults.env: this version predates cc-openfront support. Pick a newer tag or branch."

	log "installing npm 12.1.0 and the dependencies"
	npm install --global --ignore-scripts --no-audit --no-fund npm@12.1.0
	HUSKY=0 npm ci --ignore-scripts --no-audit --no-fund

	log "building the client (maps: ${maps:-all}) and the server"
	OPENFRONT_MAPS="$maps" GIT_COMMIT="$resolved" npm run build-prod
	npm run build-server-light
	echo "$resolved" >static/commit.txt

	cp -R static dist "$next/"
	cp deploy/defaults.env LICENSE LICENSE-ASSETS LICENSING.md "$next/"
	cd "$root"
	# The sources and node_modules (well over 1 GB) must not end up in the
	# build cache archive that the run instance downloads.
	rm -rf "$src"
fi

printf '%s\nresolved=%s\n' "$wanted" "$resolved" >"$next/.cc-openfront-build"
rm -rf "$app"
mv "$next" "$app"
log "openfront-light $resolved ready in app/ ($(du -sh "$app" | cut -f1))"
