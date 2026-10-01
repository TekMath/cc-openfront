# Deploy with the script (Terraform)

The easiest way. One command asks you a few questions and creates everything
with [Terraform](https://developer.hashicorp.com/terraform). Run it again
later to apply any change.

## Prerequisites

- A [Clever Cloud](https://console.clever-cloud.com) account.
- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5`.
- [Node.js](https://nodejs.org) (any recent version, only to install Clever
  Tools).
- Git, to clone this repository.

It runs on **macOS and Linux** (`scripts/deploy.sh`, bash) and on
**Windows** (`scripts\deploy.ps1`, PowerShell 5.1 or 7). On Windows,
`winget install Hashicorp.Terraform OpenJS.NodeJS.LTS Git.Git` installs the
three tools (open a new terminal afterwards).

## Deploy

macOS, Linux:

```bash
git clone https://github.com/TekMath/cc-openfront.git
cd cc-openfront
./scripts/deploy.sh
```

Windows (PowerShell):

```powershell
git clone https://github.com/TekMath/cc-openfront.git
cd cc-openfront
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
```

`-ExecutionPolicy Bypass` lets this one script run without changing your
system settings (Windows blocks `.ps1` files by default). If you already
allowed scripts (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`),
`.\scripts\deploy.ps1` is enough.

The script:

1. checks that Terraform and Node.js are installed;
2. installs [Clever Tools](https://www.clever.cloud/developers/doc/cli/)
   (`npm install --global clever-tools`) if the `clever` command is missing,
   or falls back to `npx clever-tools` when the global install is not
   allowed;
3. runs `clever login` if you are not logged in (your browser opens);
4. lists your organisations and lets you pick one, type its name or ID, or
   **create a new one** (Clever Cloud asks for billing details: your name,
   country, address);
5. asks for the **application name** (it is also the address,
   `https://<name>.cleverapps.io`) and the **region**;
6. writes them to `terraform/terraform.tfvars` (git-ignored);
7. runs `terraform init` and `terraform apply`. Terraform shows what it will
   create: type `yes`.

At the end it prints your server's address. The first start takes a minute or
two. Follow it with `clever logs --app <app_id>` (the script prints the
command). Then open the address, click **Create Lobby** and send the link to
your friends.

Terraform creates a **Linux** application running
[the Mise flavour](deploy-mise.md) of cc-openfront: one instance (XS), the
domain, HTTPS redirect and the environment variables. It pushes this
repository (`github.com/TekMath/cc-openfront`, variable
`cc_openfront_repository`) to it.

## Change a setting

Edit `terraform/terraform.tfvars`, then run the script again (or
`terraform -chdir=terraform apply`). When it finds the file, the script asks
"Deploy it as is?": answer `y`. Answer `n` to start over with new questions
(the old file is kept as `terraform.tfvars.<date>.bak`).

Every variable you can add is explained in [configuration.md](configuration.md),
and [`terraform.tfvars.example`](../terraform/terraform.tfvars.example) has
ready-made profiles ("my maps", "my fork", bigger instance, ...). For example,
to pick the maps:

```hcl
organisation      = "orga_xxx"
name              = "my-openfront"
region            = "par"

openfront_build   = "source"
openfront_version = "v1.0.0"
openfront_maps    = "world,europe,iceland"
```

## Options

| Option / variable    | Effect                                                                                  |
| -------------------- | --------------------------------------------------------------------------------------- |
| `--yes`, `-y` (Windows: `-Yes`) | No confirmation: reuses an existing `terraform.tfvars` and runs `terraform apply -auto-approve`. |
| `CC_ORGANISATION`    | Organisation ID (`orga_xxx`, or `user_xxx` for your personal space). Skips the question. |
| `OPENFRONT_APP_NAME` | Application name. Skips the question.                                                   |
| `OPENFRONT_REGION`   | Region (default `par` when the two variables above are set).                            |
| `CLEVER_TOKEN`, `CLEVER_SECRET` | Clever Cloud credentials instead of `clever login` (CI). Passed to Terraform as `CC_OAUTH_TOKEN` / `CC_OAUTH_SECRET`. |

Fully non-interactive (CI, a coding agent):

```bash
CC_ORGANISATION=orga_xxx OPENFRONT_APP_NAME=my-openfront ./scripts/deploy.sh --yes
```

```powershell
$env:CC_ORGANISATION = "orga_xxx"; $env:OPENFRONT_APP_NAME = "my-openfront"
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Yes
```

## Without the script

The script only writes `terraform.tfvars` and calls Terraform. By hand:

```bash
clever login # the Terraform provider reuses these credentials
cd terraform
cp terraform.tfvars.example terraform.tfvars # set organisation and name, pick a profile
terraform init
terraform apply
```

`clever profile` shows your personal space ID (`user_xxx`). Organisation IDs
(`orga_xxx`) are in the Console, or:

```bash
clever curl https://api.clever-cloud.com/v2/organisations
```

Terraform outputs `url` (the address) and `app_id` (for
`clever link <app_id>`, `clever logs`, ...):

```bash
terraform -chdir=terraform output
```

## Delete

```bash
terraform -chdir=terraform destroy
```

Keep `terraform/terraform.tfstate` (git-ignored) from the first `apply` until
the `destroy`: it is how Terraform finds the application again. Without it,
delete the application from the Console or with
`clever delete --app <app_id>`.

## Troubleshooting

- **The domain is taken.** `<name>.cleverapps.io` addresses are shared by
  every Clever Cloud user. Change `name` in `terraform/terraform.tfvars` (or
  set `domain`) and run the script again.
- **"no stable release found".** The application started but openfront-light
  has no release to download yet. Set `openfront_version` to an existing tag,
  or build from source (`openfront_build = "source"`). See
  [configuration.md](configuration.md).
- **The new organisation cannot create applications.** Add a payment method
  (or a coupon) to it in the Console, then run the script again.
- **Creating the organisation fails.** Create it in the
  [Console](https://console.clever-cloud.com), then run the script again and
  pick it.
- **Terraform cannot authenticate.** Run `clever login` again. The provider
  reads `~/.config/clever-cloud/clever-tools.json`
  (`%APPDATA%\clever-cloud\clever-tools.json` on Windows), or
  `CC_OAUTH_TOKEN` / `CC_OAUTH_SECRET`.
- **Windows: "running scripts is disabled on this system".** Start the script
  with `powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1`.
- **Windows: `terraform`, `node` or `clever` "is not recognized".** The
  installer added it to the PATH of new terminals only: open a new one.
- **Anything else.** `clever logs --app <app_id>` shows the build and the
  server. Common cases are in [operations.md](operations.md).
