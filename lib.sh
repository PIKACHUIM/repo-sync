#!/usr/bin/env bash
#
# lib.sh - 共享函数库
#
# 包含所有模块共用的：
#   日志输出（彩色 + 文件）
#   错误处理
#   配置验证
#   依赖检查
#   工具函数
#

# ============================================================
# 颜色定义（仅在终端支持时启用）
# ============================================================
# shellcheck disable=SC2034
# CYAN 在 sync.sh 中使用
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
fi

# ============================================================
# 路径常量
# ============================================================

# 日志文件（按日期）
LOG_DATE=$(date '+%Y-%m-%d')
readonly LOG_DATE
readonly LOG_FILE="${LOG_DIR}/repo-sync-${LOG_DATE}.log"

# ============================================================
# 错误处理
# ============================================================

# 全局错误处理函数
# 通过 trap ERR 调用，输出行号和失败命令
handle_error() {
    local line="${1}"
    local cmd="${2}"
    log_error "脚本在行 ${line} 执行失败: ${cmd}"
    exit 1
}

# ============================================================
# 日志函数
# ============================================================

# 确保日志目录存在
ensure_log_dir() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        mkdir -p "${LOG_DIR}"
    fi
}

# 日志通用函数（内部使用）
_log() {
    local level="${1}"
    local color="${2}"
    shift 2
    local log_time
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    local msg
    msg="[${level}] ${log_time} - $*"
    echo -e "${color}${msg}${NC}"
    echo -e "${msg}" >> "${LOG_FILE}"
}

# INFO 级别日志（蓝色）
log_info() {
    _log "INFO" "${BLUE}" "$@"
}

# WARN 级别日志（黄色）
log_warn() {
    _log "WARN" "${YELLOW}" "$@"
}

# ERROR 级别日志（红色 >&2）
log_error() {
    local log_time
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    local msg
    msg="[ERROR] ${log_time} - $*"
    echo -e "${RED}${msg}${NC}" >&2
    echo -e "${msg}" >> "${LOG_FILE}"
}

# SUCCESS 级别日志（绿色）
log_success() {
    _log "SUCCESS" "${GREEN}" "$@"
}

# ============================================================
# 工具函数
# ============================================================

# 获取当前时间戳（UTC，格式：YYYYMMDD-HHMMSS）
get_timestamp() {
    date -u '+%Y%m%d-%H%M%S'
}

# 安全的命令执行函数
# 用法：run_cmd command [args...]
# 自动记录执行的命令，失败时记录错误并返回非零
run_cmd() {
    local cmd_str="$*"
    log_info "执行: ${cmd_str}"
    if ! "$@"; then
        log_error "命令执行失败: ${cmd_str}"
        return 1
    fi
}

# ============================================================
# 依赖检查
# ============================================================

# 检查所有必需的依赖工具
check_dependencies() {
    local deps=("wget" "aptly" "gpg" "gzip" "bzip2" "xz")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少依赖工具: ${missing[*]}"
        log_error "请安装: apt-get install -y ${missing[*]}"
        exit 1
    fi

    log_info "所有依赖检查通过"
}

# ============================================================
# 配置验证
# ============================================================

# 验证 config.sh 中的关键配置项
validate_config() {
    local errors=()

    # 检查必要配置
    if [[ -z "${OBS_URL:-}" ]]; then
        errors+=("OBS_URL 未设置")
    fi

    if [[ -z "${CACHE_DIR:-}" ]]; then
        errors+=("CACHE_DIR 未设置")
    fi

    # 检查仓库配置
    if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
        errors+=("REPO_NAMES 未配置任何仓库")
    fi

    if [[ ${#DISTRIBUTIONS[@]} -eq 0 ]]; then
        errors+=("DISTRIBUTIONS 未配置")
    fi

    if [[ ${#REPO_NAMES[@]} -ne ${#DISTRIBUTIONS[@]} ]]; then
        errors+=("REPO_NAMES (${#REPO_NAMES[@]}) 与 DISTRIBUTIONS (${#DISTRIBUTIONS[@]}) 数量不匹配")
    fi

    # 检查架构配置
    if [[ ${#ARCHS[@]} -eq 0 ]]; then
        errors+=("ARCHS 未配置任何架构")
    fi

    # 检查 GPG 配置
    if [[ "${SIGN:-false}" == "true" ]]; then
        if [[ -z "${GPG_KEY:-}" ]]; then
            errors+=("SIGN=true 但 GPG_KEY 未设置")
        fi
        if ! gpg --list-key "${GPG_KEY}" &>/dev/null; then
            errors+=("GPG 密钥不存在: ${GPG_KEY}")
        fi
    fi

    # 输出错误并退出
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "配置验证失败:"
        local err
        for err in "${errors[@]}"; do
            log_error "  - ${err}"
        done
        exit 1
    fi

    log_success "配置验证通过"
}

# ============================================================
# 目录管理
# ============================================================

# 确保缓存目录存在
ensure_cache_dir() {
    if [[ ! -d "${CACHE_DIR}" ]]; then
        mkdir -p "${CACHE_DIR}"
        log_info "创建缓存目录: ${CACHE_DIR}"
    fi
}

# ============================================================
# 辅助判断函数
# ============================================================

# 检查 aptly 仓库是否存在
aptly_repo_exists() {
    local name="${1}"
    aptly repo show "${name}" &>/dev/null
}

# 检查 aptly Snapshot 是否存在
aptly_snapshot_exists() {
    local name="${1}"
    aptly snapshot show "${name}" &>/dev/null
}

# 检查是否有已发布的版本
aptly_publish_exists() {
    local dist="${1}"
    local prefix="${2:-.}"
    aptly publish list -raw | grep -q "^${prefix} ${dist}\b"
}
