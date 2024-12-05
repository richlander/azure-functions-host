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
    $CommitId,
    [String]
    $ArtifactVersion,
    [String]
    $GithubToken
)

# Import helper functions
Import-Module "$PSScriptRoot/SharedUtilities.psm1" -Force

# Validate inputs
Write-Log "Validating inputs..."
if (-not $BranchName) {
    Write-Log "BranchName cannot be null or empty" -Throw
}
if (-not $RepositoryName) {
    Write-Log "RepositoryName cannot be null or empty" -Throw
}

#$GithubToken = $Env:GITHUB_TOKEN
if (-not $GithubToken) {
    Write-Log "GitHub token not found in environment variable 'GITHUB_TOKEN'" -Throw
}

$headers = @{
    Authorization = "Bearer $GithubToken"
    'User-Agent' = 'PowerShell'
}

$releaseNotes = $null

try {

    # The repo is already cloned in the pipeline. This is just for local testing.
    <#
    # Clone the repository
    git clone https://$githubToken@github.com/Azure/azure-functions-host
    Write-Log "Cloned into local"
    Set-Location "azure-functions-host"
    git checkout $BranchName
    Write-Log "Checked out branch"
    #>

    # Define paths and validate release notes
    Write-Log "Reading release notes..."
    $releaseNotesPath = Join-Path -Path $pwd -ChildPath "release_notes.md"

    if (-not (Test-Path -Path $releaseNotesPath)) {
        Write-Log "Release notes file not found at $releaseNotesPath" -Throw
    }

    $releaseNotes = Get-Content -Path $releaseNotesPath -Raw
    if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
        Write-Log "Release notes are empty or could not be read from $releaseNotesPath" -Throw
    }

    $zipFilter = Get-ZipFilter -ArtifactVersion $ArtifactVersion

    # Find and extract zip files
    $artifactPath = "$PSScriptRoot/artifactsFolder" # This needs to be defined as an input parameter
    $shortenedVersion = Get-VersionFromAssembly -ArtifactPath $artifactPath -ZipFilter $zipFilter

    if ([string]::IsNullOrWhiteSpace($CommitId)) {
        Write-Log "CommitId is not provided. Fetching the latest commit ID from the branch $BranchName..."
        $CommitId = Get-LatestCommitId -BranchName $BranchName -Headers $headers -RepositoryName $RepositoryName
    }

    # Create JSON request body for GitHub API
    $jsonRequest = @{
        name             = $shortenedVersion
        target_commitish = $CommitId
        tag_name         = "v" + $shortenedVersion
        body             = $releaseNotes
        draft            = $true
        prerelease       = $false
    } | ConvertTo-Json

    # Make the REST API call to create a release
    $uri = "https://api.github.com/repos/$RepositoryName/releases"
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $jsonRequest -ContentType 'application/json'

    try {
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
            Write-Log "Successfully created release and tag for version $shortenedVersion on branch $BranchName. Response status code: $($response.StatusCode)"
        } else {
            $errorMsg = "Unexpected status code: $($response.StatusCode). Failed to create release and tag for version $shortenedVersion on branch $BranchName."
            Write-Log $errorMsg -Throw
        }
    }
    catch {
        $errorMsg = "Error occurred while creating release and tag for version $shortenedVersion on branch $BranchName. Error details: $_"
        Write-Log $errorMsg -Throw
    }
}
catch {
    Write-Log "An error occurred: $_" -Throw
}