#!/bin/bash

root_dir="$( cd "$( dirname $0 )" && pwd )"
port=5000
data_dir=/data
cert_dir=/certs
tls_cert=
tls_key=


installDocker(){
    curl -fsSL https://get.docker.com/ | sh
    service docker start
}


pullRegistry(){
    docker pull registry:2

    mkdir -p data_dir
    mkdir -p cert_dir

    docker run -d -p $port:5000 -v $data_dir:/var/lib/registry registry:2
}

download_images() {

IMAGES_CACHE=/tmp/kubespray_cache
INVENTORY_FILE=${root_dir}/air-gap.ini

mkdir -p ${IMAGES_CACHE}/images

mkdir -p /etc/kubernetes

ansible-playbook -i  ${INVENTORY_FILE}  ${root_dir}/../cluster.yml \
	--tags download  \
	-e download_run_once=true \
	-e download_localhost=false \
	--become --become-user root
        -e download_cache_dir="${IMAGES_CACHE}" \
        -e proxy_env='{"HTTPS_PROXY": "", "HTTP_PROXY": "", "NO_PROXY": "", "http_proxy": "", "https_proxy": "", "no_proxy": ""}' \
        -e ansible_architecture="x86_64" \
        -e ansible_system="Linux" \
        -e ansible_os_family="RedHat" 

}

loadPublicImages(){
    public_img=$(docker images | awk '{print $1":" $2}' | grep -v REPO)
    for s in $public_img; do
        #docker pull $s
        docker tag $s localhost:5000/$s
        docker push localhost:5000/$s
    done
}

#installDocker
pullRegistry
download_images
loadPublicImages
