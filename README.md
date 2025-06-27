#1 cleanup_ocp_env.sh Remove old VMs, ignition, manifests 
#2 prep_openshift_network_env.sh Setup libvirt network, /etc/hosts, validations 
#3 generate_ignitions_and_boot_vms.sh Create manifests, embed .ign, start VMs 
#4 check_openshift_network_and_apache.sh Validate network state and Apache serving .ign
