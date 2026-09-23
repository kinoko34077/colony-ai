function Get-KntJson {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }
    try {
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "JSON parse error: $Path :: $($_.Exception.Message)"
    }
}

function Get-KntJsonType {
    param($Value)

    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { return "boolean" }
    if ($Value -is [string]) { return "string" }
    if ($Value -is [System.Array]) { return "array" }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) { return "integer" }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return "number" }
    return "object"
}

function Get-KntJsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-KntJsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Test-KntJsonEqual {
    param($Left, $Right)
    if ((Get-KntJsonType $Left) -ne (Get-KntJsonType $Right)) { return $false }
    if ((Get-KntJsonType $Left) -in @("object", "array")) {
        return ((ConvertTo-Json $Left -Compress -Depth 100) -eq (ConvertTo-Json $Right -Compress -Depth 100))
    }
    return $Left -eq $Right
}

function Test-KntSchemaNode {
    param(
        $Data,
        $Schema,
        [string]$Path
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Schema) { return $errors.ToArray() }

    $typeSchema = Get-KntJsonProperty $Schema "type"
    if ($null -ne $typeSchema) {
        $actualType = Get-KntJsonType $Data
        $allowedTypes = if ($typeSchema -is [System.Array]) { @($typeSchema) } else { @($typeSchema) }
        $typeMatches = $false
        foreach ($allowed in $allowedTypes) {
            if ([string]$allowed -eq $actualType -or ([string]$allowed -eq "number" -and $actualType -eq "integer")) {
                $typeMatches = $true
            }
        }
        if (-not $typeMatches) {
            [void]$errors.Add("$Path has type $actualType but expected $($allowedTypes -join ',')")
            return $errors.ToArray()
        }
    }

    $const = Get-KntJsonProperty $Schema "const"
    if ($null -ne $const -and -not (Test-KntJsonEqual $Data $const)) {
        [void]$errors.Add("$Path must equal $const")
    }

    $enum = Get-KntJsonProperty $Schema "enum"
    if ($null -ne $enum) {
        $enumMatch = $false
        foreach ($candidate in @($enum)) {
            if (Test-KntJsonEqual $Data $candidate) { $enumMatch = $true }
        }
        if (-not $enumMatch) { [void]$errors.Add("$Path is not an allowed value") }
    }

    $oneOf = Get-KntJsonProperty $Schema "oneOf"
    if ($null -ne $oneOf) {
        $oneOfMatchCount = 0
        $oneOfFailureMessages = New-Object System.Collections.Generic.List[string]
        foreach ($candidateSchema in @($oneOf)) {
            $candidateErrors = @(Test-KntSchemaNode -Data $Data -Schema $candidateSchema -Path $Path)
            if ($candidateErrors.Count -eq 0) {
                $oneOfMatchCount++
            }
            else {
                foreach ($candidateError in $candidateErrors) {
                    [void]$oneOfFailureMessages.Add($candidateError)
                }
            }
        }
        if ($oneOfMatchCount -ne 1) {
            $detail = ""
            if ($oneOfMatchCount -eq 0 -and $oneOfFailureMessages.Count -gt 0) {
                $detail = ": " + (($oneOfFailureMessages | Select-Object -Unique) -join "; ")
            }
            [void]$errors.Add("$Path does not match exactly one oneOf schema (matched $oneOfMatchCount)$detail")
        }
    }

    $actualType = Get-KntJsonType $Data
    if ($actualType -eq "object") {
        $required = Get-KntJsonProperty $Schema "required"
        if ($null -ne $required) {
            foreach ($requiredName in @($required)) {
                if (-not (Test-KntJsonProperty $Data ([string]$requiredName))) {
                    [void]$errors.Add("$Path is missing required property '$requiredName'")
                }
            }
        }

        $propertiesSchema = Get-KntJsonProperty $Schema "properties"
        $additionalProperties = Get-KntJsonProperty $Schema "additionalProperties"
        foreach ($property in $Data.PSObject.Properties | Sort-Object Name) {
            $propertySchema = if ($null -ne $propertiesSchema) { Get-KntJsonProperty $propertiesSchema $property.Name } else { $null }
            if ($null -ne $propertySchema) {
                foreach ($errorText in @(Test-KntSchemaNode -Data $property.Value -Schema $propertySchema -Path "$Path.$($property.Name)")) {
                    [void]$errors.Add($errorText)
                }
            }
            elseif ($additionalProperties -eq $false) {
                [void]$errors.Add("$Path has unknown property '$($property.Name)'")
            }
            elseif ((Get-KntJsonType $additionalProperties) -eq "object") {
                foreach ($errorText in @(Test-KntSchemaNode -Data $property.Value -Schema $additionalProperties -Path "$Path.$($property.Name)")) {
                    [void]$errors.Add($errorText)
                }
            }
        }
    }

    if ($actualType -eq "array") {
        $itemsSchema = Get-KntJsonProperty $Schema "items"
        if ($null -ne $itemsSchema) {
            for ($index = 0; $index -lt $Data.Count; $index++) {
                foreach ($errorText in @(Test-KntSchemaNode -Data $Data[$index] -Schema $itemsSchema -Path "$Path[$index]")) {
                    [void]$errors.Add($errorText)
                }
            }
        }
        if ((Get-KntJsonProperty $Schema "uniqueItems") -eq $true) {
            $serialized = @($Data | ForEach-Object { ConvertTo-Json $_ -Compress -Depth 100 })
            if (($serialized | Select-Object -Unique).Count -ne $serialized.Count) {
                [void]$errors.Add("$Path must contain unique items")
            }
        }
    }

    if ($actualType -eq "string") {
        $minLength = Get-KntJsonProperty $Schema "minLength"
        if ($null -ne $minLength -and $Data.Length -lt [int]$minLength) {
            [void]$errors.Add("$Path must have at least $minLength characters")
        }
        $pattern = Get-KntJsonProperty $Schema "pattern"
        if ($null -ne $pattern -and -not [regex]::IsMatch([string]$Data, [string]$pattern)) {
            [void]$errors.Add("$Path does not match pattern $pattern")
        }
    }

    return $errors.ToArray()
}

function Test-KntSchema {
    param(
        [Parameter(Mandatory=$true)]$Data,
        [Parameter(Mandatory=$true)]$Schema,
        [Parameter(Mandatory=$true)][string]$Path
    )
    return @(Test-KntSchemaNode -Data $Data -Schema $Schema -Path $Path)
}
