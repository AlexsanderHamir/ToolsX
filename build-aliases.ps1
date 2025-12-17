# PowerShell alias functions for build scripts
# Add this to your PowerShell profile: . "C:\Users\gomes\Documents\ToolsX\build-aliases.ps1"
# Or source it directly: . .\build-aliases.ps1

# Get the directory where this script is located (works from profile or when sourced)
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # Fallback: use the ToolsX directory path
    $scriptDir = "C:\Users\gomes\Documents\ToolsX"
}

function build_from_commit_cloud {
    <#
    .SYNOPSIS
    Builds and pushes Docker images using Docker Build Cloud
    
    .DESCRIPTION
    Alias function for build-from-commit-cloud.ps1 that accepts all arguments and passes them through.
    
    .PARAMETER CommitHash
    Optional commit hash to build from
    
    .EXAMPLE
    build_from_commit_cloud
    
    .EXAMPLE
    build_from_commit_cloud abc1234
    
    .EXAMPLE
    $env:BUILD_TYPE="production"; build_from_commit_cloud abc1234
    #>
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CommitHash
    )
    
    $scriptPath = Join-Path $scriptDir "build-from-commit-cloud.ps1"
    & $scriptPath @CommitHash
}

function build_from_commit {
    <#
    .SYNOPSIS
    Builds and pushes Docker images using buildx
    
    .DESCRIPTION
    Alias function for build-from-commit.ps1
    
    .EXAMPLE
    build_from_commit
    #>
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )
    
    $scriptPath = Join-Path $scriptDir "build-from-commit.ps1"
    & $scriptPath @Arguments
}

function build_from_commit_nonroot {
    <#
    .SYNOPSIS
    Builds and pushes non-root Docker images using buildx
    
    .DESCRIPTION
    Alias function for build-from-commit-nonroot.ps1
    
    .EXAMPLE
    build_from_commit_nonroot
    #>
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )
    
    $scriptPath = Join-Path $scriptDir "build-from-commit-nonroot.ps1"
    & $scriptPath @Arguments
}
