<#
.SYNOPSIS
    gc_logging.ps1 — shared structured logging module for grndctrl-delta packages.

.DESCRIPTION
    Dot-source this module at the top of any package script:

        . "$PSScriptRoot\..\modules\gc_logging.ps1"

    Then call Write-GcLog anywhere in your script.

.NOTES
    Module  : gc_logging
    Version : 1.0.0
#>

function Write-GcLog {
    <#
    .SYNOPSIS
        Writes a structured JSON log entry to stdout and optionally to a log file.

    .PARAMETER Level
        Severity level: DEBUG | INFO | WARN | ERROR

    .PARAMETER Message
        Human-readable log message.

    .PARAMETER Package
        Name of the calling package. Defaults to the calling script's base name.

    .PARAMETER Data
        Optional hashtable of additional structured fields to include in the log entry.
    #>
    param(
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level   = "INFO",

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Package = (Split-Path -LeafBase $MyInvocation.ScriptName),

        [hashtable]$Data = @{}
    )

    $entry = [ordered]@{
        timestamp = (Get-Date -Format "o")
        level     = $Level
        package   = $Package
        message   = $Message
    }

    foreach ($key in $Data.Keys) {
        $entry[$key] = $Data[$key]
    }

    $json = $entry | ConvertTo-Json -Compress
    Write-Output $json

    # Optional: write to GC_LOG_PATH if set in environment
    if ($env:GC_LOG_PATH) {
        try {
            Add-Content -Path $env:GC_LOG_PATH -Value $json -ErrorAction SilentlyContinue
        } catch {}
    }
}
