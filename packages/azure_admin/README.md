# azure_admin

Manage Entra ID users and groups via Microsoft Graph from GroundControl.

---

## Authentication

The script tries three auth methods in order:

| Priority | Method | When used |
|---|---|---|
| 1 | **Service principal — client secret** | `GC_AZURE_TENANT_ID` + `GC_AZURE_CLIENT_ID` + `GC_AZURE_CLIENT_SECRET` are all set in a config profile |
| 2 | **Service principal — certificate** | `GC_AZURE_TENANT_ID` + `GC_AZURE_CLIENT_ID` + `GC_AZURE_CLIENT_CERTIFICATE_PATH` are all set |
| 3 | **Interactive browser** | No SP credentials found — `Connect-MgGraph` opens a browser sign-in prompt (or reuses a cached MSAL token silently if you have already signed in) |

You never need to run `connect_tenant` manually before using another action. Any action that requires Graph access will authenticate automatically.

### Setting up a service principal (recommended for repeated use)

1. Register an app in Entra ID → Certificates & secrets → create a client secret
2. Grant it **Application** permissions: `User.ReadWrite.All`, `Group.ReadWrite.All`, `Directory.Read.All` — then grant admin consent
3. In GroundControl → Config Profiles, add a profile with:

| Key | Secret? | Value |
|---|---|---|
| `GC_AZURE_TENANT_ID` | No | Your tenant GUID (e.g. `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) |
| `GC_AZURE_CLIENT_ID` | No | The app registration's Application (client) ID |
| `GC_AZURE_CLIENT_SECRET` | **Yes** | The client secret value |

---

## Required PowerShell modules

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

The script imports `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, and `Microsoft.Graph.Groups`.

---

## Actions

### Users

#### `az_get_user`
Retrieve a single user by object ID or UPN.

| Parameter | Required | Description |
|---|---|---|
| `user_id` | ✅ | Object ID (GUID) or UPN (e.g. `user@contoso.com`) |
| `select_properties` | — | Comma-separated list of Graph properties to return. Default: `id, displayName, userPrincipalName, accountEnabled, mail, jobTitle, department` |

---

#### `az_list_users`
List users, optionally filtered by name/UPN prefix.

| Parameter | Required | Description |
|---|---|---|
| `search` | — | Prefix to filter by `displayName` or `userPrincipalName` |
| `top` | — | Max results to return. Default: 25 |

---

#### `az_create_user`
Create a new Entra ID user.

| Parameter | Required | Description |
|---|---|---|
| `display_name` | ✅ | Full display name |
| `user_principal_name` | ✅ | Login UPN, e.g. `jane@contoso.com` |
| `mail_nickname` | ✅ | Mail alias (the part before the `@`) |
| `temporary_password` | ✅ | Temporary password for first sign-in |
| `account_enabled` | — | `true` / `false`. Default: `true` |
| `force_change_password_next_sign_in` | — | `true` / `false`. Default: `true` |

---

#### `az_update_user`
Update profile fields on an existing user. Pass only the fields you want to change.

| Parameter | Required | Description |
|---|---|---|
| `user_id` | ✅ | Object ID or UPN |
| `display_name` | — | New display name |
| `job_title` | — | Job title |
| `department` | — | Department |
| `mobile_phone` | — | Mobile phone number |
| `office_location` | — | Office location |
| `account_enabled` | — | `true` / `false` to enable/disable the account |

---

#### `az_disable_user`
Disable a user account (does not delete it).

| Parameter | Required | Description |
|---|---|---|
| `user_id` | ✅ | Object ID or UPN |

---

#### `az_delete_user`
⚠️ **Destructive — requires approval.** Permanently deletes a user.

| Parameter | Required | Description |
|---|---|---|
| `user_id` | ✅ | Object ID or UPN |

---

#### `az_export_users_csv`
Export all users to a CSV file.

| Parameter | Required | Description |
|---|---|---|
| `output_path` | ✅ | Full path for the output `.csv` file |
| `top` | — | Max users to export. Default: 999 |

---

### Groups

#### `az_get_group`
Look up a group by ID or display name. Returns up to 10 matches when searching by name.

| Parameter | Required | Description |
|---|---|---|
| `group_id_or_name` | ✅ | Group object ID (GUID) or display name prefix |

---

#### `az_list_groups`
List groups, optionally filtered by name prefix.

| Parameter | Required | Description |
|---|---|---|
| `search` | — | Display name prefix filter |
| `top` | — | Max results. Default: 25 |

---

#### `az_create_security_group`
Create a new mail-disabled security group.

| Parameter | Required | Description |
|---|---|---|
| `display_name` | ✅ | Group display name |
| `mail_nickname` | ✅ | Mail nickname |
| `description` | — | Optional description |

---

#### `az_add_group_member`
Add a user (or other directory object) to a group.

| Parameter | Required | Description |
|---|---|---|
| `group_id` | ✅ | Group object ID |
| `member_id` | ✅ | Object ID of the member to add |

---

#### `az_remove_group_member`
Remove a member from a group.

| Parameter | Required | Description |
|---|---|---|
| `group_id` | ✅ | Group object ID |
| `member_id` | ✅ | Object ID of the member to remove |

---

#### `az_list_group_members`
List members of a group.

| Parameter | Required | Description |
|---|---|---|
| `group_id` | ✅ | Group object ID |
| `top` | — | Max results. Default: 100 |

---

### Connection

#### `az_connect_tenant`
⌨️ **Interactive.** Opens a browser sign-in to establish a delegated Graph session. Useful if you want to authenticate as yourself rather than a service principal. Runs in a visible terminal window.

> **Note:** Session tokens are not shared across separate GroundControl tool calls. For persistent unattended access configure a service principal profile (see above). The interactive fallback in `Ensure-GraphConnection` uses the MSAL token cache so commands run shortly after a browser sign-in will be silent.

| Parameter | Required | Description |
|---|---|---|
| `tenant_id` | — | Target a specific tenant |
| `scopes` | — | Comma-separated Graph scopes. Default: `User.ReadWrite.All, Group.ReadWrite.All, Directory.Read.All` |

---

## Output format

Every action returns a JSON object:

```json
{
  "ok": true,
  "action": "get_user",
  "message": "Retrieved user 'jane@contoso.com'.",
  "timestamp": "2026-05-22T...",
  "mock_or_test_result": false,
  "user": { ... }
}
```

On failure `ok` is `false` and `message` contains the error text.
