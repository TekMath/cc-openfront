# Your own fork of openfront-light

[openfront-light](https://github.com/TekMath/openfront-light) is itself a
fork of [OpenFront](https://github.com/openfrontio/OpenFrontIO), stripped
down for private servers. Fork it when you want to change the game (rules,
UI, maps), or publish releases and images with your own map selection.
cc-openfront deploys your fork like the original.

Fork **openfront-light**, not upstream OpenFront: upstream needs nginx,
supervisord and a closed-source API, and cc-openfront does not support it.

## Level 1: build your fork from source

The simplest. No release, no CI.

1. On GitHub, fork `TekMath/openfront-light` (a public fork, so Clever Cloud
   can clone it).
2. Commit and push your changes to a branch (or tag them).
3. Deploy in source mode, pointing at your fork:

   ```hcl
   # terraform/terraform.tfvars
   openfront_build   = "source"
   openfront_repo    = "https://github.com/you/openfront-light"
   openfront_version = "main"                 # a branch or a tag
   openfront_maps    = "world,europe"         # optional
   ```

   Or with the CLI: `clever env set OPENFRONT_BUILD source`,
   `OPENFRONT_REPO ...`, `OPENFRONT_VERSION main`, then
   `clever scale --build-flavor M` and `clever restart --without-cache`.

Each deploy builds on a dedicated M instance (a few minutes). After a new
push to the branch, rebuild with `clever restart --without-cache`.

## Level 2: publish releases and an image, like openfront-light

Then deployments download a prebuilt tarball (about a minute, no build
instance), and you get a Docker image for the
[Docker deployment](deploy-docker.md). openfront-light's CI does it all.

1. **Enable GitHub Actions** on your fork (tab **Actions**: forks start with
   workflows disabled).
2. **Choose the maps** of your releases: **Settings > Secrets and variables >
   Actions > Variables**, add `OPENFRONT_MAPS`, e.g.
   `world,europe,iceland,japan`. Without it, CI uses
   `world,giantworldmap,europe,northamerica,southamerica,asia,africa`.
3. **Tag a version** and push the tag:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

   After lint and tests, the CI workflow publishes:

   - the image `ghcr.io/<you>/<repo>:v1.0.0` (and `:latest` for a stable
     tag; a tag with a `-`, like `v1.1.0-rc.1`, is a pre-release);
   - the GitHub release `v1.0.0` with `openfront-light-v1.0.0.tar.gz` and its
     `.sha256`.

4. **Make the image public**: on GitHub, your profile > **Packages** > the
   package > **Package settings** > **Change visibility**. A new package is
   private. (Or keep it private and give Clever Cloud a token with
   `CC_DOCKER_LOGIN_*`, see [deploy-docker.md](deploy-docker.md).)
5. **Deploy it** in release mode:

   ```hcl
   openfront_repo    = "https://github.com/you/openfront-light"
   openfront_version = "v1.0.0"   # or leave it out for your latest release
   ```

   For Docker, replace the image in the Dockerfile with
   `ghcr.io/<you>/<repo>`.

## What your fork must keep

cc-openfront relies on these parts of openfront-light. Keep them when you
change things.

Release mode ([`scripts/build.sh`](../scripts/build.sh)):

- The repository is on GitHub, and `/releases/latest` points at a stable
  release (or you pin `OPENFRONT_VERSION`).
- Each release carries `openfront-light-<tag>.tar.gz` and
  `openfront-light-<tag>.tar.gz.sha256`. **Keep that asset name** even if you
  rename your repository.
- The tarball has one top-level folder holding `static/` (with
  `static/commit.txt`), `dist/server/Server.mjs`, `defaults.env`, `LICENSE`,
  `LICENSE-ASSETS` and `LICENSING.md`. This is the `artifact` stage of
  `Dockerfile.light`.

Source mode:

- `deploy/defaults.env`, `LICENSE`, `LICENSE-ASSETS`, `LICENSING.md` at the
  root.
- `package-lock.json` and the npm scripts `build-prod` (client, honours
  `OPENFRONT_MAPS`) and `build-server-light` (bundles the server into
  `dist/server/Server.mjs`).
- Node.js `>=24.15 <25` and npm 12.1.0.

At run time (both modes, and the image):

- The server listens on `PORT`, forwards to its workers itself with
  `WORKER_PROXY=inprocess`, and needs `DOMAIN` and `GIT_COMMIT`.

## Keep up with openfront-light (and upstream)

```bash
git remote add openfront-light https://github.com/TekMath/openfront-light.git
git fetch openfront-light
git merge openfront-light/main
```

openfront-light lists every change it made to upstream in its
[`CLAUDE.md`](https://github.com/TekMath/openfront-light/blob/main/CLAUDE.md)
and marks it in the code with `openfront-light:` comments, which helps when
merging.

## License

openfront-light's code is under the **AGPL-3.0**. If you run a **modified**
version, you must offer its source code to your players, for example with a
link to your fork in the game. Keep the "© OpenFront and Contributors" notices
visible. Assets in `resources/` are CC BY-SA 4.0, and those in
`proprietary/` are All Rights Reserved (see its
[LICENSING.md](https://github.com/TekMath/openfront-light/blob/main/LICENSING.md)).
