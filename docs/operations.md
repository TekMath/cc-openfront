# Operations: update, roll back, logs, delete

The commands below use the `clever` CLI. Run them in a folder linked to the
application (`clever link <app_id>`), or add `--app <app_id or name>`. With
Terraform, `terraform -chdir=terraform output app_id` prints the ID.

## Logs and status

```bash
clever logs            # build and server logs, live
clever status
clever activity        # last deployments
```

A healthy start ends with
`[cc-openfront] starting openfront-light <version> for <domain> on port 8080`.

## Update or roll back

Change `OPENFRONT_VERSION` (or another `OPENFRONT_*` variable), then rebuild
**without the build cache**:

```bash
clever env set OPENFRONT_VERSION v1.1.0
clever restart --without-cache
```

In the Console, that is **Re-build and restart**. With the script or
Terraform, change `openfront_version` in `terraform/terraform.tfvars` and run
`./scripts/deploy.sh` (Windows: `scripts\deploy.ps1`) or `terraform apply`.

A plain restart reuses the previous build, and so does Terraform. To cover
that:

- in **release** mode, the `run` step notices the new settings and downloads
  the new release itself, so `terraform apply` alone is enough;
- in **source** mode, the `run` step refuses to start the old build, so the
  deployment fails with a message telling you to run
  `clever restart --without-cache`. With the **Zero downtime deployment**
  option on (Console, **Information**), the previous instance keeps serving
  until then.

Rolling back is the same with an older version. Games in progress are cut
while the new instance takes over: update between games.

`OPENFRONT_VERSION` unset means "the latest release when it was built": a new
release is only picked up by a rebuild without cache. Pin a version to know
what runs.

## Update cc-openfront itself

Terraform pushes the cc-openfront repository again on any `apply` that
changes the application. To force it, or with the CLI:

```bash
git pull
clever deploy   # Mise + CLI deployment
```

## Bigger or smaller server

```bash
clever scale --flavor S      # XS, S, M, ... always with --instances 1
```

With Terraform: `flavor = "S"`. See
[configuration.md](configuration.md#recipes).

## Common errors

| Log message                                        | Fix                                                                                                             |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `DOMAIN is not set`                                | `clever env set DOMAIN <host>` (Terraform sets it).                                                             |
| `no stable release found at .../releases/latest`   | The repository has no release yet: set `OPENFRONT_VERSION` to a tag that has a tarball, or use source mode.     |
| `cannot download .../openfront-light-<tag>.tar.gz` | That tag has no tarball (older releases): pick another tag or use source mode.                                  |
| `OPENFRONT_MAPS only applies to OPENFRONT_BUILD=source` | Unset `OPENFRONT_MAPS`, or switch to source mode.                                                          |
| `a source build cannot run here`                   | `clever restart --without-cache`.                                                                               |
| Build killed / out of memory in source mode        | `clever scale --build-flavor M` (Terraform: `build_flavor = "M"`).                                              |
| `has no deploy/defaults.env`                       | The version is too old for cc-openfront: pick a newer tag or branch.                                            |

## Delete

With the script or Terraform:

```bash
terraform -chdir=terraform destroy
```

Otherwise:

```bash
clever delete --app <app_id or name>
```

Keep `terraform/terraform.tfstate` until the `destroy`: without it, Terraform
cannot find the application, and you delete it from the Console or with
`clever delete`.
