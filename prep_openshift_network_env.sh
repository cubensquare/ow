#!/bin/bash

set -e

# === CONFIGURATION ===
NET_NAME="openshift"
BRIDGE_NAME="virbr1"
NET_XML="/tmp/virt-net.xml"
HOST_ENTRIES_FILE="/etc/hosts"
OCP_DIR="/root/ocp"
RHCOS_ISO_PATTERN="rhcos-4.16.3-x86_64-live.iso"
INSTALLER_BIN="/usr/local/bin/openshift-install"
PULL_SECRET_PATH="/root/pull-secret.json"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

# Define node MAC-IP mapping
declare -A NODE_MAP=(
  [bootstrap]="52:54:00:0f:f4:11 192.168.126.170"
  [master0]="52:54:00:f6:01:2a 192.168.126.196"
  [worker1]="52:54:00:45:8a:73 192.168.126.147"
)

CLUSTER_NAME="test-cluster"
BASE_DOMAIN="cubensquare-lab.com"

echo "🧹 Cleaning up any existing libvirt networks..."
for net in default openshift; do
  if virsh net-info "$net" >/dev/null 2>&1; then
    virsh net-destroy "$net" || true
    virsh net-undefine "$net" || true
    echo "✅ Removed existing network: $net"
  fi
done

echo "🛠 Generating new virt-net.xml"
cat <<EOF > $NET_XML
<network>
  <name>$NET_NAME</name>
  <forward mode='nat'/>
  <bridge name='$BRIDGE_NAME' stp='on' delay='0'/>
  <ip address='192.168.126.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.126.100' end='192.168.126.200'/>
      <host mac='${NODE_MAP[bootstrap]%% *}' name='bootstrap' ip='${NODE_MAP[bootstrap]##* }'/>
      <host mac='${NODE_MAP[master0]%% *}' name='master0' ip='${NODE_MAP[master0]##* }'/>
      <host mac='${NODE_MAP[worker1]%% *}' name='worker1' ip='${NODE_MAP[worker1]##* }'/>
    </dhcp>
  </ip>
</network>
EOF

echo "🧱 Defining and starting network..."
virsh net-define $NET_XML
virsh net-start $NET_NAME
virsh net-autostart $NET_NAME
echo "✅ Network '$NET_NAME' is active and autostarted."

echo "🧾 Updating /etc/hosts with OpenShift DNS entries..."
for node in "${!NODE_MAP[@]}"; do
  ip="${NODE_MAP[$node]##* }"
  echo "$ip $node.$CLUSTER_NAME.$BASE_DOMAIN $node" >> /tmp/hosts_ocp_entries
done

# Add required OpenShift FQDNs
echo "${NODE_MAP[master0]##* } api.$CLUSTER_NAME.$BASE_DOMAIN" >> /tmp/hosts_ocp_entries
echo "${NODE_MAP[master0]##* } api-int.$CLUSTER_NAME.$BASE_DOMAIN" >> /tmp/hosts_ocp_entries

# Remove old entries if any
sed -i "/$CLUSTER_NAME.$BASE_DOMAIN/d" $HOST_ENTRIES_FILE
cat /tmp/hosts_ocp_entries >> $HOST_ENTRIES_FILE
rm /tmp/hosts_ocp_entries

chmod 644 $HOST_ENTRIES_FILE
echo "✅ /etc/hosts updated with cluster entries."

echo "🔍 Verifying required files before proceeding..."

[ -f "$INSTALLER_BIN" ] && echo "✅ openshift-install binary found: $INSTALLER_BIN" || { echo "❌ openshift-install not found!"; exit 1; }
[ -f "$PULL_SECRET_PATH" ] && echo "✅ Pull secret found: $PULL_SECRET_PATH" || { echo "❌ Pull secret missing!"; exit 1; }
[ -f "$SSH_KEY_PATH" ] && echo "✅ SSH public key found: $SSH_KEY_PATH" || { echo "❌ SSH key not found!"; exit 1; }

if ls $OCP_DIR/$RHCOS_ISO_PATTERN >/dev/null 2>&1; then
  echo "✅ RHCOS ISO found: $RHCOS_ISO_PATTERN"
else
  echo "❌ RHCOS ISO ($RHCOS_ISO_PATTERN) not found in $OCP_DIR"
  exit 1
fi

echo "🎉 Environment is ready. You may now run your ignition creation and VM scripts."
