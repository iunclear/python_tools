#!/usr/bin/env bash
# 一键编译安装指定版本 OpenSSL（CentOS 7 + Ubuntu/Debian 兼容）
# 用法:
#   sudo bash install_openssl.sh 1.1.1w
#   sudo bash install_openssl.sh 3.3.1 --prefix /usr/local/openssl-3 --force-link

set -euo pipefail

# ---------- 参数 ----------
if [[ $# -lt 1 ]]; then
  echo "用法: $0 <OpenSSL版本号> [--prefix DIR] [--force-link]"
  exit 1
fi
OPENSSL_VERSION="$1"; shift || true
PREFIX="/usr/local/openssl"
FORCE_LINK="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --force-link) FORCE_LINK="yes"; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

BASE_SERIES="${OPENSSL_VERSION%%[[:alpha:]]*}"    # 1.1.1w -> 1.1.1 ; 3.3.1 -> 3.3.1
SRC_DIR="/usr/local/src"
TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
OUT="${TARBALL}"

# ---------- 小工具 ----------
RED="\033[31m"; GRN="\033[32m"; YLW="\033[33m"; BLU="\033[34m"; NRM="\033[0m"
log(){ echo -e "${BLU}>>>${NRM} $*"; }
ok(){  echo -e "${GRN}[OK]${NRM} $*"; }
warn(){ echo -e "${YLW}[WARN]${NRM} $*"; }
err(){ echo -e "${RED}[ERR]${NRM} $*" >&2; }

nprocs() { command -v nproc >/dev/null 2>&1 && nproc || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1; }

fetch() {
  # 兼容老 wget（无 --show-progress），优先 curl
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 10 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=10 "$url" -O "$out"
  else
    return 127
  fi
}

# ---------- 包管理器与依赖 ----------
PKG=""
if command -v yum >/dev/null 2>&1; then PKG="yum"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v apt-get >/dev/null 2>&1; then PKG="apt"
else err "未检测到 yum/dnf/apt-get"; exit 1; fi
ok "包管理器: $PKG"

log "安装构建依赖..."
case "$PKG" in
  yum|dnf) sudo $PKG -y install gcc make perl wget curl tar zlib-devel ca-certificates || true ;;
  apt)     sudo apt-get update -y && sudo apt-get install -y build-essential perl wget curl tar zlib1g-dev ca-certificates ;;
esac
ok "依赖安装完成"

# ---------- 下载源码（含 old/ftp 兜底） ----------
mkdir -p "$SRC_DIR"; cd "$SRC_DIR"
URLS=(
  "https://www.openssl.org/source/${TARBALL}"
  "https://www.openssl.org/source/old/${BASE_SERIES}/${TARBALL}"
  "https://ftp.openssl.org/source/old/${BASE_SERIES}/${TARBALL}"
)
SUCCESS=0
for u in "${URLS[@]}"; do
  log "尝试下载: $u"
  if fetch "$u" "$OUT"; then
    ok "下载成功: $u"
    SUCCESS=1; break
  else
    warn "下载失败: $u"
  fi
done
if [[ $SUCCESS -ne 1 ]]; then
  err "无法下载 ${TARBALL}；请核对版本（如 1.1.1w/3.3.1）。也可检查网络/代理/证书。"
  exit 1
fi

# ---------- 解压编译安装 ----------
rm -rf openssl-src && mkdir -p openssl-src
tar xzf "$OUT" -C openssl-src --strip-components=1
cd openssl-src

log "配置编译参数..."
./config --prefix="${PREFIX}" --openssldir="${PREFIX}" shared zlib

log "开始编译（并行 $(nprocs)）..."
make -j"$(nprocs)"

log "安装..."
sudo make install

# ---------- 动态库与 PATH ----------
echo "${PREFIX}/lib" | sudo tee "/etc/ld.so.conf.d/openssl-${OPENSSL_VERSION}.conf" >/dev/null
sudo ldconfig

PROFILE_SNIPPET="/etc/profile.d/openssl-${OPENSSL_VERSION}.sh"
if [[ ! -f "$PROFILE_SNIPPET" ]]; then
  echo "export PATH=${PREFIX}/bin:\$PATH" | sudo tee "$PROFILE_SNIPPET" >/dev/null
  ok "已写入 PATH: $PROFILE_SNIPPET（重新登录或 source 生效）"
fi

# 可选：替换 /usr/bin/openssl（谨慎）
if [[ "$FORCE_LINK" == "yes" ]]; then
  if [[ -x /usr/bin/openssl && ! -L /usr/bin/openssl ]]; then
    sudo mv /usr/bin/openssl /usr/bin/openssl.bak.$(date +%Y%m%d%H%M%S)
    warn "已备份系统 /usr/bin/openssl"
  fi
  sudo ln -sf "${PREFIX}/bin/openssl" /usr/bin/openssl
  ok "已软链替换 /usr/bin/openssl"
else
  warn "未替换系统 openssl；通过 PATH 优先使用新版本。"
fi

ok "安装完成：$("${PREFIX}/bin/openssl" version -a | head -n1)"
echo "当前会话可临时启用：export PATH=${PREFIX}/bin:\$PATH && openssl version"
