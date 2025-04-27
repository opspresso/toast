#!/bin/bash

set -e

# 환경 설정
OS_NAME="$(uname | awk '{print tolower($0)}')"

SHELL_DIR=$(dirname $0)

# DRY_RUN 모드 설정 (1=활성화, 그 외=비활성화)
DRY_RUN="${DRY_RUN:-0}"

# 기본 Git 설정
GIT_USERNAME="${GIT_USERNAME:-nalbam-bot}"
GIT_USEREMAIL="${GIT_USEREMAIL:-bot@nalbam.com}"

BRANCH="${BRANCH:-main}"

USERNAME="${PROJECT_USERNAME:-opspresso}"
REPONAME="${PROJECT_REPONAME:-toast-dist}"

# CI 환경 감지
CI="${CI:-false}"

# 메시지 출력 함수
echo_message() {
  local color=$1
  local message=$2

  # CI 환경이거나 tput이 사용 불가능한 경우 색상 없이 출력
  if [ "${CI}" = "true" ] || ! command -v tput > /dev/null; then
    echo -e "$message"
  else
    # 색상 코드
    # 1:빨강(에러), 2:초록(성공), 3:노랑(명령), 4:파랑(정보)
    echo -e "$(tput setaf $color)$message$(tput sgr0)"
  fi
}

error() {
  echo
  echo_message 1 "- $@"
  exit 1
}

success() {
  echo
  echo_message 2 "+ $@"
  exit 0
}

info() {
  echo
  echo_message 4 "# $@"
}

command_log() {
  echo
  echo_message 3 "$ $@"
}

# 메인 실행 함수
main() {
  # 환경 변수 확인
  info "TG_PROJECT: ${TG_PROJECT}"
  info "TG_VERSION: ${TG_VERSION}"

  # 필수 환경변수 확인
  if [ -z "${TG_PROJECT}" ] || [ -z "${TG_VERSION}" ]; then
    error "필수 환경변수가 설정되지 않았습니다. (TG_PROJECT, TG_VERSION)"
  fi

  # jq 명령어 확인
  if ! command -v jq > /dev/null; then
    error "jq가 설치되어 있지 않습니다. apt-get install -y jq 명령으로 설치하세요."
  fi

  # 타겟 파일 존재 확인
  local target_file="${SHELL_DIR}/docs/versions.json"
  if [ ! -f "${target_file}" ]; then
    error "파일을 찾을 수 없습니다: ${target_file}"
  fi

  # Git 설정
  if [ -n "${GIT_USERNAME}" ] && [ -n "${GIT_USEREMAIL}" ]; then
    command_log "Git 설정"
    git config --global user.name "${GIT_USERNAME}"
    git config --global user.email "${GIT_USEREMAIL}"
  fi

  # DRY_RUN 모드가 아닐 경우만 Git 작업 수행
  if [ "${DRY_RUN}" != "1" ]; then
    # 먼저 최신 코드 가져오기 (파일 수정 전에)
    command_log "git pull"
    git pull --rebase origin ${BRANCH}
  fi

  # 버전 v 접두사 제거
  local version=$(echo "${TG_VERSION}" | sed 's/^v//')

  # 현재 날짜를 ISO 형식으로 가져오기 (YYYY-MM-DDTHH:MM:SSZ)
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 버전 및 릴리스 날짜 업데이트
  command_log "jq를 사용하여 버전 업데이트: v${version}, 릴리스 날짜: ${current_date}"

  # jq를 사용하여 JSON 업데이트
  local tmp_file="${target_file}.tmp"

  # 다운로드 URL 생성
  local mac_url="https://github.com/${USERNAME}/${REPONAME}/releases/download/v${version}/Toast-${version}-arm64.dmg"
  local linux_url="https://github.com/${USERNAME}/${REPONAME}/releases/download/v${version}/Toast-${version}.AppImage"
  local win_url="https://github.com/${USERNAME}/${REPONAME}/releases/download/v${version}/Toast.Setup.${version}.exe"

  # jq 명령으로 versions.json 파일 업데이트
  jq --arg project "${TG_PROJECT}" \
     --arg version "${TG_VERSION}" \
     --arg date "${current_date}" \
     --arg mac_url "${mac_url}" \
     --arg linux_url "${linux_url}" \
     --arg win_url "${win_url}" \
     '.[$project].version = $version | .[$project].releaseDate = $date | .[$project].downloadUrl.mac = $mac_url | .[$project].downloadUrl.linux = $linux_url | .[$project].downloadUrl.win = $win_url' \
     "${target_file}" > "${tmp_file}"

  # 업데이트된 파일 확인
  if [ -s "${tmp_file}" ]; then
    # 파일 크기가 0보다 크면 원본 파일 대체
    cat "${tmp_file}" > "${target_file}"
    command_log "JSON 파일 업데이트 완료"
  else
    # 파일 크기가 0이면 에러
    rm -f "${tmp_file}"
    error "jq 명령 실행 중 오류가 발생했습니다."
  fi

  # 임시 파일 삭제
  rm -f "${tmp_file}"

  # DRY_RUN 모드가 아닐 경우 Git 커밋/푸시 작업 수행
  if [ "${DRY_RUN}" != "1" ]; then
    # 변경사항 커밋
    command_log "git add"
    git add "${target_file}"

    command_log "git commit"
    git commit -m "${TG_PROJECT} Release ${TG_VERSION}"

    # 변경사항 푸시
    command_log "git push"
    if [ -n "${GITHUB_TOKEN}" ]; then
      git push -q "https://${GITHUB_TOKEN}@github.com/${USERNAME}/${REPONAME}.git" ${BRANCH}
    else
      git push origin ${BRANCH}
    fi
  else
    info "DRY_RUN 모드: Git 작업을 건너뜁니다"
  fi

  if [ "${DRY_RUN}" = "1" ]; then
    info "DRY_RUN 모드에서 ${TG_PROJECT} 버전을 ${TG_VERSION}로 업데이트 시뮬레이션 완료!"
  else
    info "성공적으로 ${TG_PROJECT} 버전을 ${TG_VERSION}로 업데이트했습니다."
  fi
  success "완료!"
}

# 스크립트 실행
main
