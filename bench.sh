#!/usr/bin/env bash
set -euo pipefail

# Simple, repeatable benchmarks to compare before/after ubusmooth tweaks.
# Usage: ./bench.sh <label>
# Example: ./bench.sh baseline   ; ./bench.sh ubusmooth

LABEL=${1:-}
if [[ -z "$LABEL" ]]; then
  echo "Usage: $0 <label>"; exit 1
fi

REQS=(sysbench fio awk sed date mkdir free swapon systemd-analyze)
for cmd in "${REQS[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+="$cmd "
done
if [[ -n "${MISSING:-}" ]]; then
  echo "Installing missing tools: $MISSING"
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y sysbench fio >/dev/null 2>&1 || true
fi

ROOT_DIR=$(pwd)
OUT_DIR="$ROOT_DIR/bench"
LOG_DIR="$OUT_DIR/logs/${LABEL}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
RES_CSV="$OUT_DIR/results.csv"

# --------------- helpers ---------------
log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_DIR/run.log"; }
kv() { printf "%s,%s\n" "$1" "$2" >>"$LOG_DIR/kv.csv"; }
append_csv_header() {
  if [[ ! -f "$RES_CSV" ]]; then
    echo "timestamp,label,kernel,cpus,mem_total_mb,mem_free_mb,swap_total_mb,swap_used_mb,boot_time_sec,cpu_events,mem_throughput_mb_s,fio_write_mb_s,fio_read_mb_s" >"$RES_CSV"
  fi
}
append_csv_row() {
  echo "$ROW" >>"$RES_CSV"
}

# --------------- system info ---------------
KERNEL=$(uname -r)
CPUS=$(nproc)
MEM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
MEM_FREE_MB=$(free -m | awk '/Mem:/ {print $4}')
SWAP_TOTAL_MB=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED_MB=$(free -m | awk '/Swap:/ {print $3}')

kv kernel "$KERNEL"
kv cpus "$CPUS"
kv mem_total_mb "$MEM_TOTAL_MB"
kv mem_free_mb "$MEM_FREE_MB"
kv swap_total_mb "$SWAP_TOTAL_MB"
kv swap_used_mb "$SWAP_USED_MB"

# --------------- boot time ---------------
BOOT_TIME_SEC=$(systemd-analyze time 2>/dev/null | awk -F'=' '/startup finished/ {gsub(" s\n","",$3); print $3+0}' || echo "")
kv boot_time_sec "$BOOT_TIME_SEC"

# --------------- CPU ---------------
log "CPU: sysbench 10s all cores"
SB_CPU=$(sysbench cpu --threads="$CPUS" --time=10 run 2>&1 | tee "$LOG_DIR/sysbench-cpu.txt")
CPU_EVENTS=$(echo "$SB_CPU" | awk -F': ' '/events per second/ {print $2; exit}')
kv cpu_events "$CPU_EVENTS"

# --------------- Memory ---------------
log "Memory: sysbench 10s all cores"
SB_MEM=$(sysbench memory --threads="$CPUS" --time=10 run 2>&1 | tee "$LOG_DIR/sysbench-mem.txt")
MEM_MB_S=$(echo "$SB_MEM" | awk -F': ' '/transferred/ {print $2}' | awk '{print $1}')
kv mem_throughput_mb_s "$MEM_MB_S"

# --------------- Disk (fio) ---------------
TESTDIR="$LOG_DIR/fio"
mkdir -p "$TESTDIR"
SIZE=1G

log "Disk: fio write $SIZE"
fio --name=write --directory="$TESTDIR" --size=$SIZE --bs=1M --rw=write --iodepth=8 --numjobs=1 --direct=1 --group_reporting 2>&1 | tee "$LOG_DIR/fio-write.txt"
WRITE_MB_S=$(awk '/WRITE: bw=/ {sub("bw="," ",$0); gsub(","," ",$0); for(i=1;i<=NF;i++) if($i~"^bw=") {print $(i+1)} }' "$LOG_DIR/fio-write.txt" | head -n1)
# fallback parser
if [[ -z "$WRITE_MB_S" ]]; then WRITE_MB_S=$(awk -F'[,= ]+' '/WRITE/ {for(i=1;i<=NF;i++) if($i=="bw") print $(i+1)}' "$LOG_DIR/fio-write.txt" | head -n1); fi
kv fio_write_mb_s "$WRITE_MB_S"

log "Disk: fio read $SIZE"
fio --name=read --directory="$TESTDIR" --size=$SIZE --bs=1M --rw=read --iodepth=8 --numjobs=1 --direct=1 --group_reporting 2>&1 | tee "$LOG_DIR/fio-read.txt"
READ_MB_S=$(awk '/READ: bw=/ {sub("bw="," ",$0); gsub(","," ",$0); for(i=1;i<=NF;i++) if($i~"^bw=") {print $(i+1)} }' "$LOG_DIR/fio-read.txt" | head -n1)
if [[ -z "$READ_MB_S" ]]; then READ_MB_S=$(awk -F'[,= ]+' '/READ/ {for(i=1;i<=NF;i++) if($i=="bw") print $(i+1)}' "$LOG_DIR/fio-read.txt" | head -n1); fi
kv fio_read_mb_s "$READ_MB_S"

rm -rf "$TESTDIR" || true

# --------------- summary row ---------------
append_csv_header
ROW="$(date -Is),$LABEL,$KERNEL,$CPUS,$MEM_TOTAL_MB,$MEM_FREE_MB,$SWAP_TOTAL_MB,$SWAP_USED_MB,$BOOT_TIME_SEC,$CPU_EVENTS,$MEM_MB_S,$WRITE_MB_S,$READ_MB_S"
append_csv_row

log "Done. Summary appended to $RES_CSV"
