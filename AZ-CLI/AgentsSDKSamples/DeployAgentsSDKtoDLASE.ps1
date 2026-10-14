# ============================================================
# Script: Deploys the .NET Agents SDK NamedPipeAgent sample with
#         Direct Line App Service Extension (DL ASE)
# ============================================================
#
# Summary:
# - Creates a resource group, Windows App Service plan, and Web App
# - Creates an Entra application and Azure Bot registration
# - Enables Direct Line and configures the App Service extension
# - Clones microsoft/Agents-for-net and builds src/samples/NamedPipeAgent
# - Configures the pipe name expected by DL ASE: <site>.directline
# - Adds a test-only Web Chat page that asks for the Direct Line secret at runtime
# - Deploys the sample and verifies the /.bot extension health endpoint
#
# The NamedPipeAgent is pipe-only. It does not expose /api/messages and does not
# require Bot Service authentication settings in the agent process. DL ASE handles
# external authentication and relays activities over the named pipe.
#
# Sample: https://github.com/microsoft/Agents-for-net/tree/main/src/samples/NamedPipeAgent
#
# Prerequisites:
# - PowerShell 7+
# - Azure CLI with the botservice extension
# - Git (optional; the script downloads the GitHub archive when Git is unavailable)
# - .NET 10 SDK (the current NamedPipeAgent target framework)
# - Access to the configured internal Azure Artifacts NuGet feed
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# 0) Fixed parameters. Edit the subscription and suffix before running.
# ============================================================
#$SubscriptionId = "xxxxxx-xxxxxxxx-xxxxxxxxxxxxxx"
$SubscriptionId = "83454b68-9b7f-41a7-b08e-936b629f865b"
$RG              = "AgentsDLASEResourceGroup"
$Location        = "southindia"
$BotLocation     = "global"
$Suffix          = "123"

  #Query quota for the selected location and plan SKU before creating resources
  # az appservice list-locations --sku B1 
  #Assert-LastExitCode "Querying App Service quota for location '$Location'"

$PlanName        = "agents-dlase-plan" + $Suffix
$PlanSku         = "B1"
$WebAppName      = "agentsdlaseapp" + $Suffix
$Runtime         = "DOTNET:10"
$BotName         = "agents-dlase-bot" + $Suffix
$AppRegName      = "agents-dlase-aad" + $Suffix

$RepoUrl         = "https://github.com/microsoft/Agents-for-net.git"
$RepoFolder      = "Agents-for-net"
$NuGetSource     = "https://pkgs.dev.azure.com/dynamicscrm/OneCRM/_packaging/DPX-Tools-Upstream/nuget/v3/index.json"
$SafeDelay       = 10

function Assert-LastExitCode {
  param([Parameter(Mandatory = $true)][string]$Operation)

  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE."
  }
}

function ConvertFrom-DlAseHealthResponse {
  param([Parameter(Mandatory = $true)][object]$Response)

  if ($Response -isnot [string]) {
    return $Response
  }

  $JsonMatch = [regex]::Match($Response, '\{.*?\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $JsonMatch.Success) {
    throw "DL ASE health response did not contain a JSON object."
  }

  return $JsonMatch.Value | ConvertFrom-Json
}

foreach ($CommandName in @("az", "dotnet")) {
  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    throw "Required command '$CommandName' was not found on PATH."
  }
}

$GitCommand = Get-Command "git" -ErrorAction SilentlyContinue

# ============================================================
# 1) Sign in and select the subscription
# ============================================================
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
  # Prevent Azure CLI's login experience from asking the user to select a
  # subscription. The configured SubscriptionId is selected immediately below.
  $env:AZURE_CORE_LOGIN_EXPERIENCE_V2 = "off"
  az login --output none
  Assert-LastExitCode "Azure sign-in"
}

az account set --subscription $SubscriptionId
Assert-LastExitCode "Selecting Azure subscription"

# ============================================================
# 2) Create the resource group and Windows App Service
# ============================================================
az group create `
  --name $RG `
  --location $Location `
  --output none
Assert-LastExitCode "Creating resource group"

az appservice plan create `
  --resource-group $RG `
  --name $PlanName `
  --location $Location `
  --sku $PlanSku `
  --is-linux false `
  --output none
Assert-LastExitCode "Creating App Service plan with SKU '$PlanSku' in '$Location'. Check the regional App Service quota or choose another SKU/region"

$PlanUsesLinuxWorkers = az appservice plan show `
  --resource-group $RG `
  --name $PlanName `
  --query reserved `
  --output tsv
Assert-LastExitCode "Verifying App Service plan operating system"

if ($PlanUsesLinuxWorkers -eq "true") {
  throw "App Service plan '$PlanName' already exists as a Linux plan and cannot be converted to Windows. Delete the unused Linux plan or change PlanName, then rerun the script."
}

az webapp create `
  --resource-group $RG `
  --name $WebAppName `
  --plan $PlanName `
  --runtime $Runtime `
  --output none
Assert-LastExitCode "Creating Web App"

$SupportsAlwaysOn = $PlanSku.ToUpperInvariant() -notin @("F1", "FREE", "D1", "SHARED")

az webapp config set `
  --resource-group $RG `
  --name $WebAppName `
  --web-sockets-enabled true `
  --always-on $SupportsAlwaysOn.ToString().ToLowerInvariant() `
  --output none
Assert-LastExitCode "Enabling WebSockets and Always On"

if (-not $SupportsAlwaysOn) {
  Write-Warning "SKU '$PlanSku' does not support Always On. The agent can idle and disconnect from DL ASE."
}

$WebAppUrl = "https://$WebAppName.azurewebsites.net"

# ============================================================
# 3) Create the Entra application and Azure Bot registration
# ============================================================
# NamedPipeAgent does not use this identity directly. Azure Bot registration
# still requires an application ID.
$ExistingAppsJson = az ad app list `
  --display-name $AppRegName `
  --query "[?displayName == '$AppRegName']" `
  --output json
Assert-LastExitCode "Checking for an existing Entra application"
$ExistingApps = @($ExistingAppsJson | ConvertFrom-Json)

if ($ExistingApps.Count -gt 0) {
  $AppId = $ExistingApps[0].appId
  Write-Host "Reusing Entra application '$AppRegName' ($AppId)."
  if ($ExistingApps.Count -gt 1) {
    Write-Warning "Multiple Entra applications named '$AppRegName' exist. Reusing the first application returned by Azure CLI."
  }
} else {
  $App = az ad app create --display-name $AppRegName --output json | ConvertFrom-Json
  Assert-LastExitCode "Creating Entra application"
  $AppId = $App.appId
}

az ad sp show --id $AppId --output none 2>$null
if ($LASTEXITCODE -ne 0) {
  az ad sp create --id $AppId --output none
  Assert-LastExitCode "Creating service principal"
}

$TenantId = (az account show --query tenantId --output tsv)
Assert-LastExitCode "Reading tenant ID"

# Azure Bot requires an endpoint value, but pipe-only traffic is delivered through
# DL ASE and does not use this /api/messages URL.
$BotEndpoint = "$WebAppUrl/api/messages"

az bot create `
  --resource-group $RG `
  --name $BotName `
  --location $BotLocation `
  --appid $AppId `
  --app-type SingleTenant `
  --tenant-id $TenantId `
  --endpoint $BotEndpoint `
  --sku S1 `
  --output none
Assert-LastExitCode "Creating Azure Bot registration"

$BotResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$RG/providers/Microsoft.BotService/botServices/$BotName"

# ============================================================
# 4) Enable Direct Line and obtain the DL ASE extension key
# ============================================================
$DLExtensionKey = az bot directline show `
  --name $BotName `
  --resource-group $RG `
  --with-secrets true `
  --query "properties.properties.extensionKey1" `
  --output tsv 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($DLExtensionKey)) {
  Write-Host "Direct Line is not enabled. Creating the channel..."
  az bot directline create `
    --name $BotName `
    --resource-group $RG `
    --output none
  Assert-LastExitCode "Creating Direct Line channel"

  $DLExtensionKey = az bot directline show `
    --name $BotName `
    --resource-group $RG `
    --with-secrets true `
    --query "properties.properties.extensionKey1" `
    --output tsv
  Assert-LastExitCode "Reading Direct Line extension key"
}

if ([string]::IsNullOrWhiteSpace($DLExtensionKey)) {
  throw "Direct Line did not return an extension key."
}

az webapp config appsettings set `
  --resource-group $RG `
  --name $WebAppName `
  --settings `
  "DirectLineExtensionKey=$DLExtensionKey" `
  "DIRECTLINE_EXTENSION_VERSION=latest" `
  "ASPNETCORE_ENVIRONMENT=Production" `
  "Logging__LogLevel__Default=Information" `
  "Logging__LogLevel__Microsoft.AspNetCore=Warning" `
  --output none
Assert-LastExitCode "Configuring DL ASE application settings"

# ============================================================
# 5) Clone or update Agents-for-net
# ============================================================
$OriginalWorkingDirectory = (Get-Location).Path
$LocalRepo = Join-Path $OriginalWorkingDirectory $RepoFolder

if ((Test-Path $LocalRepo) -and $GitCommand -and (Test-Path (Join-Path $LocalRepo ".git"))) {
  git -C $LocalRepo pull --ff-only
  Assert-LastExitCode "Updating Agents-for-net"
} elseif (Test-Path (Join-Path $LocalRepo "src\samples\NamedPipeAgent\NamedPipeAgent.csproj")) {
  Write-Warning "Git is unavailable or '$LocalRepo' is not a Git checkout. Using the existing Agents-for-net files without updating them."
} elseif (Test-Path $LocalRepo) {
  throw "The path '$LocalRepo' exists but does not contain the NamedPipeAgent sample."
} elseif ($GitCommand) {
  git clone $RepoUrl $LocalRepo
  Assert-LastExitCode "Cloning Agents-for-net"
} else {
  Write-Host "Git was not found. Downloading Agents-for-net as a GitHub archive..."
  $ArchiveUrl = "https://github.com/microsoft/Agents-for-net/archive/refs/heads/main.zip"
  $ArchivePath = Join-Path $OriginalWorkingDirectory "Agents-for-net-main.zip"
  $ExtractPath = Join-Path $OriginalWorkingDirectory "Agents-for-net-download"
  $ExtractedRepo = Join-Path $ExtractPath "Agents-for-net-main"

  try {
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $ArchivePath
    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null
    Expand-Archive -Path $ArchivePath -DestinationPath $ExtractPath -Force

    if (-not (Test-Path $ExtractedRepo)) {
      throw "The downloaded archive did not contain the expected '$ExtractedRepo' directory."
    }

    Move-Item -Path $ExtractedRepo -Destination $LocalRepo
  } finally {
    if (Test-Path $ArchivePath) {
      Remove-Item $ArchivePath -Force
    }
    if (Test-Path $ExtractPath) {
      Remove-Item $ExtractPath -Recurse -Force
    }
  }
}

$AgentPath = Join-Path $LocalRepo "src\samples\NamedPipeAgent"
$ProjectPath = Join-Path $AgentPath "NamedPipeAgent.csproj"
$ProgramPath = Join-Path $AgentPath "Program.cs"

foreach ($RequiredPath in @($ProjectPath, $ProgramPath)) {
  if (-not (Test-Path $RequiredPath)) {
    throw "NamedPipeAgent file was not found: $RequiredPath"
  }
}

# ============================================================
# 6) Configure NamedPipeAgent for App Service and add a test page
# ============================================================
$ProgramContent = Get-Content $ProgramPath -Raw
$DefaultTransportCall = "builder.AddAgentNamedPipeTransport();"

if ($ProgramContent.Contains($DefaultTransportCall)) {
  $AppServiceTransport = @'
var siteName = System.Environment.GetEnvironmentVariable("APPSETTING_WEBSITE_SITE_NAME")
    ?? throw new System.InvalidOperationException("APPSETTING_WEBSITE_SITE_NAME is required for Direct Line App Service Extension.");
builder.AddAgentNamedPipeTransport(pipeName: $"{siteName}.directline");
'@
  $ProgramContent = $ProgramContent.Replace($DefaultTransportCall, $AppServiceTransport)
} elseif ($ProgramContent -notmatch 'AddAgentNamedPipeTransport\s*\(\s*pipeName:') {
  throw "NamedPipeAgent Program.cs no longer contains the expected transport registration."
}

if ($ProgramContent -notmatch 'app\.UseDefaultFiles\(\)') {
  $ProgramContent = $ProgramContent.Replace(
    "app.Run();",
    "app.UseDefaultFiles();`r`napp.UseStaticFiles();`r`n`r`napp.Run();"
  )
}

Set-Content -Path $ProgramPath -Value $ProgramContent -Encoding utf8

$WebRootPath = Join-Path $AgentPath "wwwroot"
New-Item -ItemType Directory -Path $WebRootPath -Force | Out-Null

$IndexHtml = @'
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Agents SDK DL ASE test</title>
    <script crossorigin="anonymous" src="https://cdn.botframework.com/botframework-webchat/latest/webchat.js"></script>
    <style>
      html, body { height: 100%; margin: 0; font-family: sans-serif; }
      body { display: grid; grid-template-rows: auto 1fr; }
      form { display: flex; gap: 0.5rem; padding: 0.75rem; background: #f3f3f3; }
      input { flex: 1; padding: 0.5rem; }
      button { padding: 0.5rem 1rem; }
      #status { padding: 0 0.75rem 0.75rem; background: #f3f3f3; }
      #webchat { min-height: 0; }
    </style>
  </head>
  <body>
    <div>
      <form id="connect-form">
        <input id="secret" type="password" autocomplete="off" placeholder="Direct Line secret" required />
        <button type="submit">Connect</button>
      </form>
      <div id="status">Enter a Direct Line secret to connect. The secret is not stored.</div>
    </div>
    <div id="webchat" role="main"></div>
    <script>
      document.getElementById("connect-form").addEventListener("submit", async event => {
        event.preventDefault();
        const button = event.currentTarget.querySelector("button");
        const secret = document.getElementById("secret").value.trim();
        const status = document.getElementById("status");
        button.disabled = true;
        status.textContent = "Connecting...";

        try {
          const response = await fetch("/.bot/v3/directline/tokens/generate", {
            method: "POST",
            headers: {
              "Authorization": "Bearer " + secret,
              "Content-Type": "application/json"
            },
            body: JSON.stringify({
              user: { id: "agents_sdk_dlase_test", name: "Agents SDK DL ASE test" }
            })
          });

          if (!response.ok) {
            throw new Error("Token generation failed: " + response.status + " " + response.statusText);
          }

          const { token } = await response.json();
          const directLine = await window.WebChat.createDirectLineAppServiceExtension({
            domain: window.location.origin + "/.bot/v3/directline",
            token
          });

          window.WebChat.renderWebChat({ directLine }, document.getElementById("webchat"));
          document.getElementById("secret").value = "";
          status.textContent = "Connected.";
        } catch (error) {
          console.error(error);
          status.textContent = error.message || String(error);
          button.disabled = false;
        }
      });
    </script>
  </body>
</html>
'@

Set-Content -Path (Join-Path $WebRootPath "index.html") -Value $IndexHtml -Encoding utf8

# ============================================================
# 7) Build, publish, and deploy NamedPipeAgent
# ============================================================
$PublishPath = Join-Path $OriginalWorkingDirectory "NamedPipeAgent-publish"
$ZipPath = Join-Path $OriginalWorkingDirectory "NamedPipeAgent.zip"

if (Test-Path $PublishPath) {
  Remove-Item $PublishPath -Recurse -Force
}
if (Test-Path $ZipPath) {
  Remove-Item $ZipPath -Force
}

$RestoreConfigPath = Join-Path $OriginalWorkingDirectory "NamedPipeAgent.NuGet.config"
$EscapedNuGetSource = [System.Security.SecurityElement]::Escape($NuGetSource)
$RestoreConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="ApprovedInternalFeed" value="$EscapedNuGetSource" protocolVersion="3" />
  </packageSources>
</configuration>
"@

try {
  Set-Content -Path $RestoreConfigPath -Value $RestoreConfig -Encoding utf8
  dotnet restore $ProjectPath `
    --configfile $RestoreConfigPath `
    --interactive
  Assert-LastExitCode "Restoring NamedPipeAgent from the approved internal NuGet feed '$NuGetSource'"
} finally {
  if (Test-Path $RestoreConfigPath) {
    Remove-Item $RestoreConfigPath -Force
  }
}

# DL ASE runs alongside the agent in the same IIS application. Force
# out-of-process hosting so ANCM does not reject mixed hosting models.
dotnet publish $ProjectPath `
  --configuration Release `
  --output $PublishPath `
  --no-restore `
  --property:AspNetCoreHostingModel=OutOfProcess
Assert-LastExitCode "Publishing NamedPipeAgent"

$PublishedWebConfig = Join-Path $PublishPath "web.config"
if (-not (Test-Path $PublishedWebConfig)) {
  throw "Publish output did not contain web.config for Windows App Service."
}

$PublishedWebConfigContent = Get-Content $PublishedWebConfig -Raw
if ($PublishedWebConfigContent -notmatch 'hostingModel\s*=\s*"outofprocess"') {
  throw "Published web.config does not use the required out-of-process ANCM hosting model."
}

# The upstream project intentionally excludes wwwroot. Copy the test client after
# publish so the agent remains based on the canonical pipe-only sample.
Copy-Item $WebRootPath (Join-Path $PublishPath "wwwroot") -Recurse -Force

Compress-Archive `
  -Path (Join-Path $PublishPath "*") `
  -DestinationPath $ZipPath `
  -Force

az webapp deploy `
  --resource-group $RG `
  --name $WebAppName `
  --src-path $ZipPath `
  --type zip `
  --output none
Assert-LastExitCode "Deploying NamedPipeAgent"

az webapp restart `
  --resource-group $RG `
  --name $WebAppName `
  --output none
Assert-LastExitCode "Restarting Web App"

# ============================================================
# 8) Verify DL ASE and retrieve a Direct Line secret if permitted
# ============================================================
$HealthUrl = "$WebAppUrl/.bot"
$Health = $null

for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
  Start-Sleep -Seconds $SafeDelay
  try {
    $HealthResponse = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 30
    $Health = ConvertFrom-DlAseHealthResponse -Response $HealthResponse
    if ($Health.k -eq $true -and $Health.ib -eq $true -and $Health.ob -eq $true -and $Health.initialized -eq $true) {
      break
    }
  } catch {
    Write-Host "DL ASE health check attempt $Attempt failed: $($_.Exception.Message)"
  }
}

if (-not $Health -or $Health.k -ne $true -or $Health.ib -ne $true -or $Health.ob -ne $true -or $Health.initialized -ne $true) {
  $HealthJson = if ($Health) { $Health | ConvertTo-Json -Compress } else { "No response" }
  throw "DL ASE did not become healthy. Response: $HealthJson. Check: az webapp log tail --resource-group $RG --name $WebAppName"
}

$ApiVersion = "2023-09-15-preview"
$ListKeysUrl = "https://management.azure.com$BotResourceId/channels/DirectLineChannel/listChannelWithKeys?api-version=$ApiVersion"
$DLSecret = $null

try {
  $ResponseJson = az rest `
    --method post `
    --uri $ListKeysUrl `
    --body "{}" `
    --output json
  Assert-LastExitCode "Retrieving Direct Line channel keys"

  $Response = $ResponseJson | ConvertFrom-Json
  $Site = $Response.properties.properties.sites | Select-Object -First 1
  if ($Site) {
    $DLSecret = $Site.key
  }
} catch {
  Write-Warning "Direct Line secret retrieval was not permitted: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Resource group: $RG"
Write-Host "Web App:        $WebAppUrl"
Write-Host "DL ASE health:  $HealthUrl"
Write-Host "Test client:    $WebAppUrl/"
Write-Host "Azure Bot:      $BotName"
Write-Host "Bot location:   $BotLocation"

if ($DLSecret) {
  Write-Host "Direct Line secret (keep secure): $DLSecret"
} else {
  Write-Host "Retrieve a Direct Line secret from Azure Portal > Azure Bot > Channels > Direct Line."
}
