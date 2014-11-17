#!/bin/sh

# Settings
CINDER_VOLUME_VG_NAMES="cinder-hdd"
GLANCE_API_HOST="controller"


if [ ! -f os_service_passwords.sh ]; then
  echo "Missing [os_service_passwords.sh] in current directory. Copy from controller node after running setup_controller.sh."
  exit
fi

# Set an ini value - requires the name be unique in the ini file
# Usage: set_ini_value INI_FILE SECTION_NAME FIELD_NAME FIELD_VALUE
set_ini_value() {
  local INI_FILE=$1
  local SECTION_NAME=$2
  local FIELD_NAME=$3
  local FIELD_VALUE=$4

  local SCRIPT="
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

join() {
  local IFS=$1
  shift
  echo "$*"
}


# This will be set to the IP of the controller node
INTERNAL_IP_ADDRESS=`host controller. | awk '/ / {print $4}'`

# 1 Read in passwords from controller file
. ./os_service_passwords.sh

# 2 Install cinder block storage services
apt-get install -y lvm2 cinder-volume

# 3 Enable debug logging
set_ini_value /etc/cinder/cinder.conf DEFAULT debug True

# 4 Setup database connection
set_ini_value /etc/cinder/cinder.conf database connection mysql:\/\/cinder:${CINDER_DB_PW}@controller\/cinder

# 5 Add keystone authentication configuration
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_uri http://controller:5000
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_host controller
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_port 35357
set_ini_value /etc/cinder/cinder.conf keystone_authtoken auth_protocol http
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_tenant_name service
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_user cinder
set_ini_value /etc/cinder/cinder.conf keystone_authtoken admin_password ${CINDER_OS_PW}

# 6 Setup rabbitmq message broker
set_ini_value /etc/cinder/cinder.conf DEFAULT rpc_backend cinder.openstack.common.rpc.impl_kombu
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_host controller
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_port 5672
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_userid guest
set_ini_value /etc/cinder/cinder.conf DEFAULT rabbit_password ${RABBIT_PW}

# 7 Configure image service so that bootable volumes can be created from images
set_ini_value /etc/cinder/cinder.conf DEFAULT glance_host ${GLANCE_API_HOST}

# 8 Setup storage types
TYPE_LINE=$(join , ${CINDER_VOLUME_VG_NAMES})
set_ini_value /etc/cinder/cinder.conf DEFAULT enabled_backends ${TYPE_LINE}
for VG in ${CINDER_VOLUME_VG_NAMES}; do
  set_ini_value /etc/cinder/cinder.conf ${VG} volume_driver cinder.volume.drivers.lvm.LVMISCSIDriver
  set_ini_value /etc/cinder/cinder.conf ${VG} volume_group ${VG}
  set_ini_value /etc/cinder/cinder.conf ${VG} volume_backend_name ${VG}
done

# 8 Restart block storage services
service cinder-volume restart
service tgt restart



