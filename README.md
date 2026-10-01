# cc-openfront

Your own private [OpenFront](https://openfront.io) server, to play with your
friends, on [Clever Cloud](https://www.clever.cloud), in one command.

cc-openfront deploys [openfront-light](https://github.com/TekMath/openfront-light),
a stripped-down OpenFront made for private servers. Everything is
configurable: the version, the maps, the server size, your domain, even your
own fork of the game.

## Quick start

You need a [Clever Cloud](https://console.clever-cloud.com) account, and on
your computer only [Terraform](https://developer.hashicorp.com/terraform/install)
and [Node.js](https://nodejs.org).

```bash
git clone https://github.com/TekMath/cc-openfront.git
cd cc-openfront
./scripts/deploy.sh                                          # macOS, Linux
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1  # Windows
```

The script installs the Clever Cloud CLI if needed, logs you in, lets you
pick (or create) an organisation, asks for a name and a region, and deploys.
Then open the address it prints, click **Create Lobby** and send the link to
your friends.

Details: [docs/deploy-script.md](docs/deploy-script.md).

## Other ways to deploy

| Way                                               | For whom                                                         | You need                  |
| ------------------------------------------------- | ---------------------------------------------------------------- | ------------------------- |
| **[The script](docs/deploy-script.md)** (easiest) | Everyone. Terraform keeps the whole setup in one file.           | Terraform, Node.js        |
| **[Mise + Clever CLI](docs/deploy-mise.md)**      | You prefer `clever` commands (or the Console) to Terraform.      | Clever Tools, Git         |
| **[Docker image](docs/deploy-docker.md)**         | You want the prebuilt `ghcr.io/tekmath/openfront-light` image.   | Clever Tools, Git         |

## Configuration

- [Configuration](docs/configuration.md): every Terraform variable and
  environment variable, what it is for, and recipes (pin a version, choose the
  maps, bigger server, your domain, admin API).
- [Your own fork](docs/fork.md): fork openfront-light, publish your own
  releases and image, and deploy them.

## Deploy with Claude or any coding agent

Open this repository in [Claude Code](https://claude.com/claude-code) (or
another coding agent) and describe what you want, for example:

> Deploy OpenFront in my organisation "Friends", in Montreal, with only the
> world and europe maps, on a bigger server.

[`AGENTS.md`](AGENTS.md) (read by Claude through [`CLAUDE.md`](CLAUDE.md))
tells the agent which doc to follow for each kind of request.

## More

- [How it works](docs/how-it-works.md): the Linux app, the build and run
  steps, why one instance.
- [Operations](docs/operations.md): update, roll back, logs, common errors,
  delete.

## License

cc-openfront (these scripts, docs and Terraform files) is under the
[MIT License](LICENSE).

openfront-light, which it downloads and runs, keeps its own licenses: code
under **AGPL-3.0**, assets in `resources/` under **CC BY-SA 4.0**, assets in
`proprietary/` **All Rights Reserved** (see its
[LICENSING.md](https://github.com/TekMath/openfront-light/blob/main/LICENSING.md)).
If you run a modified version, the AGPL requires you to offer its source code
to your players (see [docs/fork.md](docs/fork.md#license)).
