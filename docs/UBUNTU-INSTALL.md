# Instalación de Ubuntu Server 24.04 — pantalla por pantalla

El único paso manual del lab (~5 min). Abrí la consola de la VM:

```powershell
Start-VM opennebula-lab; vmconnect.exe localhost opennebula-lab
```

| # | Pantalla | Qué elegir |
|---|---|---|
| 1 | Idioma / teclado | El tuyo |
| 2 | Type of install | **Ubuntu Server** (el normal — NO "minimized") |
| 3 | Network | Dejar el DHCP automático de `eth0` → **Done** |
| 4 | Proxy | Vacío → Done |
| 5 | Mirror | Default → Done |
| 6 | Storage | **Use an entire disk** → el disco de 80 GB → Done → **Continue** (confirma formateo) |
| 7 | Profile | Nombre, server name, **usuario** y **password** → 📝 **ANOTALOS** (los usan los scripts 03-06) |
| 8 | Upgrade to Ubuntu Pro | Skip for now |
| 9 | SSH Setup | ☑ **Install OpenSSH server** ← **EL PASO CRÍTICO** (marcar con barra espaciadora) |
| 10 | Featured snaps | Ninguno → Done |
| 11 | Instalación | Esperar → **Reboot Now** |

Tras el reinicio, logueate en la consola y anotá la IP:

```bash
ip -4 addr show eth0 | grep inet
# ej: inet 172.28.5.113/20 ...  ->  la IP es 172.28.5.113
```

> La IP es temporal (DHCP del Default Switch — rota en cada reinicio del host). El paso 5 del README la reemplaza por una fija. Si en algún momento "perdés" la VM, buscala por su MAC: `arp -a | findstr <MAC>` (la MAC se ve con `Get-VMNetworkAdapter opennebula-lab`).

Con IP + usuario + password anotados → volvé al README, paso 4 (`03-Bootstrap-Ssh.ps1`).

## Opcional: instalación 100% desatendida

Ubuntu soporta [autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html) con un seed cloud-init (NoCloud), lo que eliminaría este paso manual. No está incluido en el repo para mantener las dependencias en cero (generar el seed ISO en Windows requiere herramientas extra). Si te interesa, es un buen primer PR 😉.
