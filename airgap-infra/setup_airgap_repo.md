# Setting Repo for Air Gap Installation

Requirements to setup repo for Air Gap installation,
  - Repo vm/machine used for installation should have internet access
  - The machine should be part of AirGap network
  - In this example we assumed ubuntu os is used

# Setup docker registry!
  - git clone kubespray.git
  - cd <kubespary>/airgap-infra/
  - bash docker_registry.sh
  
  All the images used for the installation is downloaded and pushed to the docker registry

# Setup deb, yum, binary repo!
 
  - Run "bash download_bin.sh"
  - Create the docker image using "docker build -t "<image-name>" ."
  - Run the created image "docker run -t -d --rm --name <container-name> -p 8083:80 <image-name>:latest"
  - Now the repo is running with 8083
  - update the variables for offline installation as per [https://github.com/kubernetes-sigs/kubespray/blob/master/docs/offline-environment.md]
 - files_repo, yum_repo , ubuntu_repo can be updated to <instance_ip>:8083

 
 
