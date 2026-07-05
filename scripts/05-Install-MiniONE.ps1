<#
.SYNOPSIS
  Paso 5 - Instala OpenNebula 7.2 con miniONE dentro de la VM, 100% desatendido.
.DESCRIPTION
  Via SSH (clave del paso 3): actualiza Ubuntu, descarga miniONE del release
  oficial y lo ejecuta con --yes. Instala: front-end + Sunstone + nodo KVM local
  + red virtual NAT (172.16.100.0/24) + datastores + template Alpine de prueba.
  El log completo queda ADENTRO de la VM (/root/minione-install.log) - leccion
  aprendida: si la sesion SSH se corta, el log sobrevive.
  Duracion tipica: 8-12 min.
.EXAMPLE
  .\05-Install-MiniONE.ps1 -VmUser labadmin -SunstonePassword 'MiPasswordFuerte'
.NOTES
  NO requiere admin en Windows. La password es la del usuario oneadmin (Sunstone).
#>
param(
    [Parameter(Mandatory)][string]$VmUser,
    [Parameter(Mandatory)][string]$SunstonePassword,
    [string]$VmIp    = '192.168.222.10',
    [string]$Version = 'v7.2.0'
)

$ErrorActionPreference = 'Stop'

# sanity: acceso sin password funcionando
$test = ssh -o BatchMode=yes -o ConnectTimeout=10 "$VmUser@$VmIp" "sudo -n true && echo OK"
if ($test -notmatch 'OK') { throw "No hay acceso SSH+sudo sin password a $VmUser@$VmIp. Ejecuta antes 03-Bootstrap-Ssh.ps1." }

$url = "https://github.com/OpenNebula/minione/releases/download/$Version/minione"
Write-Host "==> Instalando miniONE $Version en $VmIp (8-12 min, salida en vivo) ..." -ForegroundColor Cyan

$remote = "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; " +
          "{ echo '=== [1/3] apt update/upgrade ==='; apt-get update -q && apt-get -yq upgrade; " +
          "echo '=== [2/3] descarga minione ==='; wget -q '$url' -O /root/minione && chmod +x /root/minione; " +
          "echo '=== [3/3] minione install ==='; /root/minione --yes --password '$SunstonePassword'; " +
          "echo === EXIT_CODE=`$? ===; } 2>&1 | tee /root/minione-install.log"

ssh "$VmUser@$VmIp" "sudo -n bash -c `"$remote`""

Write-Host ""
Write-Host "Si arriba dice 'EXIT_CODE=0' y el Report muestra la URL de Sunstone:" -ForegroundColor Green
Write-Host "  Sunstone:  http://$VmIp/   (usuario: oneadmin / la password que pasaste)" -ForegroundColor Green
Write-Host "Siguiente: .\06-Validate-Lab.ps1 -VmUser $VmUser" -ForegroundColor Yellow
