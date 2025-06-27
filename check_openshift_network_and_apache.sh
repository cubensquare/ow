#!/bin/bash

# Define expected IPs and MACs
declare -A nodes
nodes=(
  [bootstrap]="52:54:00:0f:f4:11 192.168.126.170"
  [master0]="52:54:00:f6:01:2a 192.168.126.196"
  [worker1]="52:54:00:45:8a:73 192.168.126.147"
)

echo "🔍 Checking if 'openshift' virtual network is active..."
if virsh net-list --all | grep -q 'openshift'; then
  echo "✅ openshift network is defined."
else
  echo "❌ openshift network is not defined."
  exit 1
fi

if virsh net-list | grep -q 'openshift'; then
  echo "✅ openshift network is active."
else
  echo "❌ openshift network is not active. Starting it..."
  virsh net-start openshift || { echo "❌ Failed to start openshift network."; exit 1; }
fi

if virsh net-autostart openshift; then
  echo "✅ openshift network is set to autostart."
fi

echo "🧾 Verifying MAC ↔ IP ↔ Hostname bindings..."
for name in "${!nodes[@]}"; do
  mac=$(echo ${nodes[$name]} | cut -d' ' -f1)
  ip=$(echo ${nodes[$name]} | cut -d' ' -f2)
  echo "   $name -> MAC: $mac , IP: $ip"
done

echo "🧪 Checking Apache HTTP server status..."
if systemctl is-active apache2 >/dev/null 2>&1 || systemctl is-active httpd >/dev/null 2>&1; then
  echo "✅ Apache is running."
else
  echo "❌ Apache is not running. Start it with: sudo systemctl start apache2"
  exit 1
fi

echo "📁 Checking .ign files in /var/www/html..."
cd /var/www/html || { echo "❌ /var/www/html not found"; exit 1; }

for ign in bootstrap.ign master.ign worker.ign; do
  if [ -f "$ign" ]; then
    echo "✅ Found $ign"
  else
    echo "❌ Missing $ign"
  fi
done

echo "🌐 Curl test from host to local Apache server (http://192.168.0.11/IGN)..."
for ign in bootstrap.ign master.ign worker.ign; do
  curl -s --head http://192.168.0.11/$ign | head -n 1 | grep "200 OK" > /dev/null
  if [ $? -eq 0 ]; then
    echo "✅ $ign accessible"
  else
    echo "❌ $ign not accessible from host"
  fi
done

echo "📌 If VMs are running, test curl from inside them with:"
echo "    curl http://192.168.126.1/bootstrap.ign"

echo "🎉 All checks done. If there are ❌ above, please fix them before proceeding."
