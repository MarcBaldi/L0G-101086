# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2018 Jacob Keller. All rights reserved.
# vim: et:ts=4:sw=4

# Terminate on all errors...
$ErrorActionPreference = "Stop"

# Load the shared module
Import-Module -Force -DisableNameChecking (Join-Path -Path $PSScriptRoot -ChildPath l0g-101086.psm1)

# See l0g-101086.psm1 for descriptions of each configuration field
$RequiredParameters = @(
    "extra_upload_data"
    "last_format_file"
    "format_encounters_log"
    "arcdps_logs"
    "guilds"
)

# Load the configuration from the default file
$config = Load-Configuration (Get-Config-File) 2 $RequiredParameters
if (-not $config) {
    exit
}

Set-Logfile $config.format_encounters_log

# Check that the ancillary data folder has already been created
if (-not (X-Test-Path $config.extra_upload_data)) {
    Read-Host -Prompt "The $($config.extra_upload_data) can't be found. Try running upload-logs.ps1 first? Press enter to exit"
    exit
}

if (-not $config.discord_json_data) {
    Read-Host -Prompt "The discord JSON data directory must be configured. Press enter to exit"
    exit
} elseif (-not (X-Test-Path $config.discord_json_data)) {
    try {
        New-Item -ItemType directory -Path $config.discord_json_data
    } catch {
        Write-Exception $_
        Read-Host -Prompt "Unable to create $($config.discord_json_data). Press enter to exit"
        exit
    }
}

if (-not $config.last_format_file) {
    Read-Host -Prompt "A file to store last format time must be configured. Press enter to exit"
    exit
} elseif (-not (X-Test-Path (Split-Path $config.last_format_file))) {
    Read-Host -Prompt "The path for the last_format_file appears invalid. Press enter to exit"
    exit
}

Log-Output "~~~"
Log-Output "Formatting encounters for discord at $(Get-Date)..."
Log-Output "~~~"

# Load the last format time
if (X-Test-Path $config.last_format_file) {
    $last_format_time = Get-Content -Raw -Path $config.last_format_file | ConvertFrom-Json | Select-Object -ExpandProperty "DateTime" | Get-Date
}

$next_format_time = Get-Date

# If we have a last format time, we want to limit our scan to all files since
# the last time that we formatted.
#
# Search the extras directory for all evtc directories with a time newer than the last format time.
if (Test-Path $config.last_format_file) {
    $last_upload_time = Get-Content -Raw -Path $config.last_format_file | ConvertFrom-Json | Select-Object -ExpandProperty "DateTime" | Get-Date
    $dirs = @(Get-ChildItem -Directory -Filter "*.evtc" -LiteralPath $config.extra_upload_data | Where-Object { $_.CreationTime -gt $last_format_time} | Sort-Object -Property CreationTime | ForEach-Object {$_.Name})
} else {
    $dirs = @(Get-ChildItem -Directory -Filter "*.evtc" -LiteralPath $config.extra_upload_data | Sort-Object -Property CreationTime | ForEach-Object {$_.Name})
}

if ($dirs -and $dirs.Length -gt 0) {
    Log-And-Write-Output "Found $($dirs.Length) EVTC files to format and post"

    # Load each of the evtc directories as a boss hash table
    $bosses = @()
    foreach($d in $dirs) {
        $bosses += @(Load-From-EVTC $config $d)
    }

    Format-And-Publish-All $config $bosses
}

# Update the format time
$next_format_time | Select-Object -Property DateTime| ConvertTo-Json | Out-File -Force $config.last_format_file
# SIG # Begin signature block
# MIIFZAYJKoZIhvcNAQcCoIIFVTCCBVECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUzYLz83iSdKuUpnstLbHVd+1v
# scCgggMCMIIC/jCCAeagAwIBAgIQFFuA0ERIe5ZFRAzvqUXg0TANBgkqhkiG9w0B
# AQsFADAXMRUwEwYDVQQDDAxKYWNvYiBLZWxsZXIwHhcNMTgxMDI4MDU1MzQzWhcN
# MTkxMDI4MDYxMzQzWjAXMRUwEwYDVQQDDAxKYWNvYiBLZWxsZXIwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDXGkNeGuDBzVQwrOwaZx8ovS5BfaSsG5xx
# 3qaOK7YDsvpcebJMVK6eyjVO8X49bu4Q23ESyAmyD6udo+nGow2HmBaadmx3XtTY
# BDJrlf0dvf3j6HKsY/L9PQ1qa2lASDRoGUTZygflijc+Q9JJo7EG/QefwLrKF1Bw
# vF7eg6remPiJmT9JwhmEDy2H8jZn32B8+AAaaoYxP62+1kayn/smhHYLHBlzPSN3
# c8M74jGwIVLWHcy+3GS5cLQ2TgRiqLjTQujKn7t5EasGjsUZLNl/1mMUae4kt35E
# l+IThauMio4vm2ooB169X1hKS9/cd83bxzGkmxHbNYBdLsQK6USlAgMBAAGjRjBE
# MA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQU
# tKQNud96B8lWJUbI02sltSDIExkwDQYJKoZIhvcNAQELBQADggEBAIC17zjVumO0
# kgo+Qn/bmePqejGCZl5ajfYhNLMEBCnK1wqZBtV/7sAgK8HNBDuVJWRShGCJle6T
# XQrt5MaVqE5RMOxRMkSBTHHw1n+y63kfSUgL/7/m1VMlpUHFqnC5nnkzQNpDABwz
# irro884sMu9rwzOn2GqoRfA9iFjdd3+6o1PTh0ms6rGP+U40cWXwLia/gHYS9Nfj
# SJtrPmWejpWCRGaEimyDZoK+KZNGGecphrbU20vgNUaKVz2ukESa4bdpaAbaG51Z
# 3wmtVSFveRwVuhDPTkRSp2h9sMGqfK3KJZW/CPRYYE/UwpXTNttMfftJ83btibZ3
# j/LuvKgyF94xggHMMIIByAIBATArMBcxFTATBgNVBAMMDEphY29iIEtlbGxlcgIQ
# FFuA0ERIe5ZFRAzvqUXg0TAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU5znuTicseKLhEkMJ/PKm
# 1od/nkgwDQYJKoZIhvcNAQEBBQAEggEAH6YZTbQAf0Fc7ZQsyGHkSQbGHUp/hf2L
# vIKz/O+rX9lx41b7pRne4d6zOm3XGo8rRdaYVPzJMfc1JTcIh/mJf1UCe/rKM+Lh
# oLfOoYNoV6/3JUNrYlCHklhgJQQn9wGywME2W+eqK+a5eudGQi3A2Tk1q5NDR3aX
# kn7pGANGa/WAdEiv0kG2EnNc5lMM1O3F2tfbjvfHMoAvCy/e3jetpWu+rTKHiAZ0
# nsIf790KLWZ/DyfgTDk7ZBbiFz/afrAD56loDix6Fh0CCXrtWPBOajY25Eq+Vqol
# hOMFJffiHqDl5e0DS1uqRg9msKOHtevbwN5IzNwP2YhZb3laVZ7FGw==
# SIG # End signature block
