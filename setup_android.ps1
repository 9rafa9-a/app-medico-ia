# Android Dev Kit Installer (Fixed Encoding)
$ErrorActionPreference = "Stop"

$INSTALL_DIR = "C:\AndroidDev"
$JDK_URL = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"
$FLUTTER_URL = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.19.6-stable.zip" 

Write-Host ">>> Iniciando Instalacao do Kit Android Dev..." -ForegroundColor Cyan

# 1. Start
if (!(Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
    Write-Host "Pasta criada: $INSTALL_DIR"
}

# 2. Java JDK 17
$jdkZip = "$INSTALL_DIR\jdk.zip"
if (!(Test-Path "$INSTALL_DIR\jdk-17")) {
    Write-Host "Baixando Java JDK 17..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $JDK_URL -OutFile $jdkZip
    
    Write-Host "Extraindo Java..." -ForegroundColor Yellow
    Expand-Archive -Path $jdkZip -DestinationPath $INSTALL_DIR -Force
    
    $extracted = Get-ChildItem "$INSTALL_DIR\jdk-17*" | Select-Object -First 1
    Rename-Item $extracted.FullName "jdk-17"
    Remove-Item $jdkZip
    Write-Host "Java Instalado." -ForegroundColor Green
} else {
    Write-Host "Java ja existe."
}

# 3. Flutter
$flutterZip = "$INSTALL_DIR\flutter.zip"
if (!(Test-Path "$INSTALL_DIR\flutter")) {
    Write-Host "Baixando Flutter SDK 3.19.6..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $FLUTTER_URL -OutFile $flutterZip
    
    Write-Host "Extraindo Flutter..." -ForegroundColor Yellow
    Expand-Archive -Path $flutterZip -DestinationPath $INSTALL_DIR -Force
    Remove-Item $flutterZip
    Write-Host "Flutter Instalado." -ForegroundColor Green
} else {
    Write-Host "Flutter ja existe."
}

# 4. PATH
Write-Host "Configurando PATH..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$newPaths = @("$INSTALL_DIR\jdk-17\bin", "$INSTALL_DIR\flutter\bin")
$updatedPath = $userPath

foreach ($p in $newPaths) {
    if ($userPath -notlike "*$p*") {
        $updatedPath += ";$p"
        Write-Host "Adicionando ao PATH: $p" -ForegroundColor Green
    }
}

if ($updatedPath -ne $userPath) {
    [Environment]::SetEnvironmentVariable("Path", $updatedPath, "User")
    [Environment]::SetEnvironmentVariable("JAVA_HOME", "$INSTALL_DIR\jdk-17", "User")
    Write-Host "PATH atualizado. Reinicie o terminal." -ForegroundColor Cyan
} else {
    Write-Host "PATH ja estava configurado."
}

Write-Host "Instalacao Concluida. Feche e abra o terminal." -ForegroundColor Cyan
