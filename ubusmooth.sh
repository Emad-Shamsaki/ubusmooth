#!/usr/bin/env bash
set -euo pipefail

# UbuSmooth: light, reversible Ubuntu optimizations
# Works on GNOME/XFCE; tested on Ubuntu 20.04+.

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash $0 [options]"
    exit 1
  fi
}

CONF_SYSCTL="/etc/sysctl.d/99-ubusmooth.conf"
CONF_ZRAM="/etc/default/zramswap"
LOG="/var/log/ubusmooth.log"

log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG"; }

enable_zram() {
  log "Enabling zram (compressed RAM swap)…"
  apt-get update -y >>"$LOG" 2>&1
  apt-get install -y zram-tools >>"$LOG" 2>&1 || {
    log "Could not install zram-tools"; return 1; }

  if [[ -f "$CONF_ZRAM" && ! -f "${CONF_ZRAM}.bak" ]]; then
    cp -a "$CONF_ZRAM" "${CONF_ZRAM}.bak"
  fi

  cat >/etc/default/zramswap <<'EOF'
# UbuSmooth defaults: use half of RAM as zram, higher priority than disk swap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

  systemctl enable --now zramswap.service >>"$LOG" 2>&1 || true
  log "zram enabled. Current swap:"
  swapon --show || true
}

tune_kernel() {
  log "Applying kernel VM tuning…"
  if [[ -f "$CONF_SYSCTL" && ! -f "${CONF_SYSCTL}.bak" ]]; then
    cp -a "$CONF_SYSCTL" "${CONF_SYSCTL}.bak"
  fi

  cat >"$CONF_SYSCTL" <<'EOF'
# UbuSmooth: gentle memory tuning
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  sysctl --system >>"$LOG" 2>&1
  log "Tuning applied: swappiness=$(sysctl -n vm.swappiness), vfs_cache_pressure=$(sysctl -n vm.vfs_cache_pressure)"
}

install_tlp() {
  log "Installing and enabling TLP…"
  apt-get update -y >>"$LOG" 2>&1
  apt-get install -y tlp tlp-rdw >>"$LOG" 2>&1 || true

  # Avoid conflicts with power-profiles-daemon (on newer Ubuntu)
  if systemctl is-enabled power-profiles-daemon &>/dev/null; then
    systemctl disable --now power-profiles-daemon >>"$LOG" 2>&1 || true
  fi

  systemctl enable --now tlp >>"$LOG" 2>&1 || true
  tlp start >>"$LOG" 2>&1 || true
  log "TLP active. (Laptops benefit most; desktops are fine too.)"
}

enable_trim() {
  log "Enabling weekly SSD TRIM…"
  systemctl enable --now fstrim.timer >>"$LOG" 2>&1 || true
  systemctl status fstrim.timer --no-pager || true
}

apt_cleanup() {
  log "Cleaning apt caches and orphans…"
  apt-get -y autoremove >>"$LOG" 2>&1 || true
  apt-get -y autoclean  >>"$LOG" 2>&1 || true
  log "Cleanup complete."
}

xfce_compositor_toggle() {
  local mode="${1:-off}"
  if command -v xfconf-query >/dev/null 2>&1; then
    log "Setting XFCE compositing: $mode"
    if [[ "$mode" == "off" ]]; then
      xfconf-query -c xfwm4 -p /general/use_compositing -s false || true
    else
      xfconf-query -c xfwm4 -p /general/use_compositing -s true || true
    fi
  else
    log "XFCE not detected (xfconf-query missing). Skipping."
  fi
}

show_info() {
  echo "=== System info ==="
  uname -a
  echo
  echo "RAM:"; free -h
  echo
  echo "Swap:"; swapon --show || true
  echo
  echo "Desktop session: $XDG_CURRENT_DESKTOP (if set)"
  echo "==================="
}

revert_changes() {
  log "Reverting UbuSmooth changes…"
  # Revert sysctl
  if [[ -f "${CONF_SYSCTL}.bak" ]]; then
    mv -f "${CONF_SYSCTL}.bak" "$CONF_SYSCTL"
  else
    rm -f "$CONF_SYSCTL"
  fi
  sysctl --system >>"$LOG" 2>&1 || true

  # Disable zram
  systemctl disable --now zramswap.service >>"$LOG" 2>&1 || true
  if [[ -f "${CONF_ZRAM}.bak" ]]; then
    mv -f "${CONF_ZRAM}.bak" "$CONF_ZRAM"
  else
    rm -f "$CONF_ZRAM"
  fi
  swapoff -a || true

  # Restore power-profiles-daemon, stop tlp (optional)
  if systemctl list-unit-files | grep -q power-profiles-daemon; then
    systemctl enable --now power-profiles-daemon >>"$LOG" 2>&1 || true
  fi
  systemctl disable --now tlp >>"$LOG" 2>&1 || true

  # TRIM timer back to distro default (usually enabled anyway)
  systemctl enable --now fstrim.timer >>"$LOG" 2>&1 || true

  log "Revert complete. You may reboot to fully apply."
}

usage() {
  cat <<EOF
UbuSmooth - make Ubuntu feel lighter

Usage:
  sudo bash $0 --all                Apply all recommended tweaks
  sudo bash $0 --info               Show system info
  sudo bash $0 --zram               Enable/configure zram
  sudo bash $0 --kernel             Apply kernel VM tuning
  sudo bash $0 --tlp                Install & enable TLP
  sudo bash $0 --trim               Enable weekly SSD TRIM
  sudo bash $0 --cleanup            Apt cleanup
  sudo bash $0 --xfce-compositor off|on   Toggle XFCE compositing
  sudo bash $0 --revert             Undo changes made by UbuSmooth
  sudo bash $0 --help               This help

Log: $LOG
EOF
}

main() {
  if [[ $# -eq 0 ]]; then usage; exit 0; fi
  require_root

  case "${1:-}" in
    --all)
      enable_zram
      tune_kernel
      install_tlp
      enable_trim
      apt_cleanup
      log "All tweaks applied. Consider logging out/in or rebooting."
      ;;
    --info) show_info ;;
    --zram) enable_zram ;;
    --kernel) tune_kernel ;;
    --tlp) install_tlp ;;
    --trim) enable_trim ;;
    --cleanup) apt_cleanup ;;
    --xfce-compositor)
      shift || true
      xfce_compositor_toggle "${1:-off}"
      ;;
    --revert) revert_changes ;;
    --help|-h) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
