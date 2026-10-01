# Credentials: run `clever login` once; the provider reads the OAuth tokens
# from the clever-tools configuration (or CC_OAUTH_TOKEN / CC_OAUTH_SECRET).
provider "clevercloud" {
  organisation = var.organisation
}

locals {
  domain       = coalesce(var.domain, "${var.name}.cleverapps.io")
  source_build = var.openfront_build == "source"

  # The variables cc-openfront reads (see docs/configuration.md). Unset ones are dropped:
  # the provider refuses null values, and the scripts have their own defaults.
  managed_env = {
    for k, v in {
      DOMAIN            = local.domain
      OPENFRONT_BUILD   = var.openfront_build
      OPENFRONT_VERSION = var.openfront_version
      OPENFRONT_REPO    = var.openfront_repo
      OPENFRONT_MAPS    = var.openfront_maps
      NUM_WORKERS       = var.num_workers == null ? null : tostring(var.num_workers)
    } : k => v if v != null && v != ""
  }
  managed_keys = ["DOMAIN", "OPENFRONT_BUILD", "OPENFRONT_VERSION", "OPENFRONT_REPO", "OPENFRONT_MAPS", "NUM_WORKERS"]
}

resource "clevercloud_linux" "openfront" {
  name        = var.name
  description = "openfront-light private server (cc-openfront)"
  region      = var.region

  # Always exactly one instance. Lobbies and running games live in the memory
  # of this one process tree, so a second instance would split players
  # between two servers that do not know each other's games (and a scale-down
  # would drop games). Grow the instance (flavor) instead.
  min_instance_count = 1
  max_instance_count = 1
  smallest_flavor    = var.flavor
  biggest_flavor     = var.flavor

  # A source build needs ~4 GB (measured), more than the run instance: build
  # on a dedicated instance, only then. Null turns the build instance off
  # again when going back to release mode.
  build_flavor = local.source_build ? var.build_flavor : null

  vhosts         = [{ fqdn = local.domain }]
  redirect_https = true

  environment = merge(var.extra_env, local.managed_env)

  # Terraform pushes the HEAD of this repository on create, and again on any
  # apply that changes the application. The build and run commands come from
  # its mise.toml (tasks `build` and `run`).
  deployment {
    repository = var.cc_openfront_repository
  }

  lifecycle {
    precondition {
      condition     = var.openfront_maps == null || var.openfront_maps == "" || local.source_build
      error_message = "openfront_maps only applies to openfront_build = \"source\": a release tarball has its maps built in."
    }
    precondition {
      condition     = length(setintersection(keys(var.extra_env), local.managed_keys)) == 0
      error_message = "extra_env cannot set DOMAIN, OPENFRONT_BUILD, OPENFRONT_VERSION, OPENFRONT_REPO, OPENFRONT_MAPS or NUM_WORKERS: use the dedicated variables."
    }
  }
}
