#!/bin/bash
#
# Copyright (c) 2017-2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

[[ "${DEBUG}" != "" ]] && set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../common.bash"
source "${SCRIPT_PATH}/../cri-containerd/lib.sh"

# golang is installed in /usr/local/go/bin/ add that path
export PATH="$PATH:/usr/local/go/bin"

ARCH=$(uname -m)

containerd_runtime_type="io.containerd.kata-${KATA_HYPERVISOR}.v2"

containerd_shim_path="$(command -v containerd-shim)"

#containerd config file
export tmp_dir=$(mktemp -t -d test-cri-containerd.XXXX)
export REPORT_DIR="${tmp_dir}"
export CONTAINERD_CONFIG_FILE="${tmp_dir}/test-containerd-config"
export CONTAINERD_CONFIG_FILE_TEMP="${CONTAINERD_CONFIG_FILE}.temp"
export default_containerd_config_backup="$CONTAINERD_CONFIG_FILE.backup"

TESTS_UNION=(generic.bats)

function cleanup() {
	ci_cleanup
	[ -d "$tmp_dir" ] && rm -rf "${tmp_dir}"
}

trap cleanup EXIT

function err_report() {
	echo "::group::ERROR - containerd logs"
	echo "-------------------------------------"
	sudo journalctl -xe -t containerd
	echo "-------------------------------------"
	echo "::endgroup::"

	echo "::group::ERROR - Kata Containers logs"
	echo "-------------------------------------"
	sudo journalctl -xe -t kata
	echo "-------------------------------------"
	echo "::endgroup::"
}

function TestContainerMemoryUpdate() {
	if [[ "${KATA_HYPERVISOR}" != "qemu" ]] || [[ "${ARCH}" == "ppc64le" ]] || [[ "${ARCH}" == "s390x" ]]; then
		return
	fi

	test_virtio_mem=$1

	if [ $test_virtio_mem -eq 1 ]; then
		if [[ "$ARCH" != "x86_64" ]]; then
			return
		fi
		info "Test container memory update with virtio-mem"

		sudo sed -i -e 's/^#enable_virtio_mem.*$/enable_virtio_mem = true/g' "${kata_config}"
	else
		info "Test container memory update without virtio-mem"

		sudo sed -i -e 's/^enable_virtio_mem.*$/#enable_virtio_mem = true/g' "${kata_config}"
	fi

	testContainerStart

	vm_size=$(($(sudo crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
	if [ $vm_size -gt $((2*1024*1024*1024)) ] || [ $vm_size -lt $((2*1024*1024*1024-128*1024*1024)) ]; then
		testContainerStop
		die "The VM memory size $vm_size before update is not right"
	fi

	sudo crictl update --memory $((2*1024*1024*1024)) $cid
	sleep 1

	vm_size=$(($(sudo crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
	if [ $vm_size -gt $((4*1024*1024*1024)) ] || [ $vm_size -lt $((4*1024*1024*1024-128*1024*1024)) ]; then
		testContainerStop
		die "The VM memory size $vm_size after increase is not right"
	fi

	if [ $test_virtio_mem -eq 1 ]; then
		sudo crictl update --memory $((1*1024*1024*1024)) $cid
		sleep 1

		vm_size=$(($(sudo crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
		if [ $vm_size -gt $((3*1024*1024*1024)) ] || [ $vm_size -lt $((3*1024*1024*1024-128*1024*1024)) ]; then
			testContainerStop
			die "The VM memory size $vm_size after decrease is not right"
		fi
	fi

	testContainerStop
}

function getContainerSwapInfo() {
	swap_size=$(($(sudo crictl exec $cid cat /proc/meminfo | grep "SwapTotal:" | awk '{print $2}')*1024))
	# NOTE: these below two checks only works on cgroup v1
	swappiness=$(sudo crictl exec $cid cat /sys/fs/cgroup/memory/memory.swappiness)
	swap_in_bytes=$(sudo crictl exec $cid cat /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes)
}

function TestContainerSwap() {
	if [[ "${KATA_HYPERVISOR}" != "qemu" ]] || [[ "${ARCH}" != "x86_64" ]]; then
		return
	fi

	local container_yaml=${REPORT_DIR}/container.yaml
	local image="busybox:latest"

	info "Test container with guest swap"

	create_containerd_config "kata-${KATA_HYPERVISOR}" 1
	sudo sed -i -e 's/^#enable_guest_swap.*$/enable_guest_swap = true/g' "${kata_config}"

	# Test without swap device
	testContainerStart
	getContainerSwapInfo
	# Current default swappiness is 60
	if [ $swappiness -ne 60 ]; then
		testContainerStop
		die "The VM swappiness $swappiness without swap device is not right"
	fi
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		testContainerStop
		die "The VM swap_in_bytes $swap_in_bytes without swap device is not right"
	fi
	if [ $swap_size -ne 0 ]; then
		testContainerStop
		die "The VM swap size $swap_size without swap device is not right"
	fi
	testContainerStop

	# Test with swap device
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-swap
  namespace: default
  uid: busybox-swap-uid
annotations:
  io.katacontainers.container.resource.swappiness: "100"
  io.katacontainers.container.resource.swap_in_bytes: "1610612736"
linux:
  resources:
    memory_limit_in_bytes: 1073741824
image:
  image: "$image"
command:
- top
EOF

	testContainerStart 1
	getContainerSwapInfo
	testContainerStop

	if [ $swappiness -ne 100 ]; then
		die "The VM swappiness $swappiness with swap device is not right"
	fi
	if [ $swap_in_bytes -ne 1610612736 ]; then
		die "The VM swap_in_bytes $swap_in_bytes with swap device is not right"
	fi
	if [ $swap_size -ne 536870912 ]; then
		die "The VM swap size $swap_size with swap device is not right"
	fi

	# Test without swap_in_bytes
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-swap
  namespace: default
  uid: busybox-swap-uid
annotations:
  io.katacontainers.container.resource.swappiness: "100"
linux:
  resources:
    memory_limit_in_bytes: 1073741824
image:
  image: "$image"
command:
- top
EOF

	testContainerStart 1
	getContainerSwapInfo
	testContainerStop

	if [ $swappiness -ne 100 ]; then
		die "The VM swappiness $swappiness without swap_in_bytes is not right"
	fi
	# swap_in_bytes is not set, it should be a value that bigger than 1125899906842624
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		die "The VM swap_in_bytes $swap_in_bytes without swap_in_bytes is not right"
	fi
	if [ $swap_size -ne 1073741824 ]; then
		die "The VM swap size $swap_size without swap_in_bytes is not right"
	fi

	# Test without memory_limit_in_bytes
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-swap
  namespace: default
  uid: busybox-swap-uid
annotations:
  io.katacontainers.container.resource.swappiness: "100"
image:
  image: "$image"
command:
- top
EOF

	testContainerStart 1
	getContainerSwapInfo
	testContainerStop

	if [ $swappiness -ne 100 ]; then
		die "The VM swappiness $swappiness without memory_limit_in_bytes is not right"
	fi
	# swap_in_bytes is not set, it should be a value that bigger than 1125899906842624
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		die "The VM swap_in_bytes $swap_in_bytes without memory_limit_in_bytes is not right"
	fi
	if [ $swap_size -ne 2147483648 ]; then
		die "The VM swap size $swap_size without memory_limit_in_bytes is not right"
	fi

	create_containerd_config "kata-${KATA_HYPERVISOR}"
}

function main() {

	info "Stop crio service"
	systemctl is-active --quiet crio && sudo systemctl stop crio

	info "Stop containerd service"
	systemctl is-active --quiet containerd && stop_containerd

	# Configure enviroment if running in CI
	ci_config

	pushd "containerd"
	make GO_BUILDTAGS="no_btrfs"
	sudo -E PATH="${PATH}:/usr/local/bin" \
		make install
	popd

	create_containerd_config "kata-${KATA_HYPERVISOR}"

	# trap error for print containerd and kata-containers log
	trap err_report ERR

	# TestContainerSwap is currently failing with GHA.
	# Let's re-enable it as soon as we get it to work.
	# Reference: https://github.com/kata-containers/kata-containers/issues/7410
	# TestContainerSwap

	# TODO: runtime-rs doesn't support memory update currently
	#if [ "$KATA_HYPERVISOR" != "dragonball" ]; then
	#	TestContainerMemoryUpdate 1
	#	TestContainerMemoryUpdate 0
	#fi

	pushd "$SCRIPT_PATH"
	bats ${TESTS_UNION[@]}
	popd
}

main
