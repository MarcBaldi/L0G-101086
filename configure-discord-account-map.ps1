# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2018 Jacob Keller. All rights reserved.
# vim: et:ts=4:sw=4

# Terminate on all errors...
$ErrorActionPreference = "Stop"

# Load the shared module
Import-Module -Force -DisableNameChecking (Join-Path -Path $PSScriptRoot -ChildPath l0g-101086.psm1)

# Path to JSON-formatted configuration file
$config_file = Get-Config-File
$backup_file = "${config_file}.bk"

# discord_map
#
# The discord_map is a mapping of GW2 account names to discord user
# ids. It should be a hash map keyed by the GW2 account name. The
# discord user IDs are expected to be the full hiddden ID of the
# player mention as shown by typing \@discord name (for example
# "\@serenamyr#8942") into a discord channel. You can also find it
# by enabling the Developer tools configuration in Discord and then
# right clicking a player mention and selecting "Copy ID"
#
# This is expected to be a hash table

if (X-Test-Path $backup_file) {
    Read-Host -Prompt "Please remove the backup file before running this script. Press enter to exit"
    exit
}

# Load the configuration from the default file
$config = Load-Configuration $config_file 2
if (-not $config) {
    exit
}

Write-Output "The configuration file has the following guilds:"

$config.guilds | ForEach-Object {
    Write-Output "$($_.name)"
}

$guild_name = Read-Host -Prompt "Which guild would you like to configure?"

$guild = $config.guilds | where { $_.name -eq $guild_name }

if (-not $guild) {
    Write-Output "${guild_name} is not one of the configured guilds."
    Read-Host -Prompt "Press any key to exit."
    exit
}

# Check if the token has already been set
if ($guild.discord_map) {
    Write-Output "A discord account map already exists for this guild."

    # offer to delete any current mappings
    $guild.discord_map | Get-Member -Type NoteProperty | where { $guild.discord_map."$($_.Name)" -is [string] } | ForEach-Object {
        $delete = Read-Host -Prompt "Delete mapping for $($_.Name))? (Y/N)"
        if ($delete -eq "Y") {
            $guild.discord_map.PSObject.Members.Remove($_.Name)
        }
    }
}

# ask if the user wants to add more mappings
do {
    Write-Output = ""
    $add = Read-Host -Prompt "Would you like to add a new mappping? (Y/N)"
    if ($add -eq "Y") {
        Write-Output "I need a Guild Wars 2 account name and the assiocated discord id"
        Write-Output "To generate the discord id you can enter their mention into a"
        Write-Output "discord channel, prefixed by a backslash"
        Write-Output ""
        $gw2name = Read-Host -Prompt "GW2 account name"
        $discord = Read-Host -Prompt "Discord id"
        if ((-not $gw2name) -or (-not $discord)) {
            continue
        }
        $guild.discord_map | Add-Member -MemberType NoteProperty -Name "$gw2name" -Value "$discord"
    }
} while ($add -eq "Y")

# Write the configuration file out
Write-Configuration $config $config_file $backup_file

Read-Host -Prompt "Configured the discord account map. Press enter to exit"
exit

