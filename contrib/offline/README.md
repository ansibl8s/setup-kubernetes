# Offline deployment

## manage-offline-container-images.sh

Container image collecting script for offline deployment

This script has two features:
(1) Get container images from an environment which is deployed online, or set `IMAGES_FROM_FILE`
    environment variable to get images from a file (e.g. temp/images.list after running the
    ./generate_list.sh script).
(2) Deploy local container registry and register the container images to the registry.

Step(1) should be done online site as a preparation, then we bring the gotten images
to the target offline environment. if images are from a private registry,
you need to set `PRIVATE_REGISTRY` environment variable.
Then we will run step(2) for registering the images to local registry, or to an existing
registry set by the `DESTINATION_REGISTRY` environment variable. By default, the local registry
will run on port 5000. This can be changed with the `REGISTRY_PORT` environment variable

Step(1) can be operated with:

```shell
manage-offline-container-images.sh   create
```

Step(2) can be operated with:

```shell
manage-offline-container-images.sh   register
```

## generate_list.sh

This script generates the list of downloaded files and the list of container images by `roles/kubespray-defaults/defaults/main/download.yml` file.

Run this script will execute `generate_list.yml` playbook in kubespray root directory and generate four files,
all downloaded files url in files.list, all container images in images.list, jinja2 templates in *.template.

```shell
./generate_list.sh
tree temp
temp
├── files.list
├── files.list.template
├── images.list
└── images.list.template
0 directories, 5 files
```

In some cases you may want to update some component version, you can declare version variables in ansible inventory file or group_vars,
then run `./generate_list.sh -i [inventory_file]` to update file.list and images.list.

## manage-offline-files.sh

This script will download all files according to `temp/files.list` and run nginx container to provide offline file download.

Step(1) generate `files.list`

```shell
./generate_list.sh
```

Step(2) download files and run nginx container

```shell
./manage-offline-files.sh
```

when nginx container is running, it can be accessed through <http://127.0.0.1:8080/>.

## upload2artifactory.py

After the steps above, this script can recursively upload each file under a directory to a generic repository in Artifactory.

Environment Variables:

- USERNAME -- At least permissions'Deploy/Cache' and 'Delete/Overwrite'.
- TOKEN -- Generate this with 'Set Me Up' in your user.
- BASE_URL -- The URL including the repository name.

Step(3) (optional) upload files to Artifactory

```shell
cd kubespray/contrib/offline/offline-files
export USERNAME=admin
export TOKEN=...
export BASE_URL=https://artifactory.example.com/artifactory/a-generic-repo/
./upload2artifactory.py
```
