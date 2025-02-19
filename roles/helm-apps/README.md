Role Name
=========

This role is intended to be used to fetch and deploy Helm Charts as part of
cluster installation or upgrading with kubespray.

Requirements
------------

The role needs to be executed on a host with access to the Kubernetes API, and
with the helm binary in place.

Role Variables
--------------

See meta/argument_specs.yml

Playbook example:

```yaml
---
- hosts: kube_control_plane[0]
  gather_facts: no
  roles:
    - name: helm-apps
      releases:
        - name: app
          namespace: app
          chart_ref: simple-app/simple-app
        - name: app2
          namespace: app
          chart_ref: simple-app/simple-app
          wait_timeout: "10m" # override the same option in `release_common_opts`
      repositories: "{{ repos }}"
        - name: simple-app
          url: "https://blog.leiwang.info/simple-app"
      release_common_opts: "{{ helm_params }}"
        wait_timeout: "5m"
```

OCI helm repo
-------------

You can also use oci helm repositories
oci does not require "repo add"
But "repo registry login" is required

```yaml
---
- hosts: kube_control_plane[0]
  gather_facts: no
  roles:
    - name: helm-apps
      releases:
        - name: app2
          namespace: app
          chart_ref: "oci://blog.leiwang.info:5000/simple-app"
      auths:
        - username: "user"
          password: "xxxx"
          host: "blog.leiwang.info:5000"
      release_common_opts: "{{ helm_params }}"
        wait_timeout: "5m"
```
