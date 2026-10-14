# ============================================================
# Script: Creates an Azure healthcare agent service resource
#         (formerly Azure Health Bot)
# ============================================================
#
# Summary:
# - Signs in and selects the configured Azure subscription
# - Registers the Microsoft.HealthBot resource provider
# - Validates the selected region and healthcare agent name
# - Creates a resource group and healthcare agent service resource
# - Assigns the signed-in user the Healthcare Agent Admin role
# - Prints links for managing the resource and authoring a custom scenario
#
# Resource quickstart:
# https://learn.microsoft.com/azure/health-bot/quickstart-createyourhealthcarebot
#
# Custom scenario quickstart:
# https://learn.microsoft.com/azure/health-bot/quickstart-createyourfirstscenario
#
# Custom scenarios are authored or imported through the healthcare agent service
# Management Portal. Microsoft does not document a public ARM resource or API for
# scenario deployment, so this script does not call unsupported private endpoints.
# Follow the companion README to create the "hello" scenario after deployment.
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# 0) Fixed parameters. Edit the subscription and suffix before running.
# ============================================================
$SubscriptionId = "83454b68-9b7f-41a7-b08e-936b629f865b"
$RG              = "HealthcareAgentResourceGroup"
$Location        = "westeurope"
$Suffix          = "sample"

$HealthBotName   = "healthcare-agent-$Suffix"
$SkuName         = "F0"
$ApiVersion      = "2025-11-01"
$AssignCurrentUserAsAdmin = $true

$HealthcareAgentAdminRoleId = "f1082fec-a70f-419f-9230-885d2550fb38"

function Assert-LastExitCode {
  param([Parameter(Mandatory = $true)][string]$Operation)

  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE."
  }
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
  throw "Required command 'az' was not found on PATH."
}

if ($HealthBotName -cnotmatch '^[a-z][a-z-]{0,28}[a-z]$') {
  throw "HealthBotName must contain 2-30 lowercase letters or hyphens, start with a letter, and end with a letter."
}

if ($SkuName -notin @("F0", "C0", "C1", "PES")) {
  throw "SkuName must be one of: F0, C0, C1, PES."
}

# ============================================================
# 1) Sign in and select the subscription
# ============================================================
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
  $env:AZURE_CORE_LOGIN_EXPERIENCE_V2 = "off"
  az login --output none
  Assert-LastExitCode "Azure sign-in"
}

az account set --subscription $SubscriptionId
Assert-LastExitCode "Selecting Azure subscription"

# ============================================================
# 2) Register Microsoft.HealthBot and validate the region
# ============================================================
az provider register `
  --namespace Microsoft.HealthBot `
  --wait `
  --output none
Assert-LastExitCode "Registering the Microsoft.HealthBot resource provider"

$LocationJson = az account list-locations `
  --query "[?name == '$Location'] | [0]" `
  --output json
Assert-LastExitCode "Resolving Azure location '$Location'"

$LocationInfo = $LocationJson | ConvertFrom-Json
if (-not $LocationInfo) {
  throw "Azure location '$Location' was not found for the selected subscription."
}

$SupportedLocations = @(az provider show `
  --namespace Microsoft.HealthBot `
  --query "resourceTypes[?resourceType == 'healthBots'].locations[]" `
  --output tsv)
Assert-LastExitCode "Reading supported healthcare agent service locations"

if ($SupportedLocations -notcontains $LocationInfo.displayName) {
  throw "Location '$Location' ($($LocationInfo.displayName)) is not supported for Microsoft.HealthBot/healthBots. Supported locations: $($SupportedLocations -join ', ')."
}

# ============================================================
# 3) Create the resource group and healthcare agent service
# ============================================================
az group create `
  --name $RG `
  --location $Location `
  --output none
Assert-LastExitCode "Creating resource group"

$HealthBotResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$RG/providers/Microsoft.HealthBot/healthBots/$HealthBotName"
$HealthBotResourceUri = "https://management.azure.com{0}?api-version={1}" -f $HealthBotResourceId, $ApiVersion
$ParsedHealthBotResourceUri = [System.Uri]$HealthBotResourceUri

if ($ParsedHealthBotResourceUri.Host -ne "management.azure.com") {
  throw "The generated healthcare agent service management URI is invalid: $HealthBotResourceUri"
}

$RequestBody = @{
  location = $Location
  sku = @{
    name = $SkuName
  }
  properties = @{}
  tags = @{
    Sample = "BotFrameworkUtilities"
  }
} | ConvertTo-Json -Depth 5 -Compress

$AccessToken = az account get-access-token `
  --resource "https://management.azure.com/" `
  --query accessToken `
  --output tsv
Assert-LastExitCode "Acquiring an Azure Resource Manager access token"

try {
  $RequestHeaders = @{
    Authorization = "Bearer $AccessToken"
    Accept = "application/json"
  }

  $HealthBot = Invoke-RestMethod `
    -Method Put `
    -Uri $HealthBotResourceUri `
    -Headers $RequestHeaders `
    -ContentType "application/json" `
    -Body $RequestBody
} catch {
  $FailureDetails = if ($_.ErrorDetails.Message) {
    $_.ErrorDetails.Message
  } else {
    $_.Exception.Message
  }
  throw "Creating healthcare agent service '$HealthBotName' failed: $FailureDetails"
} finally {
  $AccessToken = $null
  $RequestHeaders = $null
}

if (-not $HealthBot.id) {
  throw "Healthcare agent service creation did not return a resource ID."
}

# ============================================================
# 4) Assign the signed-in user as Healthcare Agent Admin
# ============================================================
if ($AssignCurrentUserAsAdmin) {
  $CurrentUserObjectId = az ad signed-in-user show --query id --output tsv
  Assert-LastExitCode "Reading the signed-in user object ID"

  if ([string]::IsNullOrWhiteSpace($CurrentUserObjectId)) {
    throw "The signed-in Azure CLI identity is not a user. Set AssignCurrentUserAsAdmin to false or assign the Healthcare Agent Admin role separately."
  }

  $ExistingRoleAssignment = az role assignment list `
    --assignee $CurrentUserObjectId `
    --scope $HealthBotResourceId `
    --role $HealthcareAgentAdminRoleId `
    --query "[0].id" `
    --output tsv
  Assert-LastExitCode "Checking the Healthcare Agent Admin role assignment"

  if ([string]::IsNullOrWhiteSpace($ExistingRoleAssignment)) {
    az role assignment create `
      --assignee-object-id $CurrentUserObjectId `
      --assignee-principal-type User `
      --role $HealthcareAgentAdminRoleId `
      --scope $HealthBotResourceId `
      --output none
    Assert-LastExitCode "Assigning the Healthcare Agent Admin role"
  } else {
    Write-Host "The signed-in user already has Healthcare Agent Admin on this resource."
  }
}

# ============================================================
# 5) Output management and scenario-authoring links
# ============================================================
$AzurePortalUrl = "https://portal.azure.com/#resource$HealthBotResourceId/overview"
$ScenarioQuickstartUrl = "https://learn.microsoft.com/azure/health-bot/quickstart-createyourfirstscenario"

Write-Host ""
Write-Host "Healthcare agent service deployment complete."
Write-Host "Name:             $HealthBotName"
Write-Host "Resource group:   $RG"
Write-Host "Location:         $Location"
Write-Host "SKU:              $SkuName"
Write-Host "Resource ID:      $HealthBotResourceId"
Write-Host "Azure portal:     $AzurePortalUrl"
Write-Host "Scenario guide:   $ScenarioQuickstartUrl"
Write-Host ""
Write-Host "Next: open the Azure portal link, select the healthcare agent service Management Portal, and follow the companion README to create the 'hello' scenario."
