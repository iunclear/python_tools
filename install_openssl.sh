#!/bin/bash
#
# 一键编译安装指定版本 OpenSSL（CentOS 7 专用）
# 用法: ./install_openssl.sh 1.1.1w
#

set -e

if [ -z "$1" ]; then
    echo "用法: $0 <OpenSSL版本号> 例如: $0 1.1.1w"
    exit 1
fi

OPENSSL_VERSION="$1"
INSTALL_DIR="/usr/local/openssl"

echo ">>> 安装依赖..."
yum install -y wget tar gcc make perl zlib-devel

echo ">>> 下载 OpenSSL ${OPENSSL_VERSION} ..."
cd /usr/local/src
wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz

echo ">>> 解压..."
tar xvf openssl-${OPENSSL_VERSION}.tar.gz
cd openssl-${OPENSSL_VERSION}

echo ">>> 编译安装..."
./config --prefix=${INSTALL_DIR} --openssldir=${INSTALL_DIR} shared zlib
make -j"$(nproc)"
make install

echo ">>> 配置系统环境..."
echo "${INSTALL_DIR}/lib" > /etc/ld.so.conf.d/openssl-${OPENSSL_VERSION}.conf
ldconfig

if [ -f /usr/bin/openssl ]; then
    mv /usr/bin/openssl /usr/bin/openssl.bak
fi
ln -sf ${INSTALL_DIR}/bin/openssl /usr/bin/openssl

echo ">>> 验证版本..."
openssl version -a

echo ">>> 安装完成"
