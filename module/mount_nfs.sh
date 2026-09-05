#!/system/bin/sh
set -eu

log() { echo "pixel-nfs: $*"; }

if [ "$#" -ne 2 ]; then
  log "usage: $0 SERVER /EXPORT/PATH"
  exit 2
fi

server=$1
export_path=$2
nfs_mount=/mnt/pixel_nfs
visible_mount=/mnt/runtime/write/emulated/0/the_binding

if [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]; then
  log "must run in PID 1's mount namespace"
  exit 1
fi

case "$export_path" in
  /*) ;;
  *) log "export path must begin with /"; exit 2 ;;
esac

umount "$visible_mount" 2>/dev/null || true
umount "$nfs_mount" 2>/dev/null || true

magiskpolicy --live "allow kernel kernel capability net_raw" || true
magiskpolicy --live "allow kernel kernel capability net_bind_service" || true
magiskpolicy --live "allow media_rw_data_file media_rw_data_file filesystem associate" || true

mkdir -p "$nfs_mount" "$visible_mount"
mount -t nfs \
  -o rw,nosuid,nodev,noexec,noatime,vers=3,proto=tcp,soft,timeo=100,retrans=3,addr="$server",nolock,nosharecache,context=u:object_r:media_rw_data_file:s0 \
  "$server:$export_path" "$nfs_mount"

mkdir -p "$nfs_mount/the_binding"
chmod -R 0777 "$nfs_mount/the_binding" || true

mount -t sdcardfs \
  -o rw,nosuid,nodev,noexec,noatime,gid=9997 \
  "$nfs_mount/the_binding" "$visible_mount"

log "mounted $server:$export_path at /storage/emulated/0/the_binding"
