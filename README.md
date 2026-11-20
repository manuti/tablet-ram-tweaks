# Tablet RAM Tweaks (2GB devices)

Optimización de memoria para tablets Android con **2 GB RAM** corriendo **LineageOS + Magisk (root)**.

> Probado en tablet genérica ARM64 (kernel 5.x) con zram habilitado. Compatible con Shield Tablet y similares.

---

## 🎯 Objetivo

| Antes (stock) | Después (tweaks) |
|---------------|------------------|
| Swap: 512 MB zram (lzo) | Swap: **1 GB total** (512 MB zram + 512 MB archivo) |
| Swappiness: 60 | **100** (swap agresivo) |
| Cache pressure: 100 | **200** (reclama cache antes) |
| LMK: conservador | **Agresivo** (mata cached apps primero) |
| Min free: ~12 MB | **56 MB** (reserva para allocations críticas) |

**Resultado**: El sistema usa swap *antes* de matar tu app en foreground (Termux, Pi, navegador). GMS/Play Services (~300 MB) se comprime en zram en lugar de forzar OOM kill.

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
echo "description=Optimiza RAM en tablets 2GB: swappiness 100, zram zstd, LMK agresivo, swap file 512MB" >> /data/adb/modules/ram-tweaks/module.prop

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
| `vm.swappiness=100` | Máximo | Kernel mueve páginas anónimas a swap *apenas* hay presión, protegiendo cache de archivos y apps foreground |
| `vm.vfs_cache_pressure=200` | 2x default | Reclama dentry/inode cache (metadata FS) antes que page cache de datos |
| `vm.min_free_kbytes=57344` | 56 MB | Reserva RAM para allocations atómicas (red, drivers, GPU); evita stalls en `kswapd` |
| `zram comp_algorithm=zstd` | Mejor ratio | ~1.5-2x compresión vs lzo en ARM64, similar CPU |
| `zram disksize=1GB` | Intento | Si kernel tiene memoria contigua, duplica swap comprimido |
| `LMK minfree=18432,23040,27648,32256,55296,82944` | Agresivo | Mata cached apps (adj=0, 58, 116) a 72/90/108 MB libres; foreground (adj=1000) solo a 324 MB |
| `/data/swapfile 512MB` | Respaldo | Swap en disco real (no comprimido) para cuando zram se llena; prioridad 5 (menor que zram) |

---

## 📊 Métricas esperadas

```bash
# Antes
Mem:           1.9Gi       1.3Gi       118Mi       599Mi       664Mi
Swap:          511Mi       124Mi       387Mi

# Después (en reposo)
Mem:           1.9Gi       1.4Gi       200Mi       562Mi       504Mi
Swap:          1.0Gi         0Mi       1.0Gi
```

| Métrica | Stock | Tweaked | Nota |
|---------|-------|---------|------|
| **MemAvailable** | ~680 MB | ~516 MB | Baja porque `min_free_kbytes` reserva más |
| **Swap libre** | ~387 MB | **~1024 MB** | 2.6x más buffer |
| **Presión OOM** | Media | **Baja** | Apps foreground sobreviven más |
| **Latencia bajo carga** | Picos | **Suave** | Swap absorbe picos |

> **Trade-off**: `MemAvailable` baja ~160 MB en idle, pero ganas **~640 MB de swap real** que evita kills cuando abres Chrome + Pi + Termux.

---

## 🧪 Verificación

```bash
# Ver parámetros activos
su -c "cat /proc/sys/vm/swappiness /proc/sys/vm/vfs_cache_pressure /proc/sys/vm/min_free_kbytes"
# Debe salir: 100 / 200 / 57344

# Ver swap
su -c "cat /proc/swaps"
# Debe mostrar zram (pri 10) + /data/swapfile (pri 5)

# Ver LMK
su -c "cat /sys/module/lowmemorykiller/parameters/minfree"
# Debe mostrar: 18432,23040,27648,32256,55296,82944

# Ver zram algo
su -c "cat /sys/block/zram0/comp_algorithm"
# Debe mostrar: [zstd] lzo lz4 ...
```

---

## ⚠️ Ajustes si hay problemas

| Síntoma | Fix |
|---------|-----|
| Lag / stutters al abrir apps | `su -c "echo 80 > /proc/sys/vm/swappiness"` (menos agresivo) |
| zram no crece a 1GB | Kernel sin memoria contigua; deja 512 MB, el swap file cubre |
| Bootloop | Borra `/data/adb/service.d/99-ram-tweaks.sh` o desactiva módulo Magisk desde recovery |
| `/data` lleno | Reduce swap file: `count=256` (256 MB) |

---

## 📝 Licencia

MIT — úsalo, modifícalo, compártelo.

---

## 🔗 Referencias

- [Kernel docs: vm.swappiness](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)
- [zram: zstd vs lzo](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/zram.html)
- [Android LMK tuning](https://source.android.com/docs/core/perf/lmkd)
- [Magisk service.d scripts](https://topjohnwu.github.io/Magisk/guides.html#service-d-scripts)