#!/bin/sh

# Settings
PUBLIC_IP_ADDRESS='192.168.1.10'

if [ ! -f os_service_passwords.sh ]; then
  echo "Missing [os_service_passwords.sh] in current directory. Copy from controller node after running setup_controller.sh."
  exit
fi

# Set an ini value - requires the name be unique in the ini file
# Usage: set_ini_value INI_FILE SECTION_NAME FIELD_NAME FIELD_VALUE
set_ini_value() {
  INI_FILE=$1
  SECTION_NAME=$2
  FIELD_NAME=$3
  FIELD_VALUE=$4

SCRIPT="
#!/usr/bin/python
from configobj import ConfigObj
import sys

(ini_file,section,name,value) = sys.argv[1:]

config = ConfigObj(ini_file)
if section not in config:
  config[section] = dict()
config[section][name]=value
config.write()

"
  python -c "${SCRIPT}" "${INI_FILE}" "${SECTION_NAME}" "${FIELD_NAME}" "${FIELD_VALUE}"
}


# This will be set to the IP of the controller node
INTERNAL_IP_ADDRESS=`host controller. | awk '/ / {print $4}'`

# 1 Read in passwords from controller file
. ./os_service_passwords.sh


# 2 Install service and client
apt-get install -y nova-compute-kvm python-guestfs


# 3 Make current kernel readable by guestfs
dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-$(uname -r) || true

# 4 Make new kernels readable by guestfs
STATOVERRIDE_CONTENTS='
#!/bin/sh
version="$1"
# passing the kernel version is required
[ -z "${version}" ] && exit 0
dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-${version} || true
'
echo "${STATOVERRIDE_CONTENTS}" > /etc/kernel/postinst.d/statoverride
chmod +x /etc/kernel/postinst.d/statoverride

# 5 Replace entire nova.conf
NOVA_CONF_CONTENT="
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
iscsi_helper=tgtadm
libvirt_use_virtio_for_bridges=True
connection_type=libvirt
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
volumes_path=/var/lib/nova/volumes
enabled_apis=ec2,osapi_compute,metadata
ec2_dmz_host=controller

# Use keystone for auth
auth_strategy=keystone

# Use RabbitMQ
#rpc_backend = nova.rpc.impl_kombu
rpc_backend = rabbit
rabbit_host = controller
rabbit_userid = guest
rabbit_password = ${RABBIT_PW}

# Point to controller
my_ip=${INTERNAL_IP_ADDRESS}
vnc_enabled = True
vncserver_listen=0.0.0.0
vncserver_proxyclient_address=${INTERNAL_IP_ADDRESS}
novncproxy_base_url = http://${PUBLIC_IP_ADDRESS}:6080/vnc_auto.html


# Glance image storage
glance_host = image

# OpenVSwitch Networking using Neutron
network_api_class = nova.network.neutronv2.api.API
neutron_url = http://controller:9696
neutron_auth_strategy = keystone
neutron_admin_tenant_name = service
neutron_admin_username = neutron
neutron_admin_password = ${NEUTRON_OS_PW}
neutron_admin_auth_url = http://controller:35357/v2.0
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
security_group_api = neutron
service_neutron_metadata_proxy = True
neutron_metadata_proxy_shared_secret = ${NEUTRON_METADATA_SHARED_SECRET}


# Ceilometer usage tracking
instance_usage_audit = True
instance_usage_audit_period = hour
notify_on_state_change = vm_and_task_state
notification_driver = nova.openstack.common.notifier.rpc_notifier
notification_driver = ceilometer.compute.nova_notifier


[database]
connection = mysql://nova:${NOVA_DB_PW}@controller/nova


[keystone_authtoken]
auth_uri = http://controller:5000
auth_host = controller
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = ${NOVA_OS_PW}
"

echo "${NOVA_CONF_CONTENT}" > /etc/nova/nova.conf


# 6 Clear sqllite db
rm -f /var/lib/nova/nova.sqllite

# 7 Restart compute service
service nova-compute restart

# 8 Setup networking sysctl properties
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
sysctl -p

# 8a Unfortunately neutron.conf has a duplicate entry in the default, disable for now
sed -i "s/^service_provider=/#service_provider=/" /etc/neutron/neutron.conf

# 9 Install networking components
apt-get install -y neutron-common neutron-plugin-ml2 neutron-plugin-openvswitch-agent

# 10 Setup neutron basics
set_ini_value /etc/neutron/neutron.conf database connection mysql:\/\/neutron:${NEUTRON_DB_PW}@controller\/neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT debug True

# 11 Setup keystone auth for neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_host controller
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_password ${NEUTRON_OS_PW}

# 12 Setup rabbit config for neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT notification_driver neutron.openstack.common.notifier.rpc_notifier
set_ini_value /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_kombu
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_host controller
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_password ${RABBIT_PW}

# 13 Setup ML2 plugin system
set_ini_value /etc/neutron/neutron.conf DEFAULT core_plugin ml2
set_ini_valuonfig ML2 plugin for VLAN
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges physnet1:100:199

# 14 Security group setup
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# 15 This section apparently needs to be here for vlan - Icehouse docs unclear
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings physnet1:br-backend
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs integration_bridge br-int
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs network_vlan_ranges physnet1:100:199

# 16 Setup openvswitch bridges
service openvswitch-switch restart
ovs-vsctl add-br br-backend || true
ovs-vsctl add-br br-int || true
ovs-vsctl add-port br-backend em1 || true
set_ini_value /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True

# 17 Restart openvswitch
service openvswitch-switch restart

# 18 Restart compute
service nova-compute restart

# 19 Restart networking
service neutron-plugin-openvswitch-agent restart



