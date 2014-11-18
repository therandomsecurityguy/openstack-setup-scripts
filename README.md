openstack-setup-scripts
=======================

NUC/Brix single NIC/multi-node Openstack setup scripts

These are some basic scripts that are used to:

 * Install dependencies
 * Create physical/virtual networks
 * Install Openstack core components
 * Create random password file
 
### Files included:

 * interfaces
 * setup_controller.sh
 * setup_compute.sh
 * setup_dashboard.sh
 * setup_block_storage_node.sh
 * setup_block_storage_api.sh
 * setup_image_storage.sh
 * setup_network_gateway.sh
 * setup_networks.sh

## Usage

Run setup_controller.sh on controller node first. Will error on mysql connection unless 'secondary' interface has been defined via interfaces file. Run setup_network_gateway.sh next on controller and so on. For VXLAN configurations, change 'ML2 plugin' configuration in setup_network_gateway.sh.

## Assumptions

You should be using a managed switch at minumum with 802.1q trunked ports to your devices.


