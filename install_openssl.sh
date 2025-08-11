#!/usr/bin/env bash
# 一键编译安装指定版本 OpenSSL（兼容 CentOS 7+/RHEL、Ubuntu/Debian）
# 用法:
#   sudo bash install_openssl.sh 3.3.1
#   sudo bash install_openssl.sh 1.1.1w --prefix /usr/local/openssl-1.1 --force-link
#
# 选项:
#   --prefix <DIR>     安装目录（默认 /usr/local/openssl）
#   --force-link       用软链替换系统 /usr/bin/openssl（谨慎！）
#   --no-color         关闭彩色输出

set -euo pipefail

# -------- 彩色输出 --------
if [[ "${2:-}" == "--no-color" || "${3:-}" == "--no-color" || "${4:-}" == "--no-color" ]]; then
  RED=""; GRN=""; YLW=""; BLU=""; NRM=""
else
  RED="\033[31m"; GRN="\033[32m"; YLW="\033[33m"; BLU="\033[34m"; NRM="\033[0m"
fi
log() { echo -e "${BLU}>>>${NRM} $*"; }
ok()  { echo -e "${GRN}[OK]${NRM} $*"; }
warn(){ echo -e "${YLW}[WARN]${NRM} $*"; }
err() { echo -e "${RED}[ERR]${NRM} $*" >&2; }

# -------- 参数 --------
if [[ $# -lt 1 ]]; then
  err "用法: $0 <OpenSSL版本号> [--prefix DIR] [--force-link]"
  exit 1
fi
OPENSSL_VERSION="$1"; shift || true
PREFIX="/usr/local/openssl"
FORCE_LINK="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --force-link) FORCE_LINK="yes"; shift ;;
    --no-color) shift ;; # 已处理
    *) err "未知参数: $1"; exit 1 ;;
  esac
done

# 提取主次版本，用于 old 目录兜底。例: 1.1.1w -> 1.1.1
BASE_SERIES="${OPENSSL_VERSION%%[[:alpha:]]*}"

SRC_DIR="/usr/local/src"
BUILD_DIR="${SRC_DIR}/openssl-${OPENSSL_VERSION}"
TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"

# -------- 检测包管理器 --------
PKG=""
if command -v yum >/dev/null 2>&1; then
  PKG="yum"
elif command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
elif command -v apt-get >/dev/null 2>&1; then
  PKG="apt"
else
  err "未检测到 yum/dnf/apt-get，请手动安装依赖后再试"
  exit 1
fi
ok "包管理器: ${PKG}"

# -------- 安装依赖 --------
log "安装构建依赖..."
case "$PKG" in
  yum|dnf)
    # 兼容 CentOS 7：gcc make perl wget tar zlib-devel ca-certificates
    sudo $PKG -y install gcc make perl wget tar zlib-devel ca-certificates || true
    # 可选：CentOS 7 旧 GCC 如遇到更高标准要求，可启用 devtoolset（按需手动）
    ;;
  apt)
    sudo apt-get update -y
    sudo apt-get install -y build-essential perl wget tar zlib1g-dev ca-certificates
    ;;
esac
ok "依赖安装完成"

# -------- 下载源码（带 old 目录兜底）--------
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

DOWNLOAD_OK=0
URLS=(
  "https://www.openssl.org/source/${TARBALL}"
  "https://www.openssl.org/source/old/${BASE_SERIES}/${TARBALL}"
)
for u in "${URLS[@]}"; do
  log "尝试下载: $u"
  if wget -q --show-progress "$u" -O "$TARBALL"; then
    DOWNLOAD_OK=1; ok "下载成功: $u"; break
  else
    warn "下载失败: $u"
  fi
done
if [[ $DOWNLOAD_OK -ne 1 ]]; then
  err "无法下载 ${TARBALL}，请检查版本号是否存在。可去 https://www.openssl.org/source/ 查询。"
  exit 1
fi

# -------- 解压并编译安装 --------
log "解压源码..."
rm -rf "$BUILD_DIR"
tar xzf "$TARBALL"
cd "$BUILD_DIR"

log "配置编译参数..."
# shared: 生成共享库；zlib: 使用系统 zlib；--openssldir 指定配置/证书目录
./config --prefix="${PREFIX}" --openssldir="${PREFIX}" shared zlib

log "开始编译（并行: $(nproc)）..."
make -j"$(nproc)"

log "安装..."
sudo make install

# -------- 配置动态库与 PATH --------
log "写入动态库路径并 ldconfig..."
echo "${PREFIX}/lib" | sudo tee "/etc/ld.so.conf.d/openssl-${OPENSSL_VERSION}.conf" >/dev/null
sudo ldconfig

# 将新 openssl 放入 PATH（更安全的方式，避免直接覆盖系统文件）
PROFILE_SNIPPET="/etc/profile.d/openssl-${OPENSSL_VERSION}.sh"
if [[ ! -f "${PROFILE_SNIPPET}" ]]; then
  echo "export PATH=${PREFIX}/bin:\$PATH" | sudo tee "${PROFILE_SNIPPET}" >/dev/null
  ok "已写入 PATH 配置: ${PROFILE_SNIPPET}（重新登录或 source 生效）"
else
  warn "PATH 配置已存在: ${PROFILE_SNIPPET}"
fi

# 可选：强制软链替换系统 /usr/bin/openssl（谨慎）
if [[ "${FORCE_LINK}" == "yes" ]]; then
  if [[ -x /usr/bin/openssl && ! -L /usr/bin/openssl ]]; then
    sudo mv /usr/bin/openssl /usr/bin/openssl.bak.$(date +%Y%m%d%H%M%S)
    warn "已备份原系统 /usr/bin/openssl"
  fi
  sudo ln -sf "${PREFIX}/bin/openssl" /usr/bin/openssl
  ok "已用软链替换系统 /usr/bin/openssl -> ${PREFIX}/bin/openssl"
else
  warn "未替换系统 /usr/bin/openssl。通过 PATH 优先级使用新版本，或带 --force-link 参数执行以替换。"
fi

# -------- 验证 --------
echo
ok "安装完成！版本信息："
"${PREFIX}/bin/openssl" version -a || true
echo
echo "当前会话使用新版本可执行："
echo "  export PATH=${PREFIX}/bin:\$PATH && openssl version"
