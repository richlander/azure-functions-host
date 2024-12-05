#	
# Copyright (c) Microsoft. All rights reserved.	
# Licensed under the MIT license. See LICENSE file in the project root for full license information.	
#

# Description: Helper functions for the release scripts
function Write-Log
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Message,

        [Switch]
        $Throw
    )

    $Message = (Get-Date -Format G)  + " -- $Message"

    if ($Throw)
    {
        throw $Message
    }

    Write-Host $Message
}

function Get-ZipFilter
{
    param (
        [String]
        $ArtifactVersion
    )

    Write-Log "Determining zip filter for ArtifactVersion: $ArtifactVersion"

    $zipFilter = switch ($ArtifactVersion) {
        "6" { "FunctionsInProc\.\d.6.+\.zip" }
        "8" { "FunctionsInProc8\.\d.+\.zip" }
        default { "Functions\.\d.+\.zip" }
    }

    return $zipFilter
}

function Get-SymbolZipFilter
{
    param (
        [string]
        $ArtifactVersion
    )

    Write-Log "Determining symbol ZIP filter for ArtifactVersion: $ArtifactVersion"

    $symbolZipFilter = switch ($ArtifactVersion) {
        "6" { "Functions\.Symbols\.\d\.6.+\.zip" }
        "8" { "Functions.Symbols\.\d\.8.+\.zip" }
        default { "Functions\.Symbols\.\d+\.(?!6|8).+\.zip" }
    }

    return $symbolZipFilter
}

function Get-VersionFromAssembly
{
    param (
        [string]
        $ArtifactPath,
        [string]
        $ZipFilter
    )

    if (-not (Test-Path -Path $ArtifactPath)) {
        Write-Log "The artifact path '$ArtifactPath' does not exist." -Throw
    }

    # Get ZIP files matching the filter
    Write-Log "Searching for ZIP files in '$ArtifactPath' with filter '$ZipFilter'"
    $zipFiles = Get-ChildItem -Path $ArtifactPath -Filter *.zip -Recurse | Where-Object { $_.Name -match $ZipFilter }

    if ($zipFiles.Count -eq 0) {
        Write-Log "No ZIP files matching the filter '$ZipFilter' were found in the directory: $ArtifactPath" -Throw
    }

    # Process each ZIP file
    foreach ($zipFile in $zipFiles) {
        Write-Log "Found ZIP file: $($zipFile.FullName)"

        $destinationPath = Join-Path -Path $zipFile.DirectoryName -ChildPath $zipFile.BaseName

        if (Test-Path $destinationPath) {
            Write-Log "Deleting existing destination path: $destinationPath"
            Remove-Item -Path $destinationPath\* -Recurse -Force
        }

        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile.FullName, $destinationPath)
            Write-Log "Successfully extracted ZIP file to: $destinationPath"
        } catch {
            Write-Log "Failed to extract ZIP file: $($zipFile.FullName). Error: $_" -Throw
        }

        # Find and process assembly files
        $assemblyFiles = Get-ChildItem -Path $destinationPath -Filter *.WebHost.dll -Recurse
        if ($assemblyFiles.Count -eq 0) {
            Write-Log "No assembly files (*.WebHost.dll) found in $destinationPath" -Throw
        }

        $assemblyVersion = $assemblyFiles | ForEach-Object {
            [PSCustomObject]@{
                Name            = $_.Name
                FileVersion     = $_.VersionInfo.FileVersion
                AssemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($_.FullName).Version
            }
        }

        if (-not $assemblyVersion) {
            Write-Log "No assembly version information could be retrieved from files in $destinationPath" -Throw
        }

        # Extract version and set variables
        $newVersion = ($assemblyVersion).FileVersion
        $splittedArray = $newVersion -split " "
        if (-not $splittedArray) {
            Write-Log "Failed to split version information: $newVersion" -Throw
        }

        Write-Log "Version extracted from assembly: $newVersion"

        $tagVersion = $splittedArray[0]
        $versionParts = $tagVersion -split '\.'
        $shortenedVersion = ($versionParts[0..2] -join '.')

        Write-Log "Setting shortened version: $shortenedVersion"
        Write-Log "##vso[task.setvariable variable=Version;isOutput=true]$shortenedVersion"

        # Exit after processing the first ZIP file successfully
        return $shortenedVersion
    }
}

function Get-LatestCommitId
{
    param (
        [String]
        $BranchName,
        [Hashtable]
        $Headers,
        [String]
        $RepositoryName
    )

    Write-Log "Fetching the latest commit ID from the branch $BranchName..."

    $uri = "https://api.github.com/repos/$RepositoryName/branches/$BranchName"
    $response = Invoke-RestMethod -Uri $uri -Headers $header -Method Get

    $commitSHA = $response.commit.sha

    if ([string]::IsNullOrWhiteSpace($commitSHA)) {
        Write-Log "CommitId is not provided. Fetching the latest commit ID from the branch $BranchName..." -Throw
    }

    return $commitSHA
}
