#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="${PROJECT_DIR}/export/android"
PRESET_NAME="Android"
OUTPUT_NAME="snake_combat"
CHECK_ONLY=false
PACKAGE_ZIP=true

usage() {
  cat <<'EOF'
Usage: ./export_android.sh [--name <output_name>] [--check] [--no-zip]

Options:
  --name <output_name>  Output APK base name (default: snake_combat)
  --check               Validate export prerequisites only (no build)
  --no-zip              Skip zipping APK after export
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

if ! grep -Fq 'name="Android"' "${PRESET_FILE}"; then
  echo "Error: export preset 'Android' was not found in export_presets.cfg." >&2
  exit 1
fi

if [[ "${CHECK_ONLY}" == "true" ]]; then
  "${GODOT_CMD[@]}" --headless --version >/dev/null
  if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "Check passed: Godot CLI and Android preset found (set ANDROID_HOME or ANDROID_SDK_ROOT before real export)."
  else
    echo "Check passed: Godot CLI, Android preset, and Android SDK env vars detected."
  fi
  exit 0
fi

mkdir -p "${EXPORT_DIR}"
OUTPUT_APK="${EXPORT_DIR}/${OUTPUT_NAME}.apk"

"${GODOT_CMD[@]}" --headless --path "${PROJECT_DIR}" --export-release "${PRESET_NAME}" "${OUTPUT_APK}"

if [[ "${PACKAGE_ZIP}" == "true" ]] && command -v zip >/dev/null 2>&1; then
  ZIP_PATH="${EXPORT_DIR}/${OUTPUT_NAME}_android.zip"
  rm -f "${ZIP_PATH}"
  (
    cd "${EXPORT_DIR}"
    zip -9 -q -X "$(basename "${ZIP_PATH}")" "$(basename "${OUTPUT_APK}")"
  )
  echo "Compressed package: ${ZIP_PATH}"
fi

echo "Android export complete: ${OUTPUT_APK}"
