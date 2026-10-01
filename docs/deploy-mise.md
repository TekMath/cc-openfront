# Deploy with Mise and the Clever CLI

This guide deploys cc-openfront by hand, with the `clever` command line, on
Clever Cloud's [Linux runtime](https://www.clever.cloud/developers/doc/applications/linux/).
No Terraform. It is what [the script](deploy-script.md) does for you, step by
step, in the style of Clever Cloud's [guides](https://www.clever.cloud/developers/guides/).

## Overview

The application is a **Linux** app that runs this repository. Clever Cloud
installs Node.js 24 with [Mise](https://mise.jdx.dev) (from `mise.toml`),
then runs two Mise tasks:

- `build` ([`scripts/build.sh`](../scripts/build.sh)) downloads the
  openfront-light release tarball (and checks its SHA-256), or builds it from
  source, into `app/`;
- `run` ([`scripts/run.sh`](../scripts/run.sh)) starts the server on the port
  Clever Cloud gives it.

Every setting is an environment variable. More details in
[how-it-works.md](how-it-works.md).

## Prerequisites

- A [Clever Cloud](https://console.clever-cloud.com) account.
- Git.
- [Clever Tools](https://www.clever.cloud/developers/doc/cli/install/), the
  `clever` command. Pick one:

  ```bash
  npm install --global clever-tools          # with Node.js
  brew install clevercloud/tap/clever-tools  # macOS / Linux with Homebrew
  npx clever-tools@latest <command>          # no install
  ```

Then log in (your browser opens):

```bash
clever login
clever profile # checks it worked, shows your personal space ID (user_xxx)
```

## Get the code

```bash
git clone https://github.com/TekMath/cc-openfront.git
cd cc-openfront
```

`clever deploy` pushes the current Git commit, so any change you make here
must be committed first.

## Create the application

```bash
clever create --type linux my-openfront --region par
```

- `--org <orga_xxx or name>` creates it in an organisation instead of your
  personal space.
- `--region`: `par`, `rbx`, `ldn`, `wsw`, `mtl`, `sgp`, `syd`, ... Pick one
  close to your players.

This also links the folder to the application (`.clever.json`), so the next
commands need no `--app`.

## Size: always one instance

```bash
clever scale --flavor XS --instances 1
```

Games live in the memory of the one server process: a second instance would
split players between two servers that do not see each other's games. For
more games at once, pick a bigger flavor (`S`, `M`), never more instances.

## Domain

```bash
clever domain add my-openfront.cleverapps.io
```

`cleverapps.io` names are shared by every Clever Cloud user: pick one nobody
took. Your own domain works too (`clever domain add games.example.com`, then
the DNS record from Clever Cloud's
[domain docs](https://www.clever.cloud/developers/doc/administrate/domain-names/)).

## Environment variables

Only `DOMAIN` is required. It must be the host name players use:

```bash
clever env set DOMAIN my-openfront.cleverapps.io
```

Optional (all of them are in [configuration.md](configuration.md)):

```bash
clever env set OPENFRONT_VERSION v1.0.0   # pin a version (default: latest release)
clever env set NUM_WORKERS 1
clever env set ADMIN_BOT_API_KEY change-me
```

### Your maps, or your fork: build from source

The prebuilt release has a fixed set of maps. To choose them, or to run your
own fork, build from source:

```bash
clever env set OPENFRONT_BUILD source
clever env set OPENFRONT_VERSION v1.0.0              # a tag or a branch
clever env set OPENFRONT_MAPS world,europe,iceland   # empty = every map (~600 MB)
clever env set OPENFRONT_REPO https://github.com/you/openfront-light  # your fork, optional
```

The build needs about 4 GB of memory, more than the XS instance that runs the
game. Build on a dedicated **M** instance, billed only while it builds:

```bash
clever scale --build-flavor M
```

## Deploy

```bash
clever deploy
clever open # opens https://my-openfront.cleverapps.io
```

`clever deploy` streams the build and start logs. A release deploy takes
about a minute, a source build several minutes. Then click **Create Lobby**
and send the link to your friends.

## Update

```bash
clever env set OPENFRONT_VERSION v1.1.0
clever restart --without-cache
```

A plain `clever restart` reuses the previous build. More (rollback, logs,
delete) in [operations.md](operations.md).

## From the Console instead

1. Fork this repository on GitHub (the Console deploys from your own GitHub
   account).
2. In the [Console](https://console.clever-cloud.com), create an application:
   **Linux**, from your fork. One instance, **XS**.
3. **Environment variables**: add `DOMAIN=<your-app>.cleverapps.io` (and any
   other variable from [configuration.md](configuration.md)).
4. **Domain names**: add the same `<your-app>.cleverapps.io`.
5. Deploy, or **Re-build and restart**.

## All commands at once

```bash
clever login
git clone https://github.com/TekMath/cc-openfront.git && cd cc-openfront
clever create --type linux my-openfront --region par
clever scale --flavor XS --instances 1
clever domain add my-openfront.cleverapps.io
clever env set DOMAIN my-openfront.cleverapps.io
clever deploy
```
