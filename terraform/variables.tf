variable "organisation" {
  description = "Clever Cloud organisation that owns the application: orga_xxx, or user_xxx for your personal space. Null reads CC_ORGANISATION."
  type        = string
  default     = null
}

variable "name" {
  description = "Application name. Also the default domain: <name>.cleverapps.io."
  type        = string
  default     = "openfront"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "Use lowercase letters, digits and hyphens only, so that <name>.cleverapps.io is a valid host name."
  }
}

variable "region" {
  description = "Clever Cloud region (par, rbx, mtl, sgp, ...). Changing it re-creates the application."
  type        = string
  default     = "par"
}

variable "domain" {
  description = "Host name players use. Null uses <name>.cleverapps.io. For your own domain, also point its DNS at Clever Cloud (see their domain docs)."
  type        = string
  default     = null
}

variable "flavor" {
  description = "Instance size that runs the server (S = 2 CPU, 2 GB: enough for a few games)."
  type        = string
  default     = "S"
}

variable "build_flavor" {
  description = "Size of the dedicated build instance, used only when openfront_build = \"source\". The source build needs about 4 GB (M)."
  type        = string
  default     = "M"
}

variable "openfront_version" {
  description = "openfront-light tag (or, in source mode, branch) to deploy. Null deploys the latest stable release."
  type        = string
  default     = null
}

variable "openfront_build" {
  description = "\"release\" downloads the prebuilt tarball; \"source\" clones and builds openfront_repo (custom maps, forks)."
  type        = string
  default     = "release"

  validation {
    condition     = contains(["release", "source"], var.openfront_build)
    error_message = "openfront_build must be \"release\" or \"source\"."
  }
}

variable "openfront_repo" {
  description = "openfront-light repository (or your fork) to download releases from or to build."
  type        = string
  default     = "https://github.com/TekMath/openfront-light"
}

variable "openfront_maps" {
  description = "Comma-separated map folder names from resources/maps/ (e.g. \"world,europe\"). Source mode only; null embeds every map (~600 MB)."
  type        = string
  default     = null
}

variable "num_workers" {
  description = "Game worker processes. Null keeps openfront-light's default (1). Only change it while no game is running."
  type        = number
  default     = null
}

variable "extra_env" {
  description = "Any other environment variable for the application (NODE_OPTIONS, ADMIN_BOT_API_KEY, ...). Cannot override the ones managed by the variables above."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "cc_openfront_repository" {
  description = "Git repository of cc-openfront that Terraform pushes to the application (its HEAD)."
  type        = string
  default     = "https://github.com/TekMath/cc-openfront.git"
}
