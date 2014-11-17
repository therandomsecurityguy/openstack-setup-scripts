#!/bin/sh


# Command used to generate random passwords
GENERATE_PW_COMMAND='openssl rand -hex 12'

# Settings that user must enter
INTERNAL_IP_ADDRESS='192.168.200.1'
PUBLIC_IP_ADDRESS='192.168.1.10'
IMAGE_SERVER_INTERNAL_IP_ADDRESS='192.168.200.1'

ADMIN_EMAIL='openstack-test@localhost'
ADMIN_PW=$(${GENERATE_PW_COMMAND})
INITIAL_OS_USER_NAME='cloud'
INITIAL_OS_TENANT_NAME='first-tenant'
INITIAL_OS_TENANT_DESCRIPTION='Initial tenant'
INITIAL_OS_USER_EMAIL='openstack-test@localhost'
INITIAL_OS_USER_PW=$(${GENERATE_PW_COMMAND})


# Function for setting up mysql dbs
# Usage: setup_mysql_db DB_NAME USER PASSWORD
setup_mysql_db() {
  DB_NAME=$1
  USER_NAME=$2
  PASSWORD=$3
  echo "Setting up db [${DB_NAME}] user [${USER_NAME}] pw [${PASSWORD}]"
  mysql -uroot -Be "CREATE DATABASE ${DB_NAME};"
  mysql -uroot -Be "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${USER_NAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';"
  mysql -uroot -Be "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${USER_NAME}'@'%' IDENTIFIED BY '${PASSWORD}';"
  mysql -uroot -Be "FLUSH PRIVILEGES;"
}


# Function for setting up keystone users
# Usage: setup_keystone_service_user USER PASSWORD
setup_keystone_service_user() {
  USER_NAME=$1
  PASSWORD=$2
  echo "Adding keystone user [${USER_NAME}] pw [${PASSWORD}]"
  keystone user-create --name=${USER_NAME} --pass=${PASSWORD} --email="${USER_NAME}@localhost"
  keystone user-role-add --user=${USER_NAME} --tenant=service --role=admin
}

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

# Delete an ini value - requires the name be unique in the ini file
# Usage: delete_ini_value INI_FILE SECTION_NAME FIELD_NAME
delete_ini_value() {
  INI_FILE=$1
  SECTION_NAME=$2
  FIELD_NAME=$3

DEL_SCRIPT="
#!/usr/bin/python
from configobj import ConfigObj
import sys

(ini_file,section,name) = sys.argv[1:]

config = ConfigObj(ini_file)
if section in config:
  if name in config[section]:
    del config[section][name]
    config.write()

"
  python -c "${DEL_SCRIPT}" "${INI_FILE}" "${SECTION_NAME}" "${FIELD_NAME}"
}

# Generate passwords
RABBIT_PW=$(${GENERATE_PW_COMMAND})
ADMIN_TEMP_TOKEN=$(${GENERATE_PW_COMMAND})

KEYSTONE_DB_PW=$(${GENERATE_PW_COMMAND})
GLANCE_DB_PW=$(${GENERATE_PW_COMMAND})
NOVA_DB_PW=$(${GENERATE_PW_COMMAND})
HORIZON_DB_PW=$(${GENERATE_PW_COMMAND})
CINDER_DB_PW=$(${GENERATE_PW_COMMAND})
NEUTRON_DB_PW=$(${GENERATE_PW_COMMAND})
HEAT_DB_PW=$(${GENERATE_PW_COMMAND})
CEILOMETER_DB_PW=$(${GENERATE_PW_COMMAND})
TROVE_DB_PW=$(${GENERATE_PW_COMMAND})

KEYSTONE_OS_PW=$(${GENERATE_PW_COMMAND})
GLANCE_OS_PW=$(${GENERATE_PW_COMMAND})
NOVA_OS_PW=$(${GENERATE_PW_COMMAND})
HORIZON_OS_PW=$(${GENERATE_PW_COMMAND})
CINDER_OS_PW=$(${GENERATE_PW_COMMAND})
NEUTRON_OS_PW=$(${GENERATE_PW_COMMAND})
HEAT_OS_PW=$(${GENERATE_PW_COMMAND})
CEILOMETER_OS_PW=$(${GENERATE_PW_COMMAND})
TROVE_OS_PW=$(${GENERATE_PW_COMMAND})
SWIFT_OS_PW=$(${GENERATE_PW_COMMAND})

NEUTRON_METADATA_SHARED_SECRET=$(${GENERATE_PW_COMMAND})

# Write passwords to file
echo "#!/bin/sh" > os_service_passwords.sh
for var in RABBIT_PW ADMIN_PW KEYSTONE_DB_PW GLANCE_DB_PW NOVA_DB_PW HORIZON_DB_PW CINDER_DB_PW NEUTRON_DB_PW HEAT_DB_PW CEILOMETER_DB_PW TROVE_DB_PW KEYSTONE_OS_PW GLANCE_OS_PW NOVA_OS_PW HORIZON_OS_PW CINDER_OS_PW NEUTRON_OS_PW HEAT_OS_PW CEILOMETER_OS_PW TROVE_OS_PW NEUTRON_METADATA_SHARED_SECRET INITIAL_OS_USER_PW; do
  eval pw_val=\$$var
  echo "${var}=${pw_val}" >> os_service_passwords.sh
done
chmod u+x os_service_passwords.sh

echo "Passwords written to [os_service_passwords.sh]. Copy this file to other nodes for setup."

# 8 Update os packages
#apt-get update
#apt-get -y dist-upgrade

# 9 Install vlan support tools
apt-get install -y vlan

# 10 Install dnsmasq
apt-get install -y dnsmasq

# 11 Install mysql server
apt-get install -y mysql-server

# 12 Install python mysql api
apt-get install -y python-mysqldb

# 13 Install NTP
apt-get install -y ntp

# 14 Install rabbitmq
apt-get install -y rabbitmq-server

# 15 Allow mysql access from local subnet
sed -i "s/#\?bind-address.*=.*/bind-address=${INTERNAL_IP_ADDRESS}/" /etc/mysql/my.cnf

# 16 Configure mysql for improved innodb handling
OPENSTACK_MYSQL_VARS="# OpenStack Icehouse recommended settings\ndefault-storage-engine = innodb\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ncharacter-set-server = utf8\n\n# InnoDB Tuning parameters\ninnodb_file_per_table\ninnodb_buffer_pool_size = 768M\ninnodb_buffer_pool_instances = 2\ninnodb_log_file_size = 50M\ninnodb_log_buffer_size = 8M\ninnodb_flush_log_at_trx_commit = 2 # Flush to OS on TX commit, rather than waiting for disk flush\ninnodb_flush_method = O_DIRECT\n\n"

sed -i "s/\[mysqldump\]/${OPENSTACK_MYSQL_VARS}[mysqldump]/" /etc/mysql/my.cnf


# 17: Purge mysql db files
cd /var/lib/mysql
rm -rf ib* mysql keystone nova neutron glance cinder heat ceilometer trove
cd -

# 18 Stop mysql
service mysql stop
sleep 5

# 19 Ensure mysql db is installed and remove temporary tables and users
mysql_install_db
service mysql start
#mysql_secure_installation

# 20 Set rabbitmq password
rabbitmqctl change_password guest ${RABBIT_PW}

# 21 Install keystone
apt-get install -y keystone
service keystone stop
sleep 3

# 22 Create keystone database and grant privileges
setup_mysql_db keystone keystone ${KEYSTONE_DB_PW}

# 23 Setup keystone configuration
set_ini_value /etc/keystone/keystone.conf DEFAULT admin_token ${ADMIN_TEMP_TOKEN}
set_ini_value /etc/keystone/keystone.conf DEFAULT log_dir /var/log/keystone
set_ini_value /etc/keystone/keystone.conf database connection mysql:\/\/keystone:${KEYSTONE_DB_PW}@controller\/keystone

# 24 Add 'controller' to hosts file
echo "${INTERNAL_IP_ADDRESS} controller" >> /etc/hosts

# 25 Populate keystone db
keystone-manage db_sync

# 26 Restart keystone
service keystone restart
echo "Waiting for 5 seconds for keystone to restart.."
sleep 5

# 27 Delete keystone sqllite db
rm -f /var/lib/keystone/keystone.db

# 28 Variables for initial keystone setup
export OS_SERVICE_ENDPOINT=http://controller:35357/v2.0
export OS_SERVICE_TOKEN=${ADMIN_TEMP_TOKEN}

# 29 Create admin user
keystone user-create --name=admin --pass=${ADMIN_PW} --email="${ADMIN_EMAIL}"
keystone role-create --name=admin
keystone tenant-create --name=admin --description="Admin Tenant"
keystone user-role-add --user=admin --tenant=admin --role=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin

# 30 Create initial Openstack user
keystone user-create --name=${INITIAL_OS_USER_NAME} --pass=${INITIAL_OS_USER_PW} --email="${INITIAL_OS_USER_EMAIL}"
keystone tenant-create --name=${INITIAL_OS_TENANT_NAME} --description="${INITIAL_OS_TENANT_DESCRIPTION}"
keystone user-role-add --user=${INITIAL_OS_USER_NAME} --role=_member_ --tenant=${INITIAL_OS_TENANT_NAME}

# 31 Create service tenant
keystone tenant-create --name=service --description="Service Tenant"

# 32 Setup service endpoints
keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ identity / {print $2}') \
   --publicurl=http://${PUBLIC_IP_ADDRESS}:5000/v2.0 \
   --internalurl=http://controller:5000/v2.0 \
   --adminurl=http://${PUBLIC_IP_ADDRESS}:35357/v2.0 

# 33 Remove temporary admin token
delete_ini_value /etc/keystone/keystone.conf DEFAULT admin_token

# 34 Restart keystone
service keystone restart
echo "Waiting for 5 seconds for keystone to restart.."
sleep 5

# 35 Variables for keystone setup using admin
unset OS_SERVICE_ENDPOINT
unset OS_SERVICE_TOKEN
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PW}
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://controller:35357/v2.0

# 36 Create os-admin-rc.sh which sets environment variables for admin operations
RC_CONTENT="
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PW}
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://controller:35357/v2.0
"
echo "${RC_CONTENT}" > os-admin-rc.sh
chmod u+x os-admin-rc.sh


# 37 Setup DB users for other services
setup_mysql_db glance glance ${GLANCE_DB_PW}
setup_mysql_db nova nova ${NOVA_DB_PW}
setup_mysql_db cinder cinder ${CINDER_DB_PW}
setup_mysql_db neutron neutron ${NEUTRON_DB_PW}
setup_mysql_db heat heat ${HEAT_DB_PW}
setup_mysql_db trove trove ${TROVE_DB_PW}

# 38 Setup keystone users for services
setup_keystone_service_user glance ${GLANCE_OS_PW}
setup_keystone_service_user nova ${NOVA_OS_PW}
setup_keystone_service_user cinder ${CINDER_OS_PW}
setup_keystone_service_user neutron ${NEUTRON_OS_PW}
setup_keystone_service_user heat ${HEAT_OS_PW}
setup_keystone_service_user trove ${TROVE_OS_PW}

setup_keystone_service_user swift ${SWIFT_OS_PW}
setup_keystone_service_user ceilometer ${CEILOMETER_OS_PW}

# 39 Add 'image' to hosts file
echo "${IMAGE_SERVER_INTERNAL_IP_ADDRESS} image" >> /etc/hosts


# 40 Install service and client
apt-get install -y nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient


# 41 Replace entire nova.conf
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


# 42 Clear sqllite db
rm -f /var/lib/nova/nova.sqllite

# 43 Create database tables
su -s /bin/sh -c "nova-manage db sync" nova

# 44 Register compute with identity service
keystone service-create --name=nova --type=compute --description="OpenStack Compute"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ compute / {print $2}') \
   --publicurl=http://${PUBLIC_IP_ADDRESS}:8774/v2/%\(tenant_id\)s \
   --internalurl=http://controller:8774/v2/%\(tenant_id\)s \
   --adminurl=http://${PUBLIC_IP_ADDRESS}:8774/v2/%\(tenant_id\)s

# 45 Restart nova
service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

# 46 Install network api service 
apt-get install -y neutron-server neutron-plugin-ml2

# 47a Unfortunately neutron.conf has a duplicate entry in the default, disable for now
sed -i "s/^service_provider=/#service_provider=/" /etc/neutron/neutron.conf

# 47 Update neutron.conf 
set_ini_value /etc/neutron/neutron.conf DEFAULT debug True
set_ini_value /etc/neutron/neutron.conf DEFAULT core_plugin ml2
set_ini_value /etc/neutron/neutron.conf DEFAULT service_plugins router
set_ini_value /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
set_ini_value /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
set_ini_value /etc/neutron/neutron.conf database connection mysql:\/\/neutron:${NEUTRON_DB_PW}@controller\/neutron

# 48 Setup rabbit config for neutron
set_ini_value /etc/neutron/neutron.conf DEFAULT notification_driver neutron.openstack.common.notifier.rpc_notifier
set_ini_value /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_kombu
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_host controller
set_ini_value /etc/neutron/neutron.conf DEFAULT rabbit_password ${RABBIT_PW}

# 49 Setup keystone auth for neutron
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_host controller
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
set_ini_value /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
set_ini_value /etc/neutron/neutron.conf keystone_authtoken admin_password ${NEUTRON_OS_PW}


# 50 Create service endpoint
keystone service-create --name=neutron --type=network --description="OpenStack Networking"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ network / {print $2}') \
   --publicurl=http://${PUBLIC_IP_ADDRESS}:9696 \
   --internalurl=http://controller:9696 \
   --adminurl=http://${PUBLIC_IP_ADDRESS}:9696

# 51 Get service tenant id
SERVICE_TENANT_ID=`keystone tenant-get service | awk '/ id / { print $4 }'`


# 52 Setup notification from neutron to nova compute
set_ini_value /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
set_ini_value /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
set_ini_value /etc/neutron/neutron.conf DEFAULT nova_url http://controller:8774/v2
set_ini_value /etc/neutron/neutron.conf DEFAULT nova_admin_username nova
set_ini_value /etc/neutron/neutron.conf DEFAULT nova_admin_tenant_id ${SERVICE_TENANT_ID}
set_ini_value /etc/neutron/neutron.conf DEFAULT nova_admin_password ${NOVA_OS_PW}
set_ini_value /etc/neutron/neutron.conf DEFAULT nova_admin_auth_url http://controller:35357/v2.0

# 53 Config ML2 plugin for VLAN
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vlan
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges physnet1:100:199

# 54 Security group setup
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# 55 This section apparently needs to be here for vlan - Icehouse docs unclear
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings physnet1:br-backend
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs integration_bridge br-int
set_ini_value /etc/neutron/plugins/ml2/ml2_conf.ini ovs network_vlan_ranges physnet1:100:199

# 56 Restart compute services
service nova-api restart
service nova-scheduler restart
service nova-conductor restart

# 57 Restart networking services
service neutron-server restart





























  

