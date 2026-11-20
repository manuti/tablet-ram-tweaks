#!/system/bin/sh
sleep 3
echo 60 > /proc/sys/vm/swappiness
echo 100 > /proc/sys/vm/vfs_cache_pressure
echo '57344 57344 57344' > /proc/sys/vm/min_free_kbytes 2>/dev/null
if [ -f /sys/block/zram0/comp_algorithm ]; then
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null
fi
swapoff /dev/block/zram0 2>/dev/null
mkswap /dev/block/zram0 2>/dev/null
swapon /dev/block/zram0 -p 10 2>/dev/null
if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
    echo '4096,4096,4096,12288,20480,30720' > /sys/module/lowmemorykiller/parameters/minfree
fi
if [ -f /data/swapfile ]; then
    swapon /data/swapfile -p 5 2>/dev/null
fi
echo '[ram-tweaks] Applied' > /dev/kmsg 2>/dev/null || true
