<#
.SYNOPSIS
  Paso 3 - Deja la VM operable 100% remoto: clave SSH + sudo sin password + IP estatica latente.
.DESCRIPTION
  Con Ubuntu recien instalado (IP por DHCP del Default Switch), este script:
  1. Genera una clave SSH ed25519 en Windows si no existe (~/.ssh/id_ed25519)
  2. Instala la clave publica en la VM        (te pide la password 1 vez)
  3. Configura sudo sin password para el usuario (te pide la password 1 vez mas)
  4. Escribe la IP ESTATICA en netplan SIN aplicarla (queda latente; se activa
     con el reinicio que hace 04-Setup-LabNetwork.ps1)
  Desde aca en adelante, todo el lab se opera por SSH sin tocar la consola.
.EXAMPLE
  .\03-Bootstrap-Ssh.ps1 -VmIp 172.28.5.113 -VmUser labadmin
.NOTES
  NO requiere admin. La IP actual de la VM se ve en su consola: ip -4 addr show eth0
#>
param(
    [Parameter(Mandatory)][string]$VmIp,
    [Parameter(Mandatory)][string]$VmUser,
    [string]$StaticIp   = '192.168.222.10',
    [int]   $PrefixLen  = 24,
    [string]$Gateway    = '192.168.222.1',
    [string]$DnsServers = '1.1.1.1, 8.8.8.8'
)

$ErrorActionPreference = 'Stop'

# --- 1) clave SSH local
$keyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
if (-not (Test-Path "$keyPath.pub")) {
    Write-Host "==> Generando clave SSH ed25519 ..." -ForegroundColor Cyan
    if (-not (Test-Path (Split-Path $keyPath))) { New-Item -ItemType Directory (Split-Path $keyPath) | Out-Null }
    ssh-keygen -q -t ed25519 -N '""' -C 'opennebula-lab' -f $keyPath
}
$pub = (Get-Content "$keyPath.pub" -Raw).Trim()

# --- 2) instalar clave publica (password 1/2)
Write-Host "==> Instalando clave publica en $VmUser@$VmIp (password 1 de 2) ..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=accept-new "$VmUser@$VmIp" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo CLAVE_INSTALADA"
if ($LASTEXITCODE -ne 0) { throw "No pude instalar la clave. Verifica IP, usuario y que OpenSSH este instalado en la VM." }

# --- 3) sudo sin password (password 2/2, la pide sudo dentro de la sesion)
Write-Host "==> Configurando sudo sin password (password 2 de 2) ..." -ForegroundColor Cyan
ssh -t "$VmUser@$VmIp" "sudo bash -c `"echo '$VmUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-lab && chmod 440 /etc/sudoers.d/90-lab && echo SUDO_OK`""
if ($LASTEXITCODE -ne 0) { throw "No pude configurar sudoers." }

# --- 4) netplan estatico LATENTE (no se aplica ahora; aplica en el proximo boot real)
Write-Host "==> Escribiendo IP estatica $StaticIp/$PrefixLen (latente hasta el reinicio) ..." -ForegroundColor Cyan
$netplan = @"
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [$StaticIp/$PrefixLen]
      routes:
        - to: default
          via: $Gateway
      nameservers:
        addresses: [$DnsServers]
"@ -replace "`r`n", "`n"

$out = $netplan | ssh "$VmUser@$VmIp" "sudo -n bash -c 'cat > /etc/netplan/60-static-eth0.yaml; chmod 600 /etc/netplan/60-static-eth0.yaml; echo \"network: {config: disabled}\" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg; netplan generate && echo NETPLAN_OK'"
if ($out -notmatch 'NETPLAN_OK') { throw "No pude escribir el netplan estatico (salida: $out)" }

# --- verificacion final: acceso sin password
$test = ssh -o BatchMode=yes "$VmUser@$VmIp" "sudo -n true && echo ACCESO_TOTAL_OK"
Write-Host ""
if ($test -match 'ACCESO_TOTAL_OK') {
    Write-Host "Listo: SSH con clave + sudo sin password funcionando." -ForegroundColor Green
    Write-Host "Siguiente: .\04-Setup-LabNetwork.ps1  (en PowerShell ELEVADA)" -ForegroundColor Yellow
} else {
    Write-Warning "Algo quedo a medias - proba: ssh -o BatchMode=yes $VmUser@$VmIp 'sudo -n true'"
}
