
[CmdletBinding()]
param(
    [ValidateRange(1, 64)]
    [int]$Threads = 8
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$EsPath = Join-Path $ScriptDir 'es.exe'
$EverythingPath = Join-Path $ScriptDir 'Everything.exe'
$ListDir = Join-Path $ProjectRoot 'List'
$ListPath = Join-Path $ListDir 'list.txt'
$ManifestPath = Join-Path $ProjectRoot 'manifest.json'
$RemoteManifestUrl = 'https://cdn.jsdelivr.net/gh/iwuvcy/RustDevblogCheatChecker@main/manifest.json'
$TempFiles = [System.Collections.Generic.List[string]]::new()
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Read-Host 'Press Enter to exit' | Out-Null
    exit 1
}

function Get-TextFromWeb([string]$Url) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -UseBasicParsing
    return [string]$response.Content
}

function Get-FileSha256([string]$Path) {
    $stream = $null
    $sha = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return (([BitConverter]::ToString($sha.ComputeHash($stream))) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

function Test-HashListFile([string]$Path) {
    $valid = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed -split '\|', 3
        if ($parts.Count -lt 2) { continue }
        [int64]$size = 0
        $hash = $parts[1].Trim()
        if ([int64]::TryParse($parts[0].Trim(), [ref]$size) -and $size -ge 0 -and $hash -match '^[0-9a-fA-F]{64}$') {
            $valid++
        }
    }
    return $valid
}

function Save-LocalManifest($Manifest) {
    $json = $Manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($ManifestPath, $json + [Environment]::NewLine, $Utf8NoBom)
}

function Add-CacheToken([string]$Url, [string]$Token) {
    $separator = '?'
    if ($Url.Contains('?')) { $separator = '&' }
    return ('{0}{1}v={2}' -f $Url, $separator, [uri]::EscapeDataString($Token))
}

function Sync-ProjectManifest {
    Write-Host '[0/5] Checking updates...'

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Write-Host '      manifest.json is missing; online update check skipped.' -ForegroundColor Yellow
        return
    }

    try {
        $localManifest = ([System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json)
        $localProgramVersion = [version]([string]$localManifest.program.latest_version)
        $localDatabaseVersion = [version]([string]$localManifest.database.latest_version)
    } catch {
        Write-Host '      Local manifest.json is invalid; online update check skipped.' -ForegroundColor Yellow
        return
    }

    try {
        $cacheToken = [DateTime]::UtcNow.ToString('yyyyMMddHHmm')
        $manifestUrl = Add-CacheToken $RemoteManifestUrl $cacheToken
        $remoteManifest = ((Get-TextFromWeb $manifestUrl) | ConvertFrom-Json)
        $remoteProgramVersion = [version]([string]$remoteManifest.program.latest_version)
        $remoteDatabaseVersion = [version]([string]$remoteManifest.database.latest_version)

        if ($remoteProgramVersion -gt $localProgramVersion) {
            Write-Host "      PROJECT UPDATE AVAILABLE: $localProgramVersion -> $remoteProgramVersion" -ForegroundColor Yellow
            Write-Host "      $($remoteManifest.program.download_url)" -ForegroundColor Yellow
        } else {
            Write-Host "      Project version: $localProgramVersion"
        }

        $expectedHash = ([string]$remoteManifest.database.sha256).Trim().ToLowerInvariant()
        if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
            throw 'Remote database SHA256 is missing or invalid.'
        }

        $needsDatabaseUpdate = $remoteDatabaseVersion -gt $localDatabaseVersion
        if ((-not $needsDatabaseUpdate) -and (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
            $localHash = Get-FileSha256 $ListPath
            if ($localHash -ne $expectedHash -and $remoteDatabaseVersion -eq $localDatabaseVersion) {
                Write-Host '      Local hash list checksum differs; downloading a clean copy.' -ForegroundColor Yellow
                $needsDatabaseUpdate = $true
            }
        } elseif (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
            $needsDatabaseUpdate = $true
        }

        if ($needsDatabaseUpdate) {
            Write-Host "      Downloading hash list $localDatabaseVersion -> $remoteDatabaseVersion..." -ForegroundColor Yellow
            if (-not (Test-Path -LiteralPath $ListDir -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $ListDir -Force)
            }

            $tempList = Join-Path $ListDir ('list-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
            $TempFiles.Add($tempList)
            $databaseUrl = Add-CacheToken ([string]$remoteManifest.database.download_url) ([string]$remoteDatabaseVersion)
            Invoke-WebRequest -Uri $databaseUrl -Method Get -TimeoutSec 15 -UseBasicParsing -OutFile $tempList

            $downloadedHash = Get-FileSha256 $tempList
            if ($downloadedHash -ne $expectedHash) {
                throw "Downloaded database checksum mismatch. Expected $expectedHash, got $downloadedHash."
            }

            $recordCount = Test-HashListFile $tempList
            if ($recordCount -le 0) {
                throw 'Downloaded list.txt contains no valid records.'
            }

            Move-Item -LiteralPath $tempList -Destination $ListPath -Force

            $localManifest.database.latest_version = [string]$remoteManifest.database.latest_version
            $localManifest.database.download_url = [string]$remoteManifest.database.download_url
            $localManifest.database.sha256 = [string]$remoteManifest.database.sha256
            Save-LocalManifest $localManifest
            Write-Host "      Hash list updated to $remoteDatabaseVersion ($recordCount records)." -ForegroundColor Green
        } else {
            Write-Host "      Hash list version: $localDatabaseVersion (up to date)." -ForegroundColor Green
        }
    } catch {
        Write-Host "      Online update unavailable: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host '      Continuing with the local hash list.' -ForegroundColor DarkGray
    }
}

if (-not (Test-Path -LiteralPath $EsPath -PathType Leaf)) {
    Stop-WithError "es.exe was not found: $EsPath"
}

try {
    Sync-ProjectManifest

    if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
        throw "list.txt was not found: $ListPath"
    }

    Write-Host '[1/5] Connecting to Everything...'
    & $EsPath -get-everything-version *> $null
    if ($LASTEXITCODE -ne 0) {
        if (-not (Test-Path -LiteralPath $EverythingPath -PathType Leaf)) {
            throw 'Everything is not running and Everything.exe is not in the Utils folder.'
        }
        Write-Host '      Starting Everything.exe...'
        Start-Process -FilePath $EverythingPath -ArgumentList '-startup' | Out-Null
        $connected = $false
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 1
            & $EsPath -get-everything-version *> $null
            if ($LASTEXITCODE -eq 0) { $connected = $true; break }
        }
        if (-not $connected) { throw 'Everything did not become ready within 60 seconds.' }
    }

    Write-Host '[2/5] Rebuilding Everything indexes for all configured drives...'
    & $EsPath -reindex
    if ($LASTEXITCODE -ne 0) { throw "Everything reindex failed (exit code $LASTEXITCODE)." }
    Write-Host '      Indexing completed.' -ForegroundColor Green

    Write-Host '[3/5] Reading list.txt...'
    $targets = @{}
    $targetSizes = [System.Collections.Generic.HashSet[int64]]::new()
    $validPairs = 0
    $badLines = 0
    foreach ($line in [System.IO.File]::ReadLines($ListPath)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $parts = $line -split '\|', 3
        if ($parts.Count -lt 2) { $badLines++; continue }
        [int64]$size = 0
        $sizeText = $parts[0].Trim()
        $hash = $parts[1].Trim().ToLowerInvariant()
        if ((-not [int64]::TryParse($sizeText, [ref]$size)) -or ($size -lt 0) -or ($hash -notmatch '^[0-9a-f]{64}$')) {
            $badLines++
            continue
        }
        if (-not $targets.ContainsKey($size)) {
            $targets[$size] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        if ($targets[$size].Add($hash)) { $validPairs++ }
        [void]$targetSizes.Add($size)
    }
    if ($validPairs -eq 0) { throw "List/list.txt contains no valid '<bytes> | <sha256>' pairs." }
    Write-Host "      Valid pairs: $validPairs; unique sizes: $($targetSizes.Count); skipped lines: $badLines"

    Write-Host '[4/5] Querying Everything only for required sizes...'
    $allSizes = @($targetSizes | Sort-Object)
    $batchSize = 100
    $candidatesByPath = @{}
    for ($offset = 0; $offset -lt $allSizes.Count; $offset += $batchSize) {
        $last = [Math]::Min($offset + $batchSize - 1, $allSizes.Count - 1)
        $batch = @($allSizes[$offset..$last])
        $sizeTerms = @($batch | ForEach-Object { "size:$_" })
        $search = 'file:<' + ($sizeTerms -join '|') + '>'
        $csvPath = Join-Path $env:TEMP ("everything-candidates-{0}.csv" -f ([guid]::NewGuid().ToString('N')))
        $TempFiles.Add($csvPath)
        & $EsPath $search -export-csv $csvPath -no-header -full-path-and-name -size -size-format 1
        if ($LASTEXITCODE -ne 0) { throw "Everything size query failed (exit code $LASTEXITCODE)." }
        if (-not (Test-Path -LiteralPath $csvPath)) { continue }
        Import-Csv -LiteralPath $csvPath -Header Path,Size | ForEach-Object {
            [int64]$candidateSize = 0
            if ([int64]::TryParse(($_.Size -replace '[^0-9]',''), [ref]$candidateSize) -and $targetSizes.Contains($candidateSize)) {
                $path = [string]$_.Path
                if (-not $candidatesByPath.ContainsKey($path)) {
                    $candidatesByPath[$path] = [pscustomobject]@{ Path = $path; Size = $candidateSize }
                }
            }
        }
    }

    $candidates = @($candidatesByPath.Values)
    Write-Host "      Candidates to hash: $($candidates.Count)"
    Write-Host "[5/5] Calculating SHA256 with $Threads thread(s)..."

    $worker = {
        param([string]$Path, [int64]$Size, [string[]]$AllowedHashes)
        $stream = $null
        $sha = $null
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
            if ($AllowedHashes -contains $hash) {
                [pscustomobject]@{ Path = $Path; Size = $Size; SHA256 = $hash }
            }
        } catch {
        } finally {
            if ($stream) { $stream.Dispose() }
            if ($sha) { $sha.Dispose() }
        }
    }

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()
    $jobs = [System.Collections.Generic.List[object]]::new()
    $matches = [System.Collections.Generic.List[object]]::new()

    try {
        foreach ($candidate in $candidates) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker)
            [void]$ps.AddArgument([string]$candidate.Path)
            [void]$ps.AddArgument([int64]$candidate.Size)
            [void]$ps.AddArgument([string[]]@($targets[$candidate.Size]))
            $handle = $ps.BeginInvoke()
            $jobs.Add([pscustomobject]@{ PowerShell = $ps; Handle = $handle })
        }

        $completed = 0
        foreach ($job in $jobs) {
            $output = $job.PowerShell.EndInvoke($job.Handle)
            $completed++
            if (($completed % 25) -eq 0 -or $completed -eq $jobs.Count) {
                Write-Progress -Activity 'Calculating SHA256' -Status "$completed / $($jobs.Count)" -PercentComplete (($completed / [Math]::Max(1, $jobs.Count)) * 100)
            }
            foreach ($match in $output) { $matches.Add($match) }
            $job.PowerShell.Dispose()
        }
        Write-Progress -Activity 'Calculating SHA256' -Completed
    } finally {
        foreach ($job in $jobs) {
            if ($job.PowerShell) { $job.PowerShell.Dispose() }
        }
        $pool.Close()
        $pool.Dispose()
    }

    $matchCount = $matches.Count
    Write-Host ''
    if ($matchCount -eq 0) {
        Write-Host 'No matching files found.' -ForegroundColor Yellow
    } else {
        Write-Host "MATCHES ($matchCount):"
        foreach ($match in ($matches | Sort-Object Path)) {
            Write-Host "MATCH: $($match.Path)" -ForegroundColor Red
            Write-Host "  Bytes:  $($match.Size)"
            Write-Host "  SHA256: $($match.SHA256)"
            Write-Host ''
        }
    }

    $swTotal.Stop()
    Write-Host ("Finished in {0:n1} seconds. Matches: {1}. Threads: {2}" -f $swTotal.Elapsed.TotalSeconds, $matchCount, $Threads) -ForegroundColor Cyan
}
catch {
    Stop-WithError $_.Exception.Message
}
finally {
    foreach ($tempFile in $TempFiles) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
}

Read-Host 'Press Enter to exit' | Out-Null
