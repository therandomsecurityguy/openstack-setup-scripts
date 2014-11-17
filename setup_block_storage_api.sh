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

# 2 Install cinder block storage services
apt-get install -y cinder-api cinder-scheduler

# 3 Enable debug logging
set_ini_value /etc/cinder/cinder.conf DEFAULT debug True

# 4 Setup database connection
set_ini_value /etc/cinder/cinder.conf database connection mysql:\/\/cinder:${CINDER_DB_PW}@controller\/cinder

# 5 Create cinder database tables
su -s /bin/sh -c "cinder-manage db sync" cinder

# 6 Add keystone authentication configuration
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_uri http://controller:5000
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_host controller
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_port 35357
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_protocol http
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_tenant_name service
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_user cinder
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_password ${CINDER_OS_PW}

# 7 Setup rabbitmq message broker
set_ini_value /etc/cinder/cinder.conf DEFAULT rpc_backend cinder.openstack.common.rpc.impl_kombu
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_host controller
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_port 5672
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_userid guest
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_password ${RABBIT_PW}

# 8 Setup admin credentials so that a service can be added
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PW}
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://controller:35357/v2.0

# 9 Create service endpoint
keystone service-create --name=cinder --type=volumev2 --description="OpenStack Block Storage v2"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ volumev2 / {print $2}') \
   --publicurl=http://${PUBLIC_IP_ADDRESS}:8776/v2/%\(tenant_id\)s \
   --internalurl=http://controller:8776/v2/%\(tenant_id\)s \
   --adminurl=http://${PUBLIC_IP_ADDRESS}:8776/v2/%\(tenant_id\)s \

# 10 Restart block storage services
service cinder-scheduler restart
service cinder-api restart



