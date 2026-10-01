# Agent guide: deploying OpenFront with cc-openfront

This repository deploys [openfront-light](https://github.com/TekMath/openfront-light)
(a private-server OpenFront) on Clever Cloud. The user will usually ask you to
deploy, reconfigure, update or delete their server. Pick the doc below, read
it, then act.

## Which doc for which request

| The user wants to...                                                              | Read                                                            |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Deploy, with no preference                                                        | [docs/deploy-script.md](docs/deploy-script.md) (default choice) |
| Deploy with `clever` commands, the Console, "without Terraform", "with Mise"      | [docs/deploy-mise.md](docs/deploy-mise.md)                      |
| Deploy "with Docker", "the image", `ghcr.io/tekmath/openfront-light`              | [docs/deploy-docker.md](docs/deploy-docker.md)                  |
| Choose maps, a version, size, region, domain, workers, memory, admin API          | [docs/configuration.md](docs/configuration.md)                  |
| Run their own fork / modified game, publish their own releases or image           | [docs/fork.md](docs/fork.md)                                    |
| Update, roll back, read logs, fix a failed deploy, delete                         | [docs/operations.md](docs/operations.md)                        |
| Understand the architecture, or change `scripts/` / `terraform/`                  | [docs/how-it-works.md](docs/how-it-works.md)                    |

## How to deploy as an agent

1. Check the tools: `terraform version`, `node --version`, `clever version`
   (install with `npm install --global clever-tools` if missing).
2. Check the login: `clever profile`. If it fails, ask the user to run
   `! clever login` themselves (it opens a browser).
3. Find the organisation: `clever curl https://api.clever-cloud.com/v2/organisations`
   lists `id` and `name`. Match the name the user gave. The personal space is
   `user_xxx`.
4. Translate the request into `terraform/terraform.tfvars` using the variables
   in [docs/configuration.md](docs/configuration.md) (for example "only world
   and europe" means `openfront_build = "source"` and
   `openfront_maps = "world,europe"`; "bigger server" means `flavor = "S"`).
5. Show the user the plan (`terraform -chdir=terraform plan`), then apply:
   `./scripts/deploy.sh --yes` (reuses the tfvars you wrote; on Windows
   `powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Yes`) or
   `terraform -chdir=terraform apply`.
6. Verify: `terraform -chdir=terraform output`, then
   `clever logs --app <app_id>` until the line
   `[cc-openfront] starting openfront-light ...`. Give the user the `url`.

Without an existing `terraform.tfvars`, the script also runs non-interactively:
`CC_ORGANISATION=orga_xxx OPENFRONT_APP_NAME=<name> OPENFRONT_REGION=par ./scripts/deploy.sh --yes`
(on Windows, set the same variables with `$env:NAME = "value"` and run
`scripts\deploy.ps1 -Yes`).

## Rules

- **Ask before** creating an organisation (it needs the user's billing
  details), before `terraform destroy` / `clever delete`, and before an apply
  that re-creates the application (a `region` change does).
- If `terraform/terraform.tfstate` exists, the app is managed by Terraform:
  change settings in `terraform.tfvars` and apply. Do not use
  `clever env set` on it (the next apply reverts it); use `extra_env`.
- Never commit `terraform.tfvars`, `*.tfstate` or `.clever.json` (they hold IDs
  and secrets; they are git-ignored).
- Always exactly one instance. For more capacity, change the flavor.
- `<name>.cleverapps.io` must be free: if the apply fails on the domain,
  suggest another name.
- After changing an `OPENFRONT_*` variable outside Terraform, rebuild with
  `clever restart --without-cache`.
- Source mode needs a build instance (`build_flavor = "M"`, the default).
- Keep the docs in `docs/` up to date when you change `scripts/` or
  `terraform/`. `scripts/deploy.sh` and `scripts/deploy.ps1` do the same
  thing: change both.
