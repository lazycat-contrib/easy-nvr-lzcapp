#!/usr/bin/env bash

set -euo pipefail

version_url="${EASYNVR_VERSION_URL:-https://www.easynvr.com/public/new_version.json}"
current_version="${CURRENT_VERSION:?CURRENT_VERSION is required}"
output_file="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
fixture_file="${VERSION_JSON_FILE:-}"

temporary_file="$(mktemp)"
trap 'rm -f "${temporary_file}"' EXIT

write_output() {
  local key="$1"
  local value="$2"
  local delimiter="easynvr_output"

  while grep -Fxq "${delimiter}" <<<"${value}"; do
    delimiter="${delimiter}_x"
  done

  {
    printf '%s<<%s\n' "${key}" "${delimiter}"
    printf '%s\n' "${value}"
    printf '%s\n' "${delimiter}"
  } >>"${output_file}"
}

is_stable_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

compare_semver() {
  local left_major left_minor left_patch
  local right_major right_minor right_patch

  IFS=. read -r left_major left_minor left_patch <<<"$1"
  IFS=. read -r right_major right_minor right_patch <<<"$2"

  for pair in \
    "${left_major} ${right_major}" \
    "${left_minor} ${right_minor}" \
    "${left_patch} ${right_patch}"; do
    read -r left right <<<"${pair}"
    if ((10#${left} > 10#${right})); then
      printf '1\n'
      return
    fi
    if ((10#${left} < 10#${right})); then
      printf '%s\n' '-1'
      return
    fi
  done

  printf '0\n'
}

if ! is_stable_semver "${current_version}"; then
  echo "package.yml contains an unsupported version: ${current_version}" >&2
  exit 1
fi

request_time="$(date +%s%3N)"
if [[ -n "${fixture_file}" ]]; then
  cp -- "${fixture_file}" "${temporary_file}"
else
  separator='?'
  if [[ "${version_url}" == *'?'* ]]; then
    separator='&'
  fi
  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors \
    --connect-timeout 10 --max-time 30 \
    --header 'Cache-Control: no-cache' \
    --header 'Pragma: no-cache' \
    "${version_url}${separator}time=${request_time}" \
    --output "${temporary_file}"
fi

if ! jq -e '(.version_list | type) == "array" and (.version_list | length) > 0' \
  "${temporary_file}" >/dev/null; then
  echo 'EasyNVR version response does not contain a non-empty version_list' >&2
  exit 1
fi

write_output request_time "${request_time}"

candidate_version="$(jq -er '.version_list[0].version | strings' "${temporary_file}")"
candidate_version="${candidate_version#v}"
if ! is_stable_semver "${candidate_version}"; then
  echo "EasyNVR version_list version is not stable SemVer: ${candidate_version}" >&2
  exit 1
fi

changelog="$({
  jq -r --arg version "v${candidate_version}" '
    [
      .chnagelog[]?
      | select(.version == $version or (.version | startswith($version + "-")))
      | .items[]?
      | strings
    ]
    | unique
    | .[]
    | "- " + .
  ' "${temporary_file}"
} || true)"
if [[ -z "${changelog}" ]]; then
  changelog="EasyNVR ${candidate_version} 已由上游发布。"
fi

comparison="$(compare_semver "${candidate_version}" "${current_version}")"
if [[ "${comparison}" == '-1' ]]; then
  echo "refusing version_list downgrade ${current_version} -> ${candidate_version}" >&2
  exit 1
fi
if [[ "${comparison}" == '0' ]]; then
  write_output should_update 'false'
  write_output reason 'version-already-current'
  write_output version "${candidate_version}"
  write_output changelog "${changelog}"
  echo "EasyNVR ${candidate_version} is already current."
  exit 0
fi

write_output should_update 'true'
write_output reason 'new-version-list-version'
write_output version "${candidate_version}"
write_output changelog "${changelog}"

echo "EasyNVR version_list version ${candidate_version} is newer than ${current_version}."
