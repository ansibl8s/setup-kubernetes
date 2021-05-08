#!/bin/bash
set -eo pipefail

CURRENT_DIR=$(cd $(dirname $0); pwd)
TEMP_DIR="${CURRENT_DIR}/temp"
REPO_ROOT_DIR="${CURRENT_DIR%/contrib/offline}"

: ${IMAGE_ARCH:="amd64"}
: ${ANSIBLE_SYSTEM:="linux"}
: ${ANSIBLE_ARCHITECTURE:="x86_64"}
: ${DOWNLOAD_YML:="roles/download/defaults/main.yml"}
: ${KUBE_VERSION_YAML:="roles/kubespray-defaults/defaults/main.yaml"}

mkdir -p ${TEMP_DIR}

# ARCH used in convert {%- if image_arch != 'amd64' -%}-{{ image_arch }}{%- endif -%} to {{arch}}
if [ "${IMAGE_ARCH}" != "amd64" ]; then ARCH="${IMAGE_ARCH}"; fi

cat > ${TEMP_DIR}/generate.sh << EOF
arch=${ARCH}
image_arch=${IMAGE_ARCH}
ansible_system=${ANSIBLE_SYSTEM}
ansible_architecture=${ANSIBLE_ARCHITECTURE}
EOF

# generate all component version by $DOWNLOAD_YML
grep 'kube_version:' ${REPO_ROOT_DIR}/${KUBE_VERSION_YAML} \
| sed 's/: /=/g' >> ${TEMP_DIR}/generate.sh
grep '_version:' ${REPO_ROOT_DIR}/${DOWNLOAD_YML} \
| sed 's/: /=/g;s/{{/${/g;s/}}/}/g' | tr -d ' ' >> ${TEMP_DIR}/generate.sh
sed -i 's/kube_major_version=.*/kube_major_version=${kube_version%.*}/g' ${TEMP_DIR}/generate.sh
sed -i 's/crictl_version=.*/crictl_version=${kube_version%.*}.0/g' ${TEMP_DIR}/generate.sh

# generate all download files url
grep 'download_url:' ${REPO_ROOT_DIR}/${DOWNLOAD_YML} \
| sed 's/: /=/g;s/ //g;s/{{/${/g;s/}}/}/g;s/|lower//g;s/^.*_url=/echo /g' >> ${TEMP_DIR}/generate.sh

# generate all images list
grep -E '_repo:|_tag:' ${REPO_ROOT_DIR}/${DOWNLOAD_YML} \
| sed "s#{%- if image_arch != 'amd64' -%}-{{ image_arch }}{%- endif -%}#{{arch}}#g" \
| sed 's/: /=/g;s/{{/${/g;s/}}/}/g' | tr -d ' ' >> ${TEMP_DIR}/generate.sh
sed -n '/^downloads:/,/download_defaults:/p' ${REPO_ROOT_DIR}/${DOWNLOAD_YML} \
| sed -n "s/repo: //p;s/tag: //p" | tr -d ' ' | sed 's/{{/${/g;s/}}/}/g' \
| sed 'N;s#\n# #g' | tr ' ' ':' | sed 's/^/echo /g' >> ${TEMP_DIR}/generate.sh

# special handling for https://github.com/kubernetes-sigs/kubespray/pull/7570
sed -i 's#^coredns_image_repo=.*#coredns_image_repo=${kube_image_repo}$(if printf "%s\\n%s\\n" v1.21 ${kube_version%.*} | sort --check=quiet --version-sort; then echo -n /coredns/coredns;else echo -n /coredns; fi)#' ${TEMP_DIR}/generate.sh
sed -i 's#^coredns_image_tag=.*#coredns_image_tag=$(if printf "%s\\n%s\\n" v1.21 ${kube_version%.*} | sort --check=quiet --version-sort; then echo -n ${coredns_version};else echo -n ${coredns_version/v/}; fi)#' ${TEMP_DIR}/generate.sh

# add kube-* images to images list
KUBE_IMAGES="kube-apiserver kube-controller-manager kube-scheduler kube-proxy"
echo "${KUBE_IMAGES}" | tr ' ' '\n' | xargs -L1 -I {} \
echo 'echo ${kube_image_repo}/{}:${kube_version}' >> ${TEMP_DIR}/generate.sh

# print files.list and images.list
bash ${TEMP_DIR}/generate.sh | grep 'https' | sort > ${TEMP_DIR}/files.list
bash ${TEMP_DIR}/generate.sh | grep -v 'https' | sort > ${TEMP_DIR}/images.list
