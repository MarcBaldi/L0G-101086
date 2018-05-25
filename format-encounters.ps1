# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2018 Jacob Keller. All rights reserved.

# Terminate on all errors...
$ErrorActionPreference = "Stop"

# Path to JSON-formatted configuration file
$config_file = "l0g-101086-config.json"

# Relevant customizable configuration fields
#
# This script depends on some configuration which is meaningful
# only to the invididual user, or is not sharable for security or
# privacy concerns. This information is found in the JSON configuration
# file. The "l0g-101086-config.sample.json" file can be used as a
# basic reference to setup your own configuration

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

# discord_webhook
#
# This should contain  the URL for the discord webhook that this script
# will talk to. It can be found in the webhooks configuration page of the
# discord server. Anyone who has this link can submit content to the channel
# so it is best to keep this private.

# restsharp_path
#
# This script relies on RestSharp (http://restsharp.org/) because the built in
# "Invoke-WebRequest" was not able to work for all uses needed. This should
# be the complete path to the RestSharp.dll as obtained from RestSharp's website.

# gw2raidar_token
#
# This is the token obtained from gw2raidar's API, in connection with your account.
# It can be obtained through a webbrowser by logging into gw2raidar.com and visiting
# "https://www.gw2raidar.com/api/v2/swagger#/token"

# gw2raidar_tag_glob
#
# Set this to a glob string which matches encounter tags. If you wish to match any
# tags, or don't care about tags at all, set it to "*". Otherwise set it to a glob
# which matches the tags you care about.

# guild_text
#
# This text is shown as part of the title of the webhook posts. Any text is suitable
# but it was intended to be the guild tag, for example "[eV]"

# discord_json_data
#
# Folder which will contain the complete JSON as sent to the webserver, for debug
# purposes. May be set to the empty string, in which case this data will not be
# saved.

# last_format_file
#
# Complete path to a file which will store the last format time, used to prevent
# reposting of previous logs. The file will be stored in JSON data.

# extra_upload_data
#
# This script requires some extra data generated by upload-logs.ps1 and stored
# in a particular location. This data is generated by the C++ simpleArcParse
# utility, in addition to the upload-logs.ps1 script itself. It contains a series
# of directories key'd off of the local evtc file name, and each folder hosts
# JSON formatted data for the player accounts who participated, the success/failure
# and the uploaded dps.report link if any.

# gw2raidar_start_map
#
# This script correlates gw2raidar links to the local evtc files (and thus the dps.report files)
# by using the server start time associated with the log. It parses this data out using
# simpleArcParse, which is a C++ program designed to read minimal data from evtc files.
#
# Gw2raidar does not currently provide the original file upload, so we match it based on the
# server start time. To do so, upload-logs.ps1 stores a folder within $start_map named
# after the start time of the encounter, and inside this, hosts a JSON data file which contains
# the local evtc file name. This essenitally builds a mini-database for mapping gw2raidar
# links back to local evtc files so we can obtain player names and the dps.report links

# guild_thumbnail
#
# This is a link to an icon to show in the top right corner of the post as a thumbnail.
# We use it as a Guild thumbnail image, but this could be anything. It is expected to
# be a URL to an image file.

# emoji_map
#
# The emoji data is a map which stores the specific discord ID that maps to the emoji
# that you wish to display for each boss. This can be found by typing "\emoji" into
# a discord channel, and should return a link similar to <emoji123456789> which you
# need to place into a hash map keyed by the boss name.

# debug_mode
#
# Enables debugging mode. This will disable checking the last_format_file, and will
# output the JSON text to the console immediately instead of saving a file.
#
# It is useful to enable this during debugging so that you get immediate feedback,
# and don't have to manually edit the last_format_file every time to allow the script
# to find old encounters again. In general you should probably point your discord
# webhook to a separate hidden channel so that you don't spam anyone else on the discord
# server.

$config = Get-Content -Raw -Path $config_file | ConvertFrom-Json

# Allow path configurations to contain %UserProfile%, replacing them with the environment variable
$config | Get-Member -Type NoteProperty | where { $config."$($_.Name)" -is [string] } | ForEach-Object {
    $config."$($_.Name)" = ($config."$($_.Name)").replace("%UserProfile%", $env:USERPROFILE)
}

# We absolutely require a gw2raidar token
if (-not $config.gw2raidar_token) {
    Read-Host -Prompt "This script requires a gw2raidar authentication token. Press enter to exit"
    exit
}

# This script makes no sense without a webhook URL
if (-not $config.discord_webhook) {
    Read-Host -Prompt "This script requires a discord webhook URL. Press enter to exit"
    exit
}

# Convert UTC time into the local time zone
Function ConvertFrom-UTC($utc) {
    [TimeZone]::CurrentTimeZone.ToLocalTime($utc)
}

# Convert a unix timestamp (seconds since the Unix epoch) into a DateTime object
Function ConvertFrom-UnixDate ($UnixDate) {
    ConvertFrom-UTC ([DateTime]'1/1/1970').AddSeconds($UnixDate)
}

# Convert a DateTime object into a unix epoch timestamp
Function ConvertTo-UnixDate ($date) {
    $unixEpoch = [DateTime]'1/1/1970'
    (New-TimeSpan -Start $unixEpoch -End $date).TotalSeconds
}

# Loads account names from the local data directory
Function Get-Local-Players ($boss) {
    $names = @()

    if (!$boss.evtc) {
        return $names
    }

    $accounts = Get-Content -Raw -Path ([io.path]::combine($config.extra_upload_data, $boss.evtc, "accounts.json")) | ConvertFrom-Json
    ForEach ($account in ($accounts | Sort)) {
        if ($config.discord_map."$account") {
            $names += @($config.discord_map."$account")
        } elseif ($account -ne "") {
            $names += @("_${account}_")
        }
    }

    return $names
}

# Loads dps.report link from the local data directory
Function Get-Local-DpsReport ($boss) {
    if (!$boss.evtc) {
        return ""
    }

    $dpsreport_json = [io.path]::combine($config.extra_upload_data, $boss.evtc, "dpsreport.json")

    if (!(Test-Path -Path $dpsreport_json)) {
        return ""
    }

    $dps_report = Get-Content -Raw -Path $dpsreport_json | ConvertFrom-Json
    return $dps_report.permalink
}

# Load RestSharp
Add-Type -Path $config.restsharp_path

$gw2raidar_url = "https://gw2raidar.com"
$complete = $false

$nameToId = @{}
$nameToCmId = @{}

# Main data structure tracking information about bosses as we discover it
$bosses = @(@{name="Vale Guardian";wing=1},
            @{name="Gorseval";wing=1},
            @{name="Sabetha";wing=1},
            @{name="Slothasor";wing=2},
            @{name="Matthias";wing=2},
            @{name="Keep Construct";wing=3},
            @{name="Xera";wing=3},
            @{name="Cairn";wing=4},
            @{name="Mursaat Overseer";wing=4},
            @{name="Samarog";wing=4},
            @{name="Deimos";wing=4},
            @{name="Soulless Horror";wing=5},
            @{name="Dhuum";wing=5})

# Get the area IDs
$client = New-Object RestSharp.RestClient($gw2raidar_url)
$req = New-Object RestSharp.RestRequest("/api/v2/areas")
$req.AddHeader("Authorization", "Token $($config.gw2raidar_token)") | Out-Null
$req.Method = [RestSharp.Method]::GET

$resp = $client.Execute($req)

if ($resp.ResponseStatus -ne [RestSharp.ResponseStatus]::Completed) {
    Read-Host -Prompt "Areas request Failed, press Enter to exit"
    exit
}

$areasResp = $resp.Content | ConvertFrom-Json

# Treat Challenge Mote encounters the same as regular ones
ForEach($area in $areasResp.results) {
    if ($area.name -Match " \(CM\)$") {
        $name = $area.name -Replace " \(CM\)$", ""
        $nameToCmId.Set_Item($name, $area.id)
    } else {
        $nameToId.Set_Item($area.name, $area.id)
    }
}

# Insert IDs
$bosses | ForEach-Object { $name = $_.name; $_.Set_Item("id", $nameToId.$name); $_.Set_Item("cm_id", $nameToCmId.$name) }

# Load the last upload time, or go back forever if we can't find it
if ((-not $config.debug_mode) -and (Test-Path $config.last_format_file)) {
    $last_format_time = Get-Content -Raw -Path $config.last_format_file | ConvertFrom-Json | Select-Object -ExpandProperty "DateTime" | Get-Date
    $since = ConvertTo-UnixDate ((Get-Date -Date $last_format_time).ToUniversalTime())
} else {
    $since = 0
}

# Limit ourselves to 15 encounters at a time
$request = "/api/v2/encounters?limit=15&since=${since}"

# Main loop for getting gw2raidar links
Do {
    # Request a chunk of encounters
    $client = New-Object RestSharp.RestClient($gw2raidar_url)
    $req = New-Object RestSharp.RestRequest($request)
    $req.AddHeader("Authorization", "Token $($config.gw2raidar_token)") | Out-Null
    $req.Method = [RestSharp.Method]::GET

    $resp = $client.Execute($req)

    if ($resp.ResponseStatus -ne [RestSharp.ResponseStatus]::Completed) {
        Read-Host -Prompt "Request Failed, press Enter to exit"
        exit
    }

    $data = $resp.Content | ConvertFrom-Json

    # When we get no further results, break the loop
    if (!($data.results)) {
        break
    }

    # Parse each encounter from the results
    ForEach($encounter in $data.results) {
        $area_id = $encounter.area_id
        $url_id = $encounter.url_id
        $url = "${gw2raidar_url}/encounter/${url_id}"
        $time = ConvertFrom-UnixDate $encounter.started_at
        $age = New-TimeSpan -Start $time

        if (-not ( $encounter.tags -like $config.gw2raidar_tag_glob ) ) {
            continue
        }

        # See if we have matching local data for this encounter.
        # Local data is accessed from the extra_upload_data folder, by using
        # the gw2raidar_start_map as a mapping between encounter start time
        # and the local evtc file data that we created using upload-logs.ps1
        $map_dir = Join-Path -Path $config.gw2raidar_start_map -ChildPath $encounter.started_at
        if (Test-Path -Path $map_dir) {
            $evtc_name = Get-Content -Raw -Path (Join-Path -Path $map_dir -ChildPath "evtc.json") | ConvertFrom-Json
        } else {
            $evtc_name = $null
        }

        # Insert the url and other data into the boss list
        #
        # Note that we search in *reverse* (newest first), so as soon as we find
        # a url for a particular encounter we will not overwrite it.
        $bosses | where { -not $_.ContainsKey("url") -and ($_.id -eq $area_id -or $_.cm_id -eq $area_id) } | ForEach-Object { $_.Set_Item("url", $url); $_.Set_Item("age", $age); $_.Set_Item("time", $time); $_.Set_Item("evtc", $evtc_name) }
    }

    # If the gw2raidar API gave us a $next url, then there are more
    # encounters available to check.
    if ($data.next) {
        $request = $data.next -replace $gw2raidar_url, ""
    } else {
        $complete = $true
    }

    # We only want to show the latest run of each boss,
    # so we check to see if we've found a match for every boss
    # encounter. If so, we stop the loop
    if ( $bosses | where { -not $_.ContainsKey("url") } ) {
        # We're still missing boss URLs
    } else {
        $complete = $true
    }

} Until($complete)

# If we didnt't any URLs, this means that there are no
# bosses to publish. Note this excludes the case where
# we happen to have a dps.report without a gw2raidar URL
if (-not ( $bosses | where { $_.ContainsKey("url") } ) ) {
    Read-Host -Prompt "No new encounters to format. Press Enter to exit"
    exit
}

$boss_per_date = @{}

$this_format_time = Get-Date

$datestamp = Get-Date -Date $this_format_time -Format "yyyyMMdd-HHmmss"

# We show a set of encounters based on the day that they occurred, so if you
# run some encounters on one day, and some on another, you could run this script
# only on the second day and it would publish two separate pages for each
# day.
$bosses | ForEach-Object {
    # Skip bosses which weren't found
    if (-not $_.ContainsKey("url")) {
        return
    }

    if (-not $boss_per_date.ContainsKey($_.time.Date)) {
        $boss_per_date[$_.time.Date] = @()
    }
    $boss_per_date[$_.time.Date] += ,@($_)
}

# object holding the thumbnail URL
if ($config.guild_thumbnail) {
    $thumbnail = [PSCustomObject]@{
        url = $config.guild_thumbnail
    }
} else {
    $thumbnail = $null
}

$data = @()

$boss_per_date.GetEnumerator() | Sort-Object -Property {$_.Key.DayOfWeek}, key | ForEach-Object {
    $date = $_.key
    $some_bosses = $_.value
    $players = @()
    $fields = @()

    # We sort the bosses based on server start time
    ForEach ($boss in $some_bosses | Sort-Object -Property {$_.time}) {
        if ( -not ( $boss.ContainsKey("url") ) ) {
            continue
        }

        $name = $boss.name
        $emoji = $config.emoji_map."$name"

        $players += Get-Local-Players $boss
        $dps_report = Get-Local-DpsReport $boss

        $url = $boss.url

        # For each boss, we add a field object to the embed
        #
        # Note that PowerShell's default ConvertTo-Jsom does not handle unicode
        # characters very well, so we use @NAME@ replacement strings to represent
        # these characters, which we'll replace after calling ConvertTo-Json
        # See Convert-Payload for more details
        #
        # In some cases, we might reach here without a valid dps.report url. This
        # may occur because gw2raidar might return a URL which we don't have local
        # data for. In this case, just show the gw2raidar link alone.
        $boss_field = [PSCustomObject]@{
                # Each boss is just an emoji followed by the full name
                name = "${emoji} **${name}**"
                inline = $true
        }
        if ($dps_report) {
            # We put both the dps.report link and gw2raidar link here. We separate them by a MIDDLE DOT
            # unicode character, and we use markdown to format the URLs to include the URL as part of the
            # hover-over text.
            #
            # Discord eats extra spaces, but doesn't recognize the "zero width" space character, so we
            # insert that on an extra line in order to provide more spacing between elements
            $boss_field | Add-Member @{value="[dps.report](${dps_report} `"${dps_report}`") @MIDDLEDOT@ [gw2raidar](${url} `"${url}`")`r`n@UNICODE-ZWS@"}
        } else {
            $boss_field | Add-Member @{value="[gw2raidar](${url} `"${url}`")`r`n@UNICODE-ZWS@"}
        }

        # Insert the boss field into the array
        $fields += $boss_field
    }

    # Create a participants list separated by MIDDLE DOT unicode characters
    $participants = ($players | Select-Object -Unique) -join " @MIDDLEDOT@ "

    # Add a final field as the set of players.
    if ($participants) {
        $fields += [PSCustomObject]@{
            name = "@EMDASH@ Raiders @EMDASH@"
            value = "${participants}"
        }
    }

    # Determine which wings we did
    $wings = $($some_bosses | Sort-Object -Property {$_.time} | ForEach-Object {$_.wing} | Get-Unique) -join ", "

    $date = Get-Date -Format "MMM d, yyyy" -Date $date

    # Create the data object for this date, and add it to the list
    $data_object = [PSCustomObject]@{
        title = "$($config.guild_text) Wings: ${wings} | ${date}"
        color = 0xf9a825
        fields = $fields
    }
    if ($thumbnail) {
        $data_object | Add-Member @{thumbnail=$thumbnail}
    }
    $data += $data_object
}

# Create the payload object
$payload = [PSCustomObject]@{
    embeds = @($data)
}

# ConvertTo-JSON doesn't handle unicode characters very well, but we want to
# insert a zero-width space. To do so, we'll implement a variant that replaces
# a magic string with the expected value
#
# More strings can be added here if necessary. The initial string should be
# something innocuous which won't be generated as part of any URL or other
# generated text, and is unlikely to appear on accident
Function Convert-Payload($payload) {
    # Convert the object into a JSON string, using an increased
    # depth so that the ConvertTo-Json will completely convert
    # the layered object into JSON.
    $json = ($payload | ConvertTo-Json -Depth 10)

    $unicode_map = @{"@UNICODE-ZWS@"="\u200b";
                     "@BOXDASH@"="\u2500";
                     "@EMDASH@"="\u2014";
                     "@MIDDLEDOT@"="\u00B7"}

    # Because ConvertTo-Json doesn't really handle all of the
    # unicode characters, we need to insert these after the fact.
    $unicode_map.GetEnumerator() | ForEach-Object {
        $json = $json.replace($_.key, $_.value)
    }
    return $json
}

if ($config.debug_mode) {
    (Convert-Payload $payload) | Write-Output
} elseif (Test-Path $config.discord_json_data) {
    # Store the complete JSON we generated for later debugging
    $discord_json_file = Join-Path -Path $config.discord_json_data -ChildPath "discord-webhook-${datestamp}.txt"
    (Convert-Payload $payload) | Out-File $discord_json_file
}

# Send this request to the discord webhook
Invoke-RestMethod -Uri $config.discord_webhook -Method Post -Body (Convert-Payload $payload)

# Update the last_format_file with the new format time, so that
# future runs won't repost old links
if ((-not $config.debug_mode) -and (Test-Path $config.last_format_file)) {
    $this_format_time | Select-Object -Property DateTime| ConvertTo-Json | Out-File -Force $config.last_format_file
}
