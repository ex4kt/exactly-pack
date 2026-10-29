# Exactly: Start-Fenster vor dem Spielstart (wird von Prism als "Vor dem Start"-Befehl aufgerufen).
# Prueft die Pack-Version, laesst den packwiz-Installer mit seinem Fortschrittsbalken laufen und
# erlaubt "Starten" nur, wenn alles auf dem neuesten Stand ist. "Beenden" bricht den Start ab (Exit-Code 1).
param([switch]$Test)
$ErrorActionPreference = 'Stop'
$PackUrl = 'https://raw.githubusercontent.com/ex4kt/exactly-pack/main/pack.toml'

# Auf eine Kopie im Temp-Ordner umsteigen, damit der Installer diese Datei bei einem Update ersetzen darf.
if (-not $Test -and $PSCommandPath -and ((Split-Path $PSCommandPath -Leaf) -ne 'exactly-start-run.ps1')) {
    $kopie = Join-Path $env:TEMP 'exactly-start-run.ps1'
    Copy-Item $PSCommandPath $kopie -Force
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $kopie
    exit $LASTEXITCODE
}

function Hole-Remote {
    try {
        $h = @{ 'Cache-Control' = 'no-cache'; 'User-Agent' = 'exactly-start' }
        $r = Invoke-WebRequest -Uri ($PackUrl + '?t=' + [DateTime]::UtcNow.Ticks) -Headers $h -UseBasicParsing -TimeoutSec 20
        $bytes = [Text.Encoding]::UTF8.GetBytes($r.Content)
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLower()
        $v = ([regex]::Match($r.Content, '(?m)^version\s*=\s*"([^"]+)"')).Groups[1].Value
        return @{ Version = $v; Hash = $sha }
    } catch { return $null }
}
function Lokale-Version {
    try { return (Get-Content (Join-Path (Get-Location) 'config\exactly_neuigkeiten.txt') -TotalCount 1 -Encoding UTF8).Trim() } catch { return '' }
}
function Lokaler-Hash {
    try { return ((Get-Content (Join-Path (Get-Location) 'packwiz.json') -Raw | ConvertFrom-Json).packFileHash.value).ToLower() } catch { return '' }
}
function Pruefen {
    $remote = Hole-Remote
    $lokal = Lokale-Version
    if (-not $remote) { return @{ Status = 'offline'; Lokal = $lokal; Neu = '' } }
    if ($remote.Hash -eq (Lokaler-Hash)) { return @{ Status = 'aktuell'; Lokal = $remote.Version; Neu = $remote.Version } }
    return @{ Status = 'alt'; Lokal = $lokal; Neu = $remote.Version }
}

# Tastenbelegung des Packs (config\exactly_tasten.txt) einmal je "# stand N" in die gemeinsame options.txt eintragen.
# Static Options legt die options.txt in %APPDATA%\.minecraft ab, deshalb kommen neue Standardwerte sonst nur bei Neuinstallationen an.
# Schlaegt etwas fehl, passiert nichts (der Start wird nie blockiert); laeuft schon ein Minecraft, wird auf den naechsten Start gewartet.
function Wende-Tasten($liste = (Join-Path (Get-Location) 'config\exactly_tasten.txt'), $opt = (Join-Path $env:APPDATA '.minecraft\options.txt'), $marke = (Join-Path $env:APPDATA '.minecraft\exactly_tasten_stand.txt')) {
    try {
        if (-not (Test-Path $liste) -or -not (Test-Path $opt)) { return 'keine Datei' }
        if (Get-Process javaw -ErrorAction SilentlyContinue) { return 'Minecraft laeuft' }
        $utf8 = New-Object Text.UTF8Encoding $false
        $zeilen = [IO.File]::ReadAllLines($liste, $utf8)
        $stand = ([regex]::Match(($zeilen -join "`n"), '(?m)^# stand (\d+)')).Groups[1].Value
        if (-not $stand) { return 'kein Stand' }
        if ((Test-Path $marke) -and ([IO.File]::ReadAllText($marke).Trim() -eq $stand)) { return 'schon angewendet' }
        $neu = [ordered]@{}
        foreach ($z in $zeilen) { if ($z -match '^(key_[^:\s]+):') { $neu[$Matches[1]] = $z.Trim() } }
        $alt = [IO.File]::ReadAllLines($opt, $utf8)
        $aus = New-Object System.Collections.Generic.List[string]
        $benutzt = @{}
        foreach ($z in $alt) {
            if ($z -match '^(key_[^:\s]+):' -and $neu.Contains($Matches[1])) { $aus.Add($neu[$Matches[1]]); $benutzt[$Matches[1]] = $true } else { $aus.Add($z) }
        }
        foreach ($n in $neu.Keys) { if (-not $benutzt.ContainsKey($n)) { $aus.Add($neu[$n]) } }
        $sicherung = $opt + '.vor_tasten'
        if (-not (Test-Path $sicherung)) { Copy-Item $opt $sicherung -Force }
        [IO.File]::WriteAllText($opt, (($aus -join "`n") + "`n"), $utf8)
        [IO.File]::WriteAllText($marke, $stand, $utf8)
        return ('angewendet: ' + $neu.Count)
    } catch { return ('Fehler: ' + $_.Exception.Message) }
}

if ($Test) { Pruefen | ConvertTo-Json; exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'Exactly'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(500, 210)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false; $form.MinimizeBox = $false
$form.TopMost = $true

$titel = New-Object Windows.Forms.Label
$titel.Text = 'EXACTLY'
$titel.Font = New-Object Drawing.Font('Segoe UI', 20, [Drawing.FontStyle]::Bold)
$titel.ForeColor = [Drawing.Color]::FromArgb(200, 140, 0)
$titel.Location = New-Object Drawing.Point(20, 12); $titel.AutoSize = $true
$form.Controls.Add($titel)

$info = New-Object Windows.Forms.Label
$info.Font = New-Object Drawing.Font('Segoe UI', 10)
$info.Location = New-Object Drawing.Point(22, 60); $info.Size = New-Object Drawing.Size(456, 60)
$form.Controls.Add($info)

$balken = New-Object Windows.Forms.ProgressBar
$balken.Location = New-Object Drawing.Point(22, 124); $balken.Size = New-Object Drawing.Size(456, 18)
$balken.Style = 'Marquee'
$form.Controls.Add($balken)

function Knopf($text, $x) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Size = New-Object Drawing.Size(112, 34); $b.Location = New-Object Drawing.Point($x, 160)
    $b.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.Controls.Add($b); return $b
}
$bStart = Knopf 'Starten' 22
$bPruef = Knopf 'Erneut prüfen' 142
$bUpd = Knopf 'Aktualisieren' 262
$bEnde = Knopf 'Beenden' 382
$script:ok = $false

function Zeige($status, $text, $laeuft) {
    $info.Text = $text
    $balken.Style = if ($laeuft) { 'Marquee' } else { 'Continuous' }
    $balken.Value = if ($status -eq 'aktuell') { 100 } else { 0 }
    $bStart.Enabled = ($status -eq 'aktuell') -and -not $laeuft
    $bPruef.Enabled = -not $laeuft
    $bUpd.Enabled = -not $laeuft
    $bEnde.Enabled = -not $laeuft
}
function Neu-Pruefen {
    Zeige 'pruefe' 'Suche nach Updates ...' $true
    [Windows.Forms.Application]::DoEvents()
    $e = Pruefen
    switch ($e.Status) {
        'aktuell' { Zeige 'aktuell' ("Alles aktuell.`nVersion " + $e.Neu + ' - du kannst starten.') $false }
        'alt'     { Zeige 'alt' ("Neue Version " + $e.Neu + " verfuegbar (du hast " + $(if ($e.Lokal) { $e.Lokal } else { 'eine aeltere' }) + ").`nBitte aktualisieren, mit alter Version geht der Start nicht.") $false }
        default   { Zeige 'offline' "Keine Verbindung zu GitHub.`nOhne Internet kann ich die Version nicht pruefen. Verbinde dich und druecke Aktualisieren." $false }
    }
}

$bUpd.Add_Click({
    $java = $env:INST_JAVA; if (-not $java) { $java = 'java' }
    Zeige 'alt' 'Aktualisiere ... (das Fenster des Installers zeigt den Fortschritt)' $true
    try {
        $p = Start-Process -FilePath $java -ArgumentList @('-jar', 'packwiz-installer-bootstrap.jar', $PackUrl) -PassThru
        while (-not $p.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        if ($p.ExitCode -ne 0) { Zeige 'alt' ("Die Aktualisierung wurde nicht abgeschlossen (Code " + $p.ExitCode + ").`nDruecke Aktualisieren, um es nochmal zu versuchen.") $false; return }
    } catch {
        Zeige 'alt' ("Der Installer konnte nicht gestartet werden:`n" + $_.Exception.Message) $false; return
    }
    Neu-Pruefen
})
$bPruef.Add_Click({ Neu-Pruefen })
$bStart.Add_Click({ $script:ok = $true; $form.Close() })
$bEnde.Add_Click({ $form.Close() })
$form.Add_Shown({ $form.Activate(); Neu-Pruefen })
[void]$form.ShowDialog()
if ($script:ok) { [void](Wende-Tasten); exit 0 } else { exit 1 }
