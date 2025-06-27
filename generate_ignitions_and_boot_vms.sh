#!/bin/bash

set -e

# === CONFIGURATION ===
OCP_DIR="/root/ocp"
RHCOS_ISO="$OCP_DIR/rhcos-4.16.3-x86_64-live.iso"
INSTALLER_BIN="/usr/local/bin/openshift-install"
LOG_DIR="$OCP_DIR/logs"
mkdir -p "$LOG_DIR"

# VM MACs and IPs
declare -A VM_CONFIGS=(
  [bootstrap]="52:54:00:0f:f4:11 192.168.126.170"
  [master0]="52:54:00:f6:01:2a 192.168.126.196"
  [worker1]="52:54:00:45:8a:73 192.168.126.147"
)

# === STEP 1: Validate RHCOS ISO ===
echo "🔍 Validating RHCOS ISO..."
if [ ! -f "$RHCOS_ISO" ]; then
  echo "❌ RHCOS ISO not found: $RHCOS_ISO"
  exit 1
fi

# Basic ISO file validation
file "$RHCOS_ISO"
if ! file "$RHCOS_ISO" | grep -q "ISO 9660"; then
  echo "❌ ISO format invalid. Please re-download."
  exit 1
fi

# === STEP 2: Generate manifests and ignition files ===
echo "📁 Generating manifests..."
$INSTALLER_BIN create manifests --dir="$OCP_DIR" | tee "$LOG_DIR/create-manifests.log"

echo "🔥 Generating ignition configs..."
$INSTALLER_BIN create ignition-configs --dir="$OCP_DIR" | tee "$LOG_DIR/create-ignitions.log"

# === STEP 3: Embed .ign into ISOs ===
for role in bootstrap master worker; do
  echo "🧩 Embedding ${role}.ign into ISO..."
  podman run -it --rm -v "$OCP_DIR":/data quay.io/coreos/coreos-installer:release \
    iso ignition embed \
    -i "/data/${role}.ign" \
    -o "/data/rhcos-${role}.iso" \
    "/data/rhcos-4.16.3-x86_64-live.iso" \
    | tee "$LOG_DIR/iso-embed-${role}.log"
done

# === STEP 4: Create and boot VMs ===
echo "🚀 Launching VMs..."

declare -A MEMORY=( ["bootstrap"]=16384 ["master0"]=16384 ["worker1"]=8192 )
declare -A VCPUS=( ["bootstrap"]=4 ["master0"]=4 ["worker1"]=4 )

for vm in "${!VM_CONFIGS[@]}"; do
  MAC="${VM_CONFIGS[$vm]%% *}"
  IP="${VM_CONFIGS[$vm]##* }"
  ROLE_TYPE="${vm/bootstrap/bootstrap}"
  ROLE_TYPE="${ROLE_TYPE/master/master}"
  ROLE_TYPE="${ROLE_TYPE/worker/worker}"

  echo "🖥️ Creating VM: $vm (MAC: $MAC, IP: $IP)"
  virt-install \
    --name="$vm" \
    --memory="${MEMORY[$vm]}" \
    --vcpus="${VCPUS[$vm]}" \
    --disk path="/var/lib/libvirt/images/${vm}.qcow2",size=50,format=qcow2 \
    --os-variant=fedora-coreos-stable \
    --network network=openshift,model=virtio,mac="$MAC" \
    --graphics none \
    --console pty,target_type=serial \
    --cdrom "$OCP_DIR/rhcos-${ROLE_TYPE}.iso" \
    --noautoconsole \
    --check path_in_use=off \
    | tee "$LOG_DIR/virt-install-${vm}.log"

  echo "✅ VM $vm created. To access console:"
  echo "    virsh console $vm"
done

echo "🎉 All VMs launched. Console access available via virsh."
echo "📁 Logs stored in $LOG_DIR"
echo "🔍 Run the following to check bootstrap progress:"
echo "    openshift-install wait-for bootstrap-complete --dir=$OCP_DIR --log-level=info"
