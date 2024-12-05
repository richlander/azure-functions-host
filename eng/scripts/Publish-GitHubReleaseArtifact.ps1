#	
# Copyright (c) Microsoft. All rights reserved.	
# Licensed under the MIT license. See LICENSE file in the project root for full license information.	
#

param (
    [String]
    $BranchName,
    [String]
    $RepositoryName = 'Azure/azure-functions-host',
    [String]
    $ArtifactVersion,
    [String]
    $GithubToken
)

# Validate inputs
if (-not $BranchName) { Write-Log "BranchName cannot be null or empty" -Throw }
if (-not $RepositoryName) { Write-Log "RepositoryName cannot be null or empty" -Throw }
if (-not $ArtifactVersion) { Write-Log "ArtifactVersion cannot be null or empty" -Throw }

# GitHub API Token
# $GithubToken = $Env:GITHUB_PAT
if (-not $GithubToken) { Write-Log "GitHub token not found in environment variable 'GITHUB_PAT'" -Throw }

$headers = @{
    Authorization = "Bearer $GithubToken"
    'User-Agent' = 'PowerShell'
}

# Determine zip filters
Write-Log "Determining ZIP filters for ArtifactVersion: $ArtifactVersion"
$zipFilter = Get-ZipFilter -ArtifactVersion $ArtifactVersion

$symbolZipFilter = Get-SymbolZipFilter -ArtifactVersion $ArtifactVersion

# Find files based on the filters
#$artifactPath = $Env:SYSTEM_ARTIFACTSDIRECTORY
$artifactPath = "$PSScriptRoot/artifactsFolder"
$files = Get-ChildItem -Path $artifactPath -Filter *.zip -Recurse | Where-Object { $_.Name -match $zipFilter -or $_.Name -match $symbolZipFilter }

$shortenedVersion = Get-VersionFromAssembly -ArtifactPath $artifactPath -ZipFilter $zipFilter
if (-not $shortenedVersion) { Write-Log "Failed to extract a valid version from assembly files." -Throw }

# Get the corresponding release
Write-Log "Fetching releases from GitHub repository: $RepositoryName"
$uri = "https://api.github.com/repos/$RepositoryName/releases"

$releases = Invoke-RestMethod -Uri $uri  -Method Get -Headers $headers
if (-not $releases) { Write-Log "No releases found for repository $RepositoryName" -Throw }

$uploadUrlPrefix = $null
foreach ($release in $releases) {
    if ($release.name.StartsWith($shortenedVersion)) {
        $uploadUrlPrefix = $release.upload_url -split '{' | Select-Object -First 1
        Write-Log "Matched release: $release.name"
        break
    }
}

if (-not $uploadUrlPrefix) { Write-Log "No matching release found for version $shortenedVersion in $RepositoryName" -Throw }

# Upload artifacts to the release
Write-Log "Uploading artifacts to release: $shortenedVersion"
Write-Log "uploadUrlPrefix: $uploadUrlPrefix"

# Add headers for the upload request
$headers.Add("Content-Type", "application/zip")

foreach ($file in $files) {
    if ($file.FullName -like "*.zip" -and (-not $file.FullName.Contains("PatchedSiteExtension"))) {
        $uploadUrl = $uploadUrlPrefix + "?name=$($file.Name)"
        Write-Log "Uploading $($file.Name) to $uploadUrl"

        Invoke-RestMethod -Uri $uploadUrl `
            -Method Post `
            -Headers $headers `
            -InFile $file.FullName

        Write-Log "Uploaded $($file.Name) successfully."
    }
}
