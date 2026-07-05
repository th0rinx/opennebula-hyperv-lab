<#
.SYNOPSIS
  Paso 4 - Red estable: switch NAT propio + reinicio de la VM a su IP estatica.
.DESCRIPTION
  El 'Default Switch' de Hyper-V ROTA de subred en cada reinicio del host (la IP
  de la VM cambia todo el tiempo). Este script lo soluciona de forma definitiva:
  1. Crea un switch interno 'onelab' + NetNat de Windows (subred propia con internet)
  2. Apaga la VM (shutdown limpio)
  3. (Opcional) redimensiona RAM/CPU con chequeo de RAM libre del host
  4. Conecta la VM al switch nuevo y la arranca -> el netplan estatico del paso 3
     aplica en este boot y el lab queda FIJO en la IP elegida.
  Idempotente: se puede re-ejecutar.
.EXAMPLE
  .\04-Setup-LabNetwork.ps1
  .\04-Setup-LabNetwork.ps1 -Ram 16GB -Cpu 8   # ampliar de paso (Kubernetes)
.NOTES
  Ejecutar en PowerShell ELEVADA.
#>
#Requires -RunAsAdministrator
param(
    [string]$VMName     = 'opennebula-lab',
    [string]$SwitchName = 'onelab',
    [string]$NatName    = 'onelab-nat',
    [string]$HostIp     = '192.168.222.1',
    [int]   $PrefixLen  = 24,
    [string]$Subnet     = '192.168.222.0/24',
    [string]$StaticIp   = '192.168.222.10',
    [long]  $Ram        = 0,    # 0 = no cambiar
    [int]   $Cpu        = 0     # 0 = no cambiar
)

$ErrorActionPreference = 'Stop'

Write-Host "==> [1/4] Switch interno '$SwitchName' + NAT $Subnet ..." -ForegroundColor Cyan
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Start-Sleep -Seconds 3
}
$nic = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
if (-not (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $HostIp -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -IPAddress $HostIp -PrefixLength $PrefixLen -InterfaceIndex $nic.ifIndex | Out-Null
}
if (-not (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue)) {
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $Subnet | Out-Null
}

Write-Host "==> [2/4] Apagando la VM (shutdown limpio, ~1 min) ..." -ForegroundColor Cyan
if ((Get-VM $VMName).State -ne 'Off') { Stop-VM -Name $VMName -Force }

if ($Ram -gt 0 -or $Cpu -gt 0) {
    Write-Host "==> [3/4] Redimensionando ..." -ForegroundColor Cyan
    if ($Ram -gt 0) {
        $freeGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
        $wantGB = [math]::Round($Ram / 1GB, 1)
        if ($freeGB -lt ($wantGB + 2)) {
            throw "RAM insuficiente: pedis $wantGB GB fijos y hay $freeGB GB libres (la memoria fija necesita el bloque completo). Cerra apps o baja -Ram."
        }
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $Ram
    }
    if ($Cpu -gt 0) { Set-VMProcessor -VMName $VMName -Count $Cpu }
} else {
    Write-Host "==> [3/4] Sin cambios de RAM/CPU" -ForegroundColor DarkGray
}

Write-Host "==> [4/4] Conectando a '$SwitchName' y arrancando ..." -ForegroundColor Cyan
Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
Start-VM -Name $VMName

Write-Host "    Esperando SSH en $StaticIp ..." -ForegroundColor Cyan
$ok = $false
foreach ($i in 1..30) {
    Start-Sleep -Seconds 5
    if ((Test-NetConnection -ComputerName $StaticIp -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded) { $ok = $true; break }
}

Write-Host ""
if ($ok) {
    Write-Host "Listo. El lab quedo FIJO en $StaticIp (ya no depende del Default Switch)." -ForegroundColor Green
    Write-Host "Siguiente: .\05-Install-MiniONE.ps1 -VmUser <tu-usuario> -SunstonePassword <password-a-eleccion>" -ForegroundColor Yellow
} else {
    Write-Warning "SSH no respondio en $StaticIp tras 150s. Revisa la consola de la VM (vmconnect) e 'ip -4 addr show eth0'."
}
