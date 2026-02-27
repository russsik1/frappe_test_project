param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$Username = "Administrator",
    [string]$Password = "",
    [string]$NamePrefix = "",
    [string]$ClientScriptName = "",
    [string]$ServerScriptName = ""
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$clientScriptPath = Join-Path $scriptDir "client_script.task_auto_dates.js"
$serverScriptPath = Join-Path $scriptDir "server_script.task_auto_dates.py"

if ([string]::IsNullOrWhiteSpace($ClientScriptName)) {
    if ([string]::IsNullOrWhiteSpace($NamePrefix)) {
        $ClientScriptName = "Task Auto Dates Client"
    } else {
        $ClientScriptName = "$($NamePrefix.Trim()) Task Auto Dates Client"
    }
}

if ([string]::IsNullOrWhiteSpace($ServerScriptName)) {
    if ([string]::IsNullOrWhiteSpace($NamePrefix)) {
        $ServerScriptName = "Task Auto Dates Server"
    } else {
        $ServerScriptName = "$($NamePrefix.Trim()) Task Auto Dates Server"
    }
}

if (!(Test-Path $clientScriptPath)) {
    throw "File not found: $clientScriptPath"
}

if (!(Test-Path $serverScriptPath)) {
    throw "File not found: $serverScriptPath"
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $securePassword = Read-Host "ERPNext password for $Username" -AsSecureString
    $Password = [System.Net.NetworkCredential]::new("", $securePassword).Password
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Get-StatusCodeFromWebError {
    param([object]$ErrorRecord)

    if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
        return [int]$ErrorRecord.Exception.Response.StatusCode
    }

    return -1
}

function Test-ResourceExists {
    param(
        [string]$Doctype,
        [string]$Name
    )

    $doctypeEncoded = [System.Uri]::EscapeDataString($Doctype)
    $nameEncoded = [System.Uri]::EscapeDataString($Name)
    $uri = "$BaseUrl/api/resource/$doctypeEncoded/$nameEncoded"

    try {
        Invoke-WebRequest -Uri $uri -Method Get -WebSession $session | Out-Null
        return $true
    } catch {
        $statusCode = Get-StatusCodeFromWebError -ErrorRecord $_
        if ($statusCode -eq 404) {
            return $false
        }

        throw
    }
}

function Get-Resource {
    param(
        [string]$Doctype,
        [string]$Name
    )

    $doctypeEncoded = [System.Uri]::EscapeDataString($Doctype)
    $nameEncoded = [System.Uri]::EscapeDataString($Name)
    $uri = "$BaseUrl/api/resource/$doctypeEncoded/$nameEncoded"
    $response = Invoke-WebRequest -Uri $uri -Method Get -WebSession $session
    return ($response.Content | ConvertFrom-Json).data
}

function Upsert-Resource {
    param(
        [string]$Doctype,
        [string]$Name,
        [hashtable]$Payload
    )

    $doctypeEncoded = [System.Uri]::EscapeDataString($Doctype)
    $nameEncoded = [System.Uri]::EscapeDataString($Name)
    $uri = "$BaseUrl/api/resource/$doctypeEncoded/$nameEncoded"

    if (Test-ResourceExists -Doctype $Doctype -Name $Name) {
        Invoke-WebRequest `
            -Uri $uri `
            -Method Put `
            -WebSession $session `
            -ContentType "application/json" `
            -Body ($Payload | ConvertTo-Json -Depth 20) | Out-Null
        Write-Host "[updated] $Doctype -> $Name"
        return
    }

    $createUri = "$BaseUrl/api/resource/$doctypeEncoded"
    $createPayload = @{}
    foreach ($key in $Payload.Keys) {
        $createPayload[$key] = $Payload[$key]
    }
    $createPayload["name"] = $Name

    Invoke-WebRequest `
        -Uri $createUri `
        -Method Post `
        -WebSession $session `
        -ContentType "application/json" `
        -Body ($createPayload | ConvertTo-Json -Depth 20) | Out-Null
    Write-Host "[created] $Doctype -> $Name"
}

Invoke-WebRequest `
    -Uri "$BaseUrl/api/method/login" `
    -Method Post `
    -Body @{ usr = $Username; pwd = $Password } `
    -WebSession $session | Out-Null

Write-Host "Logged in to ERPNext: $BaseUrl"

$clientScriptCode = [System.IO.File]::ReadAllText($clientScriptPath)
$serverScriptCode = [System.IO.File]::ReadAllText($serverScriptPath)

$clientPayload = @{
    dt = "Task"
    view = "Form"
    enabled = 1
    script = $clientScriptCode
}

$serverPayload = @{
    script_type = "DocType Event"
    reference_doctype = "Task"
    doctype_event = "Before Save"
    disabled = 0
    script = $serverScriptCode
}

Upsert-Resource `
    -Doctype "Client Script" `
    -Name $ClientScriptName `
    -Payload $clientPayload

Upsert-Resource `
    -Doctype "Server Script" `
    -Name $ServerScriptName `
    -Payload $serverPayload

$clientDoc = Get-Resource -Doctype "Client Script" -Name $ClientScriptName
$serverDoc = Get-Resource -Doctype "Server Script" -Name $ServerScriptName

Write-Host "Client Script check: name=$($clientDoc.name), dt=$($clientDoc.dt), enabled=$($clientDoc.enabled)"
Write-Host "Server Script check: name=$($serverDoc.name), doctype=$($serverDoc.reference_doctype), event=$($serverDoc.doctype_event), disabled=$($serverDoc.disabled)"
Write-Host "Done."
Write-Host "If you get 'Server Scripts are disabled', enable them with:"
Write-Host "docker compose -f pwd.yml exec backend bench --site frontend set-config server_script_enabled true"
Write-Host "docker compose -f pwd.yml exec backend bench set-config -g server_script_enabled 1"
