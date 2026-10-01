# Deploy the Docker image

openfront-light publishes a ready-to-run image:

```
ghcr.io/tekmath/openfront-light:latest   # newest stable release
ghcr.io/tekmath/openfront-light:v1.0.0   # a pinned version
```

It embeds **World, Giant World Map, Europe, North America, South America,
Asia and Africa**, and runs one Node process on port **8080**, which is the
port a Clever Cloud
[Docker application](https://www.clever.cloud/developers/doc/applications/docker/)
expects. Clever Cloud's load balancer handles HTTPS and WebSockets.

This way does not use this repository's scripts: a Docker application only
needs a Dockerfile that starts from the image.

## Prerequisites

- A [Clever Cloud](https://console.clever-cloud.com) account.
- Git and [Clever Tools](https://www.clever.cloud/developers/doc/cli/install/)
  (`npm install --global clever-tools`), logged in with `clever login`.
- No Docker on your computer: Clever Cloud pulls the image.

## Deploy

```bash
mkdir my-openfront && cd my-openfront

cat > Dockerfile <<'EOF'
# Clever Cloud passes every environment variable of the application as a
# build argument: OPENFRONT_VERSION picks the image tag.
ARG OPENFRONT_VERSION=latest
FROM ghcr.io/tekmath/openfront-light:${OPENFRONT_VERSION}
CMD ["node", "dist/server/Server.mjs"]
EOF

git init && git add Dockerfile && git commit -m "openfront-light on Clever Cloud"

clever create --type docker my-openfront --region par   # --org orga_xxx for an organisation
clever scale --flavor XS --instances 1
clever domain add my-openfront.cleverapps.io
clever env set DOMAIN my-openfront.cleverapps.io
clever deploy
clever open
```

- **One instance only**: games live in the memory of the server process. For
  more games, pick a bigger flavor (`S`, `M`), not more instances.
- `cleverapps.io` names are shared by every Clever Cloud user: pick one
  nobody took.
- `DOMAIN` is required: it must be the host name players use.

From the Console: create a **Docker** application from a GitHub repository
holding this one Dockerfile, set `DOMAIN`, add the domain, deploy.

## Settings

The image reads the same runtime variables as the other deployments:
`DOMAIN`, `NUM_WORKERS`, `NODE_OPTIONS` (default
`--max-old-space-size=384`, raise it on a bigger flavor), `ADMIN_BOT_API_KEY`.
See [configuration.md](configuration.md#docker-deployment).

| Variable            | Default  | Use                                                            |
| ------------------- | -------- | -------------------------------------------------------------- |
| `OPENFRONT_VERSION` | `latest` | Image tag, read at build time by the Dockerfile above.         |
| `CC_DOCKER_LOGIN_USERNAME`, `CC_DOCKER_LOGIN_PASSWORD`, `CC_DOCKER_LOGIN_SERVER` | (unset) | Only for a **private** image, e.g. your fork's: `ghcr.io`, your GitHub user and a token with `read:packages`. |

`OPENFRONT_BUILD`, `OPENFRONT_REPO` and `OPENFRONT_MAPS` do not apply here:
the maps are baked into the image.

## Update or roll back

```bash
clever env set OPENFRONT_VERSION v1.1.0
clever restart --without-cache
```

`--without-cache` makes Clever Cloud pull the image again, which also picks up
a new `latest`. Update between games: running games are cut.

## Other maps, or your own image

The published image has a fixed set of maps. Three ways to get others:

1. **Use the Linux deployment in source mode** (simplest, no image):
   `OPENFRONT_BUILD=source` and `OPENFRONT_MAPS=...`, see
   [deploy-mise.md](deploy-mise.md#your-maps-or-your-fork-build-from-source).
2. **Let Clever Cloud build openfront-light's `Dockerfile.light`.** Create the
   Docker application from a clone of
   [openfront-light](https://github.com/TekMath/openfront-light) (or your
   fork) instead of the one-line Dockerfile:

   ```bash
   git clone https://github.com/TekMath/openfront-light.git && cd openfront-light
   git checkout v1.0.0
   clever create --type docker my-openfront --region par
   clever scale --flavor XS --instances 1 --build-flavor M   # the build needs ~4 GB
   clever domain add my-openfront.cleverapps.io
   clever env set DOMAIN my-openfront.cleverapps.io
   clever env set CC_DOCKERFILE Dockerfile.light
   clever env set OPENFRONT_MAPS world,europe,iceland       # becomes the build argument
   clever env set GIT_COMMIT v1.0.0                         # version shown in the game
   clever deploy
   ```

3. **Publish your own image** from a fork, with openfront-light's CI: see
   [fork.md](fork.md). Then replace `ghcr.io/tekmath/openfront-light` with
   `ghcr.io/<you>/<your-repo>` in the Dockerfile.

## Delete

```bash
clever delete --app my-openfront
```
