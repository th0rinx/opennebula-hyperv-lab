# 🌩️ OpenNebula 7.2 sobre Hyper-V — cloud privado en tu PC con Windows 11

![Windows 11](https://img.shields.io/badge/Windows%2011-Pro-0078D4?logo=windows11)
![OpenNebula](https://img.shields.io/badge/OpenNebula-7.2-0DB4C4)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

**De Windows 11 Pro limpio a un cloud privado [OpenNebula](https://opennebula.io/) con KVM real en ~40 minutos, 90% scripteado, $0 de infraestructura.**

Sin VPS, sin VirtualBox, sin WSL frágil: el truco es la **virtualización anidada de Hyper-V** — una VM Ubuntu que a su vez virtualiza con KVM por hardware. Convive con Docker Desktop sin conflicto (comparten hipervisor).

```
Tu CPU (Intel VT-x / AMD-V)
└── Hyper-V (hipervisor tipo 1, incluido en Windows 11 Pro)
    ├── Windows 11 (tu escritorio)
    ├── WSL2 / Docker Desktop (si lo tenés — intacto)
    └── VM "opennebula-lab" — Ubuntu Server 24.04 LTS
        │   ExposeVirtualizationExtensions = true   ← la clave
        ├── OpenNebula 7.2 (Sunstone, OneFlow, OneGate, Marketplace)
        ├── Nodo KVM (libvirt sobre /dev/kvm REAL, no emulación)
        └── Tus VMs anidadas (Alpine, WordPress, GLPI, Kubernetes/OneKE...)
```

> 🔎 Validado end-to-end: la VM anidada corre con `domain type=kvm` (aceleración por hardware). Tres niveles de virtualización apilados.

## Requisitos

| Recurso | Mínimo | Recomendado (para Kubernetes/OneKE) |
|---|---|---|
| Windows | 11 Pro / 10 Pro (Hyper-V) | 11 Pro |
| CPU | 4 núcleos con VT-x / AMD-V | 6+ núcleos |
| RAM | 16 GB (VM de 8-12 GB) | 32 GB (VM de 16 GB) |
| Disco | 90 GB libres | 150 GB |
| Otros | OpenSSH client (incluido en Windows 10/11) | — |

## Paso a paso

> Los scripts marcados 🔒 van en PowerShell **como Administrador**. Todos aceptan parámetros (`Get-Help .\script.ps1 -Detailed`).

### 1. 🔒 Habilitar Hyper-V (una sola vez + reinicio)

```powershell
cd scripts
.\01-Enable-HyperV.ps1
# reiniciar, y despues:
.\01-Enable-HyperV.ps1 -Verify
```

### 2. 🔒 Crear la VM (descarga el ISO y verifica SHA256 sola)

```powershell
.\02-Create-LabVM.ps1                    # 12 GB / 4 vCPU
# o si vas a correr Kubernetes despues:
.\02-Create-LabVM.ps1 -Ram 16GB -Cpu 8
```

### 3. ⌨️ Instalar Ubuntu (el único paso manual, ~5 min)

```powershell
Start-VM opennebula-lab; vmconnect.exe localhost opennebula-lab
```

Instalador TUI de Ubuntu — guía pantalla por pantalla en [docs/UBUNTU-INSTALL.md](docs/UBUNTU-INSTALL.md). Lo **crítico**: marcar ☑ `Install OpenSSH server`, anotar usuario/password, y al final anotar la IP (`ip -4 addr show eth0`).

### 4. Bootstrap SSH (desde acá, nunca más tocás la consola)

```powershell
.\03-Bootstrap-Ssh.ps1 -VmIp <IP-que-anotaste> -VmUser <tu-usuario>
```

Instala tu clave SSH, configura sudo sin password y deja la IP estática lista (latente). Te pide la password de la VM 2 veces — son las últimas.

### 5. 🔒 Red estable (adiós al Default Switch que rota de IP)

```powershell
.\04-Setup-LabNetwork.ps1
# opcional, ampliar de paso: -Ram 16GB -Cpu 8
```

Crea el switch NAT `onelab` (192.168.222.0/24) y reinicia la VM en su IP fija: **192.168.222.10**, para siempre.

### 6. Instalar OpenNebula (miniONE, desatendido, ~10 min)

```powershell
.\05-Install-MiniONE.ps1 -VmUser <tu-usuario> -SunstonePassword <una-password-fuerte>
```

### 7. Validar todo

```powershell
.\06-Validate-Lab.ps1 -VmUser <tu-usuario>
```

Chequea servicios, host KVM, datastores, Sunstone, e instancia una VM Alpine verificando que corre con **KVM real** y tiene red.

## Resultado

- **Sunstone (web UI):** `http://192.168.222.10/` → usuario `oneadmin` + tu password
- **SSH:** `ssh <tu-usuario>@192.168.222.10` (con clave, sin password)
- Marketplace con 130+ appliances listas (WordPress, Kubernetes/OneKE, Harbor...)
- Red virtual NAT interna `172.16.100.0/24` para tus VMs anidadas

## Después del lab

- 📓 [docs/JOURNAL.md](docs/JOURNAL.md) — la bitácora real del build original: decisiones (por qué no Docker/VirtualBox/VPS), incidencias reales y la batalla de desplegar Kubernetes OneKE por CLI con sus 5 root-causes.
- 🩺 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — los problemas que te vas a encontrar (porque nos los encontramos): IP que "desaparece", VM que no arranca por RAM, netplan que no aplica, y más.
- 🧩 Segunda parte: **GLPI 11 desplegado como VM dentro de este lab** → repo [`glpi-on-opennebula`](https://github.com/th0rinx/glpi-on-opennebula).

## Advertencias honestas

- Es un **laboratorio**: un solo nodo, sin HA, credenciales simples. No es producción.
- Los pasos manuales que quedan: el reinicio del paso 1, la instalación TUI de Ubuntu del paso 3, y pasar IP/usuario a los scripts. Todo lo demás es correr comandos en orden.
- Si el host Windows se reinicia, Hyper-V *suspende/restaura* la VM: las VMs anidadas suelen quedar `poff` — `onevm resume <id>` y listo.

## Licencia

MIT — usalo, rompelo, mejoralo. PRs bienvenidos.

---

*Construido y documentado en vivo sobre un AMD Ryzen 5 5600G / 32 GB, julio 2026.*
