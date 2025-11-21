#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="${ROOT_DIR}/release"

DATE_STR="$(date +%Y%m%d)"

MOCK_RELEASE_NAME="AudienceSensingMock_${DATE_STR}"
MOCK_WORK_DIR="${RELEASE_DIR}/${MOCK_RELEASE_NAME}"
MOCK_ZIP_PATH="${RELEASE_DIR}/${MOCK_RELEASE_NAME}.zip"

mkdir -p "${RELEASE_DIR}"

echo ">>> [Mock] ROOT_DIR    = ${ROOT_DIR}"
echo ">>> [Mock] RELEASE_DIR = ${RELEASE_DIR}"
echo ">>> [Mock] DATE_STR    = ${DATE_STR}"
echo

if ! command -v pyinstaller >/dev/null 2>&1; then
  echo "!!! 请安装 pyinstaller: pip install pyinstaller" >&2
  exit 1
fi

rm -rf "${MOCK_WORK_DIR}"
mkdir -p "${MOCK_WORK_DIR}"

cd "${ROOT_DIR}"
rm -rf build dist *.spec || true

########################################
# 生成 server.exe
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
    sys.argv = ["server", "--grpc", "--interval", os.environ.get("INTERVAL", "100")]
    runpy.run_module("app.server", run_name="__main__")

if __name__ == "__main__":
    main()
EOF

echo ">>> [Mock] 构建 server.exe ..."
pyinstaller --onefile --name server "${TMP_SERVER_WRAPPER}"
rm -f "${TMP_SERVER_WRAPPER}"

########################################
# 生成 audio_processor_mock.exe
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
# 生成 audience_sensing_mock.exe
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
# 4) 组装 zip
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

  # 如果目标文件已存在，先删掉
  rm -f "${MOCK_ZIP_PATH}" || true

  if command -v zip >/dev/null 2>&1; then
      echo ">>> 检测到 zip 命令，使用 zip 压缩..."
      zip -r "${MOCK_ZIP_PATH}" "${MOCK_RELEASE_NAME}"
  else
      echo ">>> 未检测到 zip 命令，使用 PowerShell Compress-Archive 代替..."
      powershell.exe -NoLogo -NoProfile -Command \
        "Compress-Archive -Path '${MOCK_RELEASE_NAME}' -DestinationPath '${MOCK_RELEASE_NAME}.zip' -Force"
  fi
)

echo ">>> [Mock] 完成: ${MOCK_ZIP_PATH}"
echo
