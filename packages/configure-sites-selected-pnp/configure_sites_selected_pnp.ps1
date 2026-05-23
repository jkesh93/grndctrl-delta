<#
.SYNOPSIS
Configure Sites.Selected access for an app registration on one SharePoint Online site using PnP.PowerShell.

.DESCRIPTION
This script signs you into the target SharePoint site using your admin account through PnP.PowerShell,
then grants an Azure/Entra app registration access to only that selected site.

IMPORTANT:
You need two different app/client IDs:

1. PnPClientId
   Used only for the interactive admin login to PnP.PowerShell.
   This app registration must support delegated/public-client login.

2. AppId
   The target app registration that should receive Sites.Selected access to the SharePoint site.

The target app registration should already have:
  Microsoft Graph -> Application permission -> Sites.Selected
  Admin consent granted

Supported selected-site permissions:
  Read
  Write
  Manage
  FullControl

.EXAMPLE
.\configure_sites_selected_pnp.ps1 `
  -SiteUrl "https://cadmv.sharepoint.com/sites/DMV_DocRepository" `
  -PnPClientId "YOUR_PNP_LOGIN_APP_CLIENT_ID" `
  -AppId "a5250526-3497-4187-9e34-48e1be464c7a" `
  -DisplayName "snow_svc_full_control" `
  -Permission FullControl
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$PnPClientId,

    [Parameter(Mandatory = $false)]
    [string]$AppId,

    [Parameter(Mandatory = $false)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Read", "Write", "Manage", "FullControl")]
    [string]$Permission,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]$InstallModuleIfMissing = "true"
)

$ErrorActionPreference = "Stop"

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-PermissionValue {
    param(
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    Write-Host ""
    Write-Host "Choose selected-site permission:"
    Write-Host "  1. Read        - read-only"
    Write-Host "  2. Write       - read/write"
    Write-Host "  3. Manage      - manage site permissions/content where supported"
    Write-Host "  4. FullControl - full control on the selected site"
    Write-Host ""

    while ($true) {
        $choice = Read-Host "Enter 1, 2, 3, 4, or permission name"

        switch ($choice.Trim().ToLowerInvariant()) {
            "1" { return "Read" }
            "read" { return "Read" }

            "2" { return "Write" }
            "write" { return "Write" }
            "readwrite" { return "Write" }
            "read-write" { return "Write" }
            "read/write" { return "Write" }

            "3" { return "Manage" }
            "manage" { return "Manage" }

            "4" { return "FullControl" }
            "fullcontrol" { return "FullControl" }
            "full control" { return "FullControl" }

            default {
                Write-Host "Invalid permission. Try again."
            }
        }
    }
}

function Test-Truthy {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return @("true", "1", "yes", "y") -contains $Value.Trim().ToLowerInvariant()
}

function Ensure-PnPModule {
    $module = Get-Module -ListAvailable -Name "PnP.PowerShell" | Select-Object -First 1

    if (-not $module) {
        if (Test-Truthy -Value $InstallModuleIfMissing) {
            Write-Host "PnP.PowerShell is not installed. Installing it for CurrentUser..."
            Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
        }
        else {
            throw "PnP.PowerShell is not installed. Install it with: Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber"
        }
    }

    Import-Module PnP.PowerShell -ErrorAction Stop
}

function Test-PowerShellVersionForPnP {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This version of PnP.PowerShell requires PowerShell 7.4 or higher. You are running PowerShell $($PSVersionTable.PSVersion). Open PowerShell 7 by running 'pwsh', then rerun this script."
    }

    if ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 4) {
        throw "This version of PnP.PowerShell requires PowerShell 7.4 or higher. You are running PowerShell $($PSVersionTable.PSVersion). Update PowerShell 7, then rerun this script."
    }
}

try {
    Write-Host ""
    Write-Host "Configure Sites.Selected for one SharePoint site using PnP.PowerShell"
    Write-Host "--------------------------------------------------------------------"
    Write-Host ""

    Test-PowerShellVersionForPnP

    $SiteUrl = Read-RequiredValue `
        -Prompt "Enter SharePoint site URL, for example https://contoso.sharepoint.com/sites/Finance" `
        -CurrentValue $SiteUrl

    $PnPClientId = Read-RequiredValue `
        -Prompt "Enter PnP interactive login app client ID" `
        -CurrentValue $PnPClientId

    $AppId = Read-RequiredValue `
        -Prompt "Enter target app registration Application/client ID to grant site access" `
        -CurrentValue $AppId

    $DisplayName = Read-RequiredValue `
        -Prompt "Enter display name for the target app permission entry" `
        -CurrentValue $DisplayName

    $Permission = Read-PermissionValue -CurrentValue $Permission

    Ensure-PnPModule

    Write-Host ""
    Write-Host "Connecting to SharePoint site with interactive sign-in..."
    Write-Host "Site URL:      $SiteUrl"
    Write-Host "PnP Client ID: $PnPClientId"
    Write-Host ""

    Connect-PnPOnline `
        -Url $SiteUrl `
        -Interactive `
        -ClientId $PnPClientId

    Write-Host ""
    Write-Host "Current selected-site app permissions before change:"
    Write-Host ""

    try {
        $existingPermissions = Get-PnPAzureADAppSitePermission -Site $SiteUrl

        if ($existingPermissions) {
            $existingPermissions | Format-Table -AutoSize
        }
        else {
            Write-Host "No existing app site permissions returned."
        }
    }
    catch {
        Write-Host "Could not list existing permissions before change: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Permission to grant:"
    Write-Host "  Site URL:          $SiteUrl"
    Write-Host "  PnP Login App ID:  $PnPClientId"
    Write-Host "  Target App ID:     $AppId"
    Write-Host "  Target App Name:   $DisplayName"
    Write-Host "  Permission:        $Permission"
    Write-Host ""

    $confirm = Read-Host "Type YES to grant the target app access to this selected site"

    if ($confirm -ne "YES") {
        throw "Cancelled. No changes were made."
    }

    Write-Host ""
    Write-Host "Granting selected-site permission..."

    $grant = Grant-PnPAzureADAppSitePermission `
        -AppId $AppId `
        -DisplayName $DisplayName `
        -Site $SiteUrl `
        -Permissions $Permission

    Write-Host ""
    Write-Host "Selected-site permission granted."
    Write-Host ""
    Write-Host "Current selected-site app permissions after change:"
    Write-Host ""

    $afterPermissions = Get-PnPAzureADAppSitePermission -Site $SiteUrl
    $afterPermissions | Format-Table -AutoSize

    $result = [ordered]@{
        ok = $true
        action = "configure_sites_selected_pnp"
        message = "Configured Sites.Selected permission for the target app registration on the selected SharePoint site."
        timestamp = (Get-Date).ToString("o")
        site_url = $SiteUrl
        pnp_client_id = $PnPClientId
        target_app_id = $AppId
        target_display_name = $DisplayName
        permission = $Permission
        grant_result = $grant
    }

    Write-Host ""
    $result | ConvertTo-Json -Depth 10
}
catch {
    Write-Host ""
    Write-Host "Failed."
    Write-Host ""

    $errorMessage = $_.Exception.Message

    if ($_.Exception.InnerException) {
        $errorMessage = "$errorMessage Inner exception: $($_.Exception.InnerException.Message)"
    }

    $result = [ordered]@{
        ok = $false
        action = "configure_sites_selected_pnp"
        message = $errorMessage
        timestamp = (Get-Date).ToString("o")
        site_url = $SiteUrl
        pnp_client_id = $PnPClientId
        target_app_id = $AppId
        target_display_name = $DisplayName
        permission = $Permission
        powershell_version = $PSVersionTable.PSVersion.ToString()
    }

    $result | ConvertTo-Json -Depth 10
    exit 1
}
finally {
    try {
        Disconnect-PnPOnline | Out-Null
    }
    catch {
        # Ignore disconnect errors.
    }
}