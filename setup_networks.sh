#!/bin/sh

# Settings
FLOATING_IP_START='192.168.1.101'
FLOATING_IP_END='192.168.1.199'
PUBLIC_NETWORK_GATEWAY='192.168.1.254’
PUBLIC_NETWORK_CIDR='192.168.1.0/24'

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

# 2 Setup environment variables for OpenStack client execution
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PW}
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://controller:35357/v2.0

# 3 Create external network
neutron net-create ext-net --shared --router:external=True
neutron subnet-create ext-net --name ext-subnet --allocation-pool start=${FLOATING_IP_START},end=${FLOATING_IP_END} --disable-dhcp --gateway ${PUBLIC_NETWORK_GATEWAY} ${PUBLIC_NETWORK_CIDR}



