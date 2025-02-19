#!/bin/bash
set -euxo pipefail

echo "CI_JOB_NAME is $CI_JOB_NAME"

if [[ "$CI_JOB_NAME" =~ "upgrade" ]]; then
  if [ "${UPGRADE_TEST}" == "false" ]; then
    echo "Job name contains 'upgrade', but UPGRADE_TEST='false'"
    exit 1
  fi
else
  if [ "${UPGRADE_TEST}" != "false" ]; then
    echo "UPGRADE_TEST!='false', but job names does not contain 'upgrade'"
    exit 1
  fi
fi

# Check out latest tag if testing upgrade
if [ "${UPGRADE_TEST}" != "false" ]; then
  git fetch --all && git checkout "$KUBESPRAY_VERSION"
  # Checkout the current tests/ directory ; even when testing old version,
  # we want the up-to-date test setup/provisionning
  git checkout "${CI_COMMIT_SHA}" -- tests/
fi

export ANSIBLE_REMOTE_USER=$SSH_USER
export ANSIBLE_BECOME=true
export ANSIBLE_BECOME_USER=root
export ANSIBLE_INVENTORY=/tmp/inventory/

cat > requirements.yaml <<EOF
collections:
- name: kubernetes.core
  version: '>=5.1.0'
  source: https://galaxy.ansible.com
EOF

make -C tests INVENTORY_DIR=${ANSIBLE_INVENTORY} create-${CI_PLATFORM} -s

# Test collection build and install by installing our collection, emptying our repository, adding
# cluster.yml, reset.yml, and remote-node.yml files that simply point to our collection's playbooks, and then
# running the same tests as before
if [[ "${CI_JOB_NAME}" =~ "collection" ]]; then
  # Build and install collection
  ansible-galaxy collection build
  ansible-galaxy collection install kubernetes_sigs-kubespray-$(grep "^version:" galaxy.yml | awk '{print $2}').tar.gz

  # Simply remove all of our files and directories except for our tests directory
  # to be absolutely certain that none of our playbooks or roles
  # are interfering with our collection
  find -mindepth 1 -maxdepth 1 ! -regex './\(tests\|inventory\)' -exec rm -rfv {} +

cat > cluster.yml <<EOF
- name: Install Kubernetes
  ansible.builtin.import_playbook: kubernetes_sigs.kubespray.cluster
EOF

cat > upgrade-cluster.yml <<EOF
- name: Install Kubernetes
  ansible.builtin.import_playbook: kubernetes_sigs.kubespray.upgrade-cluster
EOF

cat > reset.yml <<EOF
- name: Remove Kubernetes
  ansible.builtin.import_playbook: kubernetes_sigs.kubespray.reset
EOF

cat > remove-node.yml <<EOF
- name: Remove node from Kubernetes
  ansible.builtin.import_playbook: kubernetes_sigs.kubespray.remove_node
EOF

fi

ansible-playbook tests/cloud_playbooks/wait-for-ssh.yml

run_playbook () {
playbook=$1
shift
# We can set --limit here and still pass it as supplemental args because `--limit`  is a 'last one wins' option
ansible-playbook \
    -e @tests/common_vars.yml \
    -e @tests/files/${CI_JOB_NAME}.yml \
    -e local_release_dir=${PWD}/downloads \
    "$@" \
    ${playbook}
}



## START KUBESPRAY

# Create cluster
run_playbook cluster.yml

# Repeat deployment if testing upgrade
if [ "${UPGRADE_TEST}" != "false" ]; then
  git checkout "${CI_COMMIT_SHA}"

  case "${UPGRADE_TEST}" in
    "basic")
        run_playbook cluster.yml
        ;;
    "graceful")
        run_playbook upgrade-cluster.yml
        ;;
    *)
        ;;
  esac
fi

# Test control plane recovery
if [ "${RECOVER_CONTROL_PLANE_TEST}" != "false" ]; then
    run_playbook reset.yml --limit "${RECOVER_CONTROL_PLANE_TEST_GROUPS}" -e reset_confirmation=yes
    run_playbook recover-control-plane.yml -e etcd_retries=10 --limit "etcd:kube_control_plane"
fi

# Tests Cases
## Test Control Plane API
run_playbook tests/testcases/010_check-apiserver.yml
run_playbook tests/testcases/015_check-nodes-ready.yml

## Test that all nodes are Ready

if [[ ! ( "$CI_JOB_NAME" =~ "macvlan" ) ]]; then
    run_playbook tests/testcases/020_check-pods-running.yml
    run_playbook tests/testcases/030_check-network.yml
    if [[ ! ( "$CI_JOB_NAME" =~ "hardening" ) ]]; then
      # TODO: We need to remove this condition by finding alternative container
      # image instead of netchecker which doesn't work at hardening environments.
      run_playbook tests/testcases/040_check-network-adv.yml
    fi
fi

## Kubernetes conformance tests
run_playbook tests/testcases/100_check-k8s-conformance.yml

# Test node removal procedure
if [ "${REMOVE_NODE_CHECK}" = "true" ]; then
  run_playbook remove-node.yml -e skip_confirmation=yes -e node=${REMOVE_NODE_NAME}
fi

# Clean up at the end, this is to allow stage1 tests to include cleanup test
if [ "${RESET_CHECK}" = "true" ]; then
  run_playbook reset.yml -e reset_confirmation=yes
fi
