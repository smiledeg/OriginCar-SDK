#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PREFIX="/userdata/origincar_sdk"
INSTALL_PREFIX="${ORIGINCAR_SDK_INSTALL_DIR:-${DEFAULT_PREFIX}}"
CREATE_COMMAND_LINKS=1

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Options:
  --prefix PATH        Installation directory (default: /userdata/origincar_sdk)
  --no-command-links   Do not create commands in /usr/local/bin
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "[install] --prefix requires a path." >&2; exit 2; }
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      INSTALL_PREFIX="${1#*=}"
      shift
      ;;
    --no-command-links)
      CREATE_COMMAND_LINKS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[install] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${INSTALL_PREFIX}" =~ ^/[A-Za-z0-9._/-]+$ ]] ||
   [[ "${INSTALL_PREFIX}" == *"/../"* ]] ||
   [[ "${INSTALL_PREFIX}" == */.. ]]; then
  echo "[install] The installation path must be a safe absolute Linux path." >&2
  exit 2
fi

case "${INSTALL_PREFIX}" in
  /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
    echo "[install] Refusing unsafe installation path: ${INSTALL_PREFIX}" >&2
    exit 2
    ;;
esac

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

for required in bin install libexec resources README.md; do
  if [[ ! -e "${SDK_ROOT}/${required}" ]]; then
    echo "[install] SDK is incomplete; missing ${required}." >&2
    exit 1
  fi
done

case "$(uname -m)" in
  aarch64|arm64)
    ;;
  *)
    echo "[install] This SDK requires Linux AArch64 (ARM64)." >&2
    exit 1
    ;;
esac

if [[ "${EUID}" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "[install] Root privileges are required. Run: sudo bash install.sh" >&2
    exit 1
  fi
  sudo_args=(bash "${BASH_SOURCE[0]}" --prefix "${INSTALL_PREFIX}")
  if [[ "${CREATE_COMMAND_LINKS}" -eq 0 ]]; then
    sudo_args+=(--no-command-links)
  fi
  exec sudo "${sudo_args[@]}"
fi

case "${SDK_ROOT}/" in
  "${INSTALL_PREFIX}/"*)
    if [[ "${SDK_ROOT}" != "${INSTALL_PREFIX}" ]]; then
      echo "[install] Installation directory cannot be an ancestor of the SDK source directory." >&2
      exit 2
    fi
    ;;
esac
case "${INSTALL_PREFIX}/" in
  "${SDK_ROOT}/"*)
    if [[ "${SDK_ROOT}" != "${INSTALL_PREFIX}" ]]; then
      echo "[install] Installation directory cannot be inside the SDK source directory." >&2
      exit 2
    fi
    ;;
esac

set_permissions() {
  local target="$1"
  chmod -R a+rX "${target}"
  chmod 755 "${target}/install.sh" "${target}/bin/start_navigation" "${target}/bin/start_qr_navigation"
  find "${target}/install" -type f \( \
    -path '*/lib/*' -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \
  \) -exec chmod 755 {} +
}

if [[ "${SDK_ROOT}" == "${INSTALL_PREFIX}" ]]; then
  set_permissions "${INSTALL_PREFIX}"
else
  parent_dir="$(dirname "${INSTALL_PREFIX}")"
  install -d -m 755 "${parent_dir}"
  staging_dir="$(mktemp -d "${INSTALL_PREFIX}.tmp.XXXXXX")"
  backup_dir=""

  cleanup() {
    if [[ -n "${staging_dir:-}" && -d "${staging_dir}" ]]; then
      rm -rf -- "${staging_dir}"
    fi
    if [[ -n "${backup_dir:-}" && -e "${backup_dir}" && ! -e "${INSTALL_PREFIX}" ]]; then
      mv -- "${backup_dir}" "${INSTALL_PREFIX}"
    fi
  }
  trap cleanup EXIT

  cp -a "${SDK_ROOT}/bin" "${staging_dir}/"
  cp -a "${SDK_ROOT}/install" "${staging_dir}/"
  cp -a "${SDK_ROOT}/libexec" "${staging_dir}/"
  cp -a "${SDK_ROOT}/resources" "${staging_dir}/"
  cp -a "${SDK_ROOT}/README.md" "${staging_dir}/"
  cp -a "${SDK_ROOT}/install.sh" "${staging_dir}/"
  set_permissions "${staging_dir}"

  if [[ -e "${INSTALL_PREFIX}" || -L "${INSTALL_PREFIX}" ]]; then
    backup_dir="${INSTALL_PREFIX}.backup.$$"
    mv -- "${INSTALL_PREFIX}" "${backup_dir}"
  fi
  mv -- "${staging_dir}" "${INSTALL_PREFIX}"
  staging_dir=""
  if [[ -n "${backup_dir}" ]]; then
    rm -rf -- "${backup_dir}"
    backup_dir=""
  fi
  trap - EXIT
fi

if [[ "${CREATE_COMMAND_LINKS}" -eq 1 ]]; then
  install -d -m 755 /usr/local/bin
  printf '#!/usr/bin/env bash\nexec bash "%s/bin/start_navigation" "$@"\n' "${INSTALL_PREFIX}" > /usr/local/bin/origincar-start
  chmod 755 /usr/local/bin/origincar-start
fi

echo "[install] OriginCar SDK installed at ${INSTALL_PREFIX}"
if [[ "${CREATE_COMMAND_LINKS}" -eq 1 ]]; then
  echo "[install] Start with: origincar-start"
else
  echo "[install] Start with: bash ${INSTALL_PREFIX}/bin/start_navigation"
fi

if [[ ! -f /opt/ros/humble/local_setup.bash ]]; then
  echo "[install] Warning: ROS 2 Humble was not found at /opt/ros/humble." >&2
fi
if [[ ! -f /opt/tros/humble/local_setup.bash ]]; then
  echo "[install] Warning: TROS Humble was not found at /opt/tros/humble." >&2
fi
