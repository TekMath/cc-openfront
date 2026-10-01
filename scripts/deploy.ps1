# One-command deploy of cc-openfront on Clever Cloud, for Windows (see
# docs/deploy-script.md). The same script as scripts/deploy.sh, in PowerShell.
#
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1          ask a few questions, then run Terraform
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Yes     same, without Terraform's confirmation
#
# It needs Node.js (for Clever Tools) and Terraform. It installs Clever Tools
# if they are missing, logs you in, lets you pick or create an organisation,
# asks for the application name and region, writes terraform\terraform.tfvars
# and runs `terraform apply`. Run it again to apply changes you made to
# terraform\terraform.tfvars (every setting: docs/configuration.md).
#
# Non-interactive use (CI, agents): set CC_ORGANISATION (orga_xxx or
# user_xxx), OPENFRONT_APP_NAME and optionally OPENFRONT_REGION, and pass
# -Yes. An existing terraform.tfvars is then reused as is.
#
# Written for the Windows PowerShell 5.1 that ships with Windows; also runs on
# PowerShell 7 (pwsh). -Yes/-y/--yes and -Help/-h/--help are all accepted.
param(
	[Alias('y')][switch]$Yes,
	[Alias('h')][switch]$Help,
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$Api = 'https://api.clever-cloud.com'
$Root = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $Root 'terraform'
$TfVars = Join-Path $TfDir 'terraform.tfvars'
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Log([string]$Message) { Write-Host "[cc-openfront] $Message" }
function Write-Warn([string]$Message) { [Console]::Error.WriteLine("[cc-openfront] WARNING: $Message") }
function Stop-Deploy([string]$Message) {
	[Console]::Error.WriteLine("[cc-openfront] ERROR: $Message")
	exit 1
}

function Show-Usage {
	Get-Content -LiteralPath $PSCommandPath -TotalCount 15 | ForEach-Object { $_ -replace '^# ?', '' }
}

foreach ($arg in $Rest) {
	switch ($arg) {
		{ $_ -in '--yes', '-y' } { $Yes = [switch]$true }
		{ $_ -in '--help', '-h' } { $Help = [switch]$true }
		default { Stop-Deploy "unknown option `"$arg`" (see -Help)." }
	}
}
if ($Help) {
	Show-Usage
	exit 0
}
$AutoApprove = [bool]$Yes

# Read-Host "question" [default]: the answer, or the default.
function Read-Answer([string]$Question, [string]$Default = '') {
	$prompt = $Question
	if ($Default) { $prompt = "$prompt [$Default]" }
	$answer = Read-Host $prompt
	if ($answer) { return $answer }
	return $Default
}

function Read-YesNo([string]$Question, [string]$Default) {
	(Read-Answer "$Question (y/n)" $Default) -match '^[yY]'
}

# Run a native command without its output: true when it exits with 0.
# (Windows PowerShell 5.1 turns redirected stderr into errors, which would
# stop the script under ErrorActionPreference = Stop.)
function Test-Quietly([scriptblock]$Block) {
	$saved = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try { & $Block *> $null } catch { return $false } finally { $ErrorActionPreference = $saved }
	return $LASTEXITCODE -eq 0
}

# Node prints UTF-8: decode it as such (organisation names, error messages).
$SavedOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = $Utf8
try {

	# --- 1. Tools ----------------------------------------------------------

	if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
		Stop-Deploy 'Terraform is not installed: https://developer.hashicorp.com/terraform/install (or `winget install Hashicorp.Terraform`).'
	}
	if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
		Stop-Deploy 'Node.js is not installed (it comes with npm): https://nodejs.org (or `winget install OpenJS.NodeJS.LTS`).'
	}

	$CleverCmd = @('clever')
	if (-not (Get-Command clever -ErrorAction SilentlyContinue)) {
		Write-Log 'Clever Tools are not installed: installing them (npm install --global clever-tools).'
		$installed = Test-Quietly { npm install --global --no-audit --no-fund clever-tools }
		if (-not ($installed -and (Get-Command clever -ErrorAction SilentlyContinue))) {
			Write-Warn 'the global install failed (or `clever` is not on the PATH yet): using `npx clever-tools` instead.'
			$CleverCmd = @('npx', '--yes', 'clever-tools@latest')
		}
	}
	function Invoke-Clever {
		$exe = $CleverCmd[0]
		$prefix = @($CleverCmd | Select-Object -Skip 1)
		& $exe @prefix @args
	}

	# --- 2. Login ----------------------------------------------------------

	# Terraform's provider reads the credentials that `clever login` stores
	# (%APPDATA%\clever-cloud\clever-tools.json), or CC_OAUTH_TOKEN/SECRET.
	if ($env:CLEVER_TOKEN -and $env:CLEVER_SECRET) {
		if (-not $env:CC_OAUTH_TOKEN) { $env:CC_OAUTH_TOKEN = $env:CLEVER_TOKEN }
		if (-not $env:CC_OAUTH_SECRET) { $env:CC_OAUTH_SECRET = $env:CLEVER_SECRET }
	}
	if (-not (Test-Quietly { Invoke-Clever profile })) {
		Write-Log 'Logging in to Clever Cloud: your browser opens, come back here once it says you are logged in.'
		Invoke-Clever login
		if (-not (Test-Quietly { Invoke-Clever profile })) {
			Stop-Deploy 'still not logged in. Run `clever login`, then this script again.'
		}
	}

	# Invoke-Api METHOD PATH [JSON]: call the Clever Cloud API with the CLI
	# credentials. Returns @{ Ok; Status; Body }. (`clever curl` does not pass
	# curl's exit code through, hence the status code at the end.) The body
	# goes through a file: Windows PowerShell 5.1 drops the double quotes of
	# JSON passed as a native command argument.
	function Invoke-Api([string]$Method, [string]$Path, [string]$Json) {
		$curlArgs = @('-sS', '-X', $Method, '-w', '\n%{http_code}')
		$bodyFile = $null
		if ($Json) {
			$bodyFile = [System.IO.Path]::GetTempFileName()
			[System.IO.File]::WriteAllText($bodyFile, $Json, $Utf8)
			$curlArgs += @('-H', 'Content-Type: application/json', '--data-binary', "@$bodyFile")
		}
		try {
			$lines = @(Invoke-Clever curl @curlArgs "$Api$Path")
		} catch {
			$lines = @()
		} finally {
			if ($bodyFile) { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }
		}
		$status = ''
		$body = ''
		if ($lines.Count -gt 0) {
			$status = "$($lines[-1])".Trim()
			if ($lines.Count -gt 1) { $body = ($lines[0..($lines.Count - 2)] -join "`n") }
		}
		return @{ Ok = ($status -match '^2'); Status = $status; Body = $body }
	}

	# --- 3. Existing configuration -----------------------------------------

	$reuseTfVars = $false
	if (Test-Path -LiteralPath $TfVars) {
		if ($AutoApprove -or (Read-YesNo 'terraform\terraform.tfvars already exists. Deploy it as is?' 'y')) {
			$reuseTfVars = $true
		} else {
			$backup = "$TfVars.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
			Move-Item -LiteralPath $TfVars -Destination $backup
			Write-Log "moved the old file to terraform\$(Split-Path -Leaf $backup)"
		}
	}

	if (-not $reuseTfVars) {
		# --- 4. Organisation -----------------------------------------------

		$orgId = "$env:CC_ORGANISATION"
		if (-not $orgId) {
			$r = Invoke-Api GET /v2/organisations
			if (-not $r.Ok) { Stop-Deploy "cannot list your organisations (HTTP $($r.Status)): $($r.Body)" }
			$orgs = New-Object System.Collections.ArrayList
			foreach ($o in (ConvertFrom-Json -InputObject $r.Body)) { [void]$orgs.Add($o) }

			Write-Host ''
			Write-Host 'Which Clever Cloud organisation should own the server?'
			for ($i = 0; $i -lt $orgs.Count; $i++) {
				Write-Host ('  {0}) {1} ({2})' -f ($i + 1), $orgs[$i].name, $orgs[$i].id)
			}
			Write-Host '  n) Create a new organisation'
			Write-Host 'You can also type an organisation name or ID.'

			while (-not $orgId) {
				$choice = Read-Answer 'Choice' '1'
				$n = 0
				if ($choice -eq 'n') {
					# -eq on strings ignores case: "N" works too.
					$orgId = 'new'
				} elseif ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $orgs.Count) {
					$orgId = $orgs[$n - 1].id
				} else {
					foreach ($o in $orgs) {
						if ($o.name -eq $choice -or $o.id -ceq $choice) { $orgId = $o.id }
					}
					if (-not $orgId) { Write-Host "No organisation matches `"$choice`"." }
				}
			}

			if ($orgId -eq 'new') {
				Write-Host ''
				Write-Host 'Clever Cloud asks for billing details to create an organisation.'
				$orgName = ''
				$orgFullName = ''
				while (-not $orgName) { $orgName = Read-Answer 'Organisation name' }
				while (-not $orgFullName) { $orgFullName = Read-Answer 'Your full name (for invoices)' }
				$orgCountry = Read-Answer 'Country code (2 letters)' 'FR'
				$orgAddress = Read-Answer 'Street address'
				$orgCity = Read-Answer 'City'
				$orgZipcode = Read-Answer 'Zip code'
				$payload = [ordered]@{
					name             = $orgName
					description      = 'OpenFront private server (cc-openfront)'
					customerFullName = $orgFullName
					country          = $orgCountry.ToUpper()
					address          = $orgAddress
					city             = $orgCity
					zipcode          = $orgZipcode
					contacts         = @()
				}
				$self = Invoke-Api GET /v2/self
				if ($self.Ok) {
					$email = (ConvertFrom-Json -InputObject $self.Body).email
					if ($email) { $payload.billingEmail = $email }
				}
				$r = Invoke-Api POST /v2/organisations ($payload | ConvertTo-Json -Compress)
				if (-not $r.Ok) {
					Stop-Deploy "Clever Cloud refused to create the organisation (HTTP $($r.Status)): $($r.Body)
Create it in the Console (https://console.clever-cloud.com), then run this script again and pick it."
				}
				$orgId = (ConvertFrom-Json -InputObject $r.Body).id
				Write-Log "organisation `"$orgName`" created: $orgId"
			}
		}
		if ($orgId -cnotmatch '^(orga|user)_') {
			Stop-Deploy "`"$orgId`" is not an organisation ID (orga_xxx, or user_xxx for your personal space)."
		}

		# --- 5. Application ------------------------------------------------

		$appName = "$env:OPENFRONT_APP_NAME"
		if (-not $appName) {
			Write-Host ''
			Write-Host 'The application name is also its address: https://<name>.cleverapps.io.'
			Write-Host 'Those addresses are shared by every Clever Cloud user: pick one nobody took.'
			$suggestion = 'openfront-{0:x4}' -f (Get-Random -Maximum 65536)
			while ($true) {
				$appName = Read-Answer 'Application name' $suggestion
				if ($appName -cmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$') { break }
				Write-Host 'Use lowercase letters, digits and hyphens only (not at the start or the end).'
			}
		}

		$region = "$env:OPENFRONT_REGION"
		if (-not $region -and $env:CC_ORGANISATION -and $env:OPENFRONT_APP_NAME) {
			$region = 'par' # non-interactive run
		} elseif (-not $region) {
			Write-Host ''
			Write-Host 'Region, close to your players: par (Paris), rbx (Roubaix), ldn (London),'
			Write-Host 'wsw (Warsaw), mtl (Montreal), sgp (Singapore), syd (Sydney).'
			$region = Read-Answer 'Region' 'par'
		}

		# UTF-8 without a BOM and LF line endings, like scripts/deploy.sh.
		$content = @(
			"# Written by scripts/deploy.ps1 on $(Get-Date -Format 'yyyy-MM-dd'). Git-ignored: it holds your"
			'# organisation ID. Add any other setting from terraform.tfvars.example'
			'# (every variable is explained in docs/configuration.md), then run the'
			'# deploy script again to apply it (scripts\deploy.ps1, or scripts/deploy.sh).'
			''
			"organisation = `"$orgId`""
			"name         = `"$appName`""
			"region       = `"$region`""
			''
		) -join "`n"
		[System.IO.File]::WriteAllText($TfVars, $content, $Utf8)
		Write-Log 'wrote terraform\terraform.tfvars'
	}

	# --- 6. Terraform --------------------------------------------------------

	Write-Host ''
	Write-Log 'terraform init'
	terraform "-chdir=$TfDir" init -input=false | Out-Null
	if ($LASTEXITCODE -ne 0) { Stop-Deploy 'terraform init failed (see the error above).' }

	$applyArgs = @('-input=false')
	if ($AutoApprove) { $applyArgs += '-auto-approve' }
	Write-Log 'terraform apply (type "yes" to create or update the application)'
	terraform "-chdir=$TfDir" apply @applyArgs
	if ($LASTEXITCODE -ne 0) {
		Stop-Deploy 'terraform apply failed. If the error is about the domain, the name is taken: edit `name` in terraform\terraform.tfvars and run this script again. More in docs/deploy-script.md#troubleshooting.'
	}

	$url = (terraform "-chdir=$TfDir" output -raw url) -join ''
	$appId = (terraform "-chdir=$TfDir" output -raw app_id) -join ''
	Write-Host @"

[cc-openfront] Done. Your server: $url
  The first start takes a minute or two. Follow it with:
    clever logs --app $appId
  Then click "Create Lobby" and send the link to your friends.
  Change a setting: edit terraform\terraform.tfvars, run scripts\deploy.ps1 again.
  Delete everything: terraform -chdir=terraform destroy
"@
} finally {
	[Console]::OutputEncoding = $SavedOutputEncoding
}
