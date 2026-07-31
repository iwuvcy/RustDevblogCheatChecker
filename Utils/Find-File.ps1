[CmdletBinding()]
param(
    [ValidateRange(0, 64)]
    [int]$Threads = 0,

    [switch]$Reindex,

    [switch]$SkipUpdate,

    [switch]$NoDownload,

    [switch]$NoWait
)

$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent $ScriptDir
$EsPath = Join-Path $ScriptDir 'es.exe'
$EverythingPath = Join-Path $ScriptDir 'Everything.exe'
$ListDir = Join-Path $ProjectRoot 'List'
$ListPath = Join-Path $ListDir 'list.txt'
$ManifestPath = Join-Path $ProjectRoot 'manifest.json'
$RemoteManifestUrl = 'https://raw.githubusercontent.com/iwuvcy/RustDevblogCheatChecker/main/manifest.json'
$TempFiles = [System.Collections.Generic.List[string]]::new()
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
$MaxSearchLength = 16000

$ToolPackages = @{
    es = @{
        Name  = 'ES 1.1.0.37'
        x64   = @{ Url = 'https://www.voidtools.com/ES-1.1.0.37.x64.zip';   Sha256 = '3be7185707e8023cd9295dbcb7a3fa4092a3d8f52b7fa92a0b84243ab40d12f3' }
        x86   = @{ Url = 'https://www.voidtools.com/ES-1.1.0.37.x86.zip';   Sha256 = '1c805f71b19aed9680a20e04443e4205506fb8032ddb650ae1414a86cdc4d38d' }
        ARM64 = @{ Url = 'https://www.voidtools.com/ES-1.1.0.37.ARM64.zip'; Sha256 = 'ed1138873d0a78bef08b342d19056def756fde1969182f48baf6be24cd954825' }
    }
    everything = @{
        Name  = 'Everything 1.4.1.1032 portable'
        x64   = @{ Url = 'https://www.voidtools.com/Everything-1.4.1.1032.x64.zip';   Sha256 = 'f191f756996a14a11e5445fa7103d302efd510cf2fbf920e6c0c8ed51d512e36' }
        x86   = @{ Url = 'https://www.voidtools.com/Everything-1.4.1.1032.x86.zip';   Sha256 = 'd38f48dd60de6b10f9a132718ccbfddc171a7a7d1cc88ef2e4ce73c0c43dcd5f' }
        ARM64 = @{ Url = 'https://www.voidtools.com/Everything-1.4.1.1032.ARM64.zip'; Sha256 = '462caf17906e56be11ce3d701a6ea51bb1733afae8a4610880f3a6985ee9ca5e' }
    }
}

if ($Threads -le 0) {
    $Threads = [Math]::Max(1, [Math]::Min(64, [Environment]::ProcessorCount))
}

function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if (-not $NoWait) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}

function Format-Bytes([double]$Bytes) {
    if ($Bytes -ge 1073741824) { return ('{0:n2} GB' -f ($Bytes / 1073741824)) }
    if ($Bytes -ge 1048576) { return ('{0:n1} MB' -f ($Bytes / 1048576)) }
    if ($Bytes -ge 1024) { return ('{0:n1} KB' -f ($Bytes / 1024)) }
    return ('{0:n0} B' -f $Bytes)
}

$ScannerSource = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Rdcc
{
    public sealed class Candidate
    {
        public string Path;
        public long Size;
    }

    public sealed class MatchInfo
    {
        public string Path;
        public long Size;
        public string Sha256;
    }

    public sealed class FailureInfo
    {
        public string Path;
        public string Reason;
    }

    public sealed class HashList
    {
        public Dictionary<long, HashSet<string>> Targets =
            new Dictionary<long, HashSet<string>>();
        public int ValidPairs;
        public int BadLines;
        public int DuplicateLines;
        public int SizeCount { get { return Targets.Count; } }
    }

    public sealed class ScanResult
    {
        public List<MatchInfo> Matches = new List<MatchInfo>();
        public List<FailureInfo> Failures = new List<FailureInfo>();
        public int Hashed;
        public int Changed;
        public int Skipped;
        public long BytesHashed;
    }

    public sealed class CandidateSet
    {
        private readonly Dictionary<string, Candidate> _map =
            new Dictionary<string, Candidate>(StringComparer.OrdinalIgnoreCase);

        public int Count { get { return _map.Count; } }

        public Candidate[] ToArray()
        {
            Candidate[] items = new Candidate[_map.Count];
            _map.Values.CopyTo(items, 0);
            return items;
        }

        public int AddFromCsv(string csvPath, HashList db)
        {
            int added = 0;
            foreach (string line in File.ReadLines(csvPath))
            {
                if (line.Length == 0) { continue; }

                List<string> fields = ParseCsvLine(line);
                if (fields.Count < 2) { continue; }

                string path = fields[0];
                if (path.Length == 0) { continue; }

                long size;
                if (!TryParseDigits(fields[fields.Count - 1], out size)) { continue; }
                if (!db.Targets.ContainsKey(size)) { continue; }
                if (_map.ContainsKey(path)) { continue; }

                Candidate candidate = new Candidate();
                candidate.Path = path;
                candidate.Size = size;
                _map[path] = candidate;
                added++;
            }
            return added;
        }

        private static List<string> ParseCsvLine(string line)
        {
            List<string> fields = new List<string>(4);
            StringBuilder field = new StringBuilder(line.Length);
            bool quoted = false;

            for (int i = 0; i < line.Length; i++)
            {
                char ch = line[i];
                if (quoted)
                {
                    if (ch != '"') { field.Append(ch); }
                    else if (i + 1 < line.Length && line[i + 1] == '"') { field.Append('"'); i++; }
                    else { quoted = false; }
                }
                else if (ch == '"') { quoted = true; }
                else if (ch == ',') { fields.Add(field.ToString()); field.Length = 0; }
                else { field.Append(ch); }
            }

            fields.Add(field.ToString());
            return fields;
        }

        private static bool TryParseDigits(string text, out long value)
        {
            value = 0;
            bool any = false;
            for (int i = 0; i < text.Length; i++)
            {
                char ch = text[i];
                if (ch < '0' || ch > '9') { continue; }
                if (value > (long.MaxValue - (ch - '0')) / 10) { return false; }
                value = value * 10 + (ch - '0');
                any = true;
            }
            return any;
        }
    }

    public static class Scanner
    {
        private const int BufferSize = 1048576;
        private static readonly char[] HexChars = "0123456789abcdef".ToCharArray();

        private static int _processed;
        private static long _bytes;

        public static int Processed { get { return Volatile.Read(ref _processed); } }
        public static long BytesRead { get { return Interlocked.Read(ref _bytes); } }

        public static HashAlgorithm CreateHasher()
        {
            try { return new SHA256Cng(); } catch { }
            try { return new SHA256CryptoServiceProvider(); } catch { }
            return SHA256.Create();
        }

        public static string HashFile(string path)
        {
            byte[] buffer = new byte[BufferSize];
            using (HashAlgorithm sha = CreateHasher())
            using (FileStream stream = OpenRead(path))
            {
                return HashStream(stream, sha, buffer);
            }
        }

        public static HashList LoadList(string path)
        {
            HashList db = new HashList();

            foreach (string raw in File.ReadLines(path))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line[0] == '#') { continue; }

                int separator = line.IndexOf('|');
                if (separator < 0) { db.BadLines++; continue; }

                string sizeText = line.Substring(0, separator).Trim();
                string hashText = line.Substring(separator + 1);

                int comment = hashText.IndexOf('|');
                if (comment >= 0) { hashText = hashText.Substring(0, comment); }
                hashText = hashText.Trim().ToLowerInvariant();

                long size;
                bool parsed = long.TryParse(sizeText, NumberStyles.None,
                    CultureInfo.InvariantCulture, out size);
                if (!parsed || size < 0 || !IsSha256(hashText)) { db.BadLines++; continue; }

                HashSet<string> hashes;
                if (!db.Targets.TryGetValue(size, out hashes))
                {
                    hashes = new HashSet<string>(StringComparer.Ordinal);
                    db.Targets[size] = hashes;
                }

                if (hashes.Add(hashText)) { db.ValidPairs++; } else { db.DuplicateLines++; }
            }

            return db;
        }

        public static long[] SortedSizes(HashList db)
        {
            long[] sizes = new long[db.Targets.Count];
            db.Targets.Keys.CopyTo(sizes, 0);
            Array.Sort(sizes);
            return sizes;
        }

        public static Task<ScanResult> RunAsync(Candidate[] items, HashList db, int threads)
        {
            return Task.Factory.StartNew<ScanResult>(
                () => Run(items, db, threads), TaskCreationOptions.LongRunning);
        }

        public static ScanResult Run(Candidate[] items, HashList db, int threads)
        {
            ScanResult result = new ScanResult();
            _processed = 0;
            _bytes = 0;

            int total = items.Length;
            if (total == 0) { return result; }

            Array.Sort(items, (a, b) => b.Size.CompareTo(a.Size));

            if (threads < 1) { threads = 1; }
            if (threads > total) { threads = total; }

            int cursor = -1;
            int changed = 0;
            int skipped = 0;
            int hashed = 0;
            object sync = new object();
            Task[] workers = new Task[threads];

            for (int t = 0; t < threads; t++)
            {
                workers[t] = Task.Factory.StartNew(() =>
                {
                    byte[] buffer = new byte[BufferSize];
                    using (HashAlgorithm sha = CreateHasher())
                    {
                        int index;
                        while ((index = Interlocked.Increment(ref cursor)) < total)
                        {
                            Candidate item = items[index];
                            try
                            {
                                HashSet<string> allowed;
                                if (!db.Targets.TryGetValue(item.Size, out allowed))
                                {
                                    Interlocked.Increment(ref skipped);
                                    continue;
                                }

                                using (FileStream stream = OpenRead(item.Path))
                                {
                                    if (stream.Length != item.Size)
                                    {
                                        Interlocked.Increment(ref changed);
                                        continue;
                                    }

                                    string digest = HashStream(stream, sha, buffer);
                                    Interlocked.Increment(ref hashed);
                                    Interlocked.Add(ref _bytes, item.Size);

                                    if (allowed.Contains(digest))
                                    {
                                        MatchInfo match = new MatchInfo();
                                        match.Path = item.Path;
                                        match.Size = item.Size;
                                        match.Sha256 = digest;
                                        lock (sync) { result.Matches.Add(match); }
                                    }
                                }
                            }
                            catch (Exception ex)
                            {
                                FailureInfo failure = new FailureInfo();
                                failure.Path = item.Path;
                                failure.Reason = ex.Message;
                                lock (sync) { result.Failures.Add(failure); }
                            }
                            finally
                            {
                                Interlocked.Increment(ref _processed);
                            }
                        }
                    }
                }, TaskCreationOptions.LongRunning);
            }

            Task.WaitAll(workers);

            result.Matches.Sort((a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
            result.Failures.Sort((a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
            result.Changed = changed;
            result.Skipped = skipped;
            result.Hashed = hashed;
            result.BytesHashed = Interlocked.Read(ref _bytes);
            return result;
        }

        private static FileStream OpenRead(string path)
        {
            return new FileStream(path, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete, 1, FileOptions.SequentialScan);
        }

        private static string HashStream(Stream stream, HashAlgorithm sha, byte[] buffer)
        {
            sha.Initialize();
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                sha.TransformBlock(buffer, 0, read, null, 0);
            }
            sha.TransformFinalBlock(buffer, 0, 0);
            return ToHex(sha.Hash);
        }

        private static string ToHex(byte[] data)
        {
            char[] chars = new char[data.Length * 2];
            for (int i = 0; i < data.Length; i++)
            {
                chars[i * 2] = HexChars[data[i] >> 4];
                chars[i * 2 + 1] = HexChars[data[i] & 0x0F];
            }
            return new string(chars);
        }

        private static bool IsSha256(string text)
        {
            if (text == null || text.Length != 64) { return false; }
            for (int i = 0; i < 64; i++)
            {
                char ch = text[i];
                if ((ch < '0' || ch > '9') && (ch < 'a' || ch > 'f')) { return false; }
            }
            return true;
        }
    }
}
'@

function Initialize-Scanner {
    if ('Rdcc.Scanner' -as [type]) { return }
    Add-Type -TypeDefinition $ScannerSource -ReferencedAssemblies @('System.Core')
}

function Get-HostArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch (([string]$architecture).ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'ARM64' }
        default { return 'x86' }
    }
}

function Install-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $package = $ToolPackages[$Key]
    $fileName = Split-Path -Leaf $Destination

    if ($NoDownload) {
        throw ("{0} was not found and -NoDownload is set. Place {1} in the Utils folder, or download {2} from https://www.voidtools.com/downloads/" -f $fileName, $fileName, $package.Name)
    }

    $architecture = Get-HostArchitecture
    $source = $package[$architecture]
    if ($null -eq $source) {
        throw ("No {0} package is available for architecture {1}." -f $package.Name, $architecture)
    }

    Write-Host ("      {0} is missing; downloading {1} ({2}) from voidtools.com..." -f $fileName, $package.Name, $architecture) -ForegroundColor Yellow

    $zipPath = Join-Path $env:TEMP ('rdcc-tool-{0}.zip' -f ([guid]::NewGuid().ToString('N')))
    $exePath = Join-Path $env:TEMP ('rdcc-tool-{0}.exe' -f ([guid]::NewGuid().ToString('N')))
    $TempFiles.Add($zipPath)
    $TempFiles.Add($exePath)

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $source.Url -Method Get -TimeoutSec 120 -UseBasicParsing -OutFile $zipPath

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName -like '*.exe' -and $_.FullName -notlike '*/*' })
        if ($entries.Count -ne 1) {
            throw ("Expected exactly one executable in {0}, found {1}." -f $source.Url, $entries.Count)
        }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $exePath, $true)
    } finally {
        $archive.Dispose()
    }

    $expectedHash = ([string]$source.Sha256).Trim().ToLowerInvariant()
    $actualHash = [Rdcc.Scanner]::HashFile($exePath)
    if ($actualHash -ne $expectedHash) {
        throw ("{0} failed SHA-256 verification and was discarded. Expected {1}, got {2}." -f $package.Name, $expectedHash, $actualHash)
    }

    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $destinationDir -Force)
    }
    Move-Item -LiteralPath $exePath -Destination $Destination -Force
    Write-Host ("      {0} verified against its pinned SHA-256 and installed." -f $fileName) -ForegroundColor Green
}

function Get-TextFromWeb([string]$Url) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -UseBasicParsing
    return [string]$response.Content
}

function ConvertTo-JsonText([string]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Save-LocalManifest($Manifest) {
    $lf = "`n"
    $json = '{' + $lf +
        '  "schema_version": ' + ([int]$Manifest.schema_version) + ',' + $lf +
        '  "program": {' + $lf +
        '    "latest_version": ' + (ConvertTo-JsonText ([string]$Manifest.program.latest_version)) + ',' + $lf +
        '    "download_url": ' + (ConvertTo-JsonText ([string]$Manifest.program.download_url)) + $lf +
        '  },' + $lf +
        '  "database": {' + $lf +
        '    "latest_version": ' + (ConvertTo-JsonText ([string]$Manifest.database.latest_version)) + ',' + $lf +
        '    "download_url": ' + (ConvertTo-JsonText ([string]$Manifest.database.download_url)) + ',' + $lf +
        '    "sha256": ' + (ConvertTo-JsonText ([string]$Manifest.database.sha256)) + $lf +
        '  }' + $lf +
        '}' + $lf
    [System.IO.File]::WriteAllText($ManifestPath, $json, $Utf8NoBom)
}

function Add-CacheToken([string]$Url, [string]$Token) {
    $separator = '?'
    if ($Url.Contains('?')) { $separator = '&' }
    return ('{0}{1}v={2}' -f $Url, $separator, [uri]::EscapeDataString($Token))
}

function Invoke-Es {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $EsPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }

    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $stdout }
}

function Get-EverythingFileCount {
    $result = Invoke-Es @('-get-result-count', 'file:')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { return $null }
    [int64]$count = 0
    if ([int64]::TryParse((([string]$result.Output[0]) -replace '[^0-9]', ''), [ref]$count)) { return $count }
    return $null
}

function Sync-ProjectManifest {
    Write-Host '[1/5] Checking updates...'

    if ($SkipUpdate) {
        Write-Host '      Skipped (-SkipUpdate).' -ForegroundColor DarkGray
        return
    }

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

        if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
            $needsDatabaseUpdate = $true
        } elseif ($remoteDatabaseVersion -gt $localDatabaseVersion) {
            $needsDatabaseUpdate = $true
        } elseif ($remoteDatabaseVersion -eq $localDatabaseVersion -and (([Rdcc.Scanner]::HashFile($ListPath)) -ne $expectedHash)) {
            Write-Host '      Local hash list checksum differs; downloading a clean copy.' -ForegroundColor Yellow
            $needsDatabaseUpdate = $true
        } else {
            $needsDatabaseUpdate = $false
        }

        if (-not $needsDatabaseUpdate) {
            Write-Host "      Hash list version: $localDatabaseVersion (up to date)." -ForegroundColor Green
            return
        }

        Write-Host "      Downloading hash list $localDatabaseVersion -> $remoteDatabaseVersion..." -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $ListDir -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $ListDir -Force)
        }

        $tempList = Join-Path $ListDir ('list-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
        $TempFiles.Add($tempList)
        $databaseUrl = Add-CacheToken ([string]$remoteManifest.database.download_url) ([string]$remoteDatabaseVersion)
        Invoke-WebRequest -Uri $databaseUrl -Method Get -TimeoutSec 60 -UseBasicParsing -OutFile $tempList

        $downloadedHash = [Rdcc.Scanner]::HashFile($tempList)
        if ($downloadedHash -ne $expectedHash) {
            throw "Downloaded database checksum mismatch. Expected $expectedHash, got $downloadedHash."
        }

        $downloaded = [Rdcc.Scanner]::LoadList($tempList)
        if ($downloaded.ValidPairs -le 0) {
            throw 'Downloaded list.txt contains no valid records.'
        }

        Move-Item -LiteralPath $tempList -Destination $ListPath -Force

        $localManifest.database.latest_version = [string]$remoteManifest.database.latest_version
        $localManifest.database.download_url = [string]$remoteManifest.database.download_url
        $localManifest.database.sha256 = [string]$remoteManifest.database.sha256
        Save-LocalManifest $localManifest
        Write-Host "      Hash list updated to $remoteDatabaseVersion ($($downloaded.ValidPairs) records)." -ForegroundColor Green
    } catch {
        Write-Host "      Online update unavailable: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host '      Continuing with the local hash list.' -ForegroundColor DarkGray
    }
}

function Wait-EverythingIndex {
    $previousCount = -1
    $stableChecks = 0
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds 2
        $count = Get-EverythingFileCount
        if ($null -eq $count) {
            Write-Host '      Index progress cannot be measured; continuing without waiting.' -ForegroundColor Yellow
            return
        }
        if ($count -gt 0 -and $count -eq $previousCount) {
            $stableChecks++
            if ($stableChecks -ge 3) {
                Write-Host ("      Index settled at {0:n0} files." -f $count) -ForegroundColor Green
                return
            }
        } else {
            $stableChecks = 0
            $previousCount = $count
        }
    }
    Write-Host '      Index did not settle within 10 minutes; scanning against the current index.' -ForegroundColor Yellow
}

function Connect-Everything {
    Write-Host '[2/5] Connecting to Everything...'

    if (-not (Test-Path -LiteralPath $EsPath -PathType Leaf)) {
        Install-Tool 'es' $EsPath
    }

    if ((Invoke-Es @('-get-everything-version')).ExitCode -ne 0) {
        if (-not (Test-Path -LiteralPath $EverythingPath -PathType Leaf)) {
            Install-Tool 'everything' $EverythingPath
        }
        Write-Host '      Everything is not running; starting the portable copy from Utils...'
        Start-Process -FilePath $EverythingPath -ArgumentList '-startup' | Out-Null
        $connected = $false
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 1
            if ((Invoke-Es @('-get-everything-version')).ExitCode -eq 0) { $connected = $true; break }
        }
        if (-not $connected) {
            throw 'Everything did not become ready within 60 seconds. It may be waiting on an elevation prompt; indexing NTFS volumes needs Administrator rights, so re-run this scanner as Administrator.'
        }
        Write-Host '      Waiting for the index to be built...'
        Wait-EverythingIndex
    }

    $indexedFiles = Get-EverythingFileCount
    if ($null -ne $indexedFiles) {
        Write-Host ("      Everything index: {0:n0} files. Only indexed drives are scanned." -f $indexedFiles)
    }

    if (-not $Reindex) { return }

    Write-Host '      Rebuilding Everything index (-Reindex)...' -ForegroundColor Yellow
    $reindexResult = Invoke-Es @('-reindex')
    if ($reindexResult.ExitCode -ne 0) { throw "Everything reindex failed (exit code $($reindexResult.ExitCode))." }
    Wait-EverythingIndex
}

function Get-Candidates($Database) {
    Write-Host '[4/5] Querying Everything for the required sizes...'

    $sizes = [Rdcc.Scanner]::SortedSizes($Database)
    $set = New-Object Rdcc.CandidateSet
    $queries = 0
    $index = 0

    while ($index -lt $sizes.Length) {
        $terms = [System.Collections.Generic.List[string]]::new()
        $length = 0
        while ($index -lt $sizes.Length) {
            $term = 'size:' + $sizes[$index]
            if ($terms.Count -gt 0 -and ($length + $term.Length + 1) -gt $MaxSearchLength) { break }
            $terms.Add($term)
            $length += $term.Length + 1
            $index++
        }

        $search = 'file:<' + ($terms -join '|') + '>'
        $csvPath = Join-Path $env:TEMP ('everything-candidates-{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        $TempFiles.Add($csvPath)

        $esResult = Invoke-Es @($search, '-export-csv', $csvPath, '-no-header', '-full-path-and-name', '-size', '-size-format', '1')
        if ($esResult.ExitCode -ne 0) { throw "Everything size query failed (exit code $($esResult.ExitCode))." }
        $queries++

        if (Test-Path -LiteralPath $csvPath -PathType Leaf) {
            [void]$set.AddFromCsv($csvPath, $Database)
        }
    }

    Write-Host "      Everything queries: $queries; candidates to hash: $($set.Count)"
    return $set.ToArray()
}

function Invoke-Scan($Candidates, $Database) {
    Write-Host "[5/5] Calculating SHA256 with $Threads thread(s)..."

    $total = $Candidates.Length
    if ($total -eq 0) { return [Rdcc.Scanner]::Run($Candidates, $Database, $Threads) }

    $scan = [Rdcc.Scanner]::RunAsync($Candidates, $Database, $Threads)
    while (-not $scan.Wait(250)) {
        $done = [Rdcc.Scanner]::Processed
        $status = '{0} / {1} ({2})' -f $done, $total, (Format-Bytes ([Rdcc.Scanner]::BytesRead))
        Write-Progress -Activity 'Calculating SHA256' -Status $status -PercentComplete (($done / $total) * 100)
    }
    Write-Progress -Activity 'Calculating SHA256' -Completed
    return $scan.Result
}

function Write-ScanReport($Result) {
    Write-Host ''

    if ($Result.Matches.Count -eq 0) {
        Write-Host 'No matching files found.' -ForegroundColor Green
    } else {
        Write-Host "MATCHES ($($Result.Matches.Count)):" -ForegroundColor Red
        foreach ($match in $Result.Matches) {
            Write-Host "MATCH: $($match.Path)" -ForegroundColor Red
            Write-Host "  Bytes:  $($match.Size)"
            Write-Host "  SHA256: $($match.Sha256)"
            Write-Host ''
        }
    }

    if ($Result.Changed -gt 0) {
        Write-Host "NOTE: $($Result.Changed) file(s) changed size after indexing and were skipped." -ForegroundColor Yellow
    }

    if ($Result.Skipped -gt 0) {
        Write-Host "NOTE: $($Result.Skipped) candidate(s) no longer matched a listed size and were skipped." -ForegroundColor Yellow
    }

    if ($Result.Failures.Count -gt 0) {
        Write-Host ''
        Write-Host "WARNING: $($Result.Failures.Count) candidate(s) could NOT be read and were left unverified." -ForegroundColor Yellow
        Write-Host '         Re-run as Administrator to reach protected locations.' -ForegroundColor Yellow
        $shown = 0
        foreach ($failure in $Result.Failures) {
            if ($shown -ge 10) {
                Write-Host "         ... and $($Result.Failures.Count - $shown) more." -ForegroundColor Yellow
                break
            }
            Write-Host "         $($failure.Path)  --  $($failure.Reason)" -ForegroundColor DarkYellow
            $shown++
        }
    }
}

try {
    Initialize-Scanner

    Sync-ProjectManifest

    if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
        throw "list.txt was not found: $ListPath"
    }

    Connect-Everything

    Write-Host '[3/5] Reading list.txt...'
    $database = [Rdcc.Scanner]::LoadList($ListPath)
    if ($database.ValidPairs -eq 0) {
        throw "List/list.txt contains no valid '<bytes> | <sha256>' pairs."
    }
    $listSummary = "      Valid pairs: $($database.ValidPairs); unique sizes: $($database.SizeCount)"
    if ($database.BadLines -gt 0) { $listSummary += "; skipped lines: $($database.BadLines)" }
    if ($database.DuplicateLines -gt 0) { $listSummary += "; duplicates: $($database.DuplicateLines)" }
    Write-Host $listSummary

    $candidates = Get-Candidates $database

    $swScan = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-Scan $candidates $database
    $swScan.Stop()

    Write-ScanReport $result

    $swTotal.Stop()
    $totalSeconds = $swTotal.Elapsed.TotalSeconds
    $scanSeconds = $swScan.Elapsed.TotalSeconds

    $throughput = ''
    if ($result.BytesHashed -gt 0 -and $scanSeconds -gt 0) {
        $throughput = ' at {0}/s' -f (Format-Bytes ($result.BytesHashed / $scanSeconds))
    }
    Write-Host ('Finished in {0:n1} s (hashing {1:n1} s). Verified: {2} file(s), {3}{4}. Matches: {5}. Unverified: {6}. Threads: {7}.' -f `
        $totalSeconds, $scanSeconds, $result.Hashed, (Format-Bytes $result.BytesHashed), $throughput, `
        $result.Matches.Count, $result.Failures.Count, $Threads) -ForegroundColor Cyan
}
catch {
    Stop-WithError $_.Exception.Message
}
finally {
    foreach ($tempFile in $TempFiles) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
}

if (-not $NoWait) { Read-Host 'Press Enter to exit' | Out-Null }
