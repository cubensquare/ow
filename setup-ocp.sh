#!/usr/bin/env bash
# ==================================================================
#  OpenShift IPI helper for Proxmox host
#  • Downloads installer, client, RHCOS ISO+rootfs
#  • Builds install-config.yaml
#  • Generates Ignition files
#  • Tested on Proxmox VE 8 / Debian 12
# ==================================================================
set -euo pipefail

### === 0. EDIT THESE VARIABLES ===================================
# OpenShift & RHCOS version (must match)
OCP_VERSION="4.14.20"             # installer & client
RHCOS_VERSION="4.14.15"           # ISO & rootfs (same major/minor)

# Cluster basics
BASE_DOMAIN="lab.example"         # e.g. lab.example
CLUSTER_NAME="demo"               # e.g. demo (will form demo.lab.example)

# Paths to your secrets
PULL_SECRET_FILE="$HOME/pull-secret.json"   # download from cloud.redhat.com
SSH_PUB_KEY_FILE="$HOME/.ssh/id_rsa.pub"    # existing public key

# Working directory
WORKDIR="/var/lib/openshift-installer"
# ================================================================

BIN_DIR="/usr/local/bin"
DOWNLOADS="$WORKDIR/downloads"
IGN_DIR="$WORKDIR/${CLUSTER_NAME}"

mkdir -p "$DOWNLOADS" "$IGN_DIR"

echo "▶︎ Using workdir: $WORKDIR"
echo "▶︎ Download cache: $DOWNLOADS"
echo "▶︎ Ignition output: $IGN_DIR"
echo

### === 1. Download installer & client ===
CLIENT_TAR="openshift-client-linux.tar.gz"
INST_TAR="openshift-install-linux.tar.gz"

CLIENT_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}/${CLIENT_TAR}"
INST_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}/${INST_TAR}"

echo "⬇️  Downloading installer & client…"
for url in "$CLIENT_URL" "$INST_URL"; do
  file="$DOWNLOADS/$(basename "$url")"
  [[ -f "$file" ]] || curl -L -o "$file" "$url"
done

tar -xzf "$DOWNLOADS/$CLIENT_TAR" -C "$DOWNLOADS"
tar -xzf "$DOWNLOADS/$INST_TAR"   -C "$DOWNLOADS"
sudo install -m 0755 "$DOWNLOADS/oc" "$DOWNLOADS/openshift-install" "$BIN_DIR"

echo "   ✔ Installed oc & openshift-install into $BIN_DIR"
echo

### === 2. Download RHCOS ISO & rootfs ===
ISO_FILE="rhcos-${RHCOS_VERSION}-live.x86_64.iso"
ROOTFS_FILE="rhcos-${RHCOS_VERSION}-live-rootfs.x86_64.img"

BASE_DEP="https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/${RHCOS_VERSION}"
ISO_URL="${BASE_DEP}/${ISO_FILE}"
ROOTFS_URL="${BASE_DEP}/${ROOTFS_FILE}"

for url in "$ISO_URL" "$ROOTFS_URL"; do
  file="$DOWNLOADS/$(basename "$url")"
  if [[ ! -f "$file" ]]; then
    echo "⬇️  Fetching $(basename "$url") …"
    curl -L -o "$file" "$url"
  fi
done
echo "   ✔ RHCOS ISO & rootfs downloaded"
echo

### === 3. Build install-config.yaml ===
if [[ ! -f "$PULL_SECRET_FILE" ]]; then
  echo "❌ Pull-secret file not found: $PULL_SECRET_FILE"
  exit 1
fi
if [[ ! -f "$SSH_PUB_KEY_FILE" ]]; then
  echo "❌ SSH public key not found: $SSH_PUB_KEY_FILE"
  exit 1
fi

cat > "$IGN_DIR/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  none: {}          # bare-metal / Proxmox; no platform IPI
compute:
- name: worker
  replicas: 2
controlPlane:
  name: master
  replicas: 1
pullSecret: |
$(cat "$PULL_SECRET_FILE" | sed 's/^/  /')
sshKey: |
$(cat "$SSH_PUB_KEY_FILE" | sed 's/^/  /')
EOF

echo "📝 Generated install-config.yaml"
echo

### === 4. Create manifests & Ignition ===
cd "$IGN_DIR"
echo "⚙️  Running openshift-install…"
openshift-install create manifests --dir="$IGN_DIR"
openshift-install create ignition-configs --dir="$IGN_DIR"
echo "   ✔ Ignition files ready:"
ls -1 "$IGN_DIR"/*.ign
echo

### === 5. Final instructions ===
cat <<'EOT'

🚀 NEXT STEPS (in the Proxmox GUI)
----------------------------------
1. Upload the following into your Proxmox ISO storage:
     - rhcos-*-live.x86_64.iso          (boot ISO)
     - bootstrap.ign  (as tiny ISO, or serve via HTTP)
     - master.ign
     - worker.ign

2. Create four VMs:
     VM  | vCPU | RAM | Disk | Ignition
    -----|------|-----|------|----------
    900  |  4   | 8G  | 30G  | bootstrap.ign
    901  |  4   |16G  | 80G  | master.ign
    902  |  4   | 8G  | 70G  | worker.ign
    903  |  4   | 8G  | 70G  | worker.ign

3. Boot bootstrap VM first, then master, then workers.
   Monitor install from this host:
       openshift-install wait-for bootstrap-complete --dir $IGN_DIR --log-level=info

4. After bootstrap completes, delete the bootstrap VM and run:
       openshift-install wait-for install-complete --dir $IGN_DIR --log-level=info

5. Export kubeconfig:
       export KUBECONFIG=$IGN_DIR/auth/kubeconfig
       oc get nodes

Happy hacking! 💡
EOT
