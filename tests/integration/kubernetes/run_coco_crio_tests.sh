#!/bin/bash
#
# WARNING: This script is for LOCAL development and testing ONLY.
# DO NOT contribute this file upstream — it is not part of the CI pipeline.
# Use it to manually run the CoCo + CRI-O + k8s integration test flow on a dev machine.
#

set -o errexit
set -o nounset
set -o pipefail

#export DOCKER_REGISTRY=ghcr.io
#export DOCKER_REPO=kata-containers/kata-deploy-ci
#export DOCKER_TAG=
#export GH_PR_NUMBER=

export KATA_HOST_OS=ubuntu
export KATA_HYPERVISOR=qemu-coco-dev
export KUBERNETES=k0s
export CONTAINER_RUNTIME=crio
export KUBERNETES_EXTRA_PARAMS='--cri-socket remote:unix:///var/run/crio/crio.sock --kubelet-extra-args --cgroup-driver="systemd"'
export K8S_TEST_HOST_TYPE=all
export KBS=true
export KBS_INGRESS=nodeport
export SNAPSHOTTER=nydus
export PULL_TYPE=guest-pull

prep_env() {
    echo "== SETUP CRIO =="
    ./gha-run.sh setup-crio
    echo "== DEPLOY K8S =="
    ./gha-run.sh deploy-k8s
    echo "== INSTALL BATS =="
    ./gha-run.sh install-bats
    echo "== DEPLOY KATA =="
    ./gha-run.sh deploy-kata
    echo "== DEPLOY COCO KBS =="
    ./gha-run.sh deploy-coco-kbs
    echo "== INSTALL KBS CLIENT =="
    ./gha-run.sh install-kbs-client
}

teardown_env() {
    echo "== CLEANUP =="
    ./gha-run.sh cleanup
}

run_tests() {
    echo "== RUN TESTS =="
    ./gha-run.sh run-tests
}

main() {
    if [ $# -gt 0 ]; then
        case $1 in
        "-d") teardown_env ;;
        "-t") run_tests ;;
        esac
        return
    fi

    prep_env
    run_tests
}

main "$@"
