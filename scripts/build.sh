#!/usr/bin/env bash
# Builds the app with --analyze-size and tees the output to a log the Dart
# tool reads to find the analysis JSON and the artifact.
#
#   build.sh <project-dir> <log-file>
#
# Reads: FSB_PLATFORM, FSB_TARGET_PLATFORM, FSB_FLAVOR, FSB_TARGET,
#        FSB_DEFINE_FILE, FSB_BUILD_ARGS
set -euo pipefail

project_dir="$1"
log_file="$2"

case "${FSB_PLATFORM}" in
  apk)
    cmd=(flutter build apk --release --analyze-size --target-platform "${FSB_TARGET_PLATFORM}")
    ;;
  appbundle | aab)
    cmd=(flutter build appbundle --release --analyze-size --target-platform "${FSB_TARGET_PLATFORM}")
    ;;
  ios)
    cmd=(flutter build ios --release --analyze-size --no-codesign)
    ;;
  *)
    echo "::error::Unsupported platform '${FSB_PLATFORM}' (use apk, appbundle or ios)."
    exit 2
    ;;
esac

if [[ -n "${FSB_FLAVOR}" ]]; then
  cmd+=(--flavor "${FSB_FLAVOR}")
fi
if [[ -n "${FSB_TARGET}" ]]; then
  cmd+=(--target "${FSB_TARGET}")
fi
if [[ -n "${FSB_DEFINE_FILE}" ]]; then
  cmd+=("--dart-define-from-file=${FSB_DEFINE_FILE}")
fi
if [[ -n "${FSB_BUILD_ARGS}" ]]; then
  # Space separated, no shell evaluation.
  read -r -a extra <<< "${FSB_BUILD_ARGS}"
  cmd+=("${extra[@]}")
fi

mkdir -p "$(dirname "${log_file}")"
echo "::group::${cmd[*]} (in ${project_dir})"
set +e
(cd "${project_dir}" && "${cmd[@]}") 2>&1 | tee "${log_file}"
status=${PIPESTATUS[0]}
set -e
echo "::endgroup::"
if [[ ${status} -ne 0 ]]; then
  echo "::error::flutter build failed with exit code ${status} (see the log above)."
  exit "${status}"
fi
