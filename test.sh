#!/usr/bin/env bash
set -euo pipefail

########################################
# 路径 & 通用变量
########################################

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="${ROOT_DIR}/release"

DATE_STR="$(date +%Y%m%d)"

# 本番 Docker 包
SERVER_RELEASE_NAME="audience-sensing-${DATE_STR}"
SERVER_WORK_DIR="${RELEASE_DIR}/${SERVER_RELEASE_NAME}"
SERVER_TAR_PATH="${RELEASE_DIR}/${SERVER_RELEASE_NAME}.tar.gz"

# Windows Mock 包
MOCK_RELEASE_NAME="AudienceSensingMock_${DATE_STR}"
MOCK_WORK_DIR="${RELEASE_DIR}/${MOCK_RELEASE_NAME}"
MOCK_ZIP_PATH="${RELEASE_DIR}/${MOCK_RELEASE_NAME}.zip"

mkdir -p "${RELEASE_DIR}"

echo "ROOT_DIR    = ${ROOT_DIR}"
echo "RELEASE_DIR = ${RELEASE_DIR}"
echo "DATE_STR    = ${DATE_STR}"
echo

########################################
# 1. 本番 Docker 包
########################################
build_server_package() {
  echo ">>> [Server] 构建本番 Docker 发布包..."

  rm -rf "${SERVER_WORK_DIR}"
  mkdir -p "${SERVER_WORK_DIR}"

  echo ">>> [Server] 复制 compose.yml 和 scripts/*.sh ..."
  cp "${ROOT_DIR}/compose.yml" "${SERVER_WORK_DIR}/"

  # 只复制 scripts 下面的脚本文件，不复制整个目录
  mkdir -p "${SERVER_WORK_DIR}/scripts"
  cp "${ROOT_DIR}"/scripts/*.sh "${SERVER_WORK_DIR}/scripts/" 2>/dev/null || true

  echo ">>> [Server] 导出 Docker 镜像为 tar..."
  docker save -o "${SERVER_WORK_DIR}/audience-sensing-server.tar" "audience-sensing-server:latest"
  docker save -o "${SERVER_WORK_DIR}/audience-sensing.tar"         "audience-sensing:latest"

  echo ">>> [Server] 打包 audience-sensing-YYYYMMDD.tar.gz ..."
  (
    cd "${RELEASE_DIR}"
    tar czf "${SERVER_RELEASE_NAME}.tar.gz" "${SERVER_RELEASE_NAME}"
  )

  echo ">>> [Server] 完成: ${SERVER_TAR_PATH}"
  echo
}

########################################
# 2. gRPC Mock Exe + ZIP
########################################
build_grpc_mock_package() {
  echo ">>> [Mock] 构建 gRPC Windows Mock 包..."

  if ! command -v pyinstaller >/dev/null 2>&1; then
    echo "!!! 未找到 pyinstaller，请先安装： pip install pyinstaller" >&2
    exit 1
  fi

  rm -rf "${MOCK_WORK_DIR}"
  mkdir -p "${MOCK_WORK_DIR}"

  cd "${ROOT_DIR}"
  rm -rf build dist *.spec || true

  ########################################
  # 临时 wrapper: server.exe
  ########################################
  TMP_SERVER_WRAPPER="$(mktemp "${ROOT_DIR}/server_wrapper_XXXX.py")"
  cat > "${TMP_SERVER_WRAPPER}" << 'EOF'
import os, sys, runpy
from pathlib import Path

def get_root():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

ROOT = get_root()
import app.server  # noqa

def main():
    os.chdir(ROOT)
    sys.argv = ["server", "--grpc", os.environ.get("INTERVAL", "100")]
    runpy.run_module("app.server", run_name="__main__")

if __name__ == "__main__":
    main()
EOF

  echo ">>> [Mock] 构建 server.exe ..."
  pyinstaller --onefile --name server "${TMP_SERVER_WRAPPER}"
  rm -f "${TMP_SERVER_WRAPPER}"

  ########################################
  # 临时 wrapper: audio_processor_mock.exe
  ########################################
  TMP_AUDIO_WRAPPER="$(mktemp "${ROOT_DIR}/audio_wrapper_XXXX.py")"
  cat > "${TMP_AUDIO_WRAPPER}" << 'EOF'
import os, sys, runpy
from pathlib import Path

def get_root():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

ROOT = get_root()
import app.audio_processor.main  # noqa

def main():
    os.chdir(ROOT)
    sys.argv = [
        "audio_processor_mock",
        "--rtp-port", os.environ.get("RTP_PORT", "5004"),
        "--data-port", os.environ.get("DATA_PORT", "5555"),
        "--use-mock-sound",
        "--sound-mock-data",
        os.environ.get("SOUND_MOCK_DATA", "mock_data/sound_sco_1f_1_10fps.json"),
        "--clap-degree-check-interval",
        os.environ.get("CLAP_DEGREE_CHECK_INTERVAL", "0.1"),
    ]
    runpy.run_module("app.audio_processor.main", run_name="__main__")

if __name__ == "__main__":
    main()
EOF

  echo ">>> [Mock] 构建 audio_processor_mock.exe ..."
  pyinstaller --onefile --name audio_processor_mock "${TMP_AUDIO_WRAPPER}"
  rm -f "${TMP_AUDIO_WRAPPER}"

  ########################################
  # 临时 wrapper: audience_sensing_mock.exe
  ########################################
  TMP_POSE_WRAPPER="$(mktemp "${ROOT_DIR}/pose_wrapper_XXXX.py")"
  cat > "${TMP_POSE_WRAPPER}" << 'EOF'
import os, sys, runpy
from pathlib import Path

def get_root():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

ROOT = get_root()
import app.mock_data_provider.pose_data_provider  # noqa

def main():
    os.chdir(ROOT)
    sys.argv = [
        "audience_sensing_mock",
        "--pose-file",
        os.environ.get("POSE_MOCK_DATA", "mock_data/pose_sco_1f_1_10fps.json"),
        "--interval",
        os.environ.get("MOCK_INTERVAL", "0.1"),
    ]
    runpy.run_module("app.mock_data_provider.pose_data_provider", run_name="__main__")

if __name__ == "__main__":
    main()
EOF

  echo ">>> [Mock] 构建 audience_sensing_mock.exe ..."
  pyinstaller --onefile --name audience_sensing_mock "${TMP_POSE_WRAPPER}"
  rm -f "${TMP_POSE_WRAPPER}"

  ########################################
  # 装配 mock 目录
  ########################################
  echo ">>> [Mock] 组装 Mock 包目录: ${MOCK_WORK_DIR}"

  cp "${ROOT_DIR}/dist/server.exe"                "${MOCK_WORK_DIR}/"
  cp "${ROOT_DIR}/dist/audio_processor_mock.exe"  "${MOCK_WORK_DIR}/"
  cp "${ROOT_DIR}/dist/audience_sensing_mock.exe" "${MOCK_WORK_DIR}/"

  if [[ -d "${ROOT_DIR}/mock_data" ]]; then
    cp -r "${ROOT_DIR}/mock_data" "${MOCK_WORK_DIR}/mock_data"
  fi

  echo ">>> [Mock] 打包 AudienceSensingMock_YYYYMMDD.zip ..."
  (
    cd "${RELEASE_DIR}"
    rm -f "${MOCK_ZIP_PATH}" || true
    zip -r "${MOCK_ZIP_PATH}" "${MOCK_RELEASE_NAME}"
  )

  echo ">>> [Mock] 完成: ${MOCK_ZIP_PATH}"
  echo
}

########################################
# 主流程
########################################
echo "========================================"
echo " 一键打包: 本番 tar.gz + gRPC Mock zip"
echo "========================================"
echo

build_server_package
build_grpc_mock_package

echo "========================================"
echo " 全部完成！成果物："
echo "  - ${SERVER_TAR_PATH}"
echo "  - ${MOCK_ZIP_PATH}"
echo "========================================"
