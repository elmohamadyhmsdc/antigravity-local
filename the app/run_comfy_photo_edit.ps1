param(
    [string]$ComfyRoot = 'D:\Comfy-Desktop\ComfyUI-Installs\laptop\ComfyUI',
    [string]$Models = 'D:\Comfy-Desktop\ComfyUI-Shared\models'
)

$ErrorActionPreference = 'Stop'
$runtime = Join-Path $ComfyRoot '.venv\Scripts\python.exe'
$main = Join-Path $ComfyRoot 'main.py'
foreach ($target in @($runtime, $main, $Models)) {
    if (-not (Test-Path -LiteralPath $target)) { throw "ComfyUI path is missing: $target" }
}

$workspace = Join-Path $PSScriptRoot 'build\comfy-photo-edit'
$inputDir = Join-Path $workspace 'input'
$outputDir = Join-Path $workspace 'output'
$userDir = Join-Path $workspace 'user'
New-Item -ItemType Directory -Force -Path $inputDir, $outputDir, $userDir | Out-Null
$encoders = Join-Path $PSScriptRoot 'models\undress\diffusers--stable-diffusion-xl-1.0-inpainting-0.1'
foreach ($file in @('text_encoder\model.fp16.safetensors', 'text_encoder_2\model.fp16.safetensors')) {
    if (-not (Test-Path -LiteralPath (Join-Path $encoders $file))) { throw "SDXL encoder is missing: $file" }
}
$config = Join-Path $workspace 'model-paths.yaml'
$encoderPath = ConvertTo-Json (Join-Path $encoders '.') -Compress
[IO.File]::WriteAllText($config, "gallary_sdxl:`n  text_encoders: $encoderPath`n")

$env:PYTHONDONTWRITEBYTECODE = '1'
& $runtime -u $main --listen 127.0.0.1 --port 8188 --models-directory $Models `
    --extra-model-paths-config $config `
    --input-directory $inputDir --output-directory $outputDir --user-directory $userDir `
    --temp-directory $workspace --disable-auto-launch --disable-all-custom-nodes `
    --whitelist-custom-nodes ComfyUI-GGUF --disable-metadata `
    --disable-dynamic-vram --lowvram --disable-pinned-memory --reserve-vram 1.2
exit $LASTEXITCODE
