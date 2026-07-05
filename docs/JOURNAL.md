# Informe: Laboratorio de cloud privado con OpenNebula 7.2 Community sobre Windows 11

**Fecha:** 1–2 de julio de 2026
**Autor:** Luis Rojas
**Resultado:** ✅ Cloud privado operativo con VMs KVM reales, montado 100% sobre un PC de escritorio con Windows 11 — sin VPS, sin costo de infraestructura.

---

## Resumen ejecutivo

Se montó un laboratorio funcional de **OpenNebula 7.2 (edición Community)** — la plataforma open source de cloud privado / gestión de virtualización — usando exclusivamente un PC de escritorio con Windows 11 Pro. El desafío técnico central: OpenNebula necesita un host Linux con **KVM**, y se resolvió con **virtualización anidada de Hyper-V** (una VM que a su vez virtualiza). El resultado se validó de punta a punta instanciando una VM Alpine Linux dentro del cloud, confirmando aceleración KVM por hardware (`domain type = kvm`, no emulación QEMU).

**Tiempo total efectivo:** ~2 horas (incluyendo descarga de ISO, instalación de Ubuntu y troubleshooting real).
**Costo:** $0.

---

## Objetivo

Evaluar OpenNebula como plataforma de virtualización open source siguiendo la guía oficial de sandbox ([docs.opennebula.io 7.2](https://docs.opennebula.io/7.2/getting_started/try_opennebula/)), dejando un laboratorio persistente para experimentar con gestión de VMs, marketplace de appliances y, a futuro, Kubernetes (OneKE).

---

## Análisis previo: elección del método de despliegue

La documentación oficial ofrece 3 caminos:

| Método | Complejidad | Uso ideal |
|---|---|---|
| **miniONE** (script automatizado) | Baja | Evaluación / laboratorio ✅ elegido |
| PoC ISO | Media | Pruebas en bare-metal |
| Instalación manual (front-end + nodos separados) | Alta | Producción |

**Decisión:** miniONE. Un solo script instala front-end, nodo KVM, red virtual con NAT, datastores y una VM de prueba. El dilema "¿VPS o miniONE?" resultó ser una falsa dicotomía: miniONE es el instalador, y corre igual sobre un VPS que sobre una VM local — la decisión real es **dónde** correrlo.

### ¿Dónde correr el host Linux? (la decisión importante)

| Opción | Veredicto | Motivo |
|---|---|---|
| **Docker** | ❌ | OpenNebula no es una app: es infraestructura de virtualización. Necesita cargar módulos KVM en el kernel, libvirt, systemd — imposible en un contenedor. |
| **VirtualBox** | ❌ | Con Hyper-V activo (requerido por Docker Desktop/WSL2), VirtualBox corre degradado sobre la API de Hyper-V y la virtualización anidada no funciona. |
| **WSL2** | ⚠️ | Posible pero frágil (systemd, redes, sin soporte oficial). |
| **VPS Linux** | ⚠️ | Funciona y es más estable para nested virt, pero cuesta dinero. |
| **VM Hyper-V con nested virtualization** | ✅ | Hipervisor tipo 1 nativo de Windows 11 Pro, gratis, convive con Docker Desktop (comparten hipervisor), y en CPUs AMD expone AMD-V hacia adentro de la VM → KVM real. |

**Hardware disponible:** AMD Ryzen 5 5600G (6c/12t, AMD-V), 32 GB RAM, 531 GB libres en disco — cumple justo el perfil recomendado por miniONE 7.2 (32 GiB RAM / 80 GiB disco).

---

## Arquitectura final

```
AMD Ryzen 5 5600G (AMD-V)
└── Hyper-V (hipervisor tipo 1, Windows 11 Pro)
    ├── Windows 11 (escritorio)
    ├── WSL2 → Docker Desktop (preexistente, intacto)
    └── VM "opennebula-lab" — Ubuntu Server 24.04.4 LTS
        │   4 vCPU · 12 GB RAM fijos · 80 GB VHDX dinámico
        │   ExposeVirtualizationExtensions = True  ← la clave
        │
        ├── OpenNebula 7.2 front-end (Sunstone web UI, FireEdge, OneGate, OneFlow)
        ├── Nodo KVM (libvirt + qemu-kvm sobre /dev/kvm real)
        ├── Red virtual: bridge minionebr 172.16.100.0/24 con NAT
        ├── Datastores: system / default (qcow2) / files
        └── VM "alpine-test" (Alpine Linux, 1 vCPU, 256 MB)
            → estado RUNNING, IP 172.16.100.2, domain type = kvm ✅
```

Tres niveles de virtualización apilados: **Hyper-V → Ubuntu/KVM → Alpine**, todos con aceleración por hardware.

---

## Pasos ejecutados

1. **Análisis de documentación** oficial (7.2) y requisitos de miniONE; inventario de hardware del host (CPU, RAM, AMD-V, disco).
2. **Habilitación de Hyper-V** en Windows 11 Pro (`Enable-WindowsOptionalFeature` / DISM) + reinicio. Verificado que no rompe Docker Desktop.
3. **Creación de la VM** con script PowerShell idempotente (`Create-OpenNebulaVM.ps1`): Gen2, memoria fija (requisito de nested virt), `ExposeVirtualizationExtensions=$true`, MAC spoofing ON (para red de VMs anidadas), Secure Boot con plantilla Microsoft UEFI CA (compatible con Linux), ISO montado.
4. **Instalación de Ubuntu Server 24.04.4 LTS** (ISO verificado por SHA256 contra el checksum oficial) con OpenSSH server.
5. **Automatización del acceso**: instalación de clave SSH ed25519 + sudo sin password → operación remota desatendida desde Windows.
6. **Instalación de OpenNebula con miniONE v7.2.0** (`./minione --yes --password ***`), desatendida y con log persistente en la VM. Duración: ~10 min.
7. **Validación del entorno** (según la guía oficial de validación):
   - 4 servicios systemd activos (opennebula, fireedge, gate, flow)
   - Host KVM `localhost` en estado `on` (4 CPU / 11.7 GB)
   - 3 datastores `on` (77 GB, qcow2)
   - Sunstone respondiendo HTTP 200 desde el host Windows
   - **Instanciación de VM Alpine → `RUNNING`**, IP 172.16.100.2 por DHCP de la red virtual, ping 0% pérdida, y `virsh dumpxml` confirmando `domain type=kvm` (aceleración por hardware, no emulación)

---

## Incidencias reales y resolución (lo más valioso del lab)

**1. Comando PowerShell en cmd.**
`Enable-WindowsOptionalFeature` fallaba con "no se reconoce como comando" → se estaba ejecutando en Símbolo del sistema, no en PowerShell. Alternativa equivalente para cmd: `dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all`.

**2. Windows localizado en español rompe scripts.**
`Enable-VMIntegrationService -Name 'Guest Service Interface'` falló porque el nombre del componente está **localizado** en Windows en español. Lección: en scripts de Hyper-V, filtrar servicios de integración por patrón (`Where-Object Name -match 'Guest|invitado'`) y tratar los pasos opcionales como best-effort, no bloqueantes.

**3. La VM "desapareció" a mitad de la instalación.**
El síntoma: Sunstone no respondía y el SSH se cayó. Causa raíz: miniONE crea el bridge `minionebr` y aplica netplan → la interfaz renovó DHCP y el **Default Switch de Hyper-V le asignó otra IP** (172.31.7.13 → 172.31.4.86). La instalación había terminado bien (EXIT_CODE=0 en el log remoto); solo cambió la puerta de entrada. Diagnóstico: búsqueda de la MAC fija de la VM en la tabla ARP de Windows (`arp -a | findstr 00-15-5d-00-f4-00`). Lección doble: (a) loggear las instalaciones remotas **en el host remoto** (`tee /root/lab-setup.log`), no solo en la sesión SSH; (b) el Default Switch de Hyper-V no garantiza IP estable — identificar las VMs por MAC.

---

## Números del laboratorio

| Métrica | Valor |
|---|---|
| Costo de infraestructura | $0 (hardware propio + software open source) |
| Tiempo efectivo total | ~2 horas |
| Instalación miniONE propiamente | ~10 minutos |
| RAM asignada al lab | 12 GB (de 32 del host) |
| Disco | VHDX dinámico de 80 GB (uso real inicial ~7 GB) |
| Niveles de virtualización | 3 (Hyper-V → KVM → VM guest) |
| Overhead perceptible del nested virt | Bajo — boot de Alpine en segundos |

---

## Lecciones aprendidas

1. **No todo se dockeriza.** Un gestor de hipervisores necesita kernel propio; la frontera contenedor/VM sigue importando.
2. **Windows 11 Pro trae un hipervisor tipo 1 gratis** que la mayoría no usa: Hyper-V con nested virtualization (también en AMD) habilita labs de infraestructura sin pagar cloud.
3. **La coexistencia importa:** Docker Desktop (WSL2) y Hyper-V comparten hipervisor sin conflicto; VirtualBox en cambio queda degradado en ese escenario.
4. **Automatizar el acceso primero** (clave SSH + sudo NOPASSWD) paga inmediato: toda la instalación y validación se hizo desatendida desde el host.
5. **Instalaciones remotas que tocan la red se loggean en el destino,** porque la sesión que las lanzó puede no sobrevivir para contarlo.
6. **miniONE cumple lo que promete:** de Ubuntu limpio a cloud privado navegable en ~10 minutos, con marketplace de appliances incluido.

---

---

# FASE 2 — Marketplace, OneFlow, red estable y Kubernetes (mismo día)

## 1. Validación del Marketplace: WordPress por CLI

Se exportó la appliance **"Service WordPress - KVM"** del OpenNebula Public Marketplace
(130 apps disponibles) con `onemarketapp export`, y se instanció 100% desatendido.

- Detalle técnico: los templates de appliance traen `USER_INPUTS` que fuerzan prompts
  interactivos en el CLI. Para automatizar: se elimina el bloque del template y la
  appliance autogenera lo que falte.
- **Resultado:** VM `RUNNING`, y `curl` al puerto 80 devolvió el instalador
  (`<title>WordPress › Installation</title>`) — Marketplace validado de punta a punta.
- **Lección de scheduling:** el 5º VM quedó `pend` con el host ocioso — en OpenNebula
  la CPU asignada es **reserva dura** (4 vCPU = 400 puntos; 4 VMs × CPU=1 = lleno).

## 2. OneFlow: orquestación multi-VM y plantillas propias

Se creó un servicio OneFlow `svc-demo` con dos roles y dependencia explícita
(`frontend` con `parents: [backend]`): OneFlow **retuvo** el frontend hasta que los
2 backends estuvieron `RUNNING` — orquestación con orden de arranque, verificada.
Además se registró una plantilla propia (`alpine-custom`) vía CLI.

## 3. Red estable: adiós al Default Switch

El "Default Switch" de Hyper-V rota de subred en cada reinicio del host (la VM pasó
por 3 IPs en un día). Solución definitiva:

- Switch interno `onelab` + **NetNat** de Windows (192.168.222.0/24).
- IP estática en la VM vía netplan → el lab quedó fijo en `192.168.222.10`.
- De paso: VM ampliada a **8 vCPU / 16 GB** (requisito real de Kubernetes).

Dos lecciones de Hyper-V:
- Con memoria fija (requisito de nested virt), la VM **no arranca** si el host no tiene
  el bloque completo libre: 20 GB no entraban con 19.6 GB libres → 16 GB es el sweet
  spot en un host de 32 GB.
- Al reiniciar Windows, Hyper-V **suspende/restaura** la VM: no es un boot, y los
  cambios de netplan no aplican hasta un apagado/encendido real.

## 4. Kubernetes con OneKE 1.33 — la batalla que enseñó cómo funciona todo

Se desplegó **OneKE 1.33** (RKE2, Kubernetes v1.33.4) del Marketplace: servicio
OneFlow de 4 roles — VNF (router/LB), master, worker, storage — sobre 2 redes
(pública `vnet` + privada `privnet` creada por CLI).

**Resultado final:** cluster funcionando —

```
NAME                     STATUS   ROLES                       VERSION
oneke-ip-192-168-200-3   Ready    control-plane,etcd,master   v1.33.4+rke2r1
```

Pero el valor real fue la **cadena de 5 root-causes** que hubo que resolver para
llegar ahí (instanciación por CLI, sin Sunstone):

1. **Prompts en 4 capas.** Los user inputs de un servicio OneFlow viven en: la sección
   `networks`, los `template_contents` de cada rol, el CONTEXT de los VM templates, y
   (novedad 7.x) una sección `user_inputs` top-level del service template. Hubo que
   resolverlas todas para instanciar desatendido.
2. **Placeholder `<ETH0_EP0>` sin resolver.** Al quitar la sección `networks` del
   template, OneFlow dejó de sustituir los endpoints → HAProxy de la VNF quedó con IPs
   literales inválidas → nunca escuchó el puerto 6443 → el master esperó el
   control-plane 90s y abortó.
3. **Referencias `$VAR` del CONTEXT pisadas.** La mecánica real de OpenNebula:
   `template_contents` del rol aterriza en el USER_TEMPLATE de la VM y el CONTEXT lo
   *jala* con `"$ONEAPP_X"`. Esas referencias no son "inputs sin resolver": son el
   mecanismo de inyección. Se restauraron 73 referencias en 3 templates.
4. **Carrera de arranque del appliance (bug reportable de OneKE 1.33).** OneGate
   rechaza (`Not authorized`) a las VMs recién booteadas —oned aún no las marca
   RUNNING en su ciclo de monitoreo— y el `configure` del appliance es one-shot: si
   pierde la carrera, muere y no reintenta (el refresher HAProxy de la VNF, además,
   queda colgado en su loop). Workaround: re-ejecutar
   `/etc/one-appliance/service configure && ... bootstrap` una vez estabilizado.
5. **El entorno de contexto no viaja solo.** Al re-ejecutar a mano hay que cargar
   `/run/one-context/one_env` — el appliance lee su configuración de ahí, no de la
   nada.

Extra de la vida real: con 3 GB por nodo, los pulls de Cilium pusieron al master al
límite (un `kubectl` transitorio mató otro intento de configure; systemd resucitó
`rke2-server` solo). En un lab anidado, el dimensionamiento es parte del ejercicio.

**Meta-lección del lab:** las appliances automatizan el camino feliz; cuando algo se
sale de él, lo que salva es entender las tripas — OneGate, contextualización,
OneFlow, y leer el código ruby del appliance en la propia VM. Ese conocimiento es
exactamente lo que un lab debe producir.

---

## Estado final del laboratorio

| Componente | Estado |
|---|---|
| OpenNebula 7.2 (miniONE) | ✅ Sunstone fijo en 192.168.222.10 |
| WordPress (Marketplace) | ✅ RUNNING, HTTP validado |
| OneFlow multi-VM | ✅ Demostrado (svc-demo, terminado tras validar) |
| Plantilla propia | ✅ alpine-custom registrada |
| Red estable | ✅ Switch onelab + NetNat + IP estática |
| **Kubernetes OneKE 1.33** | ✅ Master `Ready` (v1.33.4+rke2r1), worker en integración |

## Próximos pasos

- [ ] Ingress (Traefik) y almacenamiento persistente (Longhorn) sobre OneKE.
- [ ] Publicar el lab como repositorio en GitHub (cuenta personal).
- [ ] Reportar upstream el bug de carrera OneGate/appliance de OneKE 1.33.

---

*Nota: las credenciales del laboratorio no se incluyen en este informe. Stack: Windows 11 Pro · Hyper-V · Ubuntu Server 24.04.4 LTS · OpenNebula 7.2 Community · miniONE v7.2.0 · KVM/libvirt · OneKE 1.33 (RKE2/Kubernetes v1.33.4).*
