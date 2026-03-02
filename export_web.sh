#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="${PROJECT_DIR}/export/web"
PRESET_NAME="Web"
OUTPUT_NAME="snake_combat_web"
CHECK_ONLY=false
PACKAGE_ZIP=true

usage() {
  cat <<'EOF'
Usage: ./export_web.sh [--name <output_name>] [--check] [--no-zip]

Options:
  --name <output_name>  Output folder name under export/web (default: snake_combat_web)
  --check               Validate export prerequisites only (no build)
  --no-zip              Skip packaging output folder into zip
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
    --no-zip)
      PACKAGE_ZIP=false
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

if ! grep -Fq 'name="Web"' "${PRESET_FILE}"; then
  echo "Error: export preset 'Web' was not found in export_presets.cfg." >&2
  exit 1
fi

if [[ "${CHECK_ONLY}" == "true" ]]; then
  "${GODOT_CMD[@]}" --headless --version >/dev/null
  echo "Check passed: Godot CLI is available and Web preset exists."
  exit 0
fi

mkdir -p "${EXPORT_DIR}"
TARGET_DIR="${EXPORT_DIR}/${OUTPUT_NAME}"
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
OUTPUT_HTML="${TARGET_DIR}/index.html"

"${GODOT_CMD[@]}" --headless --path "${PROJECT_DIR}" --export-release "${PRESET_NAME}" "${OUTPUT_HTML}"

if [[ "${PACKAGE_ZIP}" == "true" ]] && command -v zip >/dev/null 2>&1; then
  ZIP_PATH="${EXPORT_DIR}/${OUTPUT_NAME}.zip"
  rm -f "${ZIP_PATH}"
  (
    cd "${EXPORT_DIR}"
    zip -9 -q -X -r "$(basename "${ZIP_PATH}")" "$(basename "${TARGET_DIR}")"
  )
  echo "Compressed package: ${ZIP_PATH}"
fi

echo "Web export complete: ${OUTPUT_HTML}"
