Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
[Console]::OutputEncoding = $script:Utf8
$script:LanguageMap = [ordered]@{}
$languageData = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'languages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($property in $languageData.PSObject.Properties) {
    $script:LanguageMap[$property.Name] = $property.Value
}
$script:Codes = @($script:LanguageMap.Values)
$script:ApplicationId = 1146375251
$script:SchemaVersion = 1

# Compile the streaming conversion once; per-field PowerShell pipelines are costly.
if (-not ('DarktideLocalizationHash' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
public static class DarktideLocalizationHash {
    public static string Compute(string key) {
        unchecked {
            byte[] bytes = Encoding.UTF8.GetBytes(key);
            const ulong mix = 0xC6A4A7935BD1E995UL;
            ulong result = (ulong)bytes.Length * mix;
            int whole = bytes.Length / 8 * 8;
            for (int offset = 0; offset < whole; offset += 8) {
                ulong block = 0;
                for (int index = 0; index < 8; index++)
                    block |= (ulong)bytes[offset + index] << (8 * index);
                block *= mix;
                block ^= block >> 47;
                block *= mix;
                result = (result ^ block) * mix;
            }
            ulong tail = 0;
            for (int offset = whole; offset < bytes.Length; offset++)
                tail |= (ulong)bytes[offset] << (8 * (offset - whole));
            if (whole < bytes.Length) result = (result ^ tail) * mix;
            result ^= result >> 47;
            result *= mix;
            result ^= result >> 47;
            return ((uint)(result >> 32)).ToString("X8");
        }
    }

    private static string Decode(string raw) {
        if (!raw.StartsWith("\"", StringComparison.Ordinal)) {
            if (raw.Length == 0 || raw.IndexOfAny(new char[] {' ', '\t', '\r', '\n', '=', '"', '\'', '\\', ':'}) >= 0)
                throw new FormatException("Invalid unquoted SJSON string");
            return raw;
        }
        if (raw.Length < 2 || !raw.EndsWith("\"", StringComparison.Ordinal))
            throw new FormatException("Unterminated SJSON string");
        StringBuilder value = new StringBuilder();
        for (int i = 1; i < raw.Length - 1; i++) {
            char c = raw[i];
            if (c == '"') throw new FormatException("Unescaped quote in SJSON string");
            if (c != '\\') { value.Append(c); continue; }
            if (++i >= raw.Length - 1) throw new FormatException("Invalid SJSON escape");
            switch (raw[i]) {
                case 't': value.Append('\t'); break;
                case 'n': value.Append('\n'); break;
                case 'r': value.Append('\r'); break;
                case '"': value.Append('"'); break;
                case '\\': value.Append('\\'); break;
                default: throw new FormatException("Invalid SJSON escape");
            }
        }
        return value.ToString();
    }

    private static string JsonString(string text) {
        StringBuilder result = new StringBuilder("\"");
        foreach (char c in text) {
            if (c == '"' || c == '\\') result.Append('\\').Append(c);
            else if (c < 32) result.Append("\\u").Append(((int)c).ToString("x4"));
            else result.Append(c);
        }
        return result.Append('"').ToString();
    }

    private static string CsvString(string text) {
        return "\"" + text.Replace("\"", "\"\"") + "\"";
    }

    public static long Export(string root, string[] paths, Dictionary<string, string> languages,
                              HashSet<string> keys, string destination) {
        long count = 0;
        UTF8Encoding utf8 = new UTF8Encoding(false, true);
        using (StreamWriter writer = new StreamWriter(destination, false, utf8)) {
            foreach (string path in paths) {
                string resource = path.Substring(root.Length + 1).Replace('\\', '/');
                string name = null;
                string hash = null;
                StringBuilder body = null;
                HashSet<string> seen = new HashSet<string>();
                int number = 0;
                try {
                    using (StreamReader reader = new StreamReader(path, utf8, true)) {
                        string line;
                        while ((line = reader.ReadLine()) != null) {
                            number++;
                            if (line.Length == 0) continue;
                            if (body == null) {
                                if (!line.EndsWith(" = {", StringComparison.Ordinal))
                                    throw new FormatException("Expected a record header");
                                name = Decode(line.Substring(0, line.Length - 4));
                                bool isHash = Regex.IsMatch(name, "\\A[0-9A-Fa-f]{8}\\z");
                                hash = isHash ? name.ToUpperInvariant() : Compute(name);
                                if (!isHash) keys.Add(name);
                                body = new StringBuilder("{");
                                seen.Clear();
                                continue;
                            }
                            if (line == "}") {
                                if (seen.Count == 0) throw new FormatException("Record has no language fields");
                                body.Append('}');
                                writer.WriteLine(CsvString(resource) + "," + CsvString(hash) + "," + CsvString(body.ToString()));
                                body = null;
                                count++;
                                continue;
                            }
                            int delimiter = line.IndexOf(" = ", StringComparison.Ordinal);
                            string code;
                            if (!line.StartsWith("  lang_", StringComparison.Ordinal) || delimiter < 7 ||
                                !languages.TryGetValue(line.Substring(7, delimiter - 7), out code))
                                throw new FormatException("Unknown language or invalid field");
                            if (!seen.Add(code)) throw new FormatException("Duplicate language field");
                            if (seen.Count > 1) body.Append(',');
                            body.Append(JsonString(code)).Append(':').Append(JsonString(Decode(line.Substring(delimiter + 3))));
                        }
                    }
                    if (body != null) throw new FormatException("Unterminated record");
                } catch (FormatException error) {
                    throw new FormatException(path + ":" + number + ": " + error.Message, error);
                }
            }
        }
        return count;
    }
}
'@
}

function Get-SourceKeys {
    param([string] $Source, [string] $KeysFile)
    $result = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($Source) {
        $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Filter '*.lua')
        if (-not $files.Count) { throw 'Source directory contains no .lua files' }
        foreach ($file in $files) {
            $text = [IO.File]::ReadAllText($file.FullName, $script:Utf8)
            foreach ($match in [regex]::Matches($text, '(?<![A-Za-z0-9_])loc_[A-Za-z0-9_]+')) {
                [void] $result.Add($match.Value)
            }
        }
    }
    if ($KeysFile) {
        foreach ($line in [IO.File]::ReadAllLines($KeysFile, $script:Utf8)) {
            if ($line.Trim()) { [void] $result.Add($line.Trim()) }
        }
    }
    return ,$result
}

function Get-Fingerprint {
    param([string] $Path)
    $file = Get-Item -LiteralPath $Path
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($file.FullName)
    try {
        $digest = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
    return [ordered]@{
        path = $file.FullName
        bytes = $file.Length
        sha256 = $digest
    }
}

function ConvertTo-ProcessArgument {
    param([string] $Value)
    # Windows CommandLineToArgvW quoting, including trailing backslashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-Sqlite {
    param([string] $Database, [string] $Sql, [System.Collections.IDictionary] $Parameters = @{}, [switch] $ReadOnly)
    $command = [Text.StringBuilder]::new(".parameter init`n")
    foreach ($name in $Parameters.Keys) {
        $value = $Parameters[$name]
        if ($value -is [int] -or $value -is [long]) {
            [void] $command.AppendLine(".parameter set @$name $value")
        } else {
            # Only hexadecimal bytes enter the shell command; the SQL uses bindings.
            $hex = [BitConverter]::ToString($script:Utf8.GetBytes([string]$value)).Replace('-', '')
            [void] $command.AppendLine(".parameter set @$name `"CAST(X'$hex' AS TEXT)`"")
        }
    }
    [void] $command.AppendLine($Sql)
    $arguments = @('-batch', '-bail', '-init', 'NUL', '-list', '-noheader')
    if ($ReadOnly) { $arguments += '-readonly' }
    $arguments += $Database
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $script:SqliteExecutable
    $start.Arguments = ($arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $script:Utf8
    $start.StandardErrorEncoding = $script:Utf8
    $inputEncoding = [Console]::InputEncoding
    try {
        # .NET Framework derives the stdin writer's encoding from the console.
        [Console]::InputEncoding = $script:Utf8
        $process = [Diagnostics.Process]::Start($start)
    } finally {
        [Console]::InputEncoding = $inputEncoding
    }
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($command.ToString())
        $process.StandardInput.Close()
        $process.WaitForExit()
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $errorText.Trim()) { throw "SQLite failed: $errorText" }
        return $output.TrimEnd("`r", "`n")
    } finally {
        $process.Dispose()
    }
}

function Assert-Index {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Database not found: $Path" }
    $sql = 'SELECT json_array((SELECT application_id FROM pragma_application_id), (SELECT user_version FROM pragma_user_version));'
    $identity = Invoke-Sqlite -Database $Path -Sql $sql -ReadOnly | ConvertFrom-Json
    if ($identity[0] -ne $script:ApplicationId -or $identity[1] -ne $script:SchemaVersion) {
        throw 'Not a localization index created by this skill; build a separate index'
    }
}

function Get-ColumnDefinitions {
    return ($script:Codes | ForEach-Object { '"' + $_ + '" TEXT' }) -join ', '
}

function Write-CsvRow {
    param([IO.StreamWriter] $Writer, [string[]] $Values)
    $fields = foreach ($value in $Values) { '"' + $value.Replace('"', '""') + '"' }
    $Writer.WriteLine($fields -join ',')
}
