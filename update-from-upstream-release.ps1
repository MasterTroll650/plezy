param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$NewRelease
)

$ErrorActionPreference = 'Stop'

if ((git branch --show-current) -ne 'main') {
    throw 'Run this script on the main branch.'
}

if (git status --porcelain --untracked-files=no) {
    throw 'Tracked files have uncommitted changes. Commit or stash them first.'
}

$upstreamUrl = git remote get-url upstream 2>$null
if ($LASTEXITCODE -ne 0 -or !$upstreamUrl) {
    throw 'The upstream remote is missing.'
}

$oldBase = git rev-parse upstream-release
if ($LASTEXITCODE -ne 0) {
    throw 'The upstream-release branch is missing.'
}

git fetch upstream "refs/tags/${NewRelease}:refs/tags/${NewRelease}"
if ($LASTEXITCODE -ne 0) {
    throw "Plezy release tag $NewRelease could not be fetched."
}

$newBase = git rev-parse "refs/tags/$NewRelease"
if ($LASTEXITCODE -ne 0) {
    throw "Plezy release tag $NewRelease does not exist."
}
if ($newBase -eq $oldBase) {
    Write-Host "The fork already uses Plezy release $NewRelease."
    exit 0
}

git merge-base --is-ancestor $oldBase $newBase
if ($LASTEXITCODE -ne 0) {
    throw "Release $NewRelease is not a descendant of the current release base."
}

git rebase --onto $newBase $oldBase main
if ($LASTEXITCODE -ne 0) {
    throw 'Rebase stopped. Resolve the conflicts, then run git rebase --continue.'
}

git branch -f upstream-release $newBase
if ($LASTEXITCODE -ne 0) {
    throw 'Could not advance the upstream-release branch.'
}

Write-Host "Pleazy patches now use upstream release $NewRelease."
Write-Host 'Validate the app, then push with:'
Write-Host '  git push origin upstream-release'
Write-Host '  git push --force-with-lease origin main'
