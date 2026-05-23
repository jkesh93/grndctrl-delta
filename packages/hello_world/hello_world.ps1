<#
.SYNOPSIS
    Hello World — grndctrl-delta example package.

.DESCRIPTION
    Demonstrates the single-script / multi-action pattern used by grndctrl-delta packages.
    A -Action parameter dispatches to the relevant internal function.
    GroundControl injects this automatically based on the action name in package.json.

.NOTES
    Package : hello_world
    Version : 1.0.0
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("say_hello")]
    [string]$Action = "say_hello",

    # say_hello params
    [Parameter(Mandatory = $false)]
    [string]$Name = "World"
)

# ---------------------------------------------------------------------------
# Shared helpers (would normally dot-source gc_logging here)
# ---------------------------------------------------------------------------
function Write-GcLog {
    param([string]$Level, [string]$Message)
    $entry = [ordered]@{
        timestamp = (Get-Date -Format "o")
        level     = $Level
        package   = "hello_world"
        message   = $Message
    }
    Write-Output ($entry | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
function Invoke-SayHello {
    param([string]$Name)

    Write-GcLog -Level "INFO" -Message "Invoke-SayHello called with Name='$Name'"

    $result = @{
        ok      = $true
        message = "Hello, $Name! GroundControl is operational."
    }

    Write-Output ($result | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------
switch ($Action) {
    "say_hello" { Invoke-SayHello -Name $Name }
    default     {
        Write-GcLog -Level "ERROR" -Message "Unknown action: $Action"
        Write-Output '{"ok":false,"error":"Unknown action"}'
        exit 1
    }
}
