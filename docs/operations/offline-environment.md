# Offline environment

In case your servers don't have access to the internet directly (for example
when deploying on premises with security constraints), you need to get the
following artifacts in advance from another environment where has access to the internet.

* Some static files (zips and binaries)
* OS packages (rpm/deb files)
* Container images used by Kubespray. Exhaustive list depends on your setup
* [Optional] Python packages used by Kubespray (only required if your OS doesn't provide all python packages/versions
  listed in `requirements.txt`)
* [Optional] Helm chart files (only required if `helm_enabled=true`)

Then you need to setup the following services on your offline environment:

* an HTTP reverse proxy/cache/mirror to serve some static files (zips and binaries)
* an internal Yum/Deb repository for OS packages
* an internal container image registry that need to be populated with all container images used by Kubespray
* [Optional] an internal PyPi server for python packages used by Kubespray
* [Optional] an internal Helm registry for Helm chart files

You can get artifact lists with [generate_list.sh](/contrib/offline/generate_list.sh) script.
In addition, you can find some tools for offline deployment under [contrib/offline](/contrib/offline/README.md).

## Configure Inventory

Once all artifacts are accessible from your internal network, **adjust** the following variables
in your inventory to match your environment:

```yaml
# Registry overrides
kube_image_repo: "{{ registry_host }}"
gcr_image_repo: "{{ registry_host }}"
docker_image_repo: "{{ registry_host }}"
quay_image_repo: "{{ registry_host }}"
github_image_repo: "{{ registry_host }}"

kubeadm_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubeadm"
kubectl_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubectl"
kubelet_download_url: "{{ files_repo }}/kubernetes/{{ kube_version }}/kubelet"
# etcd is optional if you **DON'T** use etcd_deployment=host
etcd_download_url: "{{ files_repo }}/kubernetes/etcd/etcd-{{ etcd_version }}-linux-{{ image_arch }}.tar.gz"
cni_download_url: "{{ files_repo }}/kubernetes/cni/cni-plugins-linux-{{ image_arch }}-{{ cni_version }}.tgz"
crictl_download_url: "{{ files_repo }}/kubernetes/cri-tools/crictl-{{ crictl_version }}-{{ ansible_system | lower }}-{{ image_arch }}.tar.gz"
# If using Calico
calicoctl_download_url: "{{ files_repo }}/kubernetes/calico/{{ calico_ctl_version }}/calicoctl-linux-{{ image_arch }}"
# If using Calico with kdd
calico_crds_download_url: "{{ files_repo }}/kubernetes/calico/{{ calico_version }}.tar.gz"
# Containerd
containerd_download_url: "{{ files_repo }}/containerd-{{ containerd_version }}-linux-{{ image_arch }}.tar.gz"
runc_download_url: "{{ files_repo }}/runc.{{ image_arch }}"
nerdctl_download_url: "{{ files_repo }}/nerdctl-{{ nerdctl_version }}-{{ ansible_system | lower }}-{{ image_arch }}.tar.gz"
# Insecure registries for containerd
containerd_registries_mirrors:
  - prefix: "{{ registry_addr }}"
    mirrors:
      - host: "{{ registry_host }}"
        capabilities: ["pull", "resolve"]
        skip_verify: true

# CentOS/Redhat/AlmaLinux/Rocky Linux
## Docker / Containerd
docker_rh_repo_base_url: "{{ yum_repo }}/docker-ce/$releasever/$basearch"
docker_rh_repo_gpgkey: "{{ yum_repo }}/docker-ce/gpg"

# Fedora
## Docker
docker_fedora_repo_base_url: "{{ yum_repo }}/docker-ce/{{ ansible_distribution_major_version }}/{{ ansible_architecture }}"
docker_fedora_repo_gpgkey: "{{ yum_repo }}/docker-ce/gpg"
## Containerd
containerd_fedora_repo_base_url: "{{ yum_repo }}/containerd"
containerd_fedora_repo_gpgkey: "{{ yum_repo }}/docker-ce/gpg"

# Debian
## Docker
docker_debian_repo_base_url: "{{ debian_repo }}/docker-ce"
docker_debian_repo_gpgkey: "{{ debian_repo }}/docker-ce/gpg"
## Containerd
containerd_debian_repo_base_url: "{{ ubuntu_repo }}/containerd"
containerd_debian_repo_gpgkey: "{{ ubuntu_repo }}/containerd/gpg"
containerd_debian_repo_repokey: 'YOURREPOKEY'

# Ubuntu
## Docker
docker_ubuntu_repo_base_url: "{{ ubuntu_repo }}/docker-ce"
docker_ubuntu_repo_gpgkey: "{{ ubuntu_repo }}/docker-ce/gpg"
## Containerd
containerd_ubuntu_repo_base_url: "{{ ubuntu_repo }}/containerd"
containerd_ubuntu_repo_gpgkey: "{{ ubuntu_repo }}/containerd/gpg"
containerd_ubuntu_repo_repokey: 'YOURREPOKEY'
```

For the OS specific settings, just define the one matching your OS.
If you use the settings like the one above, you'll need to define in your inventory the following variables:

* `registry_host`: Container image registry. If you _don't_ use the same repository path for the container images that
  the ones defined
  in [kubesprays-defaults's role defaults](https://github.com/kubernetes-sigs/kubespray/blob/master/roles/kubespray-defaults/defaults/main/download.yml)
  , you need to override the `*_image_repo` for these container images. If you want to make your life easier, use the
  same repository path, you won't have to override anything else.
* `registry_addr`: Container image registry, but only have [domain or ip]:[port].
* `files_repo`: HTTP webserver or reverse proxy that is able to serve the files listed above. Path is not important, you
  can store them anywhere as long as it's accessible by kubespray. It's recommended to use `*_version` in the path so
  that you don't need to modify this setting everytime kubespray upgrades one of these components.
* `yum_repo`/`debian_repo`/`ubuntu_repo`: OS package repository depending on your OS, should point to your internal
  repository. Adjust the path accordingly. Used only for Docker/Containerd packages (if needed); other packages might
  be installed from other repositories. You might disable installing packages from other repositories by skipping
  the `system-packages` tag

## Install Kubespray Python Packages

### Recommended way: Kubespray Container Image

The easiest way is to use [kubespray container image](https://quay.io/kubespray/kubespray) as all the required packages
are baked in the image.
Just copy the container image in your private container image registry and you are all set!

### Manual installation

Look at the `requirements.txt` file and check if your OS provides all packages out-of-the-box (Using the OS package
manager). For those missing, you need to either use a proxy that has Internet access (typically from a DMZ) or setup a
PyPi server in your network that will host these packages.

If you're using an HTTP(S) proxy to download your python packages:

```bash
sudo pip install --proxy=https://[username:password@]proxyserver:port -r requirements.txt
```

When using an internal PyPi server:

```bash
# If you host all required packages
pip install -i https://pypiserver/pypi -r requirements.txt

# If you only need the ones missing from the OS package manager
pip install -i https://pypiserver/pypi package_you_miss
```

## Run Kubespray as usual

Once all artifacts are in place and your inventory properly set up, you can run kubespray with the
regular `cluster.yaml` command:

```bash
ansible-playbook -i inventory/my_airgap_cluster/hosts.yaml -b cluster.yml
```

If you use [Kubespray Container Image](#recommended-way:-kubespray-container-image), you can mount your inventory inside
the container:

```bash
docker run --rm -it -v path_to_inventory/my_airgap_cluster:inventory/my_airgap_cluster myprivateregisry.com/kubespray/kubespray:v2.14.0 ansible-playbook -i inventory/my_airgap_cluster/hosts.yaml -b cluster.yml
```
