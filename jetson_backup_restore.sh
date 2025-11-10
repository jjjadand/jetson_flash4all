#!/usr/bin/env bash
set -euo pipefail

# ===== 白名单载板 =====
VALID_BOARDS=(
  recomputer-industrial-orin-j201
  recomputer-orin-j401
  reserver-agx-orin-j501x
  reserver-agx-orin-j501x-gmsl
  reserver-industrial-orin-j401
  recomputer-orin-j40mini
  recomputer-orin-robotics-j401
  recomputer-orin-robotics-j401-gmsl
  recomputer-orin-super-j401
  jetson-orin-nano-devkit
  jetson-agx-orin-devkit
)

# ===== 默认参数（可用环境变量覆盖）=====
EXTERNAL_DEVICE="${EXTERNAL_DEVICE:-nvme0n1}"   # 目标盘
L4T_DIR="${L4T_DIR:-$(pwd)/Linux_for_Tegra}"    # L4T 目录

print_valid_boards() {
  printf 'Valid BOARD_NAME values:\n'
  for b in "${VALID_BOARDS[@]}"; do printf '  - %s\n' "$b"; done
}

print_usage_and_exit() {
  local code="${1:-0}"
  cat <<EOF
Usage:
  $(basename "$0") -b <BOARD_NAME>     # Backup (备份)
  $(basename "$0") -r <BOARD_NAME>     # Restore (覆盖恢复)
  $(basename "$0") -h                  # Help

Description:
  Wrapper for Linux_for_Tegra backup/restore on Jetson.

Options:
  -b <BOARD_NAME>   Run backup:   sudo ./tools/backup_restore/l4t_backup_restore.sh -e <dev> -b <BOARD_NAME>
  -r <BOARD_NAME>   Run restore:  sudo ./tools/backup_restore/l4t_backup_restore.sh -e <dev> -r <BOARD_NAME>
  -h                Show this help and exit

Environment overrides:
  EXTERNAL_DEVICE   (default: ${EXTERNAL_DEVICE})
  L4T_DIR           (default: ${L4T_DIR})

Examples:
  EXTERNAL_DEVICE=nvme0n1 \\
    $(basename "$0") -b recomputer-orin-j401

  $(basename "$0") -r jetson-agx-orin-devkit

Notes:
  - This script will cd into Linux_for_Tegra before running.
  - Make sure the target is in recovery mode and L4T tools exist.
EOF
  print_valid_boards
  exit "$code"
}

# ===== 解析参数 =====
MODE=""
BOARD_NAME=""

while (( "$#" )); do
  case "${1:-}" in
    -b|-r)
      if [[ -n "$MODE" ]]; then
        echo "ERROR: -b and -r are mutually exclusive." >&2
        print_usage_and_exit 2
      fi
      MODE="$1"
      shift
      BOARD_NAME="${1:-}"
      [[ -z "$BOARD_NAME" ]] && { echo "ERROR: Missing BOARD_NAME for $MODE."; print_usage_and_exit 2; }
      shift
      ;;
    -h|--help)
      print_usage_and_exit 0
      ;;
    *)
      echo "ERROR: Unknown arg: $1" >&2
      print_usage_and_exit 2
      ;;
  esac
done

# ===== 校验板卡名 =====
if [[ -z "$BOARD_NAME" ]]; then
  echo "ERROR: BOARD_NAME required." >&2
  print_usage_and_exit 2
fi

is_valid=false
for b in "${VALID_BOARDS[@]}"; do
  if [[ "$BOARD_NAME" == "$b" ]]; then is_valid=true; break; fi
done
if [[ "$is_valid" != true ]]; then
  echo "ERROR: Invalid BOARD_NAME: '$BOARD_NAME'" >&2
  print_usage_and_exit 2
fi

# ===== 校验 L4T 目录与工具 =====
if [[ ! -d "$L4T_DIR" ]]; then
  echo "ERROR: L4T_DIR not found: $L4T_DIR" >&2
  echo "       Please place this script next to Linux_for_Tegra/ or set L4T_DIR." >&2
  exit 1
fi
if [[ ! -x "$L4T_DIR/tools/backup_restore/l4t_backup_restore.sh" ]]; then
  echo "ERROR: backup tool not found or not executable:" >&2
  echo "       $L4T_DIR/tools/backup_restore/l4t_backup_restore.sh" >&2
  exit 1
fi

# ===== 进入 L4T 并执行 =====
echo "[host] L4T_DIR : $L4T_DIR"
echo "[host] DEVICE  : $EXTERNAL_DEVICE"
echo "[host] BOARD   : $BOARD_NAME"
cd "$L4T_DIR"

case "$MODE" in
  -b)
    echo "[host] Running BACKUP ..."
    set -x
    sudo ./tools/backup_restore/l4t_backup_restore.sh -e "${EXTERNAL_DEVICE}" -b "${BOARD_NAME}"
    set +x
    ;;
  -r)
    echo "[host] Running RESTORE (overwrite) ..."
    set -x
    sudo ./tools/backup_restore/l4t_backup_restore.sh -e "${EXTERNAL_DEVICE}" -r "${BOARD_NAME}"
    set +x
    ;;
  *)
    echo "ERROR: No mode selected. Use -b or -r." >&2
    print_usage_and_exit 2
    ;;
esac

echo "[host] Done."

