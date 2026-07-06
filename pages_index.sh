#!/usr/bin/env bash
#
# pages_index.sh - Cloudflare Pages 目录索引生成器
#
# 职责：
#   遍历 PUBLISH_ROOT（aptly 发布目录），为每个子目录生成
#   index.html 文件，最终输出到 PAGES_OUTPUT_DIR。
#   该目录可直接用 wrangler pages deploy 部署到 Cloudflare Pages。
#
# 生成结构：
#   PAGES_OUTPUT_DIR/
#   ├── index.html          根目录列表
#   ├── dists/
#   │   ├── index.html
#   │   ├── stable/
#   │   │   ├── index.html
#   │   │   └── ...
#   │   └── ...
#   └── pool/
#       ├── index.html
#       └── main/
#           └── index.html
#
# 文件链接指向 R2_PUBLIC_URL，目录链接指向 Pages 自身路径。
#
# 用法：
#   ./pages_index.sh              生成索引
#   ./pages_index.sh --no-deploy  只生成，不部署
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib.sh"

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# ============================================================
# 函数: format_size
# 功能: 将字节数格式化为可读形式
# ============================================================
format_size() {
    local bytes="${1:-0}"
    if   (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "scale=1; ${bytes}/1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "scale=1; ${bytes}/1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "scale=1; ${bytes}/1024" | bc)"
    else
        echo "${bytes} B"
    fi
}

# ============================================================
# 函数: html_header
# 功能: 输出 HTML 页面头部
# 参数:
#   $1 - title: 页面标题
#   $2 - breadcrumb: 面包屑 HTML
# ============================================================
html_header() {
    local title="${1}"
    local breadcrumb="${2}"

    cat <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} — ${PAGES_TITLE}</title>
  <style>
    :root {
      --bg: #0f1117;
      --surface: #1a1d27;
      --border: #2a2d3d;
      --accent: #6c8dfa;
      --accent-dim: #3d5299;
      --text: #e2e4f0;
      --text-dim: #8b8fa8;
      --green: #4ade80;
      --yellow: #fbbf24;
      --red: #f87171;
      --font-mono: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
      --radius: 8px;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 14px;
      line-height: 1.6;
      min-height: 100vh;
    }
    header {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      padding: 16px 24px;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    header .logo {
      width: 32px; height: 32px;
      background: linear-gradient(135deg, var(--accent), #a78bfa);
      border-radius: 8px;
      display: flex; align-items: center; justify-content: center;
      font-size: 18px;
      flex-shrink: 0;
    }
    header h1 { font-size: 16px; font-weight: 600; color: var(--text); }
    header p  { font-size: 12px; color: var(--text-dim); }
    .breadcrumb {
      padding: 12px 24px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      font-size: 13px;
      font-family: var(--font-mono);
    }
    .breadcrumb a { color: var(--accent); text-decoration: none; }
    .breadcrumb a:hover { text-decoration: underline; }
    .breadcrumb span { color: var(--text-dim); margin: 0 6px; }
    main { max-width: 1100px; margin: 0 auto; padding: 24px; }
    .info-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 16px 20px;
      margin-bottom: 20px;
      font-size: 13px;
      color: var(--text-dim);
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .info-card .icon { font-size: 18px; }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--surface);
      border-radius: var(--radius);
      overflow: hidden;
      border: 1px solid var(--border);
    }
    thead tr { background: rgba(108,141,250,0.08); }
    th {
      padding: 12px 16px;
      text-align: left;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--text-dim);
      border-bottom: 1px solid var(--border);
      font-weight: 600;
    }
    td {
      padding: 10px 16px;
      border-bottom: 1px solid rgba(42,45,61,0.6);
      vertical-align: middle;
    }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: rgba(108,141,250,0.04); }
    .icon-cell { width: 36px; }
    .icon-cell span { font-size: 16px; }
    .name-cell a {
      color: var(--accent);
      text-decoration: none;
      font-family: var(--font-mono);
      font-size: 13px;
    }
    .name-cell a:hover { text-decoration: underline; }
    .size-cell { color: var(--text-dim); font-family: var(--font-mono); font-size: 12px; text-align: right; }
    .date-cell { color: var(--text-dim); font-family: var(--font-mono); font-size: 12px; width: 180px; }
    .type-badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 11px;
      font-family: var(--font-mono);
    }
    .type-dir  { background: rgba(108,141,250,0.15); color: var(--accent); }
    .type-deb  { background: rgba(74,222,128,0.12);  color: var(--green); }
    .type-gz   { background: rgba(251,191,36,0.12);  color: var(--yellow); }
    .type-file { background: rgba(139,143,168,0.12); color: var(--text-dim); }
    footer {
      text-align: center;
      padding: 32px 24px;
      color: var(--text-dim);
      font-size: 12px;
      border-top: 1px solid var(--border);
      margin-top: 40px;
    }
    footer a { color: var(--accent-dim); text-decoration: none; }
    footer a:hover { color: var(--accent); }
  </style>
</head>
<body>
<header>
  <div class="logo">📦</div>
  <div>
    <h1>${PAGES_TITLE}</h1>
    <p>${PAGES_DESCRIPTION}</p>
  </div>
</header>
<div class="breadcrumb">${breadcrumb}</div>
<main>
HTML
}

# ============================================================
# 函数: html_footer
# 功能: 输出 HTML 页面尾部
# ============================================================
html_footer() {
    local generated_at
    generated_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    cat <<HTML
</main>
<footer>
  Generated at ${generated_at} by
  <a href="https://github.com/LingmoOS/repo-sync">lingmo repo-sync</a>
  &nbsp;·&nbsp;
  Hosted on <a href="https://pages.cloudflare.com">Cloudflare Pages</a>
  &nbsp;·&nbsp;
  Files served from <a href="https://developers.cloudflare.com/r2/">Cloudflare R2</a>
</footer>
</body>
</html>
HTML
}

# ============================================================
# 函数: get_file_icon
# 功能: 根据文件扩展名返回 emoji 图标和 type badge
# 参数:
#   $1 - is_dir: "true" | "false"
#   $2 - filename
# 输出: "icon type_class"（空格分隔）
# ============================================================
get_file_meta() {
    local is_dir="${1}"
    local fname="${2}"

    if [[ "${is_dir}" == "true" ]]; then
        echo "📁 dir"
        return
    fi

    case "${fname,,}" in
        *.deb)          echo "📦 deb" ;;
        *.dsc)          echo "📄 gz"  ;;
        *.tar.gz|*.tgz) echo "🗜️ gz"  ;;
        *.tar.xz|*.txz) echo "🗜️ gz"  ;;
        *.tar.bz2)      echo "🗜️ gz"  ;;
        release|inrelease|release.gpg) echo "🔑 gz" ;;
        packages*|sources*) echo "📋 gz" ;;
        *.gpg|*.asc)    echo "🔏 gz"  ;;
        *)              echo "📄 file" ;;
    esac
}

# ============================================================
# 函数: build_breadcrumb
# 功能: 根据相对路径生成面包屑 HTML
# 参数:
#   $1 - rel_path: 相对于 PUBLISH_ROOT 的路径（如 dists/stable）
# ============================================================
build_breadcrumb() {
    local rel_path="${1}"

    local crumbs="<a href=\"/\">🏠 root</a>"

    if [[ -n "${rel_path}" ]]; then
        local parts
        IFS='/' read -ra parts <<< "${rel_path}"
        local accumulated=""

        for part in "${parts[@]}"; do
            accumulated="${accumulated:+${accumulated}/}${part}"
            crumbs+="<span>/</span><a href=\"/${accumulated}/\">${part}</a>"
        done
    fi

    echo "${crumbs}"
}

# ============================================================
# 函数: generate_dir_index
# 功能: 为单个目录生成 index.html
# 参数:
#   $1 - abs_dir:  绝对路径（PUBLISH_ROOT 下的目录）
#   $2 - rel_path: 相对路径（用于构建 URL 和面包屑）
# ============================================================
generate_dir_index() {
    local abs_dir="${1}"
    local rel_path="${2}"

    # 输出目录
    local out_dir="${PAGES_OUTPUT_DIR}/${rel_path}"
    mkdir -p "${out_dir}"

    local out_file="${out_dir}/index.html"
    local title="${rel_path:-/}"
    local breadcrumb
    breadcrumb=$(build_breadcrumb "${rel_path}")

    log_info "生成索引: ${rel_path:-/} -> ${out_file}"

    {
        html_header "${title}" "${breadcrumb}"

        # APT 使用说明（仅根目录显示）
        if [[ -z "${rel_path}" ]]; then
            cat <<HTML
<div class="info-card">
  <span class="icon">💡</span>
  <div>
    <strong>APT 软件源配置：</strong>
    将以下内容写入 <code>/etc/apt/sources.list.d/lingmo.list</code><br>
    <code>deb ${R2_PUBLIC_URL} stable main</code>
  </div>
</div>
HTML
        fi

        # 目录/文件列表
        cat <<'HTML'
<table>
  <thead>
    <tr>
      <th class="icon-cell"></th>
      <th>名称</th>
      <th>类型</th>
      <th class="date-cell">修改时间</th>
      <th class="size-cell">大小</th>
    </tr>
  </thead>
  <tbody>
HTML

        # 上级目录链接（非根目录）
        if [[ -n "${rel_path}" ]]; then
            local parent_path
            parent_path=$(dirname "${rel_path}")
            [[ "${parent_path}" == "." ]] && parent_path=""
            local parent_url="/${parent_path}/"
            echo "    <tr>"
            echo "      <td class=\"icon-cell\"><span>⬆️</span></td>"
            echo "      <td class=\"name-cell\"><a href=\"${parent_url}\">..</a></td>"
            echo "      <td></td><td class=\"date-cell\"></td><td class=\"size-cell\"></td>"
            echo "    </tr>"
        fi

        # 遍历目录内容：先目录后文件，按名称排序
        local entries=()
        while IFS= read -r entry; do
            entries+=("${entry}")
        done < <(
            # 目录优先
            find "${abs_dir}" -maxdepth 1 -mindepth 1 -type d | sort
            find "${abs_dir}" -maxdepth 1 -mindepth 1 -type f | sort
        )

        for entry in "${entries[@]}"; do
            local fname
            fname=$(basename "${entry}")
            local is_dir="false"
            local entry_url

            if [[ -d "${entry}" ]]; then
                is_dir="true"
                entry_url="${fname}/"
            else
                # 文件链接指向 R2 公开 URL
                if [[ -n "${rel_path}" ]]; then
                    entry_url="${R2_PUBLIC_URL}/${rel_path}/${fname}"
                else
                    entry_url="${R2_PUBLIC_URL}/${fname}"
                fi
            fi

            local icon type_class
            read -r icon type_class <<< "$(get_file_meta "${is_dir}" "${fname}")"

            local mtime size_str
            mtime=$(stat -c '%y' "${entry}" 2>/dev/null | cut -d'.' -f1 || echo "-")
            if [[ "${is_dir}" == "true" ]]; then
                size_str="—"
            else
                local bytes
                bytes=$(stat -c '%s' "${entry}" 2>/dev/null || echo "0")
                size_str=$(format_size "${bytes}")
            fi

            echo "    <tr>"
            echo "      <td class=\"icon-cell\"><span>${icon}</span></td>"
            echo "      <td class=\"name-cell\"><a href=\"${entry_url}\">${fname}</a></td>"
            echo "      <td><span class=\"type-badge type-${type_class}\">${type_class}</span></td>"
            echo "      <td class=\"date-cell\">${mtime}</td>"
            echo "      <td class=\"size-cell\">${size_str}</td>"
            echo "    </tr>"
        done

        echo "  </tbody>"
        echo "</table>"
        html_footer

    } > "${out_file}"
}

# ============================================================
# 函数: generate_all_indexes
# 功能: 递归遍历 PUBLISH_ROOT，为每个目录生成 index.html
# ============================================================
generate_all_indexes() {
    log_info "遍历目录树: ${PUBLISH_ROOT}"

    # 清空输出目录
    rm -rf "${PAGES_OUTPUT_DIR}"
    mkdir -p "${PAGES_OUTPUT_DIR}"

    local dir_count=0

    # 生成根目录索引
    generate_dir_index "${PUBLISH_ROOT}" ""
    ((dir_count++)) || true

    # 递归生成子目录索引
    while IFS= read -r abs_dir; do
        # 计算相对路径
        local rel_path="${abs_dir#"${PUBLISH_ROOT}"/}"

        generate_dir_index "${abs_dir}" "${rel_path}"
        ((dir_count++)) || true
    done < <(find "${PUBLISH_ROOT}" -mindepth 1 -type d | sort)

    log_success "共生成 ${dir_count} 个索引文件 -> ${PAGES_OUTPUT_DIR}"
}

# ============================================================
# 函数: generate_404
# 功能: 生成 404.html（Cloudflare Pages 特性）
# ============================================================
generate_404() {
    cat > "${PAGES_OUTPUT_DIR}/404.html" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>404 Not Found — ${PAGES_TITLE}</title>
  <style>
    body { background:#0f1117; color:#e2e4f0; font-family:sans-serif;
           display:flex; align-items:center; justify-content:center;
           min-height:100vh; flex-direction:column; gap:16px; }
    h1 { font-size:64px; color:#6c8dfa; }
    p  { color:#8b8fa8; }
    a  { color:#6c8dfa; }
  </style>
</head>
<body>
  <h1>404</h1>
  <p>找不到该页面</p>
  <p><a href="/">← 返回首页</a></p>
</body>
</html>
HTML
    log_info "已生成 404.html"
}

# ============================================================
# 函数: generate_redirects
# 功能: 生成 _redirects 文件（Cloudflare Pages 路由规则）
#       将 /dists/<dist>/ 请求重定向到 R2 文件
# ============================================================
generate_redirects() {
    local out="${PAGES_OUTPUT_DIR}/_redirects"

    {
        echo "# Cloudflare Pages 重定向规则"
        echo "# 将 .deb / Release 等文件请求重定向到 R2 公开地址"
        echo ""

        # 将 pool/ 下的 .deb 文件请求转发到 R2
        echo "/pool/*  ${R2_PUBLIC_URL}/pool/:splat  200"

        # 将 dists/ 下的文件（非目录）转发到 R2
        # Pages 的 index.html 会处理目录浏览，文件则转发到 R2
        echo "/dists/*  ${R2_PUBLIC_URL}/dists/:splat  200"

    } > "${out}"

    log_info "已生成 _redirects"
}

# ============================================================
# 函数: deploy_to_pages
# 功能: 使用 wrangler 部署到 Cloudflare Pages
# ============================================================
deploy_to_pages() {
    log_info "===== 部署到 Cloudflare Pages ====="

    if ! command -v wrangler &>/dev/null; then
        log_error "wrangler 未安装，请先安装: npm install -g wrangler"
        return 1
    fi

    if [[ -z "${CF_PAGES_PROJECT:-}" ]]; then
        log_error "CF_PAGES_PROJECT 未设置"
        return 1
    fi

    log_info "项目: ${CF_PAGES_PROJECT}"
    log_info "分支: ${CF_PAGES_BRANCH}"
    log_info "目录: ${PAGES_OUTPUT_DIR}"

    run_cmd wrangler pages deploy \
        "${PAGES_OUTPUT_DIR}" \
        --project-name "${CF_PAGES_PROJECT}" \
        --branch "${CF_PAGES_BRANCH}" \
        --commit-dirty true

    log_success "Pages 部署完成"
}

# ============================================================
# 主函数
# ============================================================
main() {
    local no_deploy="false"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --no-deploy)
                no_deploy="true"
                shift
                ;;
            -h|--help)
                echo "用法: $0 [--no-deploy]"
                echo "  --no-deploy  只生成索引，不部署到 Pages"
                exit 0
                ;;
            *)
                log_warn "未知参数: ${1}"
                shift
                ;;
        esac
    done

    ensure_log_dir

    log_info "===== 开始生成 Pages 目录索引 ====="

    if [[ "${PAGES_ENABLED:-false}" != "true" ]]; then
        log_warn "Pages 索引生成未启用（PAGES_ENABLED=false），跳过"
        log_warn "如需启用，请在 config.sh 中设置 PAGES_ENABLED=true"
        exit 0
    fi

    # 检查 PUBLISH_ROOT
    if [[ ! -d "${PUBLISH_ROOT}" ]]; then
        log_error "PUBLISH_ROOT 不存在: ${PUBLISH_ROOT}"
        exit 1
    fi

    # 检查依赖
    if ! command -v bc &>/dev/null; then
        log_warn "bc 未安装，文件大小显示可能不准确"
    fi

    # 生成所有目录索引
    generate_all_indexes

    # 生成辅助文件
    generate_404
    generate_redirects

    log_success "Pages 静态文件已生成: ${PAGES_OUTPUT_DIR}"
    log_info "文件数: $(find "${PAGES_OUTPUT_DIR}" -type f | wc -l)"

    # 部署
    if [[ "${no_deploy}" != "true" ]]; then
        deploy_to_pages
    else
        log_info "跳过部署（--no-deploy）"
        log_info "手动部署命令:"
        log_info "  wrangler pages deploy ${PAGES_OUTPUT_DIR} --project-name ${CF_PAGES_PROJECT}"
    fi

    log_success "===== Pages 索引生成完成 ====="
}

main "$@"
