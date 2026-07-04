#!/usr/bin/env bash
#
# download.sh - OBS 同步下载模块
#
# 通过 wget 将 OBS 仓库镜像到本地缓存目录。
# 支持按文件类型过滤，节省带宽和磁盘空间。
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib.sh"

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# ============================================================
# 函数: wget_mirror
# 功能: 执行 wget 镜像同步
# 参数: 无（使用全局配置）
# 返回: 0 成功，非 0 失败
# ============================================================
wget_mirror() {
    local accept_list=(
        "*.deb"                # 二进制包
        "*.dsc"                # 源码包描述文件
        "*.orig.tar.*"         # 原始源码 tarball
        "*.debian.tar.*"       # Debian 修改 tarball
        "*.diff.gz"            # Debian diff
        "*.tar.xz"             # 通用源码压缩包
        "*.tar.gz"             # 通用源码压缩包
        "*.tar.bz2"            # 通用源码压缩包
        "Release"              # 仓库 Release 文件
        "Release.gpg"          # GPG 签名的 Release
        "InRelease"            # 内嵌签名的 Release
        "Packages*"            # 包索引（含 .gz/.xz/.bz2）
        "Sources*"             # 源码索引（含 .gz/.xz/.bz2）
        "*.buildinfo"          # 构建信息
        "*.changes"            # 变更文件
    )

    # 构建 accept 列表（逗号分隔，wget -A 格式）
    local IFS=','
    local accept_pattern="${accept_list[*]}"
    IFS=$' \t\n'

    log_info "开始 wget 同步..."
    log_info "源: ${OBS_URL}"
    log_info "目标: ${CACHE_DIR}"

    # 将 WGET_OPTIONS 字符串安全拆分为数组
    local wget_args=()
    # shellcheck disable=SC2206
    read -ra wget_args <<< "${WGET_OPTIONS}"

    wget_args+=(
        --directory-prefix="${CACHE_DIR}"
        -A "${accept_pattern}"
        --no-check-certificate
        --reject="*.iso,*.img,*.raw"
        "${OBS_URL}"
    )

    if run_cmd wget "${wget_args[@]}"; then
        log_success "OBS 同步完成"
        return 0
    else
        log_warn "wget --mirror 模式失败，尝试递归模式..."

        # 回退：使用简单递归下载关键文件
        local fallback_args=(
            -c -r -np -nH --cut-dirs=3 --timeout=60 -q
            --directory-prefix="${CACHE_DIR}"
            -A "${accept_pattern}"
            --no-check-certificate
            --level=5
            "${OBS_URL}"
        )

        if run_cmd wget "${fallback_args[@]}"; then
            log_success "OBS 同步完成（回退模式）"
            return 0
        else
            log_error "OBS 同步失败（主模式和回退模式均失败）"
            return 1
        fi
    fi
}

# ============================================================
# 函数: clean_cache
# 功能: 清理缓存中过时的文件
# 说明: wget 不会自动删除远端已不存在的文件，
#        此函数移除本地有但远端已不存在的 .deb / .dsc
# ============================================================
clean_cache() {
    log_info "清理缓存中无对应元数据的过时文件..."

    # 简单清理策略：删除无对应 Release/Packages 索引的零散文件
    # 更精确的清理依赖仓库元数据，此处暂不实现
    local deb_count
    local dsc_count

    deb_count=$(find "${CACHE_DIR}" -name '*.deb' -type f 2>/dev/null | wc -l)
    dsc_count=$(find "${CACHE_DIR}" -name '*.dsc' -type f 2>/dev/null | wc -l)

    log_info "缓存中 ${deb_count} 个 .deb，${dsc_count} 个 .dsc"
}

# ============================================================
# 函数: show_cache_stats
# 功能: 显示缓存目录统计信息
# ============================================================
show_cache_stats() {
    local file_count
    local total_size

    file_count=$(find "${CACHE_DIR}" -type f 2>/dev/null | wc -l)
    total_size=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1)

    log_info "缓存文件数: ${file_count}"
    log_info "缓存大小: ${total_size}"
}

# ============================================================
# 函数: find_packages
# 功能: 查找缓存目录中的 .deb 文件
# 输出: 文件路径列表（每行一个）
# ============================================================
find_packages() {
    find "${CACHE_DIR}" -name '*.deb' -type f 2>/dev/null
}

# ============================================================
# 函数: find_sources
# 功能: 查找缓存目录中的 .dsc 文件
# 输出: 文件路径列表（每行一个）
# ============================================================
find_sources() {
    find "${CACHE_DIR}" -name '*.dsc' -type f 2>/dev/null
}

# ============================================================
# 主函数
# ============================================================
main() {
    log_info "===== 开始 OBS 仓库同步 ====="

    ensure_log_dir
    ensure_cache_dir

    if ! wget_mirror; then
        exit 1
    fi

    clean_cache
    show_cache_stats
    log_success "===== OBS 仓库同步完成 ====="
}

main "$@"
