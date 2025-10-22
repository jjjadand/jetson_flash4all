# Usage:
脚本放在与`Linux_for_Tegra`文件夹同一级的目录。

```bash
  sudo ./host_run_flash.sh [BOARD_NAME] [flags]
```
第一次刷机，例如：
```bash
  sudo ./host_run_flash.sh recomputer-orin-j401
```
清理刷机后的工作目录：
```bash
  sudo ./host_run_flash.sh recomputer-orin-j401 --rm
```

更多详细输入说明参数：
```bash
  sudo ./host_run_flash.sh -h
```

Valid BOARD_NAME values: （可以刷的设备参数， 第一个参数）
  - recomputer-industrial-orin-j201
  - recomputer-orin-j401
  - reserver-agx-orin-j501x
  - reserver-agx-orin-j501x-gmsl
  - reserver-industrial-orin-j401
  - recomputer-orin-j40mini
  - recomputer-orin-robotics-j401
  - recomputer-orin-robotics-j401-gmsl
  - recomputer-orin-super-j401
  - jetson-orin-nano-devkit
  - jetson-agx-orin-devkit

# Description:
  Wrapper for Jetson Linux initrd flashing with optional build, user preseed,
  and post-flash cleanup. Flags can appear in any order.  

# Flags:
  -h, --help            Show this help and exit  
  -no_build, --no_build Skip kernel/modules build & install (dont use the args at first time，第一次刷机不要启用该参数)  
  -rm, --rm             Cleanup after flashing (preserve Linux_for_Tegra/tools/kernel_flash/initrdlog)  
  -set_user, --set_user Preseed OEM user via tools/l4t_create_default_user.sh  
  --erase-all           Erase target storage before flashing  
  --erase_all           Same as --erase-all  

# Environment overrides:
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

# Examples:
  sudo ./host_run_flash.sh                         # default board, build, no cleanup  
  sudo ./host_run_flash.sh recomputer-orin-j401 -no_build -rm  
  sudo ./host_run_flash.sh -set_user -rm  
  OEM_USER=lee OEM_PASS='p@ss' OEM_HOST=thor sudo ./host_run_flash.sh -set_user --erase-all  

# Notes:
  - The first positional argument, if present, is treated as BOARD_NAME.  
  - If BOARD_NAME is omitted, a default board is used (see script header).  

