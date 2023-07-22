#!/usr/bin/env bash

sudo apt-get update \
  && apt-get install -y wget cpio gzip;

#BUILD_DIR="/.Build"
VENUS_OS_REPOSITORY_URL="https://updates.victronenergy.com/feeds/venus/release/images/"
PATH_ARM_V7="raspberrypi2/"
PATH_ARM64_V8="raspberrypi4/"

declare -A VENUS_OS_VERSIONS_DESCRIPTIONS=(
  [STANDARD_ARM_V7]="standard 32bit ARM v7"
  [LARGE_ARM_V7]="large 32bit ArmHf v7"
  [STANDARD_ARM64_V8]="standard 64bit ARM v8"
  [LARGE_ARM64_V8]="large 64bit ARM v8"
)

declare -A VENUS_OS_VERSIONS_FILES=(
  [STANDARD_ARM_V7]="venus-swu-3-raspberrypi2.swu"
  [LARGE_ARM_V7]="venus-swu-3-large-raspberrypi2.swu"
  [STANDARD_ARM64_V8]="venus-swu-3-raspberrypi4.swu"
  [LARGE_ARM64_V8]="venus-swu-3-large-raspberrypi4.swu"
)

declare -A VENUS_OS_VERSIONS_URLS=(
  [STANDARD_ARM_V7]="${VENUS_OS_REPOSITORY_URL}${PATH_ARM_V7}${VENUS_OS_VERSIONS_FILES[STANDARD_ARM_V7]}"
  [LARGE_ARM_V7]="${VENUS_OS_REPOSITORY_URL}${PATH_ARM_V7}${VENUS_OS_VERSIONS_FILES[LARGE_ARM_V7]}"
  [STANDARD_ARM64_V8]="${VENUS_OS_REPOSITORY_URL}${PATH_ARM64_V8}${VENUS_OS_VERSIONS_FILES[STANDARD_ARM64_V8]}"
  [LARGE_ARM64_V8]="${VENUS_OS_REPOSITORY_URL}${PATH_ARM64_V8}${VENUS_OS_VERSIONS_FILES[LARGE_ARM64_V8]}"
)
  
function downloadVersion() {
  mkdir -p .Downloads
  rm -Rfv ".Downloads/${VENUS_OS_VERSIONS_FILES[$1]}"
  wget --directory-prefix=".Downloads/" "${VENUS_OS_VERSIONS_URLS[$1]}"
}

function getVersionFromImage() {
  sed "1q;d" "${1}/opt/victronenergy/version"
}

function getBuildDateFromImage() {
  sed "3q;d" "${1}/opt/victronenergy/version"
}

function cleanUpVersion() {
  if [[ -z "${1}" ]]; then
    echo "The mountpoint variable is empty, which can lead to destroying host filesystem!"
    exit 17
  fi
  echo "Clean up unnecessary files from image mounted on $1"
  local paths=(
      "${1}"./boot
      "${1}"./u-boot
      "${1}"./tmp/*
    )
  echo "Removing following directories and files: "
  echo "${paths[@]}"
  sudo rm -Rf "${paths[@]}"
}

function convertVersion() {
  current_dir=$(pwd)
  rm -Rf ".Build/$1"
  mkdir -p ".Build/$1"
  cd ".Build/$1" || exit 13
  cpio -iv < "../../.Downloads/${VENUS_OS_VERSIONS_FILES[$1]}"

  ext4_archive_pattern_match=( *.ext4.gz )
  ext4_archive_file="${ext4_archive_pattern_match[0]}"
  echo "extracting the filesystem from archive: ${ext4_archive_file}"
  gzip -d "${ext4_archive_file}"
  cd "${current_dir}" || exit 14

  MOUNT_POINT=".Build/$1/.ext4.mount/"
  mkdir -p "${MOUNT_POINT}"
  ext4_file_pattern_match=( ".Build/$1/"*.ext4 )
  ext4_file="${ext4_file_pattern_match[0]}"
  sudo mount "${ext4_file}" "${MOUNT_POINT}" -o loop
  echo "Mounted the image for ${VENUS_OS_VERSIONS_DESCRIPTIONS[$1]} on \"${MOUNT_POINT}\""
#  sleep 5m

  cleanUpVersion "${MOUNT_POINT}"
  OS_VERSION=$(getVersionFromImage "${MOUNT_POINT}")
  OS_BUILD_DATE=$(getBuildDateFromImage "${MOUNT_POINT}")
  DOCKER_IMAGE_NAME="rafaelka/venus-os"
  if [[ "${1}" =~ .*"LARGE".* ]]; then
    DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME}-large"
  fi
  DOCKER_IMAGE_TAG=${OS_VERSION#"v"}
  DOCKER_IMAGE_ARCH="linux/arm"
  if [[ "${1}" =~ .*"ARM_V7".* ]]; then
    DOCKER_IMAGE_ARCH="${DOCKER_IMAGE_ARCH}32/v7"
  elif [[ "${1}" =~ .*"ARM64_V8".* ]]; then
    DOCKER_IMAGE_ARCH="${DOCKER_IMAGE_ARCH}64/v8"
  fi
  echo "Venus OS:"
  echo "  version:    ${OS_VERSION}"
  echo "  build date: ${OS_BUILD_DATE}"
  echo "Docker:"
  echo "  OS/ARCH:    ${DOCKER_IMAGE_ARCH}"
  echo "  image name: ${DOCKER_IMAGE_NAME}"
  echo "  image tag:  ${DOCKER_IMAGE_TAG}"
  echo "  target:     ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"

  # Build docker image
  docker build \
    --file=Dockerfile \
    --tag="${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" \
    --platform="${DOCKER_IMAGE_ARCH}" \
    .Build/"$1"/

  echo "Unmounting \"${MOUNT_POINT}\""
  if ! sudo umount "${MOUNT_POINT}" ; then
    >&2 echo "Can not unmount \"${MOUNT_POINT}\" please umount it manually."
    exit 15
  fi
}

for version in "${!VENUS_OS_VERSIONS_FILES[@]}"; do
  echo "Downloading and building: ${VENUS_OS_VERSIONS_DESCRIPTIONS[$version]}"
  downloadVersion "$version"
  convertVersion "$version"
done