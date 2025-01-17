#!/usr/bin/env bats
#
# Copyright (c) 2025 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../common.bash"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	get_pod_config_dir
	policy_settings_dir="$(create_tmp_policy_settings_dir "${pod_config_dir}")"
}

doTest() {
	local pod_yaml_file="$1"
	local pod_status="$2"
	local msg="$3"

	auto_generate_policy "${policy_settings_dir}" "${pod_yaml_file}"

	# Create a pod that sends a termination message
	kubectl create -f "$pod_yaml_file"

	# Wait the pod reach a desired status
	waitForProcess "30" "5" "kubectl get -f "$pod_yaml_file" | grep $pod_status"

	# Check it received the termination message
	kubectl describe -f "$pod_yaml_file" | grep "Message:  $msg"	
}

@test "Send termination message to default path" {
	pod_yaml_file="${pod_config_dir}/pod-terminationmessage.yaml"

	doTest "$pod_yaml_file" "Completed" "My message"
}

@test "Send termination message to arbitrary file" {
	pod_yaml_file="${pod_config_dir}/pod-terminationmessagepath.yaml"

	doTest "$pod_yaml_file" "Completed" "My message to /tmp/foo"
}

@test "Get termination message from logs" {
	pod_yaml_file="${pod_config_dir}/pod-terminationmessage-from-logs.yaml"

	doTest "$pod_yaml_file" "Error" "My message from logs"
}

teardown() {
	# Debugging information
	kubectl describe -f "$pod_yaml_file" || true

	kubectl delete -f "$pod_yaml_file" || true

	delete_tmp_policy_settings_dir "${policy_settings_dir}"
}
