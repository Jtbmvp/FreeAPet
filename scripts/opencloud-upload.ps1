<#
.SYNOPSIS
  Envia imagens, modelos e áudio para o Roblox pela Open Cloud Assets API e devolve os asset IDs.

.DESCRIPTION
  Complementa a MCP do Studio: este script faz o upload (a MCP não tem chave Open Cloud) e
  depois o agente usa os IDs no Studio:
    - modelos (fbx, glb, gltf, rbxm, rbxmx) -> insert_asset(assetId)
    - imagens (png, jpg, bmp, tga)          -> TextureID / Image = "rbxassetid://<id>"
    - áudio (mp3, ogg, wav, flac)           -> SoundId = "rbxassetid://<id>"

  A chave nunca vai para o Git: lê-se de $env:ROBLOX_OPEN_CLOUD_KEY ou de um ficheiro local
  ignorado (por omissão "API Key OpenCloudRoblox.txt" na raiz do repositório).
  Os uploads ficam registados em build/opencloud-uploads.json (ignorado); um ficheiro com o
  mesmo SHA-256 não volta a ser enviado, a menos que se use -Force.

.EXAMPLE
  pwsh scripts/opencloud-upload.ps1 assets/map-textures/grass.png
  pwsh scripts/opencloud-upload.ps1 assets/map-textures -Recurse -DescriptionText "Texturas do chão"
  pwsh scripts/opencloud-upload.ps1 tree.fbx -DisplayName "Tree_Oak_A" -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
    [string[]] $Path,
    [string] $DisplayName,
    [string] $DescriptionText = 'FreeAPet asset',
    # Dono dos assets: por omissão o grupo dono do jogo (jot4b Productions).
    [long] $GroupId = 11782476,
    [long] $UserId = 0,
    [string] $KeyFile,
    [string] $Manifest,
    [switch] $Recurse,
    [switch] $Force,
    # Imagens vão como "Image" (ID usável já em TextureID/Image); com -AsDecal vão como Decal.
    [switch] $AsDecal,
    [switch] $Json,
    [int] $TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $KeyFile) { $KeyFile = Join-Path $repoRoot 'API Key OpenCloudRoblox.txt' }
if (-not $Manifest) { $Manifest = Join-Path $repoRoot 'build/opencloud-uploads.json' }

$apiKey = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $apiKey) {
    if (-not (Test-Path -LiteralPath $KeyFile)) { throw "Sem chave: define ROBLOX_OPEN_CLOUD_KEY ou cria '$KeyFile'." }
    $apiKey = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
}

$types = @{
    '.png' = @('Image', 'image/png');  '.jpg' = @('Image', 'image/jpeg'); '.jpeg' = @('Image', 'image/jpeg')
    '.bmp' = @('Image', 'image/bmp');  '.tga' = @('Image', 'image/tga')
    '.fbx' = @('Model', 'model/fbx');  '.glb' = @('Model', 'model/gltf-binary'); '.gltf' = @('Model', 'model/gltf+json')
    '.rbxm' = @('Model', 'model/x-rbxm'); '.rbxmx' = @('Model', 'model/x-rbxm')
    '.mp3' = @('Audio', 'audio/mpeg'); '.ogg' = @('Audio', 'audio/ogg'); '.wav' = @('Audio', 'audio/wav'); '.flac' = @('Audio', 'audio/flac')
}

$files = foreach ($p in $Path) {
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse | Where-Object { $types.ContainsKey($_.Extension.ToLower()) }
    } else { $item }
}
if (-not $files) { throw 'Nenhum ficheiro suportado encontrado.' }

$db = @{}
if (Test-Path -LiteralPath $Manifest) {
    (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $db[$_.Name] = $_.Value }
}

$http = [System.Net.Http.HttpClient]::new()
$http.DefaultRequestHeaders.Add('x-api-key', $apiKey)
$creator = if ($UserId -gt 0) { @{ userId = "$UserId" } } else { @{ groupId = "$GroupId" } }

function Get-Kind($file) {
    $kind = $types[$file.Extension.ToLower()]
    if ($kind -and $AsDecal -and $kind[0] -eq 'Image') { $kind = @('Decal', $kind[1]) }
    $kind
}

function Invoke-Upload($file) {
    $kind = Get-Kind $file
    if (-not $kind) { throw "Tipo não suportado: $($file.Name)" }
    if ($file.Length -gt 20MB) { throw "Maior que 20 MB: $($file.Name)" }
    $name = if ($DisplayName -and $files.Count -eq 1) { $DisplayName } else { $file.BaseName }
    if ($name.Length -gt 50) { $name = $name.Substring(0, 50) }
    $request = @{
        assetType       = $kind[0]
        displayName     = $name
        description     = $DescriptionText
        creationContext = @{ creator = $creator }
    } | ConvertTo-Json -Depth 5 -Compress

    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add([System.Net.Http.StringContent]::new($request, [Text.Encoding]::UTF8, 'application/json'), 'request')
    $bytes = [System.Net.Http.ByteArrayContent]::new([IO.File]::ReadAllBytes($file.FullName))
    $bytes.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new($kind[1])
    $form.Add($bytes, 'fileContent', $file.Name)

    $res = $http.PostAsync('https://apis.roblox.com/assets/v1/assets', $form).GetAwaiter().GetResult()
    $body = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $res.IsSuccessStatusCode) { throw "Upload falhou ($([int]$res.StatusCode)) $($file.Name): $body" }
    $op = $body | ConvertFrom-Json
    $opId = if ($op.operationId) { $op.operationId } else { ($op.path -split '/')[-1] }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $op.done) {
        if ((Get-Date) -gt $deadline) { throw "Timeout à espera da operação $opId ($($file.Name))" }
        Start-Sleep -Seconds 2
        $poll = $http.GetAsync("https://apis.roblox.com/assets/v1/operations/$opId").GetAwaiter().GetResult()
        $op = $poll.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    }
    if ($op.error) { throw "Operação falhou ($($file.Name)): $($op.error | ConvertTo-Json -Compress)" }
    [pscustomobject]@{
        file       = $file.Name
        assetType  = $kind[0]
        assetId    = $op.response.assetId
        moderation = $op.response.moderationResult.moderationState
    }
}

$results = foreach ($f in $files) {
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash + ':' + (Get-Kind $f)[0]
    if (-not $Force -and $db.ContainsKey($hash)) {
        $prev = $db[$hash]
        [pscustomobject]@{ file = $f.Name; assetType = $prev.assetType; assetId = $prev.assetId; moderation = 'cached' }
        continue
    }
    try {
        $r = Invoke-Upload $f
        $db[$hash] = [pscustomobject]@{ file = $f.Name; path = $f.FullName; assetType = $r.assetType; assetId = $r.assetId; uploadedAt = (Get-Date).ToString('s') }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Manifest) | Out-Null
        $db | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Manifest -Encoding utf8
        $r
    } catch {
        [pscustomobject]@{ file = $f.Name; assetType = ''; assetId = ''; moderation = "ERRO: $($_.Exception.Message)" }
    }
}
$http.Dispose()

if ($Json) { $results | ConvertTo-Json -Depth 4 } else { $results | Format-Table -AutoSize }
if ($results | Where-Object { -not $_.assetId }) { exit 1 }
