#!/usr/bin/env bash
#
# download.sh - OBS 同步下载模块
#
# 通过 lftp mirror 将 OBS 仓库镜像到本地缓存目录。
# 支持断点续传、并行下载、按文件类型过滤。
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib.sh"

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# ============================================================
# 函数: lftp_mirror
# 功能: 执行 lftp mirror 同步
# 参数: 无（使用全局配置）
# 返回: 0 成功，非 0 失败
# ============================================================
lftp_mirror() {
    local host remote_path
    host=$(echo "${OBS_URL}" | sed -n 's|^https\?://\([^/]*\).*|\1|p')
    remote_path=$(echo "${OBS_URL}" | sed -n 's|^https\?://[^/]*\(/.*\)|\1|p')
    remote_path="${remote_path%/}"

    log_info "开始 lftp mirror 同步..."
    log_info "主机: ${host}"
    log_info "远程路径: ${remote_path}"
    log_info "本地缓存: ${CACHE_DIR}"

    # 构建 lftp 脚本
    # 使用 heredoc 避免复杂的引号转义
    lftp << EOF
open https://${host}
mirror \
    --continue \
    --parallel=8 \
    --verbose \
    --exclude-glob=*.iso \
    --exclude-glob=*.img \
    --exclude-glob=*.raw \
    --exclude-glob=index.html* \
    "${remote_path}" \
    "${CACHE_DIR}"
quit
EOF

    local ret=$?
    if [[ $ret -eq 0 ]]; then
        log_success "OBS 同步完成"
        return 0
    else
        log_error "OBS 同步失败 (lftp exit code: ${ret})"
        return 1
    fi
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

    if ! lftp_mirror; then
        exit 1
    fi

    show_cache_stats
    log_success "===== OBS 仓库同步完成 ====="
}

main "$@"
