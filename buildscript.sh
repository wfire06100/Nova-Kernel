#!/usr/bin/env bash

set -euo pipefail

# ════════════════════════════════════════════════════════════════
#  🔥 NovaKernel Unified Build Script
# ════════════════════════════════════════════════════════════════

export IN_GHA="${GITHUB_ACTIONS:-false}"

# ────────────────────────────────────────────────────────────────
#  § 1 — CONFIGURATION (الروابط والإعدادات)
# ────────────────────────────────────────────────────────────────

export CLANGVER="clang-r563880c"
export CLANG_URL="https://github.com/OmarAlsmehan/Android-tools/releases/download/clang-r563880c-1/clang-r563880c.tar.gz"
export MAGISK_API_URL="https://api.github.com/repos/topjohnwu/Magisk/releases"
export AVBTOOL_URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT"
export DEFAULT_KSU_REPO="https://github.com/OmarAlsmehan/KernelSU-Next.git"

# AnyKernel3 Config (ضع رابط الـ Fork الخاص بك هنا)
export ANYKERNEL3_URL="https://github.com/osm0sis/AnyKernel3.git"
export ANYKERNEL3_BRANCH="master"

export BRANCH="android11"
export KMI_GENERATION=2
export DEFCONF="rio_defconfig"

# Device Maps
declare -A DEVICE_IMAGE_URLS=(
    ["A73"]="https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_ODM/A736BXXSAGZA1_kernel.tar"
    ["A52S"]="https://github.com/RisenID/proprietary_vendor_samsung_a52sxq/releases/download/A528BXXUAGXK8_BTU/A528BXXUAGXK8_kernel.tar"
    ["M52"]="https://github.com/nicodotgit/proprietary_vendor_samsung_m52xq/releases/download/M526BXXS7CYE1_CAU/M526BXXS7CYE1_kernel.tar"
)

declare -A DEVICE_MAP=(
    ["a73xq"]="A73"
    ["a52sxq"]="A52S"
    ["m52xq"]="M52"
)

# Hooks URLs
declare -A HOOK_SOURCES=(
    ["scope-min-1.6"]="https://raw.githubusercontent.com/OmarAlsmehan/Random-stuff/refs/heads/main/scope-min-manual-hook.1.6-5.4.patch"
    ["rksu"]="https://raw.githubusercontent.com/rksuorg/kernel_patches/refs/heads/master/manual_hook/kernel-4.19_5.4.patch"
    ["syscall"]="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh"
    ["inline"]="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh"
)

export BACKPORT_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/backport_patches.sh"


# ────────────────────────────────────────────────────────────────
#  § 2 — UTILS & LOGGING (أدوات التسجيل)
# ────────────────────────────────────────────────────────────────

BOLD="\e[1m"; RESET="\e[0m"; DIM="\e[2m"
CYAN="\e[1;36m"; GREEN="\e[1;32m"; YELLOW="\e[1;33m"; RED="\e[1;31m"

log_group_start() {
    if [[ "$IN_GHA" == "true" ]]; then
        echo "::group::$1  $2"
    else
        echo -e "\n${CYAN}${BOLD}╔════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║  $1  $2${RESET}"
        echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${RESET}"
    fi
}
log_group_end() { [[ "$IN_GHA" == "true" ]] && echo "::endgroup::" || echo ""; }
log_notice()    { [[ "$IN_GHA" == "true" ]] && echo "::notice::$1" || true; }
log_warn()      { echo -e "${YELLOW}  ⚠   $1${RESET}"; [[ "$IN_GHA" == "true" ]] && echo "::warning::$1" || true; }
log_err()       { echo -e "${RED}${BOLD}  ✖   $1${RESET}" >&2; [[ "$IN_GHA" == "true" ]] && echo "::error::$1" || true; exit 1; }
log_step()      { echo -e "${GREEN}${BOLD}  ➤  $1${RESET}"; }
log_info()      { echo -e "${DIM}       $1${RESET}"; }
log_ok()        { echo -e "${GREEN}  ✔   $1${RESET}"; }
log_sep()       { echo -e "${DIM}  ────────────────────────────────────────${RESET}"; }
elapsed()       { date -u -d @$(( $(date +%s) - $1 )) +'%-Mm %-Ss'; }

check_dependencies() {
    log_group_start "🔍" "Dependency Check"
    local missing=false
    for tool in git curl wget unzip tar lz4 awk sed zip patch; do
        if ! command -v "$tool" &>/dev/null; then log_err "Missing: '$tool'"; missing=true; fi
    done
    $missing && log_err "Install missing tools and retry."
    log_ok "All dependencies satisfied"
    log_group_end
}


# ────────────────────────────────────────────────────────────────
#  § 3 — DEFCONFIG MANAGER
# ────────────────────────────────────────────────────────────────

set_config() {
    local config=$1; local value=$2
    local target_file="$SRC_DIR/arch/arm64/configs/$FRAG"
    [[ ! -f "$target_file" ]] && target_file="$SRC_DIR/arch/arm64/configs/$DEFCONF"
    sed -i "/^${config}=/d; /^# ${config} is not set/d" "$target_file"
    echo "${config}=${value}" >> "$target_file"
}

remove_config() {
    local config=$1
    local target_file="$SRC_DIR/arch/arm64/configs/$FRAG"
    [[ ! -f "$target_file" ]] && target_file="$SRC_DIR/arch/arm64/configs/$DEFCONF"
    sed -i "/^${config}=/d; /^# ${config} is not set/d" "$target_file"
}

inject_ksu_configs() {
    local hook_type=$1
    log_step "Injecting KernelSU configurations ($hook_type)..."

    set_config "CONFIG_KSU" "y"
    remove_config "CONFIG_KSU_MANUAL_HOOK"
    remove_config "CONFIG_KPROBES"
    remove_config "CONFIG_HAVE_KPROBES"
    remove_config "CONFIG_KPROBE_EVENTS"

    case "$hook_type" in
        kprobes)
            set_config "CONFIG_KPROBES" "y"
            set_config "CONFIG_HAVE_KPROBES" "y"
            set_config "CONFIG_KPROBE_EVENTS" "y"
            ;;
        scope-min-1.6|rksu|syscall|inline)
            set_config "CONFIG_KSU_MANUAL_HOOK" "y"
            ;;
    esac
    log_ok "Defconfig successfully updated"
}


# ────────────────────────────────────────────────────────────────
#  § 4 — HOOKS & KSU ENGINE
# ────────────────────────────────────────────────────────────────

apply_hook() {
    local type=$1
    if [[ "$type" == "kprobes" ]]; then
        log_info "Hook: kprobes — no code patches needed"
        return
    fi

    log_group_start "🪝" "Hook Patches [$type]"
    local T0=$(date +%s)

    if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
        log_warn "Hook already detected — skipping"
        log_group_end; return
    fi

    local url="${HOOK_SOURCES[$type]:-}"
    [[ -z "$url" ]] && log_err "Unknown hook type: $type"

    local filename="${url##*/}"
    local dest="$TC_DIR/$filename"

    log_step "Downloading $type..."
    wget -q "$url" -O "$dest"

    if [[ "$dest" == *.patch ]]; then
        patch -p1 -d "$SRC_DIR" < "$dest"
    elif [[ "$dest" == *.sh ]]; then
        chmod +x "$dest" && ( cd "$SRC_DIR" && bash "$dest" )
    fi

    log_ok "Hook applied in $(elapsed $T0)"
    log_group_end
}

apply_backport() {
    log_group_start "⬆️" "Backport Patches"
    if grep -q "path_umount" "$SRC_DIR/fs/namespace.c" 2>/dev/null; then
        log_warn "Backport already applied — skipping"
    else
        local script="$TC_DIR/backport.sh"
        wget -q "$BACKPORT_URL" -O "$script"
        chmod +x "$script" && ( cd "$SRC_DIR" && bash "$script" )
        log_ok "Backport applied"
    fi
    log_group_end
}

setup_kernelsu() {
    log_group_start "⚡" "KernelSU Setup"
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    rm -rf KernelSU
    git clone -b "${NK_KSU_BRANCH:-legacy}" "${NK_KSU_REPO:-$DEFAULT_KSU_REPO}" KernelSU
    log_ok "KernelSU integrated"
    log_group_end
}


# ────────────────────────────────────────────────────────────────
#  § 5 — BUILD PHASES (البناء)
# ────────────────────────────────────────────────────────────────

fetch_tools() {
    log_group_start "🧰" "Toolchain & Assets"
    mkdir -p "$TC_DIR/images"

    if [[ ! -d "$CLANG_PREBUILT_BIN" ]]; then
        log_step "Downloading Clang..."
        wget -q "$CLANG_URL" -O "$TC_DIR/clang.tar.gz"
        mkdir -p "$TC_DIR/$CLANGVER" && tar xf "$TC_DIR/clang.tar.gz" -C "$TC_DIR/$CLANGVER"
        rm "$TC_DIR/clang.tar.gz"
    fi

    [[ ! -f "$TC_DIR/magiskboot" ]] && wget -qO- "$MAGISK_API_URL" | grep -oE 'https://[^"]+\.apk' | grep 'Magisk[-.]v' | head -n1 | xargs wget -qO "$TC_DIR/magisk.apk" && unzip -p "$TC_DIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TC_DIR/magiskboot" && chmod +x "$TC_DIR/magiskboot" && rm "$TC_DIR/magisk.apk"
    [[ ! -f "$TC_DIR/avbtool" ]] && wget -qO "$TC_DIR/avbtool" "$AVBTOOL_URL" && chmod +x "$TC_DIR/avbtool"

    for name in "${!DEVICE_IMAGE_URLS[@]}"; do
        if [[ ! -d "$TC_DIR/images/$name" ]]; then
            mkdir -p "$TC_DIR/images/$name"
            wget -qO- "${DEVICE_IMAGE_URLS[$name]}" | tar xf - -C "$TC_DIR/images/$name"
            lz4 -dm --rm "$TC_DIR/images/$name/"* 2>/dev/null || true
        fi
    done
    log_ok "Tools ready"
    log_group_end
}

build_kernel() {
    log_group_start "🔨" "Kernel Compile"
    local T0=$(date +%s)
    
    # ── 1. Basic Variables ──
    export VARIANT="$NK_VARIANT"
    export DEVICE="${DEVICE_MAP[$VARIANT]}"
    export FRAG="${VARIANT}.config"
    export BUILD_TYPE=$([[ "$NK_KSU" == "true" ]] && echo "KSU" || echo "GKI")
    
    # ── 2. Compiler & Make Flags ──
    export ARCH=arm64
    export LLVM=1
    export DEPMOD=depmod
    export KCFLAGS="-D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1
    export IN_KERNEL_MODULES=1
    export INSTALL_MOD_STRIP=1

    # ── 3. GKI & KMI Settings (Android 11 / 5.4) ──
    export ABI_DEFINITION="android/abi_gki_aarch64.xml"
    export KMI_SYMBOL_LIST="android/abi_gki_aarch64"
    export ADDITIONAL_KMI_SYMBOL_LISTS="
android/abi_gki_aarch64_cuttlefish
android/abi_gki_aarch64_db845c
android/abi_gki_aarch64_exynos
android/abi_gki_aarch64_exynosauto
android/abi_gki_aarch64_fcnt
android/abi_gki_aarch64_galaxy
android/abi_gki_aarch64_goldfish
android/abi_gki_aarch64_hikey960
android/abi_gki_aarch64_imx
android/abi_gki_aarch64_oneplus
android/abi_gki_aarch64_microsoft
android/abi_gki_aarch64_oplus
android/abi_gki_aarch64_qcom
android/abi_gki_aarch64_sony
android/abi_gki_aarch64_sonywalkman
android/abi_gki_aarch64_sunxi
android/abi_gki_aarch64_trimble
android/abi_gki_aarch64_unisoc
android/abi_gki_aarch64_vivo
android/abi_gki_aarch64_xiaomi
android/abi_gki_aarch64_zebra
"
    export TRIM_NONLISTED_KMI=0
    export KMI_SYMBOL_LIST_ADD_ONLY=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export KMI_ENFORCED=0

    # ── 4. Local Version ──
    COMREV=$(git rev-parse --short HEAD)
    export LOCALVERSION="-NovaKernel-${BRANCH}-${KMI_GENERATION}-${COMREV}-${VARIANT}"

    # ── 5. KSU Defconfig Injection ──
    [[ "$NK_KSU" == "true" ]] && inject_ksu_configs "${NK_HOOK_TYPE:-kprobes}"

    # ── 6. Build Info Logging ──
    log_sep
    log_kv "Device:"    "$DEVICE ($VARIANT)"
    log_kv "Type:"      "$BUILD_TYPE"
    if [[ "$BUILD_TYPE" == "KSU" ]]; then
        log_kv "KSU Branch:" "${NK_KSU_BRANCH:-legacy}"
        log_kv "Hook:"       "${NK_HOOK_TYPE:-kprobes}"
    fi
    log_kv "Version:"   "5.4.x$LOCALVERSION"
    log_kv "Toolchain:" "$(clang --version | head -n1)"
    log_kv "Jobs:"      "$JOBS"
    log_sep

    # ── 7. Compilation Steps ──
    log_step "make clean..."
    [[ -d "$OUT_DIR" ]] && make -j"$JOBS" O="$OUT_DIR" clean >/dev/null

    log_step "make defconfig..."
    make -j"$JOBS" O="$OUT_DIR" "$DEFCONF" "$FRAG" >/dev/null

    log_step "make kernel..."
    make -j"$JOBS" O="$OUT_DIR" >/dev/null
    
    log_ok "Kernel compiled in $(elapsed $T0)"
    log_group_end
}

build_modules() {
    log_group_start "📦" "Modules"
    make -j"$JOBS" O="$OUT_DIR" INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install >/dev/null
    local MODOUT="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE/modules"
    mkdir -p "$MODOUT"
    find "$OUT_DIR/modules" -name '*.ko' -exec cp '{}' "$MODOUT/" \;
    log_ok "Modules extracted"
    log_group_end
}

stage_artifacts() {
    log_group_start "🗂️" "Staging Artifacts"
    mkdir -p "$TC_DIR/NovaKernel/$DEVICE/ZIP/META-INF/com/google/android" "$TC_DIR/NovaKernel/$DEVICE/ZIP/images"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$TC_DIR/NovaKernel/$DEVICE/kernel"
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE/dtbo.img"
    cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$TC_DIR/NovaKernel/$DEVICE/dtb"
    log_ok "Images Staged"
    log_group_end
}

gki_repack() {
    log_group_start "🖼️" "Image Repack"
    local DEST="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    mkdir -p "$DEST"

    # Boot
    cp "$TC_DIR/images/$DEVICE/boot.img" "$DEST/boot.img"
    avbtool erase_footer --image "$DEST/boot.img"
    (
        mkdir -p "$DEST/tmp" && cd "$DEST/tmp"
        magiskboot unpack ../boot.img >/dev/null
        rm kernel && cp "$OUT_DIR/arch/arm64/boot/Image" kernel
        magiskboot repack ../boot.img boot.img >/dev/null
        mv boot.img ../boot.img && cd .. && rm -rf tmp
    )

    # Vendor Boot
    cp "$TC_DIR/images/$DEVICE/vendor_boot.img" "$DEST/vendor_boot.img"
    avbtool erase_footer --image "$DEST/vendor_boot.img"
    (
        mkdir -p "$DEST/tmp" && cd "$DEST/tmp"
        magiskboot unpack -h ../vendor_boot.img >/dev/null || true
        sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header
        [[ "${DEBUG:-false}" == "true" ]] && sed -i '2 s/$/ androidboot.selinux=permissive/' header
        rm dtb && cp "$TC_DIR/NovaKernel/$DEVICE/dtb" dtb
        
        magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom" >/dev/null
        awk 'BEGIN{OFS="\t"} /^(system|vendor|product|odm)\s/&&!seen[$1]++ {rest=$4;for(i=5;i<=NF;i++)rest=rest"\t"$i; for(i=1;i<=3;i++) print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest;next}1' fstab.qcom > fstab.qcom.new

        declare -a cpio_todo=("rm first_stage_ramdisk/fstab.qcom" "add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom.new" "rm -r lib/modules" "mkdir 0755 lib/modules")
        for f in "$DEST/modules/"*; do cpio_todo+=("add 0644 lib/modules/$(basename "$f") $f"); done
        
        magiskboot cpio ramdisk.cpio "${cpio_todo[@]}" >/dev/null
        magiskboot repack ../vendor_boot.img vendor_boot.img >/dev/null
        mv vendor_boot.img ../vendor_boot.img && cd .. && rm -rf tmp
    )
    log_ok "Images repacked successfully"
    log_group_end
}

# ────────────────────────────────────────────────────────────────
#  § 6 — PACKAGING (التحزيم: AK3 أو عادي)
# ────────────────────────────────────────────────────────────────

gen_anykernel_zip() {
    log_group_start "📦" "Packaging with AnyKernel3"
    local SRC="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    local AK3_DIR="$TC_DIR/NovaKernel/$DEVICE/AnyKernel3"
    local ZIP_DIR="$TC_DIR/NovaKernel/$DEVICE/ZIP"
    
    local ZIPNAME="NovaKernel_$(date +%Y%m%d)_${BUILD_TYPE}_${VARIANT}_AK3.zip"

    log_step "Cloning AnyKernel3 repo..."
    rm -rf "$AK3_DIR"
    git clone --depth=1 -b "$ANYKERNEL3_BRANCH" "$ANYKERNEL3_URL" "$AK3_DIR" >/dev/null 2>&1
    rm -rf "$AK3_DIR/.git" "$AK3_DIR/README.md"

    log_step "Copying images to AnyKernel3..."
    cp -a "$SRC/boot.img"        "$AK3_DIR/"
    cp -a "$SRC/dtbo.img"        "$AK3_DIR/"
    cp -a "$SRC/vendor_boot.img" "$AK3_DIR/"

    log_step "Compressing AnyKernel3 ZIP..."
    mkdir -p "$ZIP_DIR"
    ( cd "$AK3_DIR"; zip -r -9 "$ZIP_DIR/$ZIPNAME" ./* >/dev/null )

    log_notice "AnyKernel3 ZIP Ready: $ZIPNAME"
    log_group_end
}

gen_zip() {
    log_group_start "🤐" "Packaging (Legacy)"
    local SRC="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    local ZIP_DIR="$TC_DIR/NovaKernel/$DEVICE/ZIP"
    
    cp -a "$SRC/boot.img" "$SRC/dtbo.img" "$SRC/vendor_boot.img" "$ZIP_DIR/images/"
    local ZIPNAME="NovaKernel_$(date +%Y%m%d)_${BUILD_TYPE}_${VARIANT}.zip"
    
    ( cd "$ZIP_DIR"; zip -r -9 "$SRC/$ZIPNAME" images META-INF >/dev/null )
    log_notice "Legacy ZIP Ready: $ZIPNAME"
    log_group_end
}


# ────────────────────────────────────────────────────────────────
#  § 7 — INTERACTIVE & MAIN 
# ────────────────────────────────────────────────────────────────

prompt_inputs() {
    [[ "$IN_GHA" == "true" ]] && return

    if [[ -z "${NK_VARIANT:-}" ]]; then
        echo -e "\n${CYAN}Select target device:${RESET}"
        echo "  [1] Galaxy A73 5G  (a73xq)"
        echo "  [2] Galaxy A52s 5G (a52sxq)"
        echo "  [3] Galaxy M52 5G  (m52xq)"
        read -rp "→ Choice [1-3]: " choice
        case "$choice" in 1) NK_VARIANT="a73xq";; 2) NK_VARIANT="a52sxq";; 3) NK_VARIANT="m52xq";; *) log_err "Invalid choice";; esac
    fi

    if [[ -z "${NK_KSU:-}" ]]; then
        echo -e "\n${CYAN}Build with KernelSU?${RESET}"
        read -rp "→ (y/N): " choice
        [[ "$choice" =~ ^[Yy]$ ]] && NK_KSU="true" || NK_KSU="false"
    fi

    if [[ "$NK_KSU" == "true" && -z "${NK_HOOK_TYPE:-}" ]]; then
        echo -e "\n${CYAN}Select Hook Type:${RESET}"
        local i=1; local keys=("kprobes" "scope-min-1.6" "rksu" "syscall" "inline")
        for k in "${keys[@]}"; do echo "  [$i] $k"; ((i++)); done
        read -rp "→ Choice: " choice
        NK_HOOK_TYPE="${keys[$((choice-1))]}"
    fi

    if [[ -z "${NK_USE_AK3:-}" ]]; then
        echo -e "\n${CYAN}Package with AnyKernel3? (Recommended)${RESET}"
        read -rp "→ (Y/n): " choice
        [[ "$choice" =~ ^[Nn]$ ]] && NK_USE_AK3="false" || NK_USE_AK3="true"
    fi
}

main() {
    if [[ "${1:-}" == "clean" ]]; then rm -rf out/ ~/toolchains/NovaKernel; exit 0; fi

    check_dependencies

    export SRC_DIR="$(pwd)"
    export OUT_DIR="$SRC_DIR/out"
    export TC_DIR="$HOME/toolchains"
    export JOBS=$(nproc)
    export CLANG_PREBUILT_BIN="$TC_DIR/$CLANGVER/bin/"
    export PATH="$TC_DIR:$CLANG_PREBUILT_BIN:$PATH"

    prompt_inputs

    export NK_VARIANT="${NK_VARIANT:-a73xq}"
    export NK_KSU="${NK_KSU:-false}"
    export USE_ANYKERNEL3="${NK_USE_AK3:-true}"

    fetch_tools

    if [[ "$NK_KSU" == "true" ]]; then
        setup_kernelsu
        apply_hook "${NK_HOOK_TYPE:-kprobes}"
        [[ "${NK_BACKPORT:-false}" == "true" ]] && apply_backport
    fi

    build_kernel
    build_modules
    stage_artifacts
    gki_repack
    
    if [[ "$USE_ANYKERNEL3" == "true" ]]; then
        gen_anykernel_zip
    else
        gen_zip
    fi

    log_notice "✅ Pipeline Finished for ${DEVICE_MAP[$NK_VARIANT]}"
}

main "$@"