#!/bin/sh

# Settings

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
  config[section] = {}
config[section][name]=value
config.write()
"
  python -c "${SCRIPT}" "${INI_FILE}" "${SECTION_NAME}" "${FIELD_NAME}" "${FIELD_VALUE}"
}



# This will be set to the IP of the controller node
INTERNAL_IP_ADDRESS=`host controller. | awk '/ / {print $4}'`

# 1 Read in passwords from controller file
. ./os_service_passwords.sh

# 2 Configure OS networking to allow forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
sysctl -p

# 3 Install services
apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent

# 4 Setup neutron basics
set_ini_value /etc/neutron/neutron.conf database connection mysql:\/\/neutron:${NEUTRON_DB_PW}@controller\/neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT debug True

# 5 Setup keystone auth for neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_host controller
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_password ${NEUTRON_OS_PW}

# 6 Setup rabbit config for neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT notification_driver neutron.openstack.common.notifier.rpc_notifier
set_ini_value /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_kombu
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_host controller
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_password ${RABBIT_PW}

# 7 Setup ML2 plugin system
set_ini_value /etc/neutron/neutron.conf DEFAULT core_plugin ml2
set_ini_value /etc/neutron/neutron.conf DEFAULT service_plugins router
set_ini_value /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True

# 8 Configure layer-3 neutron agent
set_ini_value /etc/neutron/l3_agent.ini DEFAULT debug True
set_ini_value /etc/neutron/l3_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
set_ini_value /etc/neutron/l3_agent.ini DEFAULT use_namespaces True

# 9 Configure dhcp agent
set_ini_value /etc/neutron/dhcp_agent.ini DEFAULT debug True
set_ini_value /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
set_ini_value /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
set_ini_value /etc/neutron/dhcp_agent.ini DEFAULT use_namespaces True

# 10 Configure metadata agent
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT debug True
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT auth_url http://controller:5000/v2.0
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT auth_region regionOne
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT admin_tenant_name service
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT admin_user neutron
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT admin_password ${NEUTRON_OS_PW}
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip controller
set_ini_value /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret ${NEUTRON_METADATA_SHARED_SECRET}

# 11 Config ML2 plugin for VLAN
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges physnet1:100:199

# 12 Security group setup
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# 13 This section apparently needs to be here for vlan - Icehouse docs unclear
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings physnet1:br-backend
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs integration_bridge br-int
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs network_vlan_ranges physnet1:100:199

# 14 Setup openvswitch bridges
service openvswitch-switch restart
ovs-vsctl add-br br-ex || true
ovs-vsctl add-br br-backend || true
ovs-vsctl add-br br-int || true
ovs-vsctl add-port br-backend em1 || true
ovs-vsctl add-port br-ex em1.1 || true

# 15 Restart neutron services
service neutron-plugin-openvswitch-agent restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart





