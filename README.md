# Tablet RAM Tweaks (2GB devices)

Optimización de memoria para tablets Android con **2 GB RAM** corriendo **LineageOS + Magisk (root)**.

> Probado en tablet genérica ARM64 (kernel 5.x) y **NVIDIA SHIELD Tablet K1** (ARMv7, kernel 3.10) con zram habilitado.

---

## 🎯 Objetivo

| Antes (stock) | Después (tweaks) |
|---------------|------------------|
| Swap: 512 MB zram (lzo) | Swap: **1 GB total** (512 MB zram + 512 MB archivo) |
| Swappiness: 60 | **60** (balanceado, sin lag UI) |
| Cache pressure: 100 | **100** (default) |
| LMK: conservador | **Ultra-conservador** (solo mata cached apps) |
| Min free: ~12 MB | **56 MB** (reserva para allocations críticas) |

**Resultado**: El sistema usa swap como red de seguridad *antes* de matar tu app en foreground (Termux, Pi, navegador). GMS/Play Services (~300 MB) se comprime en zram en lugar de forzar OOM kill.

---

## 🔗 Proyecto relacionado: SHIELD Tablet K1

Si usas una **NVIDIA SHIELD Tablet K1** (Tegra K1, ARMv7, kernel 3.10, Android 8.1), existe un módulo complementario específico:

> **[shield-tweaks](https://github.com/manuti/shield-tweaks)** — Magisk module con I/O scheduler (`deadline`), CPU governor (`interactive` tuned), VM dirty ratios, y ahora **integrado con estas optimizaciones de RAM/swap/LMK**.

- Corre **90s post-boot** (después de [YAKT](https://github.com/NotZeetaa/YAKT))
- Compatible: flashea ambos módulos (YAKT → shield-tweaks → tablet-ram-tweaks)
- En SHIELD K1 real: `shield-tweaks` ya incluye lo esencial de este repo

---

## 📦 Instalación

### Requisitos
- Root (Magisk)
- LineageOS / AOSP-based ROM
- Kernel con zram (casi todos lo tienen)

### Opción A: Magisk Module (recomendado)
```bash
# 1. Crear módulo Magisk
mkdir -p /data/adb/modules/ram-tweaks
cp ram-tweaks.sh /data/adb/modules/ram-tweaks/service.sh
echo "id=ram-tweaks" > /data/adb/modules/ram-tweaks/module.prop
echo "name=RAM Tweaks 2GB" >> /data/adb/modules/ram-tweaks/module.prop
echo "version=1.0" >> /data/adb/modules/ram-tweaks/module.prop
echo "author=manuti" >> /data/adb/modules/ram-tweaks/module.prop
echo "description=Optimiza RAM en tablets 2GB: swappiness 60, zram lzo/zstd, LMK ultra-conservador, swap file 512MB" >> /data/adb/modules/ram-tweaks/module.prop

# 2. Crear swap file una vez
su -c "dd if=/dev/zero of=/data/swapfile bs=1024k count=512 && mkswap /data/swapfile"

# 3. Reiniciar
reboot
```

### Opción B: Script en service.d (lo que aplicamos hoy)
```bash
su -c "cp ram-tweaks.sh /data/adb/service.d/99-ram-tweaks.sh"
su -c "chmod +x /data/adb/service.d/99-ram-tweaks.sh"
# Crear swap file
su -c "dd if=/dev/zero of=/data/swapfile bs=1024k count=512 && mkswap /data/swapfile"
# Ejecutar ya
su -c "sh /data/adb/service.d/99-ram-tweaks.sh"
```

---

## 🔧 Qué hace cada parámetro

| Parámetro | Valor | Por qué |
|-----------|-------|---------|
| `vm.swappiness=60` | Default | Balanceado: swap bajo presión real, sin lag UI por I/O constante en zram |
| `vm.vfs_cache_pressure=100` | Default | Reclamo equilibrado de dentry/inode cache |
| `vm.min_free_kbytes=57344` | 56 MB | Reserva RAM para allocations atómicas (red, drivers, GPU); evita stalls en `kswapd` |
| `zram comp_algorithm` | `zstd` (ARM64) / `lzo` (kernel 3.10) | Mejor ratio de compresión; kernel 3.10 (SHIELD K1) solo soporta lzo |
| `zram disksize` | 512 MB (nativo) | Kernel no permite redimensionar; se usa swap file como respaldo |
| `LMK minfree` | `4096,4096,4096,12288,20480,30720` | **Ultra-conservador**: FOREGROUND/VISIBLE=16MB (intocables), HIDDEN=48MB (solo cached apps mueren) |
| `/data/swapfile 512MB` | Respaldo | Swap en disco real para cuando zram se llena; prioridad 5 (menor que zram pri 10) |

---

## 📊 Métricas esperadas

```bash
# Antes (stock)
Mem:           1.9Gi       1.3Gi       118Mi       599Mi       664Mi
Swap:          511Mi       124Mi       387Mi

# Después (en reposo, SHIELD K1 real)
Mem:           1.9Gi       1.5Gi       180Mi       500Mi       430Mi
Swap:          1.0Gi       380Mi       640Mi
```

| Métrica | Stock | Tweaked | Nota |
|---------|-------|---------|------|
| **MemAvailable** | ~680 MB | ~430 MB | Baja por `min_free_kbytes` + swap usado |
| **Swap libre** | ~387 MB | **~640 MB** | 1.6x más buffer real |
| **Swap usado** | ~124 MB | **~380 MB** | GMS/background comprimido en zram |
| **Presión OOM** | Media | **Muy baja** | Apps foreground/visible protegidas |
| **Latencia bajo carga** | Picos | **Suave** | Swap absorbe, swappiness=60 evita I/O constante |

> **Trade-off**: `MemAvailable` baja ~250 MB en idle (se usa swap), pero ganas **~600 MB de swap real activo** que evita kills al abrir Chrome + Pi + Termux + Firefox.

---

## 🧪 Verificación

```bash
# Ver parámetros activos
su -c "cat /proc/sys/vm/swappiness /proc/sys/vm/vfs_cache_pressure /proc/sys/vm/min_free_kbytes"
# Debe salir: 60 / 100 / 57344

# Ver swap
su -c "cat /proc/swaps"
# Debe mostrar zram (pri 10) + /data/swapfile (pri 5)

# Ver LMK
su -c "cat /sys/module/lowmemorykiller/parameters/minfree"
# Debe mostrar: 4096,4096,4096,12288,20480,30720

# Ver zram algoritmo
su -c "cat /sys/block/zram0/comp_algorithm"
# ARM64: [zstd] lzo lz4 ...  |  Kernel 3.10: [lzo] lz4 ...
```

---

## ⚠️ Ajustes si hay problemas

| Síntoma | Fix |
|---------|-----|
| Lag / stutters al abrir apps | `su -c "echo 40 > /proc/sys/vm/swappiness"` (menos agresivo) |
| zram no crece | Kernel sin memoria contigua; deja 512 MB nativo, el swap file cubre |
| Bootloop | Borra `/data/adb/service.d/99-ram-tweaks.sh` o desactiva módulo Magisk desde recovery |
| `/data` lleno | Reduce swap file: `count=256` (256 MB) |
| Firefox tirones | Usa `firefox-lowmem-user.js` (desactiva cache disco, e10s, telemetría) |

---

## 📝 Licencia

MIT — úsalo, modifícalo, compártelo.

---

## 🔗 Referencias

- [Kernel docs: vm.swappiness](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)
- [zram: zstd vs lzo](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/zram.html)
- [Android LMK tuning](https://source.android.com/docs/core/perf/lmkd)
- [Magisk service.d scripts](https://topjohnwu.github.io/Magisk/guides.html#service-d-scripts)
- **Proyecto hermano**: [shield-tweaks](https://github.com/manuti/shield-tweaks) — I/O + CPU + VM para SHIELD K1 (archived, read-only)