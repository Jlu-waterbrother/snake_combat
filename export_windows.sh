#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="${PROJECT_DIR}/export"
PRESET_NAME="Windows Desktop"
PROJECT_NAME="snake_combat"
OUTPUT_NAME="${PROJECT_NAME}"
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./export_windows.sh [--name <output_name>] [--check]

Options:
  --name <output_name>  Output file base name (default: snake_combat)
  --check               Validate export prerequisites only (no build)
  -h, --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --name requires a value." >&2
        exit 1
      fi
      OUTPUT_NAME="$1"
      ;;
    --check)
      CHECK_ONLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'." >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
  GODOT_CMD=(flatpak run org.godotengine.Godot)
elif command -v godot4 >/dev/null 2>&1; then
  GODOT_CMD=(godot4)
elif command -v godot >/dev/null 2>&1; then
  GODOT_CMD=(godot)
else
  echo "Error: Godot executable not found (flatpak, godot4, or godot)." >&2
  exit 1
fi

PRESET_FILE="${PROJECT_DIR}/export_presets.cfg"
if [[ ! -f "${PRESET_FILE}" ]]; then
  echo "Error: export_presets.cfg not found in project root." >&2
  exit 1
fi

if ! grep -Fq 'name="Windows Desktop"' "${PRESET_FILE}"; then
  echo "Error: export preset 'Windows Desktop' was not found in export_presets.cfg." >&2
  exit 1
fi

if [[ "${CHECK_ONLY}" == "true" ]]; then
  "${GODOT_CMD[@]}" --headless --version >/dev/null
  echo "Check passed: Godot CLI is available and Windows preset exists."
  exit 0
fi

mkdir -p "${EXPORT_DIR}"
OUTPUT_EXE="${EXPORT_DIR}/${OUTPUT_NAME}.exe"

"${GODOT_CMD[@]}" --headless --path "${PROJECT_DIR}" --export-release "${PRESET_NAME}" "${OUTPUT_EXE}"

PCK_PATH="${OUTPUT_EXE%.exe}.pck"
if command -v zip >/dev/null 2>&1; then
  ZIP_PATH="${EXPORT_DIR}/${OUTPUT_NAME}_windows.zip"
  if [[ -f "${PCK_PATH}" ]]; then
    (
      cd "${EXPORT_DIR}"
      zip -9 -q "$(basename "${ZIP_PATH}")" "$(basename "${OUTPUT_EXE}")" "$(basename "${PCK_PATH}")"
    )
  else
    (
      cd "${EXPORT_DIR}"
      zip -9 -q "$(basename "${ZIP_PATH}")" "$(basename "${OUTPUT_EXE}")"
    )
  fi
  echo "Compressed package: ${ZIP_PATH}"
fi

echo "Windows export complete: ${OUTPUT_EXE}"
