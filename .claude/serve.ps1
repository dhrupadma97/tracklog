$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:5000/')
$listener.Start()
Write-Host "Serving build/web at http://localhost:5000"

$root = "C:\Users\AE12230\Desktop\AntiGravity\TrackLog - Copy\build\web"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response

    $path = $request.Url.LocalPath
    if ($path -eq '/') { $path = '/index.html' }

    $filePath = Join-Path $root ($path.TrimStart('/') -replace '/', '\')

    if (Test-Path $filePath -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $ext   = [System.IO.Path]::GetExtension($filePath).ToLower()
        $response.ContentType = switch ($ext) {
            '.html' { 'text/html; charset=utf-8' }
            '.js'   { 'application/javascript' }
            '.css'  { 'text/css' }
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.svg'  { 'image/svg+xml' }
            '.json' { 'application/json' }
            '.wasm' { 'application/wasm' }
            '.ico'  { 'image/x-icon' }
            '.ttf'  { 'font/ttf' }
            '.woff2'{ 'font/woff2' }
            default { 'application/octet-stream' }
        }
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        # SPA fallback — serve index.html for all unknown paths
        $indexPath = Join-Path $root 'index.html'
        $bytes = [System.IO.File]::ReadAllBytes($indexPath)
        $response.ContentType    = 'text/html; charset=utf-8'
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    }

    $response.OutputStream.Close()
}
