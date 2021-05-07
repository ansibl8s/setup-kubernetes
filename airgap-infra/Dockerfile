FROM ubuntu:bionic as ubuntu

RUN apt-get update
RUN apt-get install -y dpkg-dev wget gnupg2 curl

ARG ubuntu_packages="software-properties-common docker-ce docker-ce-cli apt-transport-https ca-certificates curl containerd.io"

WORKDIR /opt/packages/deb

RUN distribution=bionic && \
    curl -s -L https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    echo 'deb [trusted=yes] https://download.docker.com/linux/ubuntu/ bionic stable' > /etc/apt/sources.list.d/docker.list

RUN apt update

RUN chown -R _apt /opt/packages/deb/

RUN apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances $ubuntu_packages | grep "^\w" | sort -u)

RUN dpkg-scanpackages . | gzip -9c > Packages.gz

FROM centos as centos

WORKDIR /opt/packages/rpm

RUN yum install wget curl epel-release createrepo yum-utils -y

ARG centos_packages="containerd.io docker-ce docker-ce-cli yum-utils"

RUN yum update -y

RUN yumdownloader --resolve $centos_packages

RUN createrepo --update --workers=4 .

FROM nginx

RUN apt-get update

RUN apt install wget -y

COPY nginx_default.conf /etc/nginx/conf.d/default.conf

WORKDIR /usr/share/nginx/html

COPY --from=ubuntu /opt/packages/ .

COPY --from=centos /opt/packages/ .

WORKDIR /usr/share/nginx/html/kubernetes/

COPY kubernetes/ .
