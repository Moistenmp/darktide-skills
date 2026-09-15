[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InputDirectory,
    [Parameter(Mandatory)][string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false, $true)
[Console]::OutputEncoding = $utf8

# Keep the per-entry conversion in the built-in compiler, as in the index builder.
if (-not ('DarktideStringsConverter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public static class DarktideStringsConverter {
    private const int CountSize = 4;
    private const int EntrySize = 8;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);

    private static uint ReadUInt32(byte[] data, int offset) {
        return (uint)data[offset] | ((uint)data[offset + 1] << 8) |
               ((uint)data[offset + 2] << 16) | ((uint)data[offset + 3] << 24);
    }

    private static long ReadVariant(string path, uint language,
                                   SortedDictionary<uint, SortedDictionary<uint, string>> records,
                                   ref long duplicates) {
        byte[] data = File.ReadAllBytes(path);
        if (data.Length < CountSize) throw new FormatException(path + ": Missing entry count");
        uint count = ReadUInt32(data, 0);
        long tableEnd = CountSize + (long)count * EntrySize;
        if (tableEnd > data.Length) throw new FormatException(path + ": Truncated entry table");
        // The count is followed by hash/offset pairs; offsets are variant-relative.
        for (int index = 0; index < count; index++) {
            uint hash = ReadUInt32(data, CountSize + index * EntrySize);
            uint offset = ReadUInt32(data, CountSize + index * EntrySize + CountSize);
            if (offset < tableEnd || offset >= data.Length)
                throw new FormatException(path + ": Invalid text offset for " + hash.ToString("X8"));
            int end = Array.IndexOf(data, (byte)0, (int)offset);
            if (end < 0) throw new FormatException(path + ": Unterminated text for " + hash.ToString("X8"));
            string text;
            try {
                text = Utf8.GetString(data, (int)offset, end - (int)offset);
            } catch (DecoderFallbackException error) {
                throw new FormatException(path + ": Invalid UTF-8 for " + hash.ToString("X8"), error);
            }
            SortedDictionary<uint, string> values;
            if (!records.TryGetValue(hash, out values)) {
                values = new SortedDictionary<uint, string>();
                records.Add(hash, values);
            }
            if (values.ContainsKey(language)) duplicates++;
            // Match DTMT's last-entry-wins map insertion and report duplicates.
            values[language] = text;
        }
        return count;
    }

    private static string Quote(string text) {
        return "\"" + text.Replace("\\", "\\\\").Replace("\"", "\\\"")
                          .Replace("\t", "\\t").Replace("\r", "\\r").Replace("\n", "\\n") + "\"";
    }

    public static long[] ConvertResource(string[] paths, uint[] languages, string destination) {
        SortedDictionary<uint, SortedDictionary<uint, string>> records =
            new SortedDictionary<uint, SortedDictionary<uint, string>>();
        long translations = 0;
        long duplicates = 0;
        for (int index = 0; index < paths.Length; index++)
            translations += ReadVariant(paths[index], languages[index], records, ref duplicates);
        if (records.Count == 0) throw new FormatException(destination + ": Resource has no localization records");
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        using (StreamWriter writer = new StreamWriter(destination, false, Utf8)) {
            writer.NewLine = "\n";
            foreach (KeyValuePair<uint, SortedDictionary<uint, string>> record in records) {
                writer.WriteLine(record.Key.ToString("X8") + " = {");
                foreach (KeyValuePair<uint, string> value in record.Value)
                    writer.WriteLine("  lang_" + value.Key + " = " + Quote(value.Value));
                writer.WriteLine("}");
            }
        }
        return new long[] { translations, duplicates };
    }
}
'@
}

$root = (Get-Item -LiteralPath $InputDirectory).FullName.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Input must be a directory' }
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Output directory already exists' }
$parent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Output parent directory does not exist' }
if ($output.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be outside the input directory'
}
$languageData = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'languages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$groups = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$paths = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.strings' | Sort-Object FullName)
if (-not $paths.Count) { throw 'No raw .strings language variants found' }
foreach ($path in $paths) {
    $match = [regex]::Match($path.Name, '\A(.+)\.(0|[1-9][0-9]*)\.strings\z')
    if (-not $match.Success) { throw "$($path.FullName): Expected <resource>.<language-id>.strings" }
    $language = $match.Groups[2].Value
    if ($language -cnotin $languageData.PSObject.Properties.Name) { throw "$($path.FullName): Unknown language ID $language" }
    $relative = $path.FullName.Substring($root.Length + 1)
    $resource = [IO.Path]::Combine([IO.Path]::GetDirectoryName($relative), $match.Groups[1].Value + '.strings')
    if (-not $groups.ContainsKey($resource)) { $groups.Add($resource, [Collections.Generic.List[object]]::new()) }
    $groups[$resource].Add([pscustomobject]@{ Path = $path.FullName; Language = [uint32]$language })
}

$temporary = Join-Path $parent ('strings-' + [guid]::NewGuid().ToString('N'))
$staged = Join-Path $temporary 'converted'
$translations = 0L
$duplicates = 0L
try {
    New-Item -ItemType Directory -Path $staged | Out-Null
    foreach ($resource in ($groups.Keys | Sort-Object)) {
        $variants = @($groups[$resource] | Sort-Object Language)
        $counts = [DarktideStringsConverter]::ConvertResource(
            [string[]]$variants.Path, [uint32[]]$variants.Language, (Join-Path $staged $resource))
        $translations += $counts[0]
        $duplicates += $counts[1]
    }
    [IO.Directory]::Move($staged, $output)
} finally {
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    if ([IO.Path]::GetDirectoryName($resolvedTemporary) -ne [IO.Path]::GetFullPath($parent).TrimEnd('\', '/')) {
        throw 'Unexpected staging directory location'
    }
    if (Test-Path -LiteralPath $resolvedTemporary) { [IO.Directory]::Delete($resolvedTemporary, $true) }
}
ConvertTo-Json -InputObject ([ordered]@{
    output = $output
    resources = $groups.Count
    variants = $paths.Count
    translations = $translations
    duplicate_entries = $duplicates
}) -Compress
