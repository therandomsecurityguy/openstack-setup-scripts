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

# 2 Install services
apt-get install -y apache2 memcached libapache2-mod-wsgi openstack-dashboard

# 3 Remove ubuntu theme which breaks functionality according to
# http://docs.openstack.org/trunk/install-guide/install/apt/content/install_dashboard.html
apt-get remove -y --purge openstack-dashboard-ubuntu-theme

# 4 Set 'openstack host' to the controller node
sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = \"controller\"/" /etc/openstack-dashboard/local_settings.py

# 5 Restart apache and memcache
service apache2 restart
service memcached restart

