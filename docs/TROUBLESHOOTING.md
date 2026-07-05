# Troubleshooting — los problemas reales (nos pasaron todos)

## "Enable-WindowsOptionalFeature no se reconoce como comando"

Estás en **cmd** (Símbolo del sistema), no en PowerShell. Abrí PowerShell como Administrador, o usá el equivalente para cmd:

```
dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all
```

## La VM no arranca: "No se pueden asignar XXXX MB de RAM: Recursos insuficientes"

La memoria **fija** (obligatoria para nested virt) necesita que el host tenga el **bloque completo libre** en el momento del arranque. Con 32 GB físicos y Windows+Docker corriendo, 20 GB no entran; 16 GB es el sweet spot. Cerrá aplicaciones o bajá la RAM:

```powershell
Set-VMMemory opennebula-lab -StartupBytes 12GB
Start-VM opennebula-lab
```

## La VM "desapareció" — SSH no responde en la IP conocida

El **Default Switch** de Hyper-V rota de subred en cada reinicio del host Windows, y `netplan apply` dentro de la VM también puede renovar el DHCP (le pasó a miniONE a mitad de instalación). Buscala por su MAC:

```powershell
Get-VMNetworkAdapter opennebula-lab | Select MacAddress
arp -a | findstr <MAC-con-guiones>
```

Solución definitiva: el paso 5 (`04-Setup-LabNetwork.ps1`) — switch NAT propio + IP estática.

## Cambié el netplan pero la IP no cambia

Si el host Windows se reinició, Hyper-V **suspendió y restauró** la VM — eso NO es un boot (verificalo con `uptime`), y netplan solo aplica en boot real. Apagala y prendela de verdad:

```powershell
Stop-VM opennebula-lab -Force; Start-VM opennebula-lab
```

## Las VMs anidadas quedan en `poff` tras reiniciar el host

Mismo motivo: el suspend/restore de Hyper-V no preserva las VMs KVM anidadas. Es 1 comando:

```bash
ssh <usuario>@192.168.222.10 'sudo -u oneadmin onevm list'
ssh <usuario>@192.168.222.10 'sudo -u oneadmin onevm resume <ID>'
```

## Una VM nueva queda en `pend` eternamente

En OpenNebula la CPU asignada es **reserva dura**, no uso real: con 4 vCPU el host tiene 400 "puntos" y cada VM con `CPU=1` reserva 100 — la 5ª no entra aunque el host esté ocioso. Liberá capacidad (`onevm terminate/poweroff`) o ampliá la VM (paso 5 con `-Cpu 8`).

## miniONE dice que va a usar QEMU (emulación) en vez de KVM

La virtualización anidada no está llegando a la VM. Verificá **con la VM apagada**:

```powershell
(Get-VMProcessor opennebula-lab).ExposeVirtualizationExtensions   # debe ser True
Set-VMProcessor opennebula-lab -ExposeVirtualizationExtensions $true
```

Y adentro de la VM: `ls /dev/kvm` debe existir y `grep -cE 'vmx|svm' /proc/cpuinfo` > 0. Ojo: Dynamic Memory ON rompe nested virt — memoria fija siempre.

## Error "Enable-VMIntegrationService: no se encontró ningún componente"

Windows localizado (español u otro idioma): los nombres de los servicios de integración están traducidos. Los scripts del repo ya filtran por patrón (`'Guest|invitado'`) y lo tratan como opcional.

## Instalé appliances del Marketplace por CLI y el prompt interactivo me bloquea

Los templates de appliance traen `USER_INPUTS` que fuerzan prompts. Para automatizar: quitá el bloque `USER_INPUTS` del template (la appliance autogenera lo que falte) o pasá los valores. Si es un **servicio OneFlow** (multi-VM), los inputs viven en 4 capas: sección `networks`, `template_contents` de cada rol, CONTEXT de los VM templates, y sección `user_inputs` top-level (nueva en 7.x). El detalle completo de esta batalla está en [JOURNAL.md](JOURNAL.md), Fase 2 §4.

## Regla de oro de las instalaciones remotas

Toda instalación que toque la red del host remoto se logea **en el host remoto** (`| tee /root/algo.log`), no solo en tu sesión SSH — la sesión puede no sobrevivir para contarlo. Los scripts del repo ya lo hacen.
