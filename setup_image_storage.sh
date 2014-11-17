#!/bin/sh

# Settings
PUBLIC_IP_ADDRESS='192.168.1.10'
INTERNAL_IP_ADDRESS='192.168.200.1'



if [ ! -f os_service_passwords.sh ]; then
  echo "Missing [os_service_passwords.sh] in current directory. Copy from controller node after running setup_controller.sh."
  exit
fi



# 1 Read in passwords from controller file
. ./os_service_passwords.sh


# 2 Install service and client
apt-get install -y glance python-glanceclient python-mysqldb python-keystoneclient

# 3 Edit database connection string in glance-api
sed -i "s/#\?connection.*=.*/connection=mysql:\/\/glance:${GLANCE_DB_PW}@controller\/glance/" /etc/glance/glance-api.conf
 
# 4 Edit database connection string in glance-registry
sed -i "s/#\?connection.*=.*/connection=mysql:\/\/glance:${GLANCE_DB_PW}@controller\/glance/" /etc/glance/glance-registry.conf

# 5 Setup rabbitmq message broker
RABBIT_CONFIG_FIRSTLINES="rpc_backend = rabbit\nrabbit_host = controller"
sed -i "s/rabbit_host.*=.*/${RABBIT_CONFIG_FIRSTLINES}/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_port.*=.*/rabbit_port = 5672/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_use_ssl.*=.*/rabbit_use_ssl = false/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_userid.*=.*/rabbit_userid = guest/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_password.*=.*/rabbit_password = ${RABBIT_PW}/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_virtual_host.*=.*/#rabbit_virtual_host = /" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_virtual_host.*=.*/#rabbit_virtual_host = /" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_notification_exchange.*=.*/#rabbit_notification_exchange = glance/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_notification_topic.*=.*/#rabbit_notification_topic = notifications/" /etc/glance/glance-api.conf
sed -i "s/#\?rabbit_durable_queues.*=.*/#rabbit_durable_queues = False/" /etc/glance/glance-api.conf

# 6 Clear sqllite glance db
rm -f /var/lib/glance/glance.sqlite

# 7 Create database tables
su -s /bin/sh -c "glance-manage db_sync" glance

# 8 Configure glance for keystone auth
GLANCE_AUTH_SECHEADER="[keystone_authtoken]\nauth_uri = http:\/\/controller:5000"
sed -i "s/\[keystone_authtoken\]/${GLANCE_AUTH_SECHEADER}/" /etc/glance/glance-api.conf
sed -i "s/#\?auth_host.*=.*/auth_host = controller/" /etc/glance/glance-api.conf
sed -i "s/#\?auth_port.*=.*/auth_port = 35357/" /etc/glance/glance-api.conf
sed -i "s/#\?auth_protocol.*=.*/auth_protocol = http/" /etc/glance/glance-api.conf
sed -i "s/#\?admin_tenant_name.*=.*/admin_tenant_name = service/" /etc/glance/glance-api.conf
sed -i "s/#\?admin_user.*=.*/admin_user = glance/" /etc/glance/glance-api.conf
sed -i "s/#\?admin_password.*=.*/admin_password = ${GLANCE_OS_PW}/" /etc/glance/glance-api.conf
sed -i "s/#\?flavor.*=.*/flavor = keystone/" /etc/glance/glance-api.conf

# 9 Do the same thing in glance-registry
sed -i "s/\[keystone_authtoken\]/${GLANCE_AUTH_SECHEADER}/" /etc/glance/glance-registry.conf
sed -i "s/#\?auth_host.*=.*/auth_host = controller/" /etc/glance/glance-registry.conf
sed -i "s/#\?auth_port.*=.*/auth_port = 35357/" /etc/glance/glance-registry.conf
sed -i "s/#\?auth_protocol.*=.*/auth_protocol = http/" /etc/glance/glance-registry.conf
sed -i "s/#\?admin_tenant_name.*=.*/admin_tenant_name = service/" /etc/glance/glance-registry.conf
sed -i "s/#\?admin_user.*=.*/admin_user = glance/" /etc/glance/glance-registry.conf
sed -i "s/#\?admin_password.*=.*/admin_password = ${GLANCE_OS_PW}/" /etc/glance/glance-registry.conf
sed -i "s/#\?flavor.*=.*/flavor = keystone/" /etc/glance/glance-registry.conf

# 10 Enable verbose logging
sed -i "s/#\?verbose.*=.*/verbose = True/" /etc/glance/glance-api.conf
sed -i "s/#\?verbose.*=.*/verbose = True/" /etc/glance/glance-registry.conf


# 11 Register image with identity service
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PW}
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://controller:35357/v2.0
keystone service-create --name=glance --type=image --description="OpenStack Image Service"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ image / {print $2}') \
   --publicurl=http://${PUBLIC_IP_ADDRESS}:9292 \
   --internalurl=http://${INTERNAL_IP_ADDRESS}:9292 \
   --adminurl=http://${PUBLIC_IP_ADDRESS}:9292 

# 12 Restart glance
service glance-registry restart
service glance-api restart












