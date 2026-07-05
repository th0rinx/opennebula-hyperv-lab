<#
.SYNOPSIS
  Paso 2 - Descarga el ISO de Ubuntu Server (con verificacion SHA256) y crea la VM del lab.
.DESCRIPTION
  Crea una VM Hyper-V Gen2 con virtualizacion anidada (KVM real adentro):
  - Memoria FIJA (requisito de nested virt; Dynamic Memory no es compatible)
  - ExposeVirtualizationExtensions = true (la clave de todo el lab)
  - MAC spoofing ON (necesario para la red de las VMs anidadas)
  - Secure Boot con plantilla Microsoft UEFI CA (compatible con Ubuntu)
  Arranca conectada al 'Default Switch' (DHCP + internet sin configurar nada).
  La red definitiva con IP fija se configura despues (04-Setup-LabNetwork.ps1).
.EXAMPLE
  .\02-Create-LabVM.ps1
  .\02-Create-LabVM.ps1 -Ram 16GB -Cpu 8    # si vas a correr Kubernetes despues
.NOTES
  Ejecutar en PowerShell ELEVADA. Idempotente: aborta si la VM ya existe.
#>
#Requires -RunAsAdministrator
param(
    [string]$VMName  = 'opennebula-lab',
    [long]  $Ram     = 12GB,     # fija; para OneKE/Kubernetes usar 16GB
    [int]   $Cpu     = 4,        # para OneKE/Kubernetes usar 8
    [int]   $DiskGB  = 80,
    [string]$LabRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$IsoUrl  = 'https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso',
    [string]$Switch  = 'Default Switch'
)

$ErrorActionPreference = 'Stop'

if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    throw "La VM '$VMName' ya existe. Borrala antes (Remove-VM $VMName -Force) o usa otro -VMName."
}

# chequeo de RAM libre del host (leccion aprendida: memoria fija necesita el bloque completo)
$freeGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
$wantGB = [math]::Round($Ram / 1GB, 1)
if ($freeGB -lt ($wantGB + 2)) {
    throw "RAM insuficiente: pedis $wantGB GB fijos y el host tiene $freeGB GB libres. Cerra aplicaciones o baja -Ram."
}

$isoDir  = Join-Path $LabRoot 'iso'
$vmDir   = Join-Path $LabRoot 'vm'
foreach ($d in @($isoDir, $vmDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null } }

$isoName = Split-Path $IsoUrl -Leaf
$isoPath = Join-Path $isoDir $isoName
$vhdPath = Join-Path $vmDir "$VMName.vhdx"

# --- descarga del ISO (reanudable) + verificacion SHA256 contra el checksum oficial
if (-not (Test-Path $isoPath)) {
    Write-Host "==> Descargando $isoName (~3 GB) ..." -ForegroundColor Cyan
    curl.exe -L --retry 3 -C - -o $isoPath $IsoUrl
    if ($LASTEXITCODE -ne 0) { throw "Fallo la descarga del ISO. Verifica la URL en releases.ubuntu.com (los point releases viejos se retiran)." }
} else {
    Write-Host "==> ISO ya presente: $isoPath" -ForegroundColor Green
}

Write-Host "==> Verificando SHA256 contra el checksum oficial ..." -ForegroundColor Cyan
$sumsUrl = ($IsoUrl.Substring(0, $IsoUrl.LastIndexOf('/'))) + '/SHA256SUMS'
$sums    = (curl.exe -sL $sumsUrl) -join "`n"
$line    = $sums -split "`n" | Where-Object { $_ -match [regex]::Escape($isoName) } | Select-Object -First 1
if (-not $line) { throw "No encontre $isoName en $sumsUrl - no puedo verificar integridad." }
$expected = ($line -split '\s+')[0].Trim('\','*').ToLower()
$actual   = (Get-FileHash $isoPath -Algorithm SHA256).Hash.ToLower()
if ($expected -ne $actual) { throw "SHA256 NO coincide. Esperado: $expected / Obtenido: $actual. Borra el ISO y reintenta." }
Write-Host "    SHA256 OK: $actual" -ForegroundColor Green

# --- creacion de la VM
Write-Host "==> Creando VHDX dinamico de $DiskGB GB ..." -ForegroundColor Cyan
New-VHD -Path $vhdPath -SizeBytes ($DiskGB * 1GB) -Dynamic | Out-Null

Write-Host "==> Creando VM Gen2 '$VMName' ($wantGB GB fijos, $Cpu vCPU) ..." -ForegroundColor Cyan
New-VM -Name $VMName -MemoryStartupBytes $Ram -Generation 2 -VHDPath $vhdPath -SwitchName $Switch | Out-Null
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $Ram

Write-Host "==> Virtualizacion anidada + MAC spoofing ..." -ForegroundColor Cyan
Set-VMProcessor -VMName $VMName -Count $Cpu -ExposeVirtualizationExtensions $true
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing On

Write-Host "==> DVD con el ISO + Secure Boot compatible con Linux ..." -ForegroundColor Cyan
$dvd = Add-VMDvdDrive -VMName $VMName -Path $isoPath -Passthru
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftUEFICertificateAuthority
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd

Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false -CheckpointType Standard

# best-effort: el nombre del servicio de integracion esta LOCALIZADO segun el idioma de Windows
try {
    Get-VMIntegrationService -VMName $VMName |
        Where-Object { $_.Name -match 'Guest|invitado' } |
        Enable-VMIntegrationService -ErrorAction Stop
} catch {
    Write-Host "   (Guest Service Interface no disponible; se omite, no es necesario)" -ForegroundColor DarkYellow
}

Write-Host ""
Get-VM -Name $VMName | Format-List Name, State, ProcessorCount, MemoryStartup,
    @{N='NestedVirt';E={(Get-VMProcessor $_.Name).ExposeVirtualizationExtensions}}

Write-Host "Siguiente paso: instalar Ubuntu (ver docs/UBUNTU-INSTALL.md). Arranca con:" -ForegroundColor Yellow
Write-Host "  Start-VM -Name $VMName; vmconnect.exe localhost $VMName" -ForegroundColor Yellow
Write-Host "IMPORTANTE en el instalador: marcar 'Install OpenSSH server' y anotar usuario/password." -ForegroundColor Yellow
