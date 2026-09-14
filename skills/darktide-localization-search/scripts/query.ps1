[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Database,
    [string[]] $Key = @(),
    [string[]] $Hash = @(),
    [string[]] $Text = @(),
    [string[]] $Languages = @(),
    [string] $Resource,
    [int] $Limit = 50,
    [int] $Offset = 0,
    [switch] $Info,
    [string] $Sqlite = 'sqlite3.exe'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$script:SqliteExecutable = (Get-Command $Sqlite -CommandType Application -ErrorAction Stop).Source
$database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Database)
Assert-Index $database
if ($Info) {
    Invoke-Sqlite -Database $database -Sql 'SELECT info FROM metadata;' -ReadOnly
    return
}
if (-not $Languages.Count) { $Languages = @($script:Codes | Where-Object { $_ -cne 'comment' }) }
foreach ($code in $Languages) {
    if ($script:Codes -cnotcontains $code -or $code -ceq 'comment') { throw 'Unknown output language; comment is returned separately' }
}
if ($Limit -lt 0 -or $Offset -lt 0) { throw 'Limit and offset must be nonnegative' }
$hashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($value in $Hash) {
    if ($value -cnotmatch '\A[0-9A-Fa-f]{8}\z') { throw 'Hashes must contain exactly eight hexadecimal digits' }
    [void] $hashes.Add($value.ToUpperInvariant())
}
foreach ($value in $Key) {
    if (-not $value) { throw 'Keys must not be empty' }
    [void] $hashes.Add([DarktideLocalizationHash]::Compute($value))
}
$parameters = @{ limit = $Limit; take = $(if ($Limit) { $Limit } else { -1 }); offset = $Offset }
$filters = [Collections.Generic.List[string]]::new()
if ($hashes.Count) {
    $parameters.hashes = ConvertTo-Json -InputObject @($hashes) -Compress
    $filters.Add('hash IN (SELECT value FROM json_each(@hashes))')
}
for ($index = 0; $index -lt $Text.Count; $index++) {
    $parts = $Text[$index] -split '=', 2
    if ($parts.Count -ne 2 -or -not $parts[1] -or ($script:Codes -cnotcontains $parts[0] -and $parts[0] -cne '*')) {
        throw 'Text filters must be LANGUAGE=TEXT, or *=TEXT; text must not be empty'
    }
    $fields = if ($parts[0] -ceq '*') { @($script:Codes | Where-Object { $_ -cne 'comment' }) } else { @($parts[0]) }
    $parameter = "text$index"
    $parameters[$parameter] = $parts[1]
    $clauses = foreach ($code in $fields) { 'instr("' + $code + '", @' + $parameter + ') > 0' }
    $filters.Add('(' + ($clauses -join ' OR ') + ')')
}
if ($PSBoundParameters.ContainsKey('Resource')) {
    $parameters.resource = $Resource
    $filters.Add('resource = @resource')
}
if (-not ($hashes.Count -or $Text.Count)) { throw 'Supply at least one -Key, -Hash or -Text filter' }
$pairs = foreach ($code in ($Languages | Select-Object -Unique)) { "'$code', `"$code`"" }
$sql = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'query.sql'), $script:Utf8)
$sql = $sql.Replace('/*FILTERS*/', ($filters -join ' AND ')).Replace('/*TRANSLATIONS*/', ($pairs -join ', '))
Invoke-Sqlite -Database $database -Sql $sql -Parameters $parameters -ReadOnly
