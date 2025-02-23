#!/bin/bash

OPTION=$1
CURRENT_DIR=$(cd $(dirname $0); pwd)
TEMP_DIR="${CURRENT_DIR}/temp"

IMAGE_TAR_FILE="${CURRENT_DIR}/container-images.tar.gz"
IMAGE_DIR="${CURRENT_DIR}/container-images"
IMAGE_LIST="${IMAGE_DIR}/container-images.txt"
RETRY_COUNT=5

function create_container_image_tar() {
	set -e

	if [ -z "${IMAGES_FROM_FILE}" ]; then
		echo "Getting images from current \"$(kubectl config current-context)\""

		IMAGES=$(mktemp --suffix=-images)
		trap 'rm -f "${IMAGES}"' EXIT

		kubectl describe cronjobs,jobs,pods --all-namespaces | grep " Image:" | awk '{print $2}' | sort | uniq > "${IMAGES}"
		# NOTE: etcd and pause cannot be seen as pods.
		# The pause image is used for --pod-infra-container-image option of kubelet.
		kubectl cluster-info dump | grep -E "quay.io/coreos/etcd:|registry.k8s.io/pause:" | sed s@\"@@g >> "${IMAGES}"
	else
		echo "Getting images from file \"${IMAGES_FROM_FILE}\""
		if [ ! -f "${IMAGES_FROM_FILE}" ]; then
			echo "${IMAGES_FROM_FILE} is not a file"
			exit 1
		fi
		IMAGES=$(realpath $IMAGES_FROM_FILE)
	fi

	rm -f  ${IMAGE_TAR_FILE}
	rm -rf ${IMAGE_DIR}
	mkdir  ${IMAGE_DIR}
	cd     ${IMAGE_DIR}

	sudo ${runtime} pull registry:latest
	sudo ${runtime} save -o registry-latest.tar registry:latest

	while read -r image
	do
		FILE_NAME="$(echo ${image} | sed s@"/"@"-"@g | sed s/":"/"-"/g | sed -E 's/\@.*//g')".tar
		set +e
		for step in $(seq 1 ${RETRY_COUNT})
		do
			sudo ${runtime} pull ${image}
			if [ $? -eq 0 ]; then
				break
			fi
			echo "Failed to pull ${image} at step ${step}"
			if [ ${step} -eq ${RETRY_COUNT} ]; then
				exit 1
			fi
		done
		set -e
		sudo ${runtime} save -o ${FILE_NAME}  ${image}

		# NOTE: Here removes the following repo parts from each image
		# so that these parts will be replaced with Kubespray.
		# - kube_image_repo: "registry.k8s.io"
		# - gcr_image_repo: "gcr.io"
		# - ghcr_image_repo: "ghcr.io"
		# - docker_image_repo: "docker.io"
		# - quay_image_repo: "quay.io"
		FIRST_PART=$(echo ${image} | awk -F"/" '{print $1}')
		if [ "${FIRST_PART}" = "registry.k8s.io" ] ||
		   [ "${FIRST_PART}" = "gcr.io" ] ||
		   [ "${FIRST_PART}" = "ghcr.io" ] ||
		   [ "${FIRST_PART}" = "docker.io" ] ||
		   [ "${FIRST_PART}" = "quay.io" ] ||
		   [ "${FIRST_PART}" = "${PRIVATE_REGISTRY}" ]; then
			image=$(echo ${image} | sed s@"${FIRST_PART}/"@@ | sed -E 's/\@.*/\n/g')
		fi
		echo "${FILE_NAME}  ${image}" >> ${IMAGE_LIST}
	done < "${IMAGES}"

	cd ..
	sudo chown ${USER} ${IMAGE_DIR}/*
	tar -zcvf ${IMAGE_TAR_FILE}  ./container-images
	rm -rf ${IMAGE_DIR}

	echo ""
	echo "${IMAGE_TAR_FILE} is created to contain your container images."
	echo "Please keep this file and bring it to your offline environment."
}

function register_container_images() {
	create_registry=false
	REGISTRY_PORT=${REGISTRY_PORT:-"5000"}

	if [ -z "${DESTINATION_REGISTRY}" ]; then
		echo "DESTINATION_REGISTRY not set, will create local registry"
		create_registry=true
		DESTINATION_REGISTRY="$(hostname):${REGISTRY_PORT}"
	fi
	echo "Images will be pushed to ${DESTINATION_REGISTRY}"

	if [ ! -f ${IMAGE_TAR_FILE} ]; then
		echo "${IMAGE_TAR_FILE} should exist."
		exit 1
	fi
	if [ ! -d ${TEMP_DIR} ]; then
		mkdir ${TEMP_DIR}
	fi

	# To avoid "http: server gave http response to https client" error.
	if [ -d /etc/docker/ ]; then
		set -e
		# Ubuntu18.04, RHEL7/CentOS7
		cp ${CURRENT_DIR}/docker-daemon.json      ${TEMP_DIR}/docker-daemon.json
		sed -i s@"HOSTNAME"@"$(hostname)"@  ${TEMP_DIR}/docker-daemon.json
		sudo cp ${TEMP_DIR}/docker-daemon.json           /etc/docker/daemon.json
	elif [ -d /etc/containers/ ]; then
		set -e
		# RHEL8/CentOS8
		cp ${CURRENT_DIR}/registries.conf         ${TEMP_DIR}/registries.conf
		sed -i s@"HOSTNAME"@"$(hostname)"@  ${TEMP_DIR}/registries.conf
		sudo cp ${TEMP_DIR}/registries.conf   /etc/containers/registries.conf
	else
		echo "runtime package(docker-ce, podman, nerctl, etc.) should be installed"
		exit 1
	fi

	tar -zxvf ${IMAGE_TAR_FILE}

	if ${create_registry}; then
		sudo ${runtime} load -i ${IMAGE_DIR}/registry-latest.tar
		set +e

		sudo ${runtime} container inspect registry >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			sudo ${runtime} run --restart=always -d -p "${REGISTRY_PORT}":"${REGISTRY_PORT}" --name registry registry:latest
		fi
		set -e
	fi

	while read -r line; do
		file_name=$(echo ${line} | awk '{print $1}')
		raw_image=$(echo ${line} | awk '{print $2}')
		new_image="${DESTINATION_REGISTRY}/${raw_image}"
		load_image=$(sudo ${runtime} load -i ${IMAGE_DIR}/${file_name} | head -n1)
		org_image=$(echo "${load_image}"  | awk '{print $3}')
		# special case for tags containing the digest when using docker or podman as the container runtime
		if [ "${org_image}" == "ID:" ]; then
		  org_image=$(echo "${load_image}"  | awk '{print $4}')
		fi
		image_id=$(sudo ${runtime} image inspect ${org_image} | grep "\"Id\":" | awk -F: '{print $3}'| sed s/'\",'//)
		if [ -z "${file_name}" ]; then
			echo "Failed to get file_name for line ${line}"
			exit 1
		fi
		if [ -z "${raw_image}" ]; then
			echo "Failed to get raw_image for line ${line}"
			exit 1
		fi
		if [ -z "${org_image}" ]; then
			echo "Failed to get org_image for line ${line}"
			exit 1
		fi
		if [ -z "${image_id}" ]; then
			echo "Failed to get image_id for file ${file_name}"
			exit 1
		fi
		sudo ${runtime} load -i ${IMAGE_DIR}/${file_name}
		sudo ${runtime} tag  ${image_id} ${new_image}
		sudo ${runtime} push ${new_image}
	done <<< "$(cat ${IMAGE_LIST})"

	echo "Succeeded to register container images to local registry."
	echo "Please specify \"${DESTINATION_REGISTRY}\" for the following options in your inventry:"
	echo "- kube_image_repo"
	echo "- gcr_image_repo"
	echo "- docker_image_repo"
	echo "- quay_image_repo"
}

# get runtime command
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

if [ "${OPTION}" == "create" ]; then
	create_container_image_tar
elif [ "${OPTION}" == "register" ]; then
	register_container_images
else
	echo "This script has two features:"
	echo "(1) Get container images from an environment which is deployed online, or set IMAGES_FROM_FILE"
	echo "    environment variable to get images from a file (e.g. temp/images.list after running the"
	echo "    ./generate_list.sh script)."
	echo "(2) Deploy local container registry and register the container images to the registry."
	echo ""
	echo "Step(1) should be done online site as a preparation, then we bring"
	echo "the gotten images to the target offline environment. if images are from"
	echo "a private registry, you need to set PRIVATE_REGISTRY environment variable."
	echo "Then we will run step(2) for registering the images to local registry, or to an existing"
	echo "registry set by the DESTINATION_REGISTRY environment variable. By default, the local registry"
	echo "will run on port 5000. This can be changed with the REGISTRY_PORT environment variable"
	echo ""
	echo "${IMAGE_TAR_FILE} is created to contain your container images."
	echo "Please keep this file and bring it to your offline environment."
	echo ""
	echo "Step(1) can be operated with:"
	echo " $ ./manage-offline-container-images.sh   create"
	echo ""
	echo "Step(2) can be operated with:"
	echo " $ ./manage-offline-container-images.sh   register"
	echo ""
	echo "Please specify 'create' or 'register'."
	echo ""
	exit 1
fi
