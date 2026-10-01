# How it works

## The application

cc-openfront is a Clever Cloud **Linux** application that runs this
repository. Clever Cloud installs Node.js 24 with [Mise](https://mise.jdx.dev)
([`mise.toml`](../mise.toml)), then runs two Mise tasks:

- `build` ([`scripts/build.sh`](../scripts/build.sh)) fills `app/` with a
  runnable openfront-light:
  - `release` mode downloads `openfront-light-<tag>.tar.gz` from the GitHub
    release and checks its SHA-256 (no npm, about a minute);
  - `source` mode clones the repository at a tag or branch and builds it
    (`npm ci`, client build with the chosen maps, server bundle).

  It builds into `app.new/` and swaps at the end, so a failed build never
  leaves a half-filled `app/`, and writes the settings it used to
  `app/.cc-openfront-build`.
- `run` ([`scripts/run.sh`](../scripts/run.sh)) checks those settings against
  the current ones (see [operations.md](operations.md#update-or-roll-back)),
  then starts one Node process tree (master + `NUM_WORKERS` workers) on the
  port Clever Cloud gives it, with `defaults.env` for everything the platform
  does not set.

Clever Cloud terminates HTTPS and passes WebSockets through. The game
simulation runs in each player's browser: the server only hosts the page and
relays player actions, so a small instance handles a few games.

The [Docker deployment](deploy-docker.md) skips all this: Clever Cloud pulls
openfront-light's image, which already contains the built game.

## Exactly one instance

Lobbies and running games live in the memory of the one process tree. A
second instance would split players between two servers that do not know each
other's games, and scaling down would drop games. So the application always
runs on one instance; for more capacity, pick a bigger flavor.

## Why a build instance in source mode

The source build (`npm ci`, then the client and server builds) needs about
**4 GB of memory**, more than the XS instance (1152 MB) that runs the game.
It runs on a dedicated **M** instance (4 GB), billed only while it builds
(`clever scale --build-flavor M`; Terraform's `build_flavor`, applied only in
source mode).

Measured with `docker run --memory=<limit>` on openfront-light's build: 1 GB
and 2 GB fail (out of memory), both with `world` alone and with every map;
4 GB passes in both cases. Instance sizes come from Clever Cloud's
[product API](https://api.clever-cloud.com/v2/products/instances): XS
1152 MB, S 2048 MB, M 4096 MB, L 8192 MB.

## The Terraform module

[`terraform/`](../terraform) creates one `clevercloud_linux` resource: one
instance, the flavor, the build flavor (source mode only), the domain, HTTPS
redirect and the environment variables. Its `deployment` block pushes the
cc-openfront repository (`cc_openfront_repository`) to the application on
create and on any change. The provider reads the credentials of
`clever login`.

[`scripts/deploy.sh`](../scripts/deploy.sh) (macOS, Linux) and its
PowerShell twin [`scripts/deploy.ps1`](../scripts/deploy.ps1) (Windows) only
prepare `terraform/terraform.tfvars` (organisation, name, region) and run
Terraform. Change one, change the other the same way.

## Why not upstream OpenFront

Upstream [OpenFrontIO](https://github.com/openfrontio/OpenFrontIO) needs nginx
and supervisord in its container, and a closed-source API for accounts,
matchmaking and more. openfront-light removes those dependencies and ships a
single-process server, a release tarball and a small image.
