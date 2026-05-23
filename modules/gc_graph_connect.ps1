# gc_graph_connect.ps1
# Shared Microsoft Graph connection helper for grndctrl-delta packages.
#
# Priority order for authentication:
#   1. Existing MgGraph context in the current session (already connected — reuse it).
#   2. Service principal via env vars: GC_AZURE_TENANT_ID, GC_AZURE_CLIENT_ID, GC_AZURE_CLIENT_SECRET
#   3. Service principal via env vars: GC_AZURE_TENANT_ID, GC_AZURE_CLIENT_ID, GC_AZURE_CLIENT_CERTIFICATE_PATH
#   4. Throw with actionable guidance.
#
# Usage — dot-source this file at the top of any package script that needs Graph:
#   . "$PSScriptRoot\..\..\modules\gc_graph_connect.ps1"
#   Ensure-MgGraphConnection
#
# Config store profile keys (configure in GroundControl config store):
#   GC_AZURE_TENANT_ID                 Azure tenant ID (GUID)
#   GC_AZURE_CLIENT_ID                 App registration / service principal client ID
#   GC_AZURE_CLIENT_SECRET             Client secret (secret: true)
#   GC_AZURE_CLIENT_CERTIFICATE_PATH   Path to .pfx certificate file (alternative to client secret)

function Ensure-MgGraphConnection {
    param(
        [string[]]$RequiredScopes = @()
    )

    # 1. Already connected — check scopes and reuse.
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($context) {
        if ($RequiredScopes.Count -gt 0) {
            $missing = $RequiredScopes | Where-Object { $_ -notin $context.Scopes }
            if ($missing) {
                Write-Warning "Connected to Graph but missing scopes: $($missing -join ', '). Reconnecting."
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                return
            }
        }
        else {
            return
        }
    }

    $tenantId    = $env:GC_AZURE_TENANT_ID
    $clientId    = $env:GC_AZURE_CLIENT_ID
    $secret      = $env:GC_AZURE_CLIENT_SECRET
    $certPath    = $env:GC_AZURE_CLIENT_CERTIFICATE_PATH

    # 2. Client secret flow.
    if ($tenantId -and $clientId -and $secret) {
        $secureSecret = ConvertTo-SecureString $secret -AsPlainText -Force
        $credential   = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)
        Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome | Out-Null
        return
    }

    # 3. Certificate flow.
    if ($tenantId -and $clientId -and $certPath) {
        if (-not (Test-Path $certPath)) {
            throw "Certificate file not found at GC_AZURE_CLIENT_CERTIFICATE_PATH: $certPath"
        }
        Connect-MgGraph -TenantId $tenantId -ClientId $clientId -CertificatePath $certPath -NoWelcome | Out-Null
        return
    }

    # 4. No credentials available.
    throw (
        "Not connected to Microsoft Graph and no service principal credentials found in environment. " +
        "Options:`n" +
        "  A) Set GC_AZURE_TENANT_ID, GC_AZURE_CLIENT_ID, and GC_AZURE_CLIENT_SECRET in a config profile.`n" +
        "  B) Set GC_AZURE_TENANT_ID, GC_AZURE_CLIENT_ID, and GC_AZURE_CLIENT_CERTIFICATE_PATH for cert auth.`n" +
        "  C) Run the 'az_connect_tenant' tool in an interactive terminal to authenticate with delegated permissions."
    )
}

function Get-MgGraphConnectionInfo {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $context) {
        return @{ connected = $false }
    }
    return @{
        connected  = $true
        tenant_id  = $context.TenantId
        account    = $context.Account
        app_name   = $context.AppName
        scopes     = $context.Scopes
        auth_type  = $context.AuthType
    }
}
