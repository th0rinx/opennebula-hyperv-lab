<#
.SYNOPSIS
  Paso 1 - Habilita el rol Hyper-V en Windows 10/11 Pro.
.DESCRIPTION
  Verifica el estado del feature Microsoft-Hyper-V-All y lo habilita si falta.
  Requiere REINICIO al finalizar. Ejecutar de nuevo con -Verify tras reiniciar.
  NO rompe Docker Desktop: WSL2 y Hyper-V comparten el mismo hipervisor.
.NOTES
  Ejecutar en PowerShell ELEVADA (Administrador).
  Si estas en cmd (Simbolo del sistema), el equivalente es:
    dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all
#>
#Requires -RunAsAdministrator
param(
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

if ($Verify) {
    $ok = $true
    if (Get-Command New-VM -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Cmdlets de Hyper-V disponibles (New-VM)" -ForegroundColor Green
    } else {
        Write-Host "[X] Cmdlets de Hyper-V NO disponibles - falta habilitar o reiniciar" -ForegroundColor Red
        $ok = $false
    }
    $sw = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object Name -eq 'Default Switch'
    if ($sw) {
        Write-Host "[OK] 'Default Switch' presente" -ForegroundColor Green
    } else {
        Write-Host "[X] 'Default Switch' no encontrado" -ForegroundColor Red
        $ok = $false
    }
    if ($ok) { Write-Host "`nListo. Segui con 02-Create-LabVM.ps1" -ForegroundColor Cyan }
    exit
}

$feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($feature.State -eq 'Enabled') {
    Write-Host "Hyper-V ya esta habilitado. Verificando cmdlets..." -ForegroundColor Green
    & $PSCommandPath -Verify
    exit
}

$cpu = Get-CimInstance Win32_Processor
Write-Host "CPU: $($cpu.Name)"
Write-Host "Virtualizacion en firmware: $($cpu.VirtualizationFirmwareEnabled)"
if (-not $cpu.VirtualizationFirmwareEnabled -and -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
    Write-Warning "La virtualizacion parece deshabilitada en BIOS/UEFI (Intel VT-x / AMD-V o SVM). Habilitala primero."
}

Write-Host "`nHabilitando Microsoft-Hyper-V-All ..." -ForegroundColor Cyan
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart

Write-Host "`nLISTO. Ahora REINICIA el equipo y ejecuta:" -ForegroundColor Yellow
Write-Host "  .\01-Enable-HyperV.ps1 -Verify" -ForegroundColor Yellow
