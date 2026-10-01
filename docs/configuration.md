# Configuration

Everything is configured in two places:

- **Terraform variables** (`terraform/terraform.tfvars`), when you deploy with
  [the script](deploy-script.md) or Terraform. They create the Clever Cloud
  application (size, region, domain) and set its environment variables.
- **Environment variables** of the application, which the build and the
  server read. With [Mise and the CLI](deploy-mise.md) or
  [Docker](deploy-docker.md), you set them yourself with `clever env set`
  (or in the Console).

The Terraform variable `openfront_version` sets the environment variable
`OPENFRONT_VERSION`, and so on: the tables below show the mapping.

## How to change a setting

| You deployed with | Change a setting                                                                                         |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| The script        | Edit `terraform/terraform.tfvars`, run `./scripts/deploy.sh` (Windows: `scripts\deploy.ps1`) again.      |
| Terraform         | Edit `terraform/terraform.tfvars`, run `terraform apply`.                                                |
| Mise + CLI        | `clever env set NAME value`, then `clever restart --without-cache`.                                      |
| Docker            | Same as Mise + CLI.                                                                                      |
| Console           | **Environment variables**, then **Re-build and restart**.                                                |

Do not mix Terraform with `clever env set`: the next `terraform apply` puts
back what `terraform.tfvars` says. With Terraform, put other variables in
`extra_env`.

Why "without cache": a plain restart reuses the previous build. In release
mode, the server notices changed settings and downloads the right release by
itself, so `terraform apply` is enough. In source mode it refuses to start
the old build and asks for `clever restart --without-cache`. Details in
[operations.md](operations.md).

## Terraform variables

Defined in [`terraform/variables.tf`](../terraform/variables.tf). Only
`organisation` and `name` matter for a first deploy.

| Variable                  | Default                                      | Sets                | What it is for                                                                                                                                                                                          |
| ------------------------- | -------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `organisation`            | `CC_ORGANISATION`                            |                     | Who owns (and pays for) the application: `orga_xxx`, or `user_xxx` for your personal space (`clever profile` shows it).                                                                                |
| `name`                    | `openfront`                                  |                     | Application name, and the default address `https://<name>.cleverapps.io`. Lowercase letters, digits and hyphens. Must be free on `cleverapps.io`.                                                      |
| `region`                  | `par`                                        |                     | Data center: `par`, `rbx`, `ldn`, `wsw`, `mtl`, `sgp`, `syd`, ... Pick the closest to your players. **Changing it re-creates the application.**                                                        |
| `domain`                  | `<name>.cleverapps.io`                       | `DOMAIN`            | Host name players use. For your own domain (`games.example.com`), also add the DNS record from Clever Cloud's [domain docs](https://www.clever.cloud/developers/doc/administrate/domain-names/).        |
| `flavor`                  | `XS`                                         |                     | Size of the instance that runs the server. XS (1 CPU, 1152 MB) is enough for a few games at once; `S` (2 GB) or `M` (4 GB) for more.                                                                   |
| `build_flavor`            | `M`                                          |                     | Size of the dedicated build instance, **source mode only** (the build needs ~4 GB). Billed only while it builds.                                                                                      |
| `openfront_version`       | latest stable release                        | `OPENFRONT_VERSION` | openfront-light version to deploy: a tag (`v1.0.0`), or a branch in source mode. Pin it to know what runs and to roll back.                                                                            |
| `openfront_build`         | `release`                                    | `OPENFRONT_BUILD`   | `release`: download the prebuilt tarball (fast, fixed maps). `source`: clone and build (choose the maps, run a fork).                                                                                 |
| `openfront_repo`          | `https://github.com/TekMath/openfront-light` | `OPENFRONT_REPO`    | Repository to download releases from, or to build. Point it at [your fork](fork.md).                                                                                                                  |
| `openfront_maps`          | every map (~600 MB)                          | `OPENFRONT_MAPS`    | Source mode only. Comma-separated folders of `resources/maps/`, e.g. `world,europe,iceland`. Fewer maps: faster build, smaller download for players.                                                  |
| `num_workers`             | `1`                                          | `NUM_WORKERS`       | Game worker processes. One handles a few games; add one per extra CPU on a bigger flavor. Change it only while no game runs.                                                                           |
| `extra_env`               | `{}`                                         | anything            | Any other environment variable (`NODE_OPTIONS`, `ADMIN_BOT_API_KEY`, ...). Cannot override the variables above. Marked sensitive: Terraform does not print it.                                         |
| `cc_openfront_repository` | `https://github.com/TekMath/cc-openfront.git` |                    | The cc-openfront repository Terraform pushes to the application. Point it at your fork of cc-openfront if you changed the scripts.                                                                    |

Terraform always sets one instance (never more, see
[how-it-works.md](how-it-works.md)) and redirects HTTP to HTTPS.

## Environment variables

Set on the Clever Cloud application. Only `DOMAIN` is required.

### Read by cc-openfront (Linux / Mise deployment)

| Variable            | Default                                      | What it is for                                                                                                                                                  |
| ------------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DOMAIN`            | (required)                                   | Host name players use, e.g. `my-openfront.cleverapps.io`. The server refuses to start without it (it signs the game tokens for this host).                     |
| `OPENFRONT_VERSION` | latest stable release                        | Tag to deploy (`v1.0.0`). In source mode, a branch works too. Unset means "the latest release when it was built": a new release needs a rebuild without cache. |
| `OPENFRONT_BUILD`   | `release`                                    | `release` downloads the prebuilt tarball and checks its SHA-256. `source` clones and builds.                                                                   |
| `OPENFRONT_REPO`    | `https://github.com/TekMath/openfront-light` | Repository (or your fork) to download releases from or to build. A trailing `/` or `.git` is ignored. Release mode needs a GitHub repository.                  |
| `OPENFRONT_MAPS`    | empty (every map)                            | Source mode only (an error in release mode). Comma-separated folder names from `resources/maps/`. An unknown name fails the build.                             |

### Read by the openfront-light server (every deployment)

| Variable             | Default                    | What it is for                                                                                                                              |
| -------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `NUM_WORKERS`        | `1`                        | Game worker processes. Change it only while no game runs (game IDs are routed by worker count).                                            |
| `NODE_OPTIONS`       | heap `384` MB per process  | Node options. Put `--max-old-space-size=768` (or more) in it to give each process more memory on a bigger flavor.                          |
| `ADMIN_BOT_API_KEY`  | (unset)                    | Turns on openfront-light's admin bot HTTP API, protected by this key. Unset keeps it off.                                                  |
| `TURNSTILE_SITE_KEY` | Cloudflare always-pass key | Bot check. The default always passes, which is fine for a private server.                                                                  |
| `PORT`               | set by Clever Cloud        | Do not set it.                                                                                                                              |
| `GAME_ENV`, `WORKER_PROXY`, `INSTANCE_LETTER` | `prod`, `inprocess`, `a` | Leave them as is. They come from the release's `defaults.env` (or the image).                                        |

Leave `SUBDOMAIN`, `LOBBY_COORDINATOR`, `CDN_BASE` and the `OTEL_*` variables
**unset**: they only apply to the openfront.io infrastructure.

### Docker deployment

The [Docker deployment](deploy-docker.md) reads `DOMAIN` and the server
variables above. `OPENFRONT_VERSION` is the image tag. `OPENFRONT_BUILD`,
`OPENFRONT_REPO` and `OPENFRONT_MAPS` do not apply (the maps are in the image),
except when Clever Cloud builds `Dockerfile.light` itself, where
`OPENFRONT_MAPS` picks the maps. Docker-specific variables:
`CC_DOCKERFILE`, `CC_DOCKER_LOGIN_USERNAME`, `CC_DOCKER_LOGIN_PASSWORD`,
`CC_DOCKER_LOGIN_SERVER` (see
[Clever Cloud's Docker docs](https://www.clever.cloud/developers/doc/applications/docker/)).

## Recipes

In `terraform/terraform.tfvars` (the `clever env set` equivalent in
comments).

**Pin a version**

```hcl
openfront_version = "v1.0.0"   # OPENFRONT_VERSION=v1.0.0
```

**Choose the maps**

```hcl
openfront_build   = "source"                  # OPENFRONT_BUILD=source
openfront_version = "v1.0.0"
openfront_maps    = "world,europe,iceland"    # OPENFRONT_MAPS=world,europe,iceland
# clever scale --build-flavor M (Terraform does it for you)
```

The folder names are in
[openfront-light's `resources/maps/`](https://github.com/TekMath/openfront-light/tree/main/resources/maps).

**More players at once**

```hcl
flavor      = "S"   # clever scale --flavor S
num_workers = 2     # NUM_WORKERS=2
extra_env = {
  NODE_OPTIONS = "--max-old-space-size=768"
}
```

**Your own domain**

```hcl
domain = "games.example.com"   # clever domain add games.example.com + DOMAIN=games.example.com
```

Then add the DNS record Clever Cloud gives in its
[domain docs](https://www.clever.cloud/developers/doc/administrate/domain-names/).

**Admin bot API**

```hcl
extra_env = {
  ADMIN_BOT_API_KEY = "a-long-random-string"
}
```

**Your fork**

```hcl
openfront_build   = "source"
openfront_repo    = "https://github.com/you/openfront-light"
openfront_version = "main"
```

Or, with your own releases, keep `release` mode. See [fork.md](fork.md).
