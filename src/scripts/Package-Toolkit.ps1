# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Packages all toolkit templates for release.

    .DESCRIPTION
    Run this from the /src/scripts folder.

    .PARAMETER Template
    Optional. Name of the template or module to package. Default = * (all).

    .PARAMETER Build
    Optional. Indicates whether the Build-Toolkit command should be executed first. Default = false.

    .PARAMETER PowerBI
    Optional. Indicates whether to open Power BI files as part of the packaging process. Default = false.

    .EXAMPLE
    ./Package-Toolkit

    Generates ZIP files for each template using an existing build.

    .EXAMPLE
    ./Package-Toolkit -Build

    Builds the latest code and generates ZIP files for each template.

    .EXAMPLE
    ./Package-Toolkit -Build -PowerBI

    Builds the latest code, generates ZIP files for each template, and opens Power BI projects to be saved as PBIX files.
#>
Param(
    [Parameter(Position = 0)][string]$Template = "*",
    [switch]$Build,
    [switch]$PowerBI
)

# Use the debug flag from common parameters to determine whether to run in debug mode
$Debug = $DebugPreference -eq "Continue"

# Build toolkit if requested
if ($Build)
{
    Write-Verbose "Building $(if ($Template -eq "*") { "all templates" } else { "the $Template template" })..."
    & "$PSScriptRoot/Build-Toolkit" $Template
}

$relDir = "$PSScriptRoot/../../release"
$deployDir = "$PSScriptRoot/../../docs/deploy"

# Validate template
if ($Template -ne "*" -and -not (Test-Path $relDir))
{
    Write-Error "$Template template not found. Please confirm template name."
    return
}

Write-Host "Packaging v$version templates..."

# Package templates
$version = & "$PSScriptRoot/Get-Version"
$isPrerelease = $version -like '*-*'

Write-Verbose "Removing existing ZIP files..."
Remove-Item "$relDir/*.zip" -Force

$templates = Get-ChildItem $relDir -Directory `
| ForEach-Object {
    Write-Verbose ("Packaging $_" -replace (Get-Item $relDir).FullName, '.')
    $path = $_
    $versionSubFolder = (Join-Path $path $version)
    $zip = Join-Path (Get-Item $relDir) "$($path.Name)-v$version.zip"

    Write-Verbose "Checking for a nested version folder: $versionSubFolder"
    if ((Test-Path -Path $versionSubFolder -PathType Container) -eq $true)
    {
        Write-Verbose "  Switching to sub folder"
        $path = $versionSubFolder
    }

    # Skip if template is a Bicep Registry module
    Write-Verbose "Checking version.json to see if it's targeting the Bicep Registry"
    if (Test-Path $path/version.json)
    {
        $versionSchema = (Get-Content "$path\version.json" -Raw | ConvertFrom-Json | Select-Object -ExpandProperty '$schema')
        if ($versionSchema -like '*bicep-registry-module*')
        {
            Write-Verbose "Skipping Bicep Registry module (not included in releases)"
            return
        }
    }

    # Copy azuredeploy.json to docs/deploy folder
    Write-Verbose "Updating $($path.Name) deployment file in docs..."
    Copy-Item "$path/azuredeploy.json" "$deployDir/$($path.Name)-$version.json"
    Copy-Item "$path/azuredeploy.json" "$deployDir/$($path.Name)-latest.json"
    Copy-Item "$path/createUiDefinition.json" "$deployDir/$($path.Name)-$version.ui.json"
    Copy-Item "$path/createUiDefinition.json" "$deployDir/$($path.Name)-latest.ui.json"

    Write-Verbose ("Compressing $path to $zip" -replace (Get-Item $relDir).FullName, '.')
    Compress-Archive -Path "$path/*" -DestinationPath $zip
    return $zip
}
Write-Host "✅ $($templates.Count) templates"
Write-Host "ℹ️ Deployment files updated... Please commit the changes manually..."

# Copy open data files
Write-Verbose "Copying open data files..."
Copy-Item "$PSScriptRoot/../open-data/*.csv" $relDir
Copy-Item "$PSScriptRoot/../open-data/*.json" $relDir
Write-Host "✅ $((@(Get-ChildItem "$relDir/*.csv") + @(Get-ChildItem "$relDir/*.json")).Count) open data files"

# Package sample data files together
Write-Verbose "Packaging open data files..."
Get-ChildItem -Path "$PSScriptRoot/../open-data" -Directory `
| ForEach-Object {
    $dir = $_
    Compress-Archive -Path "$dir/*.*" -DestinationPath "$relDir/$($dir.BaseName).zip"
    Write-Host "✅ $((Get-ChildItem "$dir/*.*").Count) $($dir.BaseName) files"
}

# Copy PBIX files
Write-Verbose "Copying PBIX files..."
Copy-Item "$PSScriptRoot/../power-bi/*.pbix" $relDir -Force
Write-Host "✅ $((Get-ChildItem "$PSScriptRoot/../power-bi/*.pbix").Count) PBIX files"

# Open Power BI projects
$pbi = Get-ChildItem "$PSScriptRoot/../power-bi/*.pbip"
if ($PowerBI)
{
    Write-Host "ℹ️ $($pbi.Count) Power BI projects must be converted manually... Opening..."
    $pbi | Invoke-Item
}
elseif ($isPrerelease)
{
    Write-Host "✖️ Skipping $($pbi.Count) Power BI projects for prerelease version"
}
else
{
    Write-Host "⚠️ $($pbi.Count) Power BI projects must be converted manually!"
    Write-Host '     To open them, run: ' -NoNewline
    Write-Host './Package-Toolkit -PowerBI' -ForegroundColor Cyan
}

# Update version in docs
$docVersionPath = "$PSScriptRoot/../../docs/_includes/ftkver.txt"
$versionInDocs = Get-Content $docVersionPath -Raw
if ($versionInDocs -eq $version)
{
    Write-Host "✅ Version in docs ($versionInDocs) already up-to-date"
}
else
{
    Write-Verbose "Updating version in docs..."
    $version | Out-File $docVersionPath -NoNewline
    Write-Host "ℹ️ Version updated in docs... Please commit the changes manually..."
}

Write-Host '...done!'
Write-Host ''
