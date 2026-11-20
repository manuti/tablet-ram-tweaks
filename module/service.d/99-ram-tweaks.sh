#!/system/bin/sh
# ============================================================
# RAM Tweaks para tablets Android con 2GB RAM (LineageOS + Magisk)
# Ejecución: Magisk boot script (/data/adb/service.d/99-ram-tweaks.sh)
# ============================================================

# 1. Swappiness agresivo → prioriza swap (zram) sobre reclamar cache
#    100 = kernel swappea anon pages apenas hay presión
echo 100 > /proc/sys/vm/swappiness

# 2. VFS cache pressure → reclama dentry/inode cache antes
#    200 = 2x más agresivo que default (100)
echo 200 > /proc/sys/vm/vfs_cache_pressure

# 3. min_free_kbytes → reserva RAM libre para allocations atómicas
#    56 MB (57344 KB) en 2GB = ~2.8% | default ~12 MB
echo "57344 57344 57344" > /proc/sys/vm/min_free_kbytes 2>/dev/null

# 4. ZRAM: mejor algoritmo + recrear swap si disksize cambia
#    zstd > lzo en ratio y velocidad en ARM64 moderno
if [ -f /sys/block/zram0/comp_algorithm ]; then
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null
fi

#    Intentar 1GB zram (kernel puede ignorar si no hay contiguo)
if [ -f /sys/block/zram0/disksize ]; then
    echo 1073741824 > /sys/block/zram0/disksize 2>/dev/null  # 1 GB
    swapoff /dev/block/zram0 2>/dev/null
    mkswap /dev/block/zram0 2>/dev/null
    swapon /dev/block/zram0 -p 10 2>/dev/null   # prioridad alta
fi

# 5. LowMemoryKiller (LMK) más agresivo
#    Valores en páginas de 4KB: mata cached apps ANTES de tocar foreground
#    Default suele ser ~72,90,108,126,144,180 MB → esto mata antes
if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
    echo "9216,12288,15360,18432,27648,36864" > /sys/module/lowmemorykiller/parameters/minfree
fi

# 6. Swap file secundario en /data (512 MB) - respaldo si zram se llena
if [ -f /data/swapfile ]; then
    swapon /data/swapfile -p 5 2>/dev/null
fi

# 7. Opcional: limpiar caches al boot (descomenta si no tarda mucho)
# echo 3 > /proc/sys/vm/drop_caches