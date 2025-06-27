#!/bin/bash

set -e

# VM and storage details
VM_NAMES=("bootstrap" "master0" "worker1")
IMG_DIR="/var/lib/libvirt/images"
OCP_DIR="/root/ocp"

echo "🧹 Cleaning up OpenShift VMs and ignition artifacts..."

for vm in "${VM_NAMES[@]}"; do
  echo "🔍 Checking VM: $vm"
  if virsh dominfo "$vm" >/dev/null 2>&1; then
    echo "⚠️  VM $vm exists. Destroying and undefining..."
    virsh destroy "$vm" || true
    virsh undefine "$vm" --remove-all-storage || {
      echo "🧽 Removing storage manually for $vm..."
      rm -f "$IMG_DIR/$vm.qcow2"
    }
    echo "✅ VM $vm cleaned up."
  else
    echo "✅ VM $vm does not exist."
  fi
done

echo "🧯 Cleaning up .ign files and manifest files in $OCP_DIR..."
rm -f $OCP_DIR/*.ign
rm -rf $OCP_DIR/manifests
rm -rf $OCP_DIR/auth

echo "✅ Ignition files and manifests removed."

echo "🗂 Checking leftover RHCOS ISOs..."
find $OCP_DIR -type f -name "rhcos-*-live.iso"

echo "✅ Cleanup complete. Ready for fresh ignition and VM creation."
