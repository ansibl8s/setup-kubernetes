# Installation Guide

- [Installation Guide](#installation-guide)
  - [Prerequisite Generic Deployment Command](#prerequisite-generic-deployment-command)
  - [Ansible Configuration](#ansible-configuration)
  - [Traefik Documentations](#traefik-documentations)

## Prerequisite Generic Deployment Command

!!! attention
    The default configuration watches Ingress object from *all the namespaces*.
    To change this behavior use the flag `--providers.kubernetesIngress.namespace` to limit the scope to a particular namespace.
    See: <https://doc.traefik.io/traefik/providers/kubernetes-ingress/#namespaces>

!!! warning
    If multiple Ingresses define different paths for the same host, the ingress controller will merge the definitions.

!!! attention
    If you're using GKE you need to initialize your user as a cluster-admin with the following command:

```console
kubectl create clusterrolebinding cluster-admin-binding \
--clusterrole cluster-admin \
--user $(gcloud config get-value account)
```

## Ansible Configuration

- `traefik_namespace` (default `ingress-traefik`): namespace for installing Traefik.
- `traefik_ingress_tls_certbot_email` (defaults to `false`) to enable Traefik LetsEncrypt
   certificates integration. Otherwise we may set both `traefik_ingress_tls_chain` and
  `traefik_ingress_tls_key`, pointing to files on your Ansible deployment host. The first
  one being your server certifcate (ideally concatenated with the authorities involved in
  signing that server certificate), the latter pointing to the corresponding private key.
  If none of the `traefik_ingress_tls_` variables were set, then Traefik would generate
  self-signed certificates.
- `ingress_traefik_image_tag` (defaulkt: `v2.3`): the version of Traefik to deploy.
- `traefik_host_network` (default to `false): if set, Traefik would bind on your
  Kubernetes nodes, effectively exposing your ingress to clients outside Kubernetes SDN.
  By default, Traefik would not be available to external clients - up to you, to create
  either a NodePort or LoadBalancer Service, depending on your environment.

The default configuration disables hostNetwork, and leaves you free to expose
traefik however you want. To enable hostNetwork, set
`traefik_host_network: true`.

The default configuration enables both kubernetes regular ingress controller,
as well as traefik custom ingressroutes controller.

## Traefik Documentations

- [Install Traefik](https://doc.traefik.io/traefik/v2.3/getting-started/install-traefik/)
- [Traefik Kubernetes Ingress](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Traefik Kubernetes IngressRoute](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
