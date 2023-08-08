#!/usr/bin/env bats
#
# Copyright (c) 2021 Apple Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../common.bash"
load "${BATS_TEST_DIRNAME}/tests_common.sh"
load "${BATS_TEST_DIRNAME}/lib.sh"

setup() {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"
	get_pod_config_dir
}

@test "configmap update works, and preserves symlinks" {
        pod_name="inotify-configmap-testing"

        # Create configmap for my deployment
        kubectl apply -f "${pod_config_dir}"/inotify-configmap.yaml

        # Create deployment that expects identity-certs
        kubectl apply -f "${pod_config_dir}"/inotify-configmap-pod.yaml
        wait_pod_to_be_ready "$pod_name"

        # Update configmap
        kubectl apply -f "${pod_config_dir}"/inotify-updated-configmap.yaml

        # Ideally we'd wait for the pod to complete...
        sleep 120

        # Verify we saw the update
        result=$(kubectl get pod "$pod_name" --output="jsonpath={.status.containerStatuses[]}")
        echo $result | grep -vq Error

        kubectl delete configmap cm
}



teardown() {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"
	# Debugging information
	kubectl describe "pod/$pod_name"
	kubectl delete pod "$pod_name"
}
