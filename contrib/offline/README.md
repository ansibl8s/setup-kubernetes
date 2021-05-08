# Offline deployment

## manage-offline-container-images.sh

Container image collecting script for offline deployment

This script has two features:
(1) Get container images from an environment which is deployed online.
(2) Deploy local container registry and register the container images to the registry.

Step(1) should be done online site as a preparation, then we bring the gotten images
to the target offline environment.
Then we will run step(2) for registering the images to local registry.

Step(1) can be operated with:

```shell
manage-offline-container-images.sh   create
```

Step(2) can be operated with:

```shell
manage-offline-container-images.sh   register
```

## generate_list.sh

This script generates the list of downloaded files and the list of container images by `roles/download/defaults/main.yml` file.

Run this script will generates three files, all downloaded files url in files.list, all container images in images.list, all component version in generate.sh.

```shell
bash generate_list.sh
tree temp
temp
├── files.list
├── generate.sh
└── images.list
0 directories, 3 files
```

In some cases you may want to update some component version, you can edit `generate.sh` file, then run `bash generate.sh | grep 'https' > files.list` to update file.list or run `bash generate.sh | grep -v 'https'> images.list` to update images.list.
