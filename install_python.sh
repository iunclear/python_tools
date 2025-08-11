#!/bin/bash

# 检查是否提供了 Python 版本参数
if [ -z "$1" ]; then
    echo "使用方法: $0 <Python版本号>"
    echo "示例: $0 3.7.4"
    exit 1
fi

PYTHON_VERSION=$1
INSTALL_DIR="/usr/local/python${PYTHON_VERSION%.*}"
TAR_FILE="Python-$PYTHON_VERSION.tar.xz"
SRC_DIR="/tmp/Python-$PYTHON_VERSION"
URL="https://www.python.org/ftp/python/$PYTHON_VERSION/$TAR_FILE"

# 进入 /tmp 目录
cd /tmp || exit

# 下载指定版本的 Python
echo "正在下载 Python $PYTHON_VERSION..."
wget  "$URL"

# 解压
echo "正在解压 $TAR_FILE..."
tar -xf "$TAR_FILE"

# 进入解压后的目录
cd "$SRC_DIR" || exit

# 安装依赖（某些环境可能需要禁用特定的 yum 源）
echo "安装编译依赖..."
yum -y install gcc zlib-devel bzip2-devel openssl-devel ncurses-devel \
    sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel \
    xz-devel libffi-devel zlib* tcl-devel

set -e

# 清理可能存在的编译残留
make distclean || :

# 配置编译选项
echo "配置编译参数..."
./configure --prefix="$INSTALL_DIR" --enable-optimizations

# 获取 CPU 核心数
CPUS=$(nproc)

# 编译并安装
echo "开始编译 (使用 $CPUS 核心)..."
make -j"$CPUS"
make altinstall -j"$CPUS"

# 创建符号链接
echo "创建符号链接..."
ln -sf "$INSTALL_DIR/bin/python${PYTHON_VERSION%.*}" /usr/local/bin/python3
ln -sf "$INSTALL_DIR/bin/pip${PYTHON_VERSION%.*}" /usr/local/bin/pip3

echo "Python $PYTHON_VERSION 安装完成!"
python3 --version
pip3 --version

