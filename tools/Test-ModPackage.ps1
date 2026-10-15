param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipPath = Join-Path $RepositoryRoot 'MoreRealistic.zip'
$sourceRoot = Join-Path $RepositoryRoot 'MoreRealistic'
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Installable ZIP not found: $zipPath"
}
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Source directory not found: $sourceRoot"
}

$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$hash = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($name in @('modDesc.xml', 'scripts/RealisticMain.lua', 'icon.dds')) {
        if ($null -eq $archive.GetEntry($name)) {
            throw "Required file missing from ZIP root: $name"
        }
    }

    $prefix = [IO.Path]::GetFullPath($sourceRoot + [IO.Path]::DirectorySeparatorChar)
    $checked = 0
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $archive.Entries) {
        if ([string]::IsNullOrEmpty($entry.Name)) {
            continue
        }
        $name = $entry.FullName
        if ($name.StartsWith('/') -or $name.Contains('\') -or
            -not $names.Add($name)) {
            throw "Invalid or duplicate ZIP entry: $name"
        }
        $path = [IO.Path]::GetFullPath(
            (Join-Path $sourceRoot $name.Replace('/', [IO.Path]::DirectorySeparatorChar))
        )
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "ZIP entry escapes source directory: $name"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "ZIP file is missing from source tree: $name"
        }

        $entryStream = $entry.Open()
        $sourceStream = [IO.File]::OpenRead($path)
        try {
            $zipDigest = [BitConverter]::ToString($hash.ComputeHash($entryStream))
            $sourceDigest = [BitConverter]::ToString($hash.ComputeHash($sourceStream))
        }
        finally {
            $entryStream.Dispose()
            $sourceStream.Dispose()
        }
        if ($zipDigest -ne $sourceDigest) {
            throw "Packaged file differs from source: $name"
        }
        $checked++
    }
    # Source-parity by itself is not enough: the ZIP might omit a Lua file
    # that RealisticMain.lua loads unconditionally at game startup.
    $mainLua = [IO.File]::ReadAllText((Join-Path $sourceRoot 'scripts\RealisticMain.lua'))
    $referenced = [regex]::Matches(
        $mainLua,
        'source\(Utils\.getFilename\("([^"]+)",\s*g_currentModDirectory\)\)'
    )
    if ($referenced.Count -lt 30) {
        throw "Unexpectedly few startup script references: $($referenced.Count)"
    }
    foreach ($match in $referenced) {
        $required = $match.Groups[1].Value
        if (-not $names.Contains($required)) {
            throw "Runtime script referenced in RealisticMain.lua missing from ZIP: $required"
        }
    }    if ($checked -lt 50) {
        throw "Unexpectedly small package: $checked files"
    }
    $modDesc = [xml]([IO.File]::ReadAllText((Join-Path $sourceRoot 'modDesc.xml')))
    Write-Output "PASS: MoreRealistic.zip v$($modDesc.modDesc.version), $checked source-matching files"
}
finally {
    $archive.Dispose()
    $hash.Dispose()
}