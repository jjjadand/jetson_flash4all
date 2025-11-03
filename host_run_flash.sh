#!/usr/bin/env bash
set -euo pipefail

# ===== 合法板卡名白名单 =====
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
)

# ===== 使用说明（echo 全英文）=====
print_valid_boards() {
  printf 'Valid BOARD_NAME values:\n'
  for b in "${VALID_BOARDS[@]}"; do printf '  - %s\n' "$b"; done
}

print_usage_and_exit() {
  local code="${1:-0}"
  cat <<'EOF'
Usage:
  sudo ./host_run_flash.sh [BOARD_NAME] [flags]

Description:
  Wrapper for Jetson Linux initrd flashing with optional build, user preseed,
  and post-flash cleanup. Flags can appear in any order.

Flags:
  -h, --help            Show this help and exit
  -no_build, --no_build Skip kernel/modules build & install (Step 2)
  -rm, --rm             Cleanup after flashing (preserve Linux_for_Tegra/tools/kernel_flash/initrdlog)
  -set_user, --set_user Preseed OEM user via tools/l4t_create_default_user.sh
  --erase-all           Erase target storage before flashing
  --erase_all           Same as --erase-all

Environment overrides:
  EXTERNAL_DEVICE   (default: nvme0n1p1)
  XML_CONFIG        (default: tools/kernel_flash/flash_l4t_t234_nvme.xml)
  QSPI_CFG          (default: -c bootloader/generic/cfg/flash_t234_qspi.xml)
  NETWORK_IF        (default: usb0)
  CLEAN_AFTER       (default: 0; set 1 to enable cleanup, or use -rm)
  APPLY_BINARIES    (default: 1; run apply_binaries.sh when 1)

  # Preseed user variables (effective only with -set_user/--set_user)
  OEM_USER          (default: seeed)
  OEM_PASS          (default: seeed)
  OEM_HOST          (default: ubuntu)
  OEM_ADD_SUDO      (default: 1; when 1 pass -a)
  OEM_ACCEPT_LICENSE(default: 1; when 1 pass --accept-license)

Examples:
  sudo ./host_run_flash.sh                         # default board, build, no cleanup
  sudo ./host_run_flash.sh recomputer-orin-j401 -no_build -rm
  sudo ./host_run_flash.sh -set_user -rm
  OEM_USER=lee OEM_PASS='p@ss' OEM_HOST=thor sudo ./host_run_flash.sh -set_user --erase-all

Notes:
  - The first positional argument, if present, is treated as BOARD_NAME.
  - If BOARD_NAME is omitted, a default board is used (see script header).
EOF
  print_valid_boards
  exit "$code"
}

# ===== 提前捕获 -h/--help，允许任意位置出现 =====
for arg in "$@"; do
  case "$arg" in
    -h|--help) print_usage_and_exit 0 ;;
  esac
done

# ===== 预置用户（仅当传入 -set_user/--set_user 时启用）=====
# 可在此处修改默认用户/密码/主机名
PRESEED_USER=0                           # 只有 -set_user/--set_user 才会置为 1
OEM_USER=${OEM_USER:-seeed}
OEM_PASS=${OEM_PASS:-seeed}
OEM_HOST=${OEM_HOST:-ubuntu}
OEM_ADD_SUDO=${OEM_ADD_SUDO:-1}          # 1: 传 -a
OEM_ACCEPT_LICENSE=${OEM_ACCEPT_LICENSE:-1}  # 1: 传 --accept-license

# ===== 解析板卡名（可选位置参数）并校验 =====
DEFAULT_BOARD=recomputer-orin-super-j401
BOARD_NAME="${1:-$DEFAULT_BOARD}"
is_valid=false; for b in "${VALID_BOARDS[@]}"; do [[ "$BOARD_NAME" == "$b" ]] && is_valid=true && break; done
if [[ "$is_valid" != true ]]; then
  echo "ERROR: Invalid BOARD_NAME: '$BOARD_NAME'"
  print_usage_and_exit 2
fi

# ===== 工作路径：脚本所在目录即工作目录 =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
L4T_DIR="$BASE_DIR/Linux_for_Tegra"
TOOLCHAIN_ROOT="$BASE_DIR/aarch64--glibc--stable-2022.08-1"
TOOLCHAIN_BIN="$TOOLCHAIN_ROOT/bin"

# ===== 其他可配参数（可用 env 覆盖）=====
EXTERNAL_DEVICE="${EXTERNAL_DEVICE:-nvme0n1p1}"
XML_CONFIG="${XML_CONFIG:-tools/kernel_flash/flash_l4t_t234_nvme.xml}"
QSPI_CFG="${QSPI_CFG:--c bootloader/generic/cfg/flash_t234_qspi.xml}"
NETWORK_IF="${NETWORK_IF:-usb0}"
CLEAN_AFTER="${CLEAN_AFTER:-0}"          # 1: 刷完清理；0: 不清理
APPLY_BINARIES="${APPLY_BINARIES:-1}"    # 1: 执行 apply_binaries.sh；0: 跳过

# ===== 解析标志参数（保持单板名位置参数不变）=====
NO_BUILD=0
CLEAN_FLAG=0
for arg in "${@:2}"; do
  case "$arg" in
    -no_build|--no_build) NO_BUILD=1 ;;
    -rm|--rm)             CLEAN_FLAG=1 ;;
    -set_user|--set_user) PRESEED_USER=1 ;;
    -h|--help)            print_usage_and_exit 0 ;;
    --erase-all|--erase_all) : ;; # handled later, just allow here
    *) : ;;
  esac
done
# CLEAN_AFTER 既可通过 env 也可通过 -rm 触发
if [[ "$CLEAN_FLAG" == "1" ]]; then CLEAN_AFTER=1; fi

echo "[host] BASE_DIR: $BASE_DIR"
echo "[host] L4T_DIR : $L4T_DIR"
echo "[host] BOARD   : $BOARD_NAME"

# =======================
# Step 0: 检查工程与工具链路径
# =======================
if [[ ! -d "$L4T_DIR" || ! -d "$L4T_DIR/tools" ]]; then
  echo "ERROR: $L4T_DIR not found. Please ensure 'Linux_for_Tegra' is extracted beside this script."
  exit 1
fi
if [[ ! -d "$TOOLCHAIN_ROOT" ]]; then
  echo "WARNING: Toolchain dir not found: $TOOLCHAIN_ROOT"
  echo "         Will rely on system-wide CROSS_COMPILE/ARCH/PATH if preset."
fi

# =======================
# Step 0.5: 自动设置交叉环境变量（工具链与脚本同目录）
# =======================
if [[ -x "$TOOLCHAIN_BIN/aarch64-buildroot-linux-gnu-gcc" ]]; then
  export ARCH=arm64
  export CROSS_COMPILE="$TOOLCHAIN_BIN/aarch64-buildroot-linux-gnu-"
  export PATH="$TOOLCHAIN_BIN:$PATH"
  echo "[host] Using toolchain: $TOOLCHAIN_BIN"
else
  echo "WARNING: aarch64 toolchain not found at: $TOOLCHAIN_BIN"
  echo "         Make sure 'aarch64--glibc--stable-2022.08-1' is extracted beside this script,"
  echo "         or provide system-wide CROSS_COMPILE/ARCH/PATH."
fi
echo "[host] ARCH=${ARCH-<unset>}  CROSS_COMPILE=${CROSS_COMPILE-<unset>}"

# =======================
# Step 1: 安装宿主依赖（编译/刷机必需）
# =======================
echo "[host] Step 1.0: install host dependencies ..."
sudo apt-get update -y
sudo apt-get install -y \
  build-essential flex bison libssl-dev \
  sshpass abootimg nfs-kernel-server \
  libxml2-utils qemu-user-static

# Step 1.1: run apply_binaries.sh (non-fatal)
if [[ "$APPLY_BINARIES" == "1" ]]; then
  if [[ -x "$L4T_DIR/apply_binaries.sh" ]]; then
    echo "[host] Step 1.1: run apply_binaries.sh (APPLY_BINARIES=1) ..."
    (
      set +e
      cd "$L4T_DIR"
      sudo ./apply_binaries.sh
      rc=$?
      set -e
      if [[ $rc -ne 0 ]]; then
        echo "WARNING: apply_binaries.sh exited with code $rc; continuing."
      fi
    )
  else
    echo "WARNING: $L4T_DIR/apply_binaries.sh not found; skip."
  fi
else
  echo "[host] Step 1.1: skip apply_binaries.sh (pre-integrated rootfs)"
fi

# =======================
# Step 2: 编译源码（默认执行；传 -no_build 跳过）
# =======================
if [[ "$NO_BUILD" == "0" ]]; then
  echo "[host] Step 2: kernel/modules build & install"

  echo "[host] Step 2.0: run nvbuild.sh ..."
  if [[ -x "$L4T_DIR/source/nvbuild.sh" ]]; then
    ( cd "$L4T_DIR/source" && ./nvbuild.sh )
  else
    echo "WARNING: $L4T_DIR/source/nvbuild.sh not found or not executable; skipping."
  fi

  echo "[host] Step 2.1: run do_copy.sh ..."
  if [[ -x "$L4T_DIR/source/do_copy.sh" ]]; then
    ( cd "$L4T_DIR/source" && ./nvbuild.sh ) || true
    ( cd "$L4T_DIR/source" && ./do_copy.sh )
  else
    echo "WARNING: $L4T_DIR/source/do_copy.sh not found or not executable; skipping."
  fi

  INSTALL_MOD_PATH="$L4T_DIR/rootfs"
  if [[ ! -d "$INSTALL_MOD_PATH" ]]; then
    echo "ERROR: $INSTALL_MOD_PATH not found; rootfs is required for module install." >&2
    exit 1
  fi
  export INSTALL_MOD_PATH
  echo "[host] Step 2.2: INSTALL_MOD_PATH=$INSTALL_MOD_PATH"

  echo "[host] Step 2.3: run nvbuild.sh -i ..."
  if [[ -x "$L4T_DIR/source/nvbuild.sh" ]]; then
    ( cd "$L4T_DIR/source" && ./nvbuild.sh -i )
  else
    echo "ERROR: $L4T_DIR/source/nvbuild.sh not found or not executable." >&2
    exit 1
  fi
else
  echo "[host] -no_build specified, skip Step 2 (kernel/modules build & install)."
fi

# =======================
# Step 3: 刷机（在刷机前可选择预置用户）
# =======================

# 预置用户：仅当 PRESEED_USER=1 且工具存在
if [[ "$PRESEED_USER" == "1" ]]; then
  TOOL="$L4T_DIR/tools/l4t_create_default_user.sh"
  if [[ -x "$TOOL" ]]; then
    # 组装参数
    args=(-u "$OEM_USER" -p "$OEM_PASS" -n "$OEM_HOST")
    [[ "$OEM_ADD_SUDO" == "1" ]] && args+=(-a)
    [[ "$OEM_ACCEPT_LICENSE" == "1" ]] && args+=(--accept-license)
    echo "[host] Preseed OEM user: user=$OEM_USER host=$OEM_HOST sudo=$OEM_ADD_SUDO"
    ( cd "$L4T_DIR/tools" && sudo ./l4t_create_default_user.sh "${args[@]}" )
  else
    echo "WARNING: $TOOL not found or not executable; skip user preseed."
  fi
else
  echo "[host] Preseed user disabled (use -set_user to enable)."
fi

# 检测是否要求整盘擦除
ERASE_ALL_FLAG=0
for arg in "$@"; do
  case "$arg" in
    --erase-all|--erase_all) ERASE_ALL_FLAG=1 ;;
  esac
done

echo
echo "=== Flashing on host (BOARD: $BOARD_NAME) from $L4T_DIR ==="
cd "$L4T_DIR"

# 组装刷机命令（只执行一次）
FLASH_CMD=(sudo ./tools/kernel_flash/l4t_initrd_flash.sh
  --external-device "${EXTERNAL_DEVICE}"
  -c "${XML_CONFIG}"
  -p "${QSPI_CFG}"
  --showlogs
  --network "${NETWORK_IF}"
)

if [[ "$ERASE_ALL_FLAG" == "1" ]]; then
  echo "[host] --erase-all enabled: target storage will be erased before flashing."
  FLASH_CMD+=(--erase-all)
else
  echo "[host] --erase-all not set: flashing without full device erase."
fi

FLASH_CMD+=("${BOARD_NAME}" internal)
"${FLASH_CMD[@]}"
echo "=== Flash finished ==="

# =======================
# Step 4: 清理，仅保留原路径的 initrdlog
# =======================
if [[ "${CLEAN_AFTER}" == "1" ]]; then
  KEEP_DIR="$L4T_DIR/tools/kernel_flash/initrdlog"
  echo "[host] Cleaning $L4T_DIR (preserving $KEEP_DIR) ..."
  SAVE_DIR="$(mktemp -d)"
  if [[ -d "$KEEP_DIR" ]]; then
    rsync -aHAX "$KEEP_DIR/" "$SAVE_DIR/initrdlog/"
  fi
  sudo rm -rf "$L4T_DIR"
  mkdir -p "$KEEP_DIR"
  if [[ -d "$SAVE_DIR/initrdlog" ]]; then
    rsync -aHAX "$SAVE_DIR/initrdlog/" "$KEEP_DIR/"
  fi
  rm -rf "$SAVE_DIR"
  echo "[host] Cleanup done. Logs preserved at: $KEEP_DIR"
else
  echo "[host] Cleanup skipped. Logs remain in $L4T_DIR/tools/kernel_flash/initrdlog"
fi
