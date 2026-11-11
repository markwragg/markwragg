<#
.SYNOPSIS
    Refreshes the dynamic sections of the profile README.

.DESCRIPTION
    Updates three sections of README.md, each wrapped in HTML comment markers:
      <!--DOWNLOADS-->  total PowerShell Gallery downloads across all modules
      <!--MODULES-->    featured module table, sorted by download count
      <!--POSTS-->      most recent blog posts from the RSS/Atom feed

    If a data source can't be reached, that section is left as it is.

.EXAMPLE
    ./Update-Readme.ps1
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot 'README.md'),

    [string]$FeedUrl = 'https://wragg.io/feed.xml',

    [int]$PostCount = 3
)

$ErrorActionPreference = 'Stop'

# Every module published to the PowerShell Gallery (used for the total download count).
$AllModules = @(
    'Subnet', 'Influx', 'Watch', 'poshspec', 'HashCopy', 'ADAudit', 'CurrencyConverter', 'Lumos', 'AzCostTools',
    'Remedy', 'SlackBot', 'XKCD', 'MacNotify', 'PSHipChat', 'psprtg', 'nusync', 'Minecraft', 'AzureCAF'
)

# Modules shown in the table: name, GitHub repo and one-line description.
$Featured = @(
    @{ Name = 'Subnet';      Repo = 'PowerShell-Subnet';      Description = 'Network subnet calculations' }
    @{ Name = 'Influx';      Repo = 'PowerShell-Influx';      Description = 'Send metrics to InfluxDB' }
    @{ Name = 'Watch';       Repo = 'PowerShell-Watch';       Description = 'Re-run a scriptblock until its output changes' }
    @{ Name = 'HashCopy';    Repo = 'PowerShell-HashCopy';    Description = 'Copy only the files that have actually changed' }
    @{ Name = 'Lumos';       Repo = 'PowerShell-Lumos';       Description = 'Switch your OS between light and dark themes at sunrise and sunset' }
    @{ Name = 'AzCostTools'; Repo = 'PowerShell-AzCostTools'; Description = 'See where your Azure money is going' }
)

function Set-ReadmeSection {
    # Replaces the text between <!--Name--> and <!--/Name--> markers.
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $Pattern = "(?s)(<!--$Name-->).*?(<!--/$Name-->)"

    if ($Content -notmatch $Pattern) {
        throw "Marker '<!--$Name-->' was not found in the README."
    }

    [regex]::Replace($Content, $Pattern, { param($Match) $Match.Groups[1].Value + $Value + $Match.Groups[2].Value })
}

$Readme = Get-Content -Path $Path -Raw
$Original = $Readme

# --- PowerShell Gallery: total downloads and module table ---
try {
    $Downloads = @{}

    Find-Module -Name $AllModules -Repository PSGallery -ErrorAction SilentlyContinue | ForEach-Object {
        $Downloads[$_.Name] = [long]$_.AdditionalMetadata.downloadCount
    }

    $Total = ($Downloads.Values | Measure-Object -Sum).Sum

    if ($Total -lt 1) {
        throw 'No download counts were returned.'
    }

    # Round down to one decimal place, e.g. 2,180,055 becomes "2.1 million".
    $Millions = [math]::Floor($Total / 100000) / 10
    $Readme = Set-ReadmeSection -Content $Readme -Name 'DOWNLOADS' -Value ('{0:0.#} million' -f $Millions)

    $Rows = $Featured | Sort-Object { $Downloads[$_.Name] } -Descending | ForEach-Object {
        $VersionBadge = "[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/$($_.Name)?label=PS%20Gallery)](https://www.powershellgallery.com/packages/$($_.Name))"
        $DownloadsBadge = "[![Downloads](https://img.shields.io/powershellgallery/dt/$($_.Name)?color=D3D3D3)](https://www.powershellgallery.com/packages/$($_.Name))"
        "| [$($_.Name)](https://github.com/markwragg/$($_.Repo)) | $($_.Description) | $VersionBadge | $DownloadsBadge |"
    }

    $Table = @('| Module | What it does | Version | Downloads |', '| --- | --- | --- | --- |') + $Rows
    $Readme = Set-ReadmeSection -Content $Readme -Name 'MODULES' -Value ("`n" + ($Table -join "`n") + "`n")

    Write-Host "Gallery: $Total total downloads across $($Downloads.Count) modules."
}
catch {
    Write-Warning "Skipped the PowerShell Gallery sections: $_"
}

# --- Blog: latest posts ---
try {
    [xml]$Feed = (Invoke-WebRequest -Uri $FeedUrl).Content

    $Posts = $Feed.feed.entry | Select-Object -First $PostCount | ForEach-Object {
        $Title = if ($_.title -is [string]) { $_.title } else { $_.title.'#text' }
        $Title = [System.Net.WebUtility]::HtmlDecode($Title).Trim()
        $Link = @($_.link)[0].href

        if ($Title -and $Link) {
            "- [$Title]($Link)"
        }
    }

    if (-not $Posts) {
        throw 'No posts were found in the feed.'
    }

    $Readme = Set-ReadmeSection -Content $Readme -Name 'POSTS' -Value ("`n" + (@($Posts) -join "`n") + "`n")

    Write-Host "Blog: found $(@($Posts).Count) posts."
}
catch {
    Write-Warning "Skipped the blog section: $_"
}

if ($Readme -ne $Original) {
    Set-Content -Path $Path -Value $Readme -NoNewline
    Write-Host 'README updated.'
}
else {
    Write-Host 'No changes needed.'
}