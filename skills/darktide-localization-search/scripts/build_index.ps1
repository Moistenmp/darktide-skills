[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Strings,
    [Parameter(Mandatory)][string] $Database,
    [Parameter(Mandatory)][string] $TempRoot,
    [string] $Source,
    [string] $KeysFile,
    [string] $GameVersion,
    [switch] $Replace,
    [string] $Sqlite = 'sqlite3.exe'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$script:SqliteExecutable = (Get-Command $Sqlite -CommandType Application -ErrorAction Stop).Source
$root = (Get-Item -LiteralPath $Strings).FullName.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Strings must be a directory' }
$paths = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.strings' | Sort-Object FullName)
if (-not $paths.Count) { throw 'No .strings files found' }
$database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Database)
if (Test-Path -LiteralPath $database) {
    if (-not $Replace) { throw 'Database exists; use -Replace to rebuild this skill''s index' }
    Assert-Index $database
}
if ($Source) { $Source = (Resolve-Path -LiteralPath $Source).Path }
if ($KeysFile) { $KeysFile = (Resolve-Path -LiteralPath $KeysFile).Path }
$keys = Get-SourceKeys -Source $Source -KeysFile $KeysFile
$inputs = @($paths | ForEach-Object { Get-Fingerprint $_.FullName })
$parent = Split-Path -Parent $database
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Database parent directory does not exist' }
$stagingRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TempRoot)
if (-not (Test-Path -LiteralPath (Split-Path -Parent $stagingRoot) -PathType Container)) { throw 'Temporary root parent directory does not exist' }
[IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
$temporary = Join-Path $stagingRoot ('localization-' + [guid]::NewGuid().ToString('N'))
$count = 0
try {
    New-Item -ItemType Directory -Path $temporary | Out-Null
    $recordsCsv = Join-Path $temporary 'records.csv'
    $languageLookup = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($id in $script:LanguageMap.Keys) { $languageLookup.Add($id, $script:LanguageMap[$id]) }
    $count = [DarktideLocalizationHash]::Export($root, [string[]]$paths.FullName, $languageLookup, $keys, $recordsCsv)
    if (-not $count) { throw 'No localization records found' }
    $keysCsv = Join-Path $temporary 'keys.csv'
    $writer = [IO.StreamWriter]::new($keysCsv, $false, $script:Utf8)
    try {
        foreach ($key in $keys) { Write-CsvRow $writer @([DarktideLocalizationHash]::Compute($key), $key) }
    } finally {
        $writer.Dispose()
    }
    $schema = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'schema.sql'), $script:Utf8)
    $schema = $schema.Replace('/*COLUMNS*/', (Get-ColumnDefinitions))
    $fields = ($script:Codes | ForEach-Object { 'json_extract(body, ''$."' + $_ + '"'')' }) -join ', '
    $recordsImport = '"' + $recordsCsv.Replace('\', '/').Replace('"', '\"') + '"'
    $keysImport = '"' + $keysCsv.Replace('\', '/').Replace('"', '\"') + '"'
    $info = [ordered]@{
        created_utc = [DateTime]::UtcNow.ToString('o')
        game_version = $(if ($GameVersion) { $GameVersion } else { $null })
        strings = $inputs
        source = $(if ($Source) { $Source } else { $null })
        keys_file = $(if ($KeysFile) { Get-Fingerprint $KeysFile } else { $null })
        records = $count
        keys = $keys.Count
    }
    $staged = Join-Path $temporary 'index.sqlite'
    $sql = @"
$schema
BEGIN;
CREATE TEMP TABLE incoming(resource TEXT, hash TEXT, body TEXT);
.import --csv $recordsImport incoming
INSERT INTO localization SELECT resource, hash, $fields FROM incoming;
DROP TABLE incoming;
.import --csv $keysImport key_names
INSERT INTO metadata VALUES (@info);
COMMIT;
PRAGMA quick_check;
"@
    $check = Invoke-Sqlite -Database $staged -Sql $sql -Parameters @{ info = (ConvertTo-Json -InputObject $info -Compress -Depth 6) }
    if ($check -cne 'ok') { throw 'SQLite integrity check failed' }
    if (Test-Path -LiteralPath $database) {
        if (-not $Replace) { throw 'Database appeared during build; refusing to replace it' }
        Assert-Index $database
        [IO.File]::Replace($staged, $database, [NullString]::Value)
    } else {
        [IO.File]::Move($staged, $database)
    }
    ConvertTo-Json -InputObject ([ordered]@{ database = $database; records = $count; keys = $keys.Count }) -Compress
} finally {
    # Only remove the staging directory created by this invocation.
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    if ([IO.Path]::GetDirectoryName($resolvedTemporary) -ne [IO.Path]::GetFullPath($stagingRoot).TrimEnd('\', '/')) {
        throw 'Unexpected staging directory location'
    }
    if (Test-Path -LiteralPath $resolvedTemporary) { [IO.Directory]::Delete($resolvedTemporary, $true) }
    if ([IO.Directory]::GetFileSystemEntries($stagingRoot).Length -eq 0) {
        [IO.Directory]::Delete($stagingRoot, $false)
    }
}
