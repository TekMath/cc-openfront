#!/usr/bin/env bash
# One-command deploy of cc-openfront on Clever Cloud (see docs/deploy-script.md).
#
#   ./scripts/deploy.sh          ask a few questions, then run Terraform
#   ./scripts/deploy.sh --yes    same, without Terraform's confirmation
#
# It needs Node.js (for Clever Tools) and Terraform. It installs Clever Tools
# if they are missing, logs you in, lets you pick or create an organisation,
# asks for the application name and region, writes terraform/terraform.tfvars
# and runs `terraform apply`. Run it again to apply changes you made to
# terraform/terraform.tfvars (every setting: docs/configuration.md).
#
# Non-interactive use (CI, agents): set CC_ORGANISATION (orga_xxx or
# user_xxx), OPENFRONT_APP_NAME and optionally OPENFRONT_REGION, and pass
# --yes. An existing terraform.tfvars is then reused as is.
#
# Runs on macOS and Linux. Written for the bash 3.2 that ships with macOS (no
# mapfile, no ${var,,}) and for BSD and GNU tools alike. On Windows, use
# scripts/deploy.ps1.
set -euo pipefail

readonly API="https://api.clever-cloud.com"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="$root/terraform"
tfvars="$tf_dir/terraform.tfvars"

log() { echo "[cc-openfront] $*"; }
warn() { echo "[cc-openfront] WARNING: $*" >&2; }
die() {
	echo "[cc-openfront] ERROR: $*" >&2
	exit 1
}

usage() {
	sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

auto_approve=false
while (($#)); do
	case "$1" in
	-y | --yes) auto_approve=true ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option \"$1\" (see --help)." ;;
	esac
	shift
done

# ask VAR "question" [default]: read an answer into VAR, or the default.
ask() {
	local __answer __prompt="$2"
	if [[ -n "${3:-}" ]]; then
		__prompt="$__prompt [$3]"
	fi
	read -r -p "$__prompt: " __answer || die "no answer (stdin closed). For a non-interactive run, see --help."
	printf -v "$1" '%s' "${__answer:-${3:-}}"
}

# yes_no "question" default(y|n): succeeds on yes.
yes_no() {
	local answer
	ask answer "$1 (y/n)" "$2"
	[[ "$answer" == [yY]* ]]
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- 1. Tools --------------------------------------------------------------

command -v terraform >/dev/null ||
	die "Terraform is not installed: https://developer.hashicorp.com/terraform/install"
command -v node >/dev/null && command -v npm >/dev/null ||
	die "Node.js is not installed (it comes with npm): https://nodejs.org"

if command -v clever >/dev/null; then
	clever_cmd=(clever)
else
	log "Clever Tools are not installed: installing them (npm install --global clever-tools)."
	if npm install --global --no-audit --no-fund clever-tools >/dev/null && command -v clever >/dev/null; then
		clever_cmd=(clever)
	else
		warn "the global install failed (permissions?): using \`npx clever-tools\` instead."
		clever_cmd=(npx --yes clever-tools@latest)
	fi
fi
clever_tools() { "${clever_cmd[@]}" "$@"; }

# --- 2. Login --------------------------------------------------------------

# Terraform's provider reads the credentials that `clever login` stores
# (~/.config/clever-cloud/clever-tools.json), or CC_OAUTH_TOKEN/SECRET.
if [[ -n "${CLEVER_TOKEN:-}" && -n "${CLEVER_SECRET:-}" ]]; then
	export CC_OAUTH_TOKEN="${CC_OAUTH_TOKEN:-$CLEVER_TOKEN}"
	export CC_OAUTH_SECRET="${CC_OAUTH_SECRET:-$CLEVER_SECRET}"
fi
if ! clever_tools profile >/dev/null 2>&1; then
	log "Logging in to Clever Cloud: your browser opens, come back here once it says you are logged in."
	clever_tools login
	clever_tools profile >/dev/null 2>&1 || die "still not logged in. Run \`clever login\`, then this script again."
fi

# api METHOD PATH [JSON]: call the Clever Cloud API with the CLI credentials.
# Sets api_status and api_body; succeeds on a 2xx. (`clever curl` does not
# pass curl's exit code through, hence the status code at the end.)
api() {
	local out
	local args=(-sS -X "$1" -w '\n%{http_code}')
	if (($# >= 3)); then
		args+=(-H 'Content-Type: application/json' --data "$3")
	fi
	out="$(clever_tools curl "${args[@]}" "$API$2")" || true
	api_status="${out##*$'\n'}"
	api_body="${out%$'\n'*}"
	[[ "$api_status" == 2* ]]
}

# json EXPR: evaluate EXPR on the JSON read from stdin (bound to `d`).
json() {
	node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const d=JSON.parse(s);const r=('"$1"');if(r!==undefined)console.log(r)})'
}

# --- 3. Existing configuration ---------------------------------------------

reuse_tfvars=false
if [[ -f "$tfvars" ]]; then
	if $auto_approve || yes_no "terraform/terraform.tfvars already exists. Deploy it as is?" y; then
		reuse_tfvars=true
	else
		backup="$tfvars.$(date +%Y%m%d-%H%M%S).bak"
		mv "$tfvars" "$backup"
		log "moved the old file to ${backup#"$root"/}"
	fi
fi

if ! $reuse_tfvars; then
	# --- 4. Organisation ---------------------------------------------------

	org_id="${CC_ORGANISATION:-}"
	if [[ -z "$org_id" ]]; then
		api GET /v2/organisations || die "cannot list your organisations (HTTP $api_status): $api_body"
		org_lines="$(printf '%s' "$api_body" | json 'd.map(o => o.id + "\t" + o.name).join("\n")')"
		org_ids=()
		org_names=()
		while IFS=$'\t' read -r id name; do
			[[ -n "$id" ]] || continue
			org_ids+=("$id")
			org_names+=("$name")
		done <<<"$org_lines"

		echo
		echo "Which Clever Cloud organisation should own the server?"
		for i in "${!org_ids[@]}"; do
			printf '  %d) %s (%s)\n' "$((i + 1))" "${org_names[$i]}" "${org_ids[$i]}"
		done
		echo "  n) Create a new organisation"
		echo "You can also type an organisation name or ID."

		while [[ -z "$org_id" ]]; do
			ask choice "Choice" 1
			if [[ "$(lower "$choice")" == n ]]; then
				org_id=new
			elif [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#org_ids[@]})); then
				org_id="${org_ids[$((choice - 1))]}"
			else
				for i in "${!org_ids[@]}"; do
					if [[ "$(lower "${org_names[$i]}")" == "$(lower "$choice")" || "${org_ids[$i]}" == "$choice" ]]; then
						org_id="${org_ids[$i]}"
					fi
				done
				[[ -n "$org_id" ]] || echo "No organisation matches \"$choice\"."
			fi
		done

		if [[ "$org_id" == new ]]; then
			echo
			echo "Clever Cloud asks for billing details to create an organisation."
			ORG_NAME="" ORG_FULLNAME=""
			while [[ -z "$ORG_NAME" ]]; do ask ORG_NAME "Organisation name"; done
			while [[ -z "$ORG_FULLNAME" ]]; do ask ORG_FULLNAME "Your full name (for invoices)"; done
			ask ORG_COUNTRY "Country code (2 letters)" FR
			ask ORG_ADDRESS "Street address"
			ask ORG_CITY "City"
			ask ORG_ZIPCODE "Zip code"
			ORG_EMAIL=""
			if api GET /v2/self; then
				ORG_EMAIL="$(printf '%s' "$api_body" | json 'd.email || ""')"
			fi
			body="$(
				ORG_NAME="$ORG_NAME" ORG_FULLNAME="$ORG_FULLNAME" ORG_COUNTRY="$ORG_COUNTRY" \
					ORG_ADDRESS="$ORG_ADDRESS" ORG_CITY="$ORG_CITY" ORG_ZIPCODE="$ORG_ZIPCODE" ORG_EMAIL="$ORG_EMAIL" \
					node -e 'const e = process.env; console.log(JSON.stringify({
						name: e.ORG_NAME,
						description: "OpenFront private server (cc-openfront)",
						customerFullName: e.ORG_FULLNAME,
						country: e.ORG_COUNTRY.toUpperCase(),
						address: e.ORG_ADDRESS,
						city: e.ORG_CITY,
						zipcode: e.ORG_ZIPCODE,
						billingEmail: e.ORG_EMAIL || undefined,
						contacts: [],
					}))'
			)"
			api POST /v2/organisations "$body" ||
				die "Clever Cloud refused to create the organisation (HTTP $api_status): $api_body
Create it in the Console (https://console.clever-cloud.com), then run this script again and pick it."
			org_id="$(printf '%s' "$api_body" | json 'd.id')"
			log "organisation \"$ORG_NAME\" created: $org_id"
		fi
	fi
	[[ "$org_id" == orga_* || "$org_id" == user_* ]] ||
		die "\"$org_id\" is not an organisation ID (orga_xxx, or user_xxx for your personal space)."

	# --- 5. Application ----------------------------------------------------

	app_name="${OPENFRONT_APP_NAME:-}"
	if [[ -z "$app_name" ]]; then
		echo
		echo "The application name is also its address: https://<name>.cleverapps.io."
		echo "Those addresses are shared by every Clever Cloud user: pick one nobody took."
		suggestion="openfront-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
		while :; do
			ask app_name "Application name" "$suggestion"
			[[ "$app_name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && break
			echo "Use lowercase letters, digits and hyphens only (not at the start or the end)."
		done
	fi

	region="${OPENFRONT_REGION:-}"
	if [[ -z "$region" && -n "${CC_ORGANISATION:-}" && -n "${OPENFRONT_APP_NAME:-}" ]]; then
		region=par # non-interactive run
	elif [[ -z "$region" ]]; then
		echo
		echo "Region, close to your players: par (Paris), rbx (Roubaix), ldn (London),"
		echo "wsw (Warsaw), mtl (Montreal), sgp (Singapore), syd (Sydney)."
		ask region "Region" par
	fi

	cat >"$tfvars" <<EOF
# Written by scripts/deploy.sh on $(date +%Y-%m-%d). Git-ignored: it holds your
# organisation ID. Add any other setting from terraform.tfvars.example
# (every variable is explained in docs/configuration.md), then run the
# deploy script again to apply it (scripts/deploy.sh, or scripts\\deploy.ps1).

organisation = "$org_id"
name         = "$app_name"
region       = "$region"
EOF
	log "wrote terraform/terraform.tfvars"
fi

# --- 6. Terraform ------------------------------------------------------------

echo
log "terraform init"
terraform -chdir="$tf_dir" init -input=false >/dev/null

apply_args=(-input=false)
if $auto_approve; then
	apply_args+=(-auto-approve)
fi
log "terraform apply (type \"yes\" to create or update the application)"
if ! terraform -chdir="$tf_dir" apply "${apply_args[@]}"; then
	die "terraform apply failed. If the error is about the domain, the name is taken: edit \`name\` in terraform/terraform.tfvars and run this script again. More in docs/deploy-script.md#troubleshooting."
fi

url="$(terraform -chdir="$tf_dir" output -raw url)"
app_id="$(terraform -chdir="$tf_dir" output -raw app_id)"
cat <<EOF

[cc-openfront] Done. Your server: $url
  The first start takes a minute or two. Follow it with:
    clever logs --app $app_id
  Then click "Create Lobby" and send the link to your friends.
  Change a setting: edit terraform/terraform.tfvars, run ./scripts/deploy.sh.
  Delete everything: terraform -chdir=terraform destroy
EOF
