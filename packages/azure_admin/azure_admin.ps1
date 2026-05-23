param(
    [Parameter(Mandatory = $true)]
    [string]$Operation,

    [string]$TenantId = "",
    [string]$Scopes = "",

    [string]$UserId = "",
    [string]$SelectProperties = "",
    [string]$Search = "",
    [int]$Top = 0,

    [string]$DisplayName = "",
    [string]$UserPrincipalName = "",
    [string]$MailNickname = "",
    [string]$TemporaryPassword = "",
    [string]$ForceChangePasswordNextSignIn = "",
    [string]$AccountEnabled = "",

    [string]$JobTitle = "",
    [string]$Department = "",
    [string]$MobilePhone = "",
    [string]$OfficeLocation = "",

    [string]$GroupIdOrName = "",
    [string]$Description = "",
    [string]$GroupId = "",
    [string]$MemberId = "",

    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$timestamp = (Get-Date).ToString("o")

function New-Result {
    param(
        [bool]$Ok,
        [string]$Action,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    $result = @{
        ok = $Ok
        action = $Action
        message = $Message
        timestamp = (Get-Date).ToString("o")
        mock_or_test_result = $false
    }

    foreach ($key in $Data.Keys) {
        $result[$key] = $Data[$key]
    }

    return $result
}

function Convert-ToBool {
    param(
        [string]$Value,
        [bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "true" { return $true }
        "false" { return $false }
        default { throw "Invalid boolean value '$Value'. Use 'true' or 'false'." }
    }
}

function Escape-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Ensure-GraphModule {
    $requiredModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Users",
        "Microsoft.Graph.Groups"
    )

    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            throw "Required module '$moduleName' is not installed. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
        }
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
}

function Ensure-GraphConnection {
    $context = Get-MgContext -ErrorAction SilentlyContinue

    if ($context) { return }

    # Service principal auth via config profile env vars (preferred for unattended / agentic use).
    $tenantId = $env:GC_AZURE_TENANT_ID
    $clientId = $env:GC_AZURE_CLIENT_ID
    $secret   = $env:GC_AZURE_CLIENT_SECRET
    $certPath = $env:GC_AZURE_CLIENT_CERTIFICATE_PATH

    if ($tenantId -and $clientId -and $secret) {
        try {
            $secureSecret = ConvertTo-SecureString $secret -AsPlainText -Force
            $credential   = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)
            Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome | Out-Null
            return
        } catch {
            throw "Service principal (client secret) authentication failed: $($_.Exception.Message)"
        }
    }

    if ($tenantId -and $clientId -and $certPath) {
        if (-not (Test-Path $certPath)) {
            throw "Certificate file not found at GC_AZURE_CLIENT_CERTIFICATE_PATH: $certPath"
        }
        try {
            Connect-MgGraph -TenantId $tenantId -ClientId $clientId -CertificatePath $certPath -NoWelcome | Out-Null
            return
        } catch {
            throw "Service principal (certificate) authentication failed: $($_.Exception.Message)"
        }
    }

    # Fall back to interactive browser auth.
    # Uses MSAL token cache — silent if you have already signed in this session or previously
    # via connect_tenant; opens a browser prompt if no valid cached token is found.
    $defaultScopes = @("User.ReadWrite.All", "Group.ReadWrite.All", "Directory.Read.All")
    try {
        if ($tenantId) {
            Connect-MgGraph -TenantId $tenantId -Scopes $defaultScopes -NoWelcome | Out-Null
        } else {
            Connect-MgGraph -Scopes $defaultScopes -NoWelcome | Out-Null
        }
    } catch {
        throw (
            "Interactive authentication failed: $($_.Exception.Message)`n" +
            "To use service principal auth instead, set GC_AZURE_TENANT_ID, GC_AZURE_CLIENT_ID, " +
            "and GC_AZURE_CLIENT_SECRET in a GroundControl config profile."
        )
    }
}

function Convert-ObjectForJson {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    return $InputObject | Select-Object *
}

try {
    Ensure-GraphModule

    switch ($Operation) {
        "connect_tenant" {
            $scopeList = @()

            if ([string]::IsNullOrWhiteSpace($Scopes)) {
                $scopeList = @("User.ReadWrite.All", "Group.ReadWrite.All", "Directory.Read.All")
            }
            else {
                $scopeList = $Scopes.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }

            if ($TenantId) {
                Connect-MgGraph -TenantId $TenantId -Scopes $scopeList -NoWelcome | Out-Null
            }
            else {
                Connect-MgGraph -Scopes $scopeList -NoWelcome | Out-Null
            }

            $context = Get-MgContext

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Connected to Microsoft Graph." `
                -Data @{
                    tenant_id = $context.TenantId
                    account = $context.Account
                    scopes = $context.Scopes
                }
        }

        "get_user" {
            Ensure-GraphConnection

            if (-not $UserId) {
                throw "user_id is required for get_user."
            }

            $selectList = @()

            if ([string]::IsNullOrWhiteSpace($SelectProperties)) {
                $selectList = @("id", "displayName", "userPrincipalName", "accountEnabled", "mail", "jobTitle", "department")
            }
            else {
                $selectList = $SelectProperties.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }

            $user = Get-MgUser -UserId $UserId -Property $selectList -ErrorAction Stop | Select-Object $selectList

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Retrieved user '$UserId'." `
                -Data @{ user = Convert-ObjectForJson $user }
        }

        "list_users" {
            Ensure-GraphConnection

            $limit = if ($Top -gt 0) { $Top } else { 25 }

            if ($Search) {
                $escapedSearch = Escape-ODataString $Search
                $filter = "startswith(displayName,'$escapedSearch') or startswith(userPrincipalName,'$escapedSearch')"
                $users = Get-MgUser -Filter $filter -Top $limit -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Mail,JobTitle,Department |
                    Select-Object Id, DisplayName, UserPrincipalName, AccountEnabled, Mail, JobTitle, Department
            }
            else {
                $users = Get-MgUser -Top $limit -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Mail,JobTitle,Department |
                    Select-Object Id, DisplayName, UserPrincipalName, AccountEnabled, Mail, JobTitle, Department
            }

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Listed Entra ID users." `
                -Data @{
                    count = @($users).Count
                    users = @($users)
                }
        }

        "create_user" {
            Ensure-GraphConnection

            if (-not $DisplayName) { throw "display_name is required for create_user." }
            if (-not $UserPrincipalName) { throw "user_principal_name is required for create_user." }
            if (-not $MailNickname) { throw "mail_nickname is required for create_user." }
            if (-not $TemporaryPassword) { throw "temporary_password is required for create_user." }

            $enabled = Convert-ToBool -Value $AccountEnabled -Default $true
            $forceChange = Convert-ToBool -Value $ForceChangePasswordNextSignIn -Default $true

            $passwordProfile = @{
                password = $TemporaryPassword
                forceChangePasswordNextSignIn = $forceChange
            }

            $newUser = New-MgUser `
                -DisplayName $DisplayName `
                -UserPrincipalName $UserPrincipalName `
                -MailNickname $MailNickname `
                -AccountEnabled:$enabled `
                -PasswordProfile $passwordProfile

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Created user '$UserPrincipalName'." `
                -Data @{
                    user = @{
                        id = $newUser.Id
                        display_name = $newUser.DisplayName
                        user_principal_name = $newUser.UserPrincipalName
                        account_enabled = $newUser.AccountEnabled
                    }
                }
        }

        "update_user" {
            Ensure-GraphConnection

            if (-not $UserId) {
                throw "user_id is required for update_user."
            }

            $params = @{}

            if ($DisplayName) { $params["DisplayName"] = $DisplayName }
            if ($JobTitle) { $params["JobTitle"] = $JobTitle }
            if ($Department) { $params["Department"] = $Department }
            if ($MobilePhone) { $params["MobilePhone"] = $MobilePhone }
            if ($OfficeLocation) { $params["OfficeLocation"] = $OfficeLocation }
            if (-not [string]::IsNullOrWhiteSpace($AccountEnabled)) {
                $params["AccountEnabled"] = Convert-ToBool -Value $AccountEnabled -Default $true
            }

            if ($params.Count -eq 0) {
                throw "At least one update field is required for update_user."
            }

            Update-MgUser -UserId $UserId @params

            $updatedUser = Get-MgUser -UserId $UserId -Property Id,DisplayName,UserPrincipalName,AccountEnabled,JobTitle,Department,MobilePhone,OfficeLocation |
                Select-Object Id, DisplayName, UserPrincipalName, AccountEnabled, JobTitle, Department, MobilePhone, OfficeLocation

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Updated user '$UserId'." `
                -Data @{ user = $updatedUser }
        }

        "disable_user" {
            Ensure-GraphConnection

            if (-not $UserId) {
                throw "user_id is required for disable_user."
            }

            Update-MgUser -UserId $UserId -AccountEnabled:$false

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Disabled user '$UserId'." `
                -Data @{ user_id = $UserId }
        }

        "delete_user" {
            Ensure-GraphConnection

            if (-not $UserId) {
                throw "user_id is required for delete_user."
            }

            Remove-MgUser -UserId $UserId -Confirm:$false

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Deleted user '$UserId'." `
                -Data @{ user_id = $UserId }
        }

        "get_group" {
            Ensure-GraphConnection

            if (-not $GroupIdOrName) {
                throw "group_id_or_name is required for get_group."
            }

            $group = $null

            try {
                $group = Get-MgGroup -GroupId $GroupIdOrName -Property Id,DisplayName,Description,MailEnabled,SecurityEnabled,MailNickname |
                    Select-Object Id, DisplayName, Description, MailEnabled, SecurityEnabled, MailNickname
            }
            catch {
                $escapedGroup = Escape-ODataString $GroupIdOrName
                $filter = "startswith(displayName,'$escapedGroup')"
                $group = Get-MgGroup -Filter $filter -Top 10 -Property Id,DisplayName,Description,MailEnabled,SecurityEnabled,MailNickname |
                    Select-Object Id, DisplayName, Description, MailEnabled, SecurityEnabled, MailNickname
            }

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Retrieved matching group information." `
                -Data @{
                    count = @($group).Count
                    groups = @($group)
                }
        }

        "list_groups" {
            Ensure-GraphConnection

            $limit = if ($Top -gt 0) { $Top } else { 25 }

            if ($Search) {
                $escapedSearch = Escape-ODataString $Search
                $filter = "startswith(displayName,'$escapedSearch')"
                $groups = Get-MgGroup -Filter $filter -Top $limit -Property Id,DisplayName,Description,MailEnabled,SecurityEnabled,MailNickname |
                    Select-Object Id, DisplayName, Description, MailEnabled, SecurityEnabled, MailNickname
            }
            else {
                $groups = Get-MgGroup -Top $limit -Property Id,DisplayName,Description,MailEnabled,SecurityEnabled,MailNickname |
                    Select-Object Id, DisplayName, Description, MailEnabled, SecurityEnabled, MailNickname
            }

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Listed Entra ID groups." `
                -Data @{
                    count = @($groups).Count
                    groups = @($groups)
                }
        }

        "create_security_group" {
            Ensure-GraphConnection

            if (-not $DisplayName) { throw "display_name is required for create_security_group." }
            if (-not $MailNickname) { throw "mail_nickname is required for create_security_group." }

            $params = @{
                DisplayName = $DisplayName
                MailEnabled = $false
                MailNickname = $MailNickname
                SecurityEnabled = $true
            }

            if ($Description) {
                $params["Description"] = $Description
            }

            $group = New-MgGroup @params

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Created security group '$DisplayName'." `
                -Data @{
                    group = @{
                        id = $group.Id
                        display_name = $group.DisplayName
                        mail_nickname = $group.MailNickname
                        mail_enabled = $group.MailEnabled
                        security_enabled = $group.SecurityEnabled
                    }
                }
        }

        "add_group_member" {
            Ensure-GraphConnection

            if (-not $GroupId) { throw "group_id is required for add_group_member." }
            if (-not $MemberId) { throw "member_id is required for add_group_member." }

            $body = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId"
            }

            New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter $body

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Added member '$MemberId' to group '$GroupId'." `
                -Data @{
                    group_id = $GroupId
                    member_id = $MemberId
                }
        }

        "remove_group_member" {
            Ensure-GraphConnection

            if (-not $GroupId) { throw "group_id is required for remove_group_member." }
            if (-not $MemberId) { throw "member_id is required for remove_group_member." }

            Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $MemberId -Confirm:$false

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Removed member '$MemberId' from group '$GroupId'." `
                -Data @{
                    group_id = $GroupId
                    member_id = $MemberId
                }
        }

        "list_group_members" {
            Ensure-GraphConnection

            if (-not $GroupId) {
                throw "group_id is required for list_group_members."
            }

            $limit = if ($Top -gt 0) { $Top } else { 100 }

            $members = Get-MgGroupMember -GroupId $GroupId -Top $limit |
                Select-Object Id, DeletedDateTime, AdditionalProperties

            $normalizedMembers = @()

            foreach ($member in $members) {
                $props = $member.AdditionalProperties

                $normalizedMembers += [pscustomobject]@{
                    id = $member.Id
                    type = $props["@odata.type"]
                    display_name = $props["displayName"]
                    user_principal_name = $props["userPrincipalName"]
                    mail = $props["mail"]
                }
            }

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Listed members for group '$GroupId'." `
                -Data @{
                    group_id = $GroupId
                    count = @($normalizedMembers).Count
                    members = @($normalizedMembers)
                }
        }

        "export_users_csv" {
            Ensure-GraphConnection

            if (-not $OutputPath) {
                throw "output_path is required for export_users_csv."
            }

            $limit = if ($Top -gt 0) { $Top } else { 999 }

            $users = Get-MgUser -Top $limit -Property Id,DisplayName,UserPrincipalName,AccountEnabled,Mail,JobTitle,Department,OfficeLocation,MobilePhone,CreatedDateTime |
                Select-Object Id, DisplayName, UserPrincipalName, AccountEnabled, Mail, JobTitle, Department, OfficeLocation, MobilePhone, CreatedDateTime

            $directory = Split-Path -Parent $OutputPath

            if ($directory -and -not (Test-Path $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }

            $users | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

            $result = New-Result `
                -Ok $true `
                -Action $Operation `
                -Message "Exported Entra ID users to CSV." `
                -Data @{
                    output_path = $OutputPath
                    count = @($users).Count
                }
        }

        default {
            $result = New-Result `
                -Ok $false `
                -Action $Operation `
                -Message "Unknown operation '$Operation'."
        }
    }
}
catch {
    $result = New-Result `
        -Ok $false `
        -Action $Operation `
        -Message $_.Exception.Message `
        -Data @{
            error_type = $_.Exception.GetType().FullName
        }
}

$result | ConvertTo-Json -Depth 10