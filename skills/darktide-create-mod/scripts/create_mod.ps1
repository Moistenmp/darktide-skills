[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[AllowEmptyString()]
	[string] $OutputRoot,

	[Parameter(Mandatory = $true)]
	[AllowEmptyString()]
	[string] $Name,

	[Parameter(Mandatory = $true)]
	[AllowEmptyString()]
	[string] $Author,

	[Parameter(Mandatory = $true)]
	[AllowEmptyString()]
	[string] $Description,

	[AllowEmptyString()]
	[string] $Title,

	[AllowEmptyString()]
	[string] $Version = '1.0.0',

	[string] $Homepage,

	[string] $Source,

	[string[]] $Funding = @(),

	[string[]] $RequiredDependency = @(),

	[string[]] $LoadAfter = @(),

	[string[]] $LoadBefore = @(),

	[string[]] $LocalizedName = @(),

	[string[]] $LocalizedDescription = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validModName = '\A[A-Za-z0-9][A-Za-z0-9_-]*\z'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$titleWasSupplied = $PSBoundParameters.ContainsKey('Title')
$homepageWasSupplied = $PSBoundParameters.ContainsKey('Homepage')
$sourceWasSupplied = $PSBoundParameters.ContainsKey('Source')

function Get-DerivedTitle {
	param([string] $Value)

	$result = $Value -replace '[_-]+', ' '
	$result = $result -creplace '(?<=[a-z0-9])(?=[A-Z])', ' '
	$result = $result -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' '
	$words = @($result -split '\s+' | Where-Object { $_ })

	$converted = foreach ($word in $words) {
		if ($word -cmatch '^[^a-z]*$') {
			$word
		} else {
			$word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)
		}
	}

	return $converted -join ' '
}

function ConvertTo-LuaString {
	param([AllowEmptyString()][string] $Value)

	$builder = New-Object System.Text.StringBuilder

	foreach ($character in $Value.ToCharArray()) {
		$codePoint = [int] $character

		if ($codePoint -eq 92) {
			$encoded = '\\'
		} elseif ($codePoint -eq 34) {
			$encoded = '\"'
		} elseif ($codePoint -eq 10) {
			$encoded = '\n'
		} elseif ($codePoint -eq 13) {
			$encoded = '\r'
		} elseif ($codePoint -eq 9) {
			$encoded = '\t'
		} elseif ($codePoint -lt 32 -or $codePoint -eq 127) {
			$encoded = '\{0:000}' -f $codePoint
		} else {
			$encoded = [string] $character
		}

		[void] $builder.Append($encoded)
	}

	return '"' + $builder.ToString() + '"'
}

function Get-ValidatedUrl {
	param(
		[string] $Label,
		[string] $Value
	)

	if ($null -eq $Value) {
		return $null
	}

	$uri = $null
	$isValid = [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref] $uri)
	if ($Value -match '[\s\x00-\x1f\x7f]' -or -not $isValid -or $uri.Scheme -notin @('http', 'https') -or -not $uri.Host) {
		throw "$Label must be an HTTP or HTTPS URL"
	}

	return $Value
}

function ConvertTo-Funding {
	param([string[]] $Entries)

	$values = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
	$keys = New-Object 'System.Collections.Generic.List[string]'

	foreach ($entry in $Entries) {
		$separator = $entry.IndexOf('=')
		$provider = if ($separator -ge 0) {
			$entry.Substring(0, $separator).Trim()
		} else {
			''
		}
		$url = if ($separator -ge 0) {
			$entry.Substring($separator + 1).Trim()
		} else {
			''
		}

		if (-not $provider -or -not $url) {
			throw 'Funding entries must use PROVIDER=URL'
		}
		if ($values.ContainsKey($provider)) {
			throw "Duplicate funding provider: `"$provider`""
		}

		$url = Get-ValidatedUrl -Label "Funding URL for `"$provider`"" -Value $url
		$values.Add($provider, $url)
		$keys.Add($provider)
	}

	return [pscustomobject]@{
		Values = $values
		Keys = $keys
	}
}

function Get-ValidatedDependencies {
	param(
		[string] $Label,
		[string[]] $Values
	)

	$result = New-Object 'System.Collections.Generic.List[string]'
	$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

	foreach ($value in $Values) {
		if ($value -cnotmatch $validModName) {
			throw "Invalid $Label dependency: `"$value`""
		}
		if ($seen.Add($value)) {
			$result.Add($value)
		}
	}

	return $result.ToArray()
}

function Get-LanguageConfiguration {
	param([string] $SkillRoot)

	$configPath = Join-Path $SkillRoot 'references\languages.json'
	if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
		throw "Bundled language list is missing: $configPath"
	}

	$configText = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
	$config = $configText | ConvertFrom-Json
	if ($config -isnot [pscustomobject]) {
		throw 'Bundled language list must contain a JSON object'
	}

	$primaryProperty = $config.PSObject.Properties['primary']
	if ($null -eq $primaryProperty -or $primaryProperty.Value -isnot [string] -or -not $primaryProperty.Value.Trim()) {
		throw 'Bundled language list must define a non-empty primary language'
	}
	$primary = [string] $primaryProperty.Value

	$languagesProperty = $config.PSObject.Properties['languages']
	if ($null -eq $languagesProperty -or $languagesProperty.Value -isnot [pscustomobject]) {
		throw 'Bundled language list must define a non-empty languages object'
	}
	$languageProperties = @($languagesProperty.Value.PSObject.Properties)
	if ($languageProperties.Count -eq 0) {
		throw 'Bundled language list must define a non-empty languages object'
	}

	$supported = New-Object 'System.Collections.Generic.List[string]'
	foreach ($property in $languageProperties) {
		$code = $property.Name
		$displayName = $property.Value
		if ($code -cnotmatch $validModName) {
			throw "Invalid language code in bundled language list: `"$code`""
		}
		if ($displayName -isnot [string] -or -not $displayName.Trim()) {
			throw "Language `"$code`" must have a non-empty English name"
		}

		$supported.Add($code)
	}

	if ($supported -cnotcontains $primary) {
		throw "Primary language `"$primary`" is not in bundled language list"
	}

	return [pscustomobject]@{
		Primary = $primary
		Supported = $supported.ToArray()
	}
}

function ConvertTo-Localizations {
	param(
		[string] $Label,
		[string[]] $Entries,
		[string[]] $SupportedLanguages,
		[string] $PrimaryLanguage
	)

	$values = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
	$keys = New-Object 'System.Collections.Generic.List[string]'

	foreach ($entry in $Entries) {
		$separator = $entry.IndexOf('=')
		$language = if ($separator -ge 0) {
			$entry.Substring(0, $separator).Trim()
		} else {
			''
		}
		$text = if ($separator -ge 0) {
			$entry.Substring($separator + 1)
		} else {
			''
		}

		if (-not $language -or -not $text.Trim()) {
			throw "$Label entries must use LANGUAGE=TEXT"
		}
		if ($language -cnotmatch $validModName) {
			throw "Invalid localization language: `"$language`""
		}
		if ($SupportedLanguages -cnotcontains $language) {
			$expected = $SupportedLanguages -join ', '
			throw "Unsupported localization language: `"$language`". Expected one of: $expected"
		}
		if ($language -ceq $PrimaryLanguage) {
			throw "$Label must not override the primary `"$PrimaryLanguage`" value"
		}
		if ($values.ContainsKey($language)) {
			throw "Duplicate $Label language: `"$language`""
		}

		$values.Add($language, $text)
		$keys.Add($language)
	}

	return [pscustomobject]@{
		Values = $values
		Keys = $keys
	}
}

function Get-LuaLocalizationEntries {
	param([pscustomobject] $Localizations)

	$lines = foreach ($language in $Localizations.Keys) {
		$languageValue = ConvertTo-LuaString $language
		$textValue = ConvertTo-LuaString $Localizations.Values[$language]
		"`t`t[$languageValue] = $textValue,"
	}

	return $lines -join [Environment]::NewLine
}

function Get-JsonStringContent {
	param([AllowEmptyString()][string] $Value)

	$json = ConvertTo-Json -InputObject $Value -Compress
	return $json.Substring(1, $json.Length - 2)
}

function Replace-Tokens {
	param(
		[AllowEmptyString()][string] $Value,
		[System.Collections.IDictionary] $Replacements
	)

	$tokens = @($Replacements.Keys | Sort-Object { $_.Length } -Descending)
	if ($tokens.Count -eq 0) {
		return $Value
	}

	$pattern = ($tokens | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) -join '|'
	return [System.Text.RegularExpressions.Regex]::Replace($Value, $pattern, [System.Text.RegularExpressions.MatchEvaluator] {
		param($match)
		return [string] $Replacements[$match.Value]
	})
}

function Add-OptionalProperty {
	param(
		[pscustomobject] $Object,
		[string] $Name,
		[object] $Value
	)

	$Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Write-Utf8NoBom {
	param(
		[string] $LiteralPath,
		[AllowEmptyString()][string] $Value
	)

	[System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8NoBom)
}

function Invoke-TemplateRender {
	param(
		[string] $TemplateRoot,
		[string] $Target,
		[System.Collections.IDictionary] $CommonReplacements,
		[hashtable] $FileReplacements,
		[pscustomobject] $OptionalMetadata
	)

	[void] [System.IO.Directory]::CreateDirectory($Target)

	try {
		$items = @(Get-ChildItem -LiteralPath $TemplateRoot -Recurse -Force | Sort-Object FullName)
		$rootPrefixLength = $TemplateRoot.TrimEnd('\', '/').Length + 1

		foreach ($item in $items) {
			$relative = $item.FullName.Substring($rootPrefixLength)
			$parts = @($relative -split '[\\/]')
			$renderedParts = foreach ($part in $parts) {
				Replace-Tokens -Value $part -Replacements $CommonReplacements
			}
			$destination = $Target
			foreach ($part in $renderedParts) {
				$destination = Join-Path $destination $part
			}

			if ($item.PSIsContainer) {
				[void] [System.IO.Directory]::CreateDirectory($destination)
				continue
			}

			[void] [System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
			$content = [System.IO.File]::ReadAllText($item.FullName, [System.Text.Encoding]::UTF8)
			$replacements = [ordered]@{}
			foreach ($token in $CommonReplacements.Keys) {
				$replacements[$token] = $CommonReplacements[$token]
			}

			$normalizedRelative = $relative.Replace('\', '/')
			if ($FileReplacements.ContainsKey($normalizedRelative)) {
				foreach ($token in $FileReplacements[$normalizedRelative].Keys) {
					$replacements[$token] = $FileReplacements[$normalizedRelative][$token]
				}
			}

			$rendered = Replace-Tokens -Value $content -Replacements $replacements
			$rendered = [System.Text.RegularExpressions.Regex]::Replace(
				$rendered,
				'\r\n|\r|\n',
				[Environment]::NewLine
			)
			Write-Utf8NoBom -LiteralPath $destination -Value $rendered
		}

		$infoPath = Join-Path $Target 'info.json'
		$info = [System.IO.File]::ReadAllText($infoPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
		foreach ($property in $OptionalMetadata.PSObject.Properties) {
			Add-OptionalProperty -Object $info -Name $property.Name -Value $property.Value
		}

		$infoJson = ConvertTo-Json -InputObject $info -Depth 10
		Write-Utf8NoBom -LiteralPath $infoPath -Value ($infoJson + [Environment]::NewLine)
	} catch {
		if ([System.IO.Directory]::Exists($Target)) {
			[System.IO.Directory]::Delete($Target, $true)
		}
		throw
	}
}

function Invoke-CreateMod {
	if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
		throw "Output root does not exist: $OutputRoot"
	}
	if ($Name -cnotmatch $validModName) {
		throw "Mod name `"$Name`" must match [A-Za-z0-9][A-Za-z0-9_-]*"
	}
	if (-not $Author.Trim()) {
		throw 'Author must not be empty'
	}
	if (-not $Description.Trim()) {
		throw 'Description must not be empty'
	}
	if ($titleWasSupplied -and -not $Title.Trim()) {
		throw 'Title must not be empty when supplied'
	}
	if (-not $Version.Trim()) {
		throw 'Version must not be empty'
	}

	$resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).ProviderPath
	$target = Join-Path $resolvedOutputRoot $Name
	if (Test-Path -LiteralPath $target) {
		throw "Target folder already exists: `"$target`""
	}

	$skillRoot = Split-Path -Parent $PSScriptRoot
	$templateRoot = Join-Path $skillRoot 'assets\mod-template'
	if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
		throw "Bundled template is missing: $templateRoot"
	}
	$templateRoot = (Resolve-Path -LiteralPath $templateRoot).ProviderPath
	$languageConfig = Get-LanguageConfiguration -SkillRoot $skillRoot

	$resolvedTitle = if ($titleWasSupplied) {
		$Title
	} else {
		Get-DerivedTitle $Name
	}

	$resolvedHomepage = if ($homepageWasSupplied) {
		Get-ValidatedUrl -Label 'Homepage' -Value $Homepage
	} else {
		$null
	}
	$resolvedSource = if ($sourceWasSupplied) {
		Get-ValidatedUrl -Label 'Source' -Value $Source
	} else {
		$null
	}
	$resolvedFunding = ConvertTo-Funding -Entries $Funding
	$required = @(Get-ValidatedDependencies -Label 'required' -Values $RequiredDependency)
	$selfAfter = @(Get-ValidatedDependencies -Label 'load-after' -Values $LoadAfter)
	$selfBefore = @(Get-ValidatedDependencies -Label 'load-before' -Values $LoadBefore)
	$localizedNames = ConvertTo-Localizations -Label 'Localized name' -Entries $LocalizedName -SupportedLanguages $languageConfig.Supported -PrimaryLanguage $languageConfig.Primary
	$localizedDescriptions = ConvertTo-Localizations -Label 'Localized description' -Entries $LocalizedDescription -SupportedLanguages $languageConfig.Supported -PrimaryLanguage $languageConfig.Primary

	$optionalMetadata = [pscustomobject]@{}
	if ($resolvedHomepage) {
		Add-OptionalProperty -Object $optionalMetadata -Name 'homepage' -Value $resolvedHomepage
	}
	if ($resolvedSource) {
		Add-OptionalProperty -Object $optionalMetadata -Name 'source' -Value $resolvedSource
	}
	if ($resolvedFunding.Keys.Count -gt 0) {
		Add-OptionalProperty -Object $optionalMetadata -Name 'funding' -Value $resolvedFunding.Values
	}

	$dependencies = [pscustomobject]@{}
	if ($required.Count -gt 0) {
		Add-OptionalProperty -Object $dependencies -Name 'required' -Value $required
	}
	if ($selfAfter.Count -gt 0) {
		Add-OptionalProperty -Object $dependencies -Name 'self_after' -Value $selfAfter
	}
	if ($selfBefore.Count -gt 0) {
		Add-OptionalProperty -Object $dependencies -Name 'self_before' -Value $selfBefore
	}
	if (@($dependencies.PSObject.Properties).Count -gt 0) {
		Add-OptionalProperty -Object $optionalMetadata -Name 'dependencies' -Value $dependencies
	}

	$localizations = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
	$languages = New-Object 'System.Collections.Generic.List[string]'
	$seenLanguages = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
	foreach ($language in @($localizedNames.Keys) + @($localizedDescriptions.Keys)) {
		if ($seenLanguages.Add($language)) {
			$languages.Add($language)
		}
	}
	foreach ($language in $languages) {
		$fields = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
		if ($localizedNames.Values.ContainsKey($language)) {
			$fields.Add('name', $localizedNames.Values[$language])
		}
		if ($localizedDescriptions.Values.ContainsKey($language)) {
			$fields.Add('description', $localizedDescriptions.Values[$language])
		}
		$localizations.Add($language, $fields)
	}
	if ($localizations.Count -gt 0) {
		Add-OptionalProperty -Object $optionalMetadata -Name 'localization' -Value $localizations
	}

	$commonReplacements = [ordered]@{
		'%%name' = $Name
	}
	$fileReplacements = @{
		'info.json' = [ordered]@{
			'%%title' = Get-JsonStringContent $resolvedTitle
			'%%description' = Get-JsonStringContent $Description
			'%%version' = Get-JsonStringContent $Version
			'%%author' = Get-JsonStringContent $Author
		}
		'scripts/mods/%%name/%%name_localization.lua' = [ordered]@{
			'%%title' = (ConvertTo-LuaString $resolvedTitle).Substring(1, (ConvertTo-LuaString $resolvedTitle).Length - 2)
			'%%description' = (ConvertTo-LuaString $Description).Substring(1, (ConvertTo-LuaString $Description).Length - 2)
			'%%localized_names' = Get-LuaLocalizationEntries $localizedNames
			'%%localized_descriptions' = Get-LuaLocalizationEntries $localizedDescriptions
		}
	}

	Invoke-TemplateRender -TemplateRoot $templateRoot -Target $target -CommonReplacements $commonReplacements -FileReplacements $fileReplacements -OptionalMetadata $optionalMetadata
	[Console]::Out.WriteLine($target)
}

try {
	Invoke-CreateMod
	exit 0
} catch {
	[Console]::Error.WriteLine("error: $($_.Exception.Message)")
	exit 1
}
