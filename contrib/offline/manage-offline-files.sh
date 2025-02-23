#!/bin/bash

CURRENT_DIR=$( dirname "$(readlink -f "$0")" )
OFFLINE_FILES_DIR_NAME="offline-files"
OFFLINE_FILES_DIR="${CURRENT_DIR}/${OFFLINE_FILES_DIR_NAME}"
OFFLINE_FILES_ARCHIVE="${CURRENT_DIR}/offline-files.tar.gz"
FILES_LIST=${FILES_LIST:-"${CURRENT_DIR}/temp/files.list"}
NGINX_PORT=8080

# download files
if [ ! -f "${FILES_LIST}" ]; then
    echo "${FILES_LIST} should exist, run ./generate_list.sh first."
    exit 1
fi

rm -rf "${OFFLINE_FILES_DIR}"
rm "${OFFLINE_FILES_ARCHIVE}"
mkdir  "${OFFLINE_FILES_DIR}"

while read -r url; do
  if ! wget -x -P "${OFFLINE_FILES_DIR}" "${url}"; then
    exit 1
  fi
done < "${FILES_LIST}"

tar -czvf "${OFFLINE_FILES_ARCHIVE}"  "${OFFLINE_FILES_DIR_NAME}"

[ -n "$NO_HTTP_SERVER" ] && echo "skip to run nginx" && exit 0

# run nginx container server
if command -v nerdctl 1>/dev/null 2>&1; then
    runtime="nerdctl"
elif command -v podman 1>/dev/null 2>&1; then
    runtime="podman"
elif command -v docker 1>/dev/null 2>&1; then
    runtime="docker"
else
    echo "No supported container runtime found"
    exit 1
fi

sudo "${runtime}" container inspect nginx >/dev/null 2>&1
if [ $? -ne 0 ]; then
    sudo -E "${runtime}" run \
        --restart=always -d -p ${NGINX_PORT}:80 \
        --volume "${OFFLINE_FILES_DIR}":/usr/share/nginx/html/download \
        --volume "${CURRENT_DIR}"/nginx.conf:/etc/nginx/nginx.conf \
        --name nginx nginx:alpine
fi
