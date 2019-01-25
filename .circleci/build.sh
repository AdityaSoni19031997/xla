#!/bin/bash

set -ex

source ./env

export MAX_JOBS=8

SCCACHE="$(which sccache)"
if [ -z "${SCCACHE}" ]; then
  echo "Unable to find sccache..."
  exit 1
fi

if which sccache > /dev/null; then
  # Save sccache logs to file
  sccache --stop-server || true
  rm ~/sccache_error.log || true
  SCCACHE_ERROR_LOG=~/sccache_error.log RUST_LOG=sccache::server=error sccache --start-server

  # Report sccache stats for easier debugging
  sccache --zero-stats
fi

# setup sccache wrappers
#if hash sccache 2>/dev/null; then
#    SCCACHE_BIN_DIR="/tmp/sccache"
#    mkdir -p "$SCCACHE_BIN_DIR"
#    for compiler in cc c++ gcc g++ x86_64-linux-gnu-gcc; do
#        (
#            echo "#!/bin/sh"
#            echo "exec $(which sccache) $(which $compiler) \"\$@\""
#        ) > "$SCCACHE_BIN_DIR/$compiler"
#        chmod +x "$SCCACHE_BIN_DIR/$compiler"
#    done
#    export PATH="$SCCACHE_BIN_DIR:$PATH"
#fi

PYTORCH_DIR=/tmp/pytorch
XLA_DIR="$PYTORCH_DIR/xla"
git clone --recursive --quiet https://github.com/pytorch/pytorch.git "$PYTORCH_DIR"
cp -r "$PWD" "$XLA_DIR"

cd $PYTORCH_DIR

# Install ninja to speedup the build
pip install ninja

# Install Pytorch
patch -p1 < xla/pytorch.patch
DEBUG=1 python setup.py build develop

# Bazel doesn't work with sccache gcc. https://github.com/bazelbuild/bazel/issues/3642
sudo add-apt-repository "deb http://apt.llvm.org/trusty/ llvm-toolchain-trusty-7 main"
wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key|sudo apt-key add -
sudo apt-get -qq update

sudo apt-get -qq install clang-7 clang++-7
# Bazel dependencies
sudo apt-get -qq install pkg-config zip zlib1g-dev unzip
# XLA build requires Bazel
wget https://github.com/bazelbuild/bazel/releases/download/0.21.0/bazel-0.21.0-installer-linux-x86_64.sh
chmod +x bazel-*.sh
sudo ./bazel-*.sh
BAZEL="$(which bazel)"
if [ -z "${BAZEL}" ]; then
  echo "Unable to find bazel..."
  exit 1
fi

# Install bazels3cache for cloud cache
sudo apt-get -qq install npm
npm config set strict-ssl false
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
sudo apt-get install -qq nodejs
sudo npm install -g bazels3cache
BAZELS3CACHE="$(which bazels3cache)"
if [ -z "${BAZELS3CACHE}" ]; then
  echo "Unable to find bazels3cache..."
  exit 1
fi

bazels3cache --bucket=${XLA_CACHE_S3_BUCKET_NAME} --maxEntrySizeBytes=0 --logging.level=verbose

# install XLA
pushd "$XLA_DIR"
# Use cloud cache to build when available.
sed -i '/bazel build/ a --remote_http_cache=http://localhost:7777 \\' build_torch_xla_libs.sh

export CC=clang-7 CXX=clang++-7
python setup.py install
popd