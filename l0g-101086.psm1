# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2018 Jacob Keller. All rights reserved.

# This module contains several functions which are shared between the scripts
# related to uploading and formatting GW2 ArcDPS log files. It contains some
# general purpose utility functions, as well as functions related to managing
# the configuration file

<#
 .Synopsis
  Tests whether a path exists

 .Description
  Tests wither a given path exists. It is safe to pass a $null value to this
  function, as it will return $false in that case.

 .Parameter Path
  The path to test
#>
Function X-Test-Path {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$path)
    try {
        return Test-Path $path.trim()
    } catch {
        return $false
    }
}

<#
 .Synopsis
  Convert UTC time to the local timezone

 .Description
  Take a UTC date time object containing a UTC time and convert it to the
  local time zone

 .Parameter Time
  The UTC time value to convert
#>
Function ConvertFrom-UTC {
    [CmdletBinding()]
    param([Parameter(Mandatory)][DateTime]$time)
    [TimeZone]::CurrentTimeZone.ToLocalTime($time)
}


<#
 .Synopsis
  Convert a Unix timestamp to a DateTime object

 .Description
  Given a Unix timestamp (integer containing seconds since the Unix Epoch),
  convert it to a DateTime object representing the same time.

 .Parameter UnixDate
  The Unix timestamp to convert
#>
Function ConvertFrom-UnixDate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$UnixDate)
    ConvertFrom-UTC ([DateTime]'1/1/1970').AddSeconds($UnixDate)
}

<#
 .Synopsis
  Convert DateTime object into a Unix timestamp

 .Description
  Given a DateTime object, convert it to an integer representing seconds since
  the Unix Epoch.

 .Parameter Date
  The DateTime object to convert
#>
Function ConvertTo-UnixDate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][DateTime]$Date)
    $UnixEpoch = [DateTime]'1/1/1970'
    (New-TimeSpan -Start $UnixEpoch -End $Date).TotalSeconds
}

<#
 .Synopsis
  Returns the NoteProperties of a PSCustomObject

 .Description
  Given a PSCustomObject, return the names of each NoteProperty in the object

 .Parameter obj
  The PSCustomObject to match
#>
Function Keys {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$obj)

    return @($obj | Get-Member -MemberType NoteProperty | % Name)
}

<#
 .Description
  Configuration fields which are valid for multiple versions of the
  configuration file. Currently this is shared between the v1 and v2
  formats, as they share a common base of configuration fields.

  If path is set, then the configuration will allow exchanging %UserProfile%
  for the current $env:USERPROFILE value

  If validFields is set to an array if fields, then the subfield will be
  recursively validated. If arrayFields is set, then the field will be treated as
  an array of objects and each object in the array will be recursively validated.

  Path, validFields, and arrayFields are mutually exclusive
#>
$commonConfigurationFields =
@(
    @{
        name="config_version"
        type=[int]
    }
    @{
        name="debug_mode"
        type=[bool]
    }
    @{
        name="arcdps_logs"
        type=[string]
        path=$true
    }
    @{
        name="discord_json_data"
        type=[string]
        path=$true
    }
    @{
        name="extra_upload_data"
        type=[string]
        path=$true
    }
    @{
        name="gw2raidar_start_map"
        type=[string]
        path=$true
    }
    @{
        name="last_format_file"
        type=[string]
        path=$true
    }
    @{
        name="last_upload_file"
        type=[string]
        path=$true
    }
    @{
        name="simple_arc_parse_path"
        type=[string]
        path=$true
    }
    @{
        name="upload_log_file"
        type=[string]
        path=$true
    }
    @{
        name="guildwars2_path"
        type=[string]
        path=$true
    }
    @{
        name="dll_backup_path"
        type=[string]
        path=$true
    }
    @{
        name="gw2raidar_token"
        type=[string]
    }
    @{
        name="dps_report_token"
        type=[string]
    }
)


<#
 .Description
  Configuration fields which are valid for a v1 configuration file. Anything
  not listed here will be excluded from the generated $config object. If one
  of the fields has an incorrect type, configuration will fail to be validated.

  Fields which are common to many versions of the configuration file are stored
  in $commonConfigurationFields
#>
$v1ConfigurationFields = $commonConfigurationFields +
@(
    @{
        name="custom_tags_script"
        type=[string]
        path=$true
    }
    @{
        name="discord_webhook"
        type=[string]
    }
    @{
        name="guild_thumbnail"
        type=[string]
    }
    @{
        name="gw2raidar_tag_glob"
        type=[string]
    }
    @{
        name="guild_text"
        type=[string]
    }
    @{
        name="discord_map"
        type=[PSCustomObject]
    }
    @{
        name="emoji_map"
        type=[PSCustomObject]
    }
    @{
        name="publish_fractals"
        type=[bool]
    }
)

<#
 .Description
  Configuration fields which are valid for a v2 configuration file. Anything
  not listed here will be excluded from the generated $config object. If one
  of the fields has an incorrect type, configuration will fail to be validated.

  Fields which are common to many versions of the configuration file are stored
  in $commonConfigurationFields
#>
$v2ValidGuildFields =
@(
    @{
        name="name"
        type=[string]
    }
    @{
        name="priority"
        type=[int]
    }
    @{
        name="tag"
        type=[string]
    }
    @{
        name="webhook_url"
        type=[string]
    }
    @{
        name="thumbnail"
        type=[string]
    }
    @{
        name="fractals"
        type=[bool]
    }
    @{
        name="discord_map"
        type=[PSCustomObject]
    }
    @{
        name="emoji_map"
        type=[PSCustomObject]
    }
)

$v2ConfigurationFields = $commonConfigurationFields +
@(
    @{
        name="guilds"
        type=[Object[]]
        arrayFields=$v2ValidGuildFields
    }
)

<#
 .Synopsis
  Validate fields of an object

 .Description
  Given a set of field definitions, validate that the given object has fields
  of the correct type, possibly recursively.

  Return the object on success, with updated path data if necessary. Unknown fields
  will be removed from the returned object.

  Return $null if the object has invalid fields or is missing required fields.

 .Parameter object
  The object to validate

 .Parameter fields
  The field definition
#>
Function Validate-Object-Fields {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$Object,
          [Parameter(Mandatory)][array]$Fields,
          [Parameter(Mandatory)][AllowEmptyCollection()][array]$RequiredFields)

    # Make sure all the required parameters are actually valid
    ForEach ($parameter in $RequiredParameters) {
        if ($parameter -notin ($Fields | ForEach-Object { $_.name })) {
            Read-Host -Prompt "BUG: $parameter is not a valid parameter. Press enter to exit"
            exit
        }
    }

    # Select only the known properties, ignoring unknown properties
    $Object = $Object | Select-Object -Property ($Fields | ForEach-Object { $_.name } | where { $Object."$_" -ne $null })

    $invalid = $false
    foreach ($field in $Fields) {
        # Make sure required parameters are available
        if (-not (Get-Member -InputObject $Object -Name $field.name)) {
            if ($field.name -in $RequiredFields) {
                Write-Host "$($field.name) is a required parameter for this script."
                $invalid = $true
            }
            continue
        }

        # Make sure that the field has the expected type
        if ($Object."$($field.name)" -isnot $field.type) {
            Write-Host "$($field.name) has an unexpected type [$($Object."$($field.name)".GetType().name)]"
            $invalid = $true
            continue;
        }

        if ($field.path) {
            # Handle %UserProfile% in path fields
            $Object."$($field.name)" = $Object."$($field.name)".replace("%UserProfile%", $env:USERPROFILE)
        } elseif ($field.validFields) {
            # Recursively validate subfields. For now, just require every subfield to be set
            $Object."$($field.name)" = Validate-Object-Fields $Object."$($field.name)" $field.validFields ($field.validFields | ForEach-Object { $_.name } )
        } elseif ($field.arrayFields) {
            # Recursively validate subfields of an array of objects.  For now, just require every subfield to be set
            $ValidatedSubObjects = @()

            $arrayObjectInvalid = $false

            ForEach ($SubObject in $Object."$($field.name)") {
                $SubObject = Validate-Object-Fields $SubObject $field.arrayFields ($field.arrayFields | ForEach-Object { $_.name } )
                if (-not $SubObject) {
                    $arrayObjectInvalid = $true
                    break;
                }
                $ValidatedSubObjects += $SubObject
            }
            # If any of the sub fields was invalid, the whole array is invalid
            if ($arrayObjectInvalid) {
                $Object."$($field.name)" = $null
            } else {
                $Object."$($field.name)" = $ValidatedSubObjects
            }
        }

        # If the subfield is now null, then the recursive validation failed, and this whole field is invalid
        if ($Object."$($field.name)" -eq $null) {
            $invalid = $true
        }
    }

    if ($invalid) {
        Read-Host -Prompt "Configuration file has invalid parameters. Press enter to exit"
        return
    }

    return $Object
}

<#
 .Synopsis
  Validate a configuration object to make sure it has correct fields

 .Description
  Take a $config object, and verify that it has valid parameters with the expected
  information and types. Return the $config object on success (with updated path names)
  Return $null if the $config object is not valid.

 .Parameter config
  The configuration object to validate

 .Parameter RequiredParameters
  The parameters that are required by the invoking script
#>
Function Validate-Configuration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$config,
          [Parameter(Mandatory)][int]$version,
          [Parameter(Mandatory)][AllowEmptyCollection()][array]$RequiredParameters)

    if ($version -eq 1) {
        $configurationFields = $v1ConfigurationFields
    } elseif ($version -eq 2) {
        $configurationFields = $v2ConfigurationFields
    } else {
        Read-Host -Prompt "BUG: configuration validation does not support version ${version}. Press enter to exit"
        exit
    }

    # For now, allow an empty config_version
    if (-not $config.PSObject.Properties.Match("config_version")) {
        Write-Host "Configuration file is missing config_version field. This will be required in a future update. Please set it to the value '1'"
        $config.config_version = 1
    }

    # Make sure the config_version is set to 1. This should only be bumped if
    # the expected configuration names change. New fields should not cause a
    # bump in this version, but only removal or change of fields.
    #
    # Scripts should be resilient against new parameters not being configured.
    if ($config.config_version -ne $version) {
        Read-Host -Prompt "This script only knows how to understand config_version=${version}. Press enter to exit"
        return
    }

    $config = Validate-Object-Fields $config $configurationFields $RequiredParameters

    return $config
}

<#
 .Synopsis
  Load the configuration file and return a configuration object

 .Description
  Load the specified configuration file and return a valid configuration
  object. Will ignore unknown fields in the configuration JSON, and will
  convert magic path strings in path-like fields

 .Parameter ConfigFile
  The configuration file to load

 .Parameter version
  The version of the config file we expect, defaults to 1 currently.

 .Parameter RequiredParameters
  An array of parameters required by the script. Will ensure that the generated
  config object has non-null values for the specified paramters. Defaults to
  an empty array, meaning no parameters are required.
#>
Function Load-Configuration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigFile,
          [int]$version = 1,
          [AllowEmptyCollection()][array]$RequiredParameters = @())

    # Check that the configuration file path is valid
    if (-not (X-Test-Path $ConfigFile)) {
        Read-Host -Prompt "Unable to locate the configuration file. Press enter to exit"
        return
    }

    # Parse the configuration file and convert it from JSON
    try {
        $config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json
    } catch {
        Write-Host "Unable to read the configuration file: $($_.Exception.Message)"
        Read-Host -Prompt "Press enter to exit"
        return
    }

    $config = (Validate-Configuration $config $version $RequiredParameters)
    if (-not $config) {
        return
    }

    return $config
}
