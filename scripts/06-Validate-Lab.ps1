<#
.SYNOPSIS
  Paso 6 - Validacion end-to-end del lab (la prueba de fuego).
.DESCRIPTION
  Verifica todo el stack, de afuera hacia adentro:
  1. Servicios systemd de OpenNebula activos
  2. Host KVM 'on' + datastores 'on'
  3. Sunstone respondiendo HTTP desde Windows
  4. Instancia la VM Alpine de prueba, espera RUNNING, verifica que corre con
     KVM real (domain type=kvm, no emulacion QEMU) y que responde ping.
  Si todo da OK: tenes un cloud privado con 3 niveles de virtualizacion andando.
.EXAMPLE
  .\06-Validate-Lab.ps1 -VmUser labadmin
#>
param(
    [Parameter(Mandatory)][string]$VmUser,
    [string]$VmIp = '192.168.222.10',
    [switch]$KeepVm    # no terminar la VM alpine de prueba al final
)

$ErrorActionPreference = 'Stop'
$results = @()

function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:results += [pscustomobject]@{ Check = $name; OK = if ($ok) {'[OK]'} else {'[X]'}; Detalle = $detail }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1}  {2}" -f ($(if ($ok) {'[OK]'} else {'[X] '}), $name, $detail)) -ForegroundColor $color
}

Write-Host "==> Validando lab en $VmIp ..." -ForegroundColor Cyan

# 1. servicios
$svc = ssh -o BatchMode=yes "$VmUser@$VmIp" "systemctl is-active opennebula opennebula-fireedge opennebula-gate opennebula-flow 2>/dev/null"
Check "Servicios OpenNebula (oned/fireedge/gate/flow)" (($svc -match 'active').Count -eq 4) ($svc -join ',')

# 2. host y datastores
$hostLine = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onehost list --csv 2>/dev/null | tail -1"
Check "Host KVM en estado 'on'" ($hostLine -match ',on') $hostLine
$dsCount = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onedatastore list | grep -c ' on$'"
Check "Datastores 'on'" ([int]$dsCount -ge 3) "$dsCount de 3"

# 3. Sunstone desde Windows
try {
    $r = Invoke-WebRequest -Uri "http://$VmIp/" -UseBasicParsing -TimeoutSec 15
    Check "Sunstone HTTP desde Windows" ($r.StatusCode -eq 200) "HTTP $($r.StatusCode)"
} catch { Check "Sunstone HTTP desde Windows" $false $_.Exception.Message }

# 4. VM de prueba con KVM real
Write-Host "==> Instanciando VM Alpine de prueba ..." -ForegroundColor Cyan
ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onetemplate instantiate 0 --name validate-test >/dev/null 2>&1"
$vmid = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onevm list --csv | grep validate-test | cut -d, -f1"

$state = ''
foreach ($i in 1..24) {
    Start-Sleep -Seconds 5
    $state = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onevm show $vmid | sed -n 's/^LCM_STATE *: *//p'"
    if ($state -match 'RUNNING') { break }
}
Check "VM anidada RUNNING" ($state -match 'RUNNING') "estado: $state"

$dom = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n virsh --connect qemu:///system dumpxml one-$vmid 2>/dev/null | grep -oP 'domain type=.\K[a-z]+' | head -1"
Check "Aceleracion por hardware (domain type=kvm)" ($dom -eq 'kvm') "domain type=$dom"

$ping = ssh -o BatchMode=yes "$VmUser@$VmIp" "IP=`$(sudo -n -u oneadmin onevm show $vmid | grep -oP 'ETH0_IP=\`"\K[0-9.]+' | head -1); ping -c 2 -W 2 `$IP >/dev/null 2>&1 && echo PING_OK"
Check "Red de la VM anidada (ping)" ($ping -match 'PING_OK')

if (-not $KeepVm) {
    ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n -u oneadmin onevm terminate --hard $vmid >/dev/null 2>&1"
}

Write-Host ""
$fails = @($results | Where-Object OK -eq '[X]').Count
if ($fails -eq 0) {
    Write-Host "TODO OK - Cloud privado operativo: Hyper-V -> Ubuntu/KVM -> VMs anidadas con aceleracion real." -ForegroundColor Green
    Write-Host "Sunstone: http://$VmIp/  (oneadmin)" -ForegroundColor Green
} else {
    Write-Warning "$fails chequeos fallaron - ver docs/TROUBLESHOOTING.md"
}
