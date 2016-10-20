#!/bin/bash
source aio-config.cfg
source ~/admin-openrc.sh

if [ "$IS_OVN" -gt 0 ]; then
exit 0
fi

echo "########## INSTALL NEUTRON ##########"

CORE_PLUGIN="ml2"
MECHANISM_DRIVERS="openvswitch"

if [ "$IS_MLNX" -gt 0 ]; then

#CORE_PLUGIN="neutron.plugins.ml2.plugin.Ml2Plugin"
MECHANISM_DRIVERS="sriovnicswitch,openvswitch"

apt-get -y install neutron-sriov-agent

## sr-iov bug fix:
## https://www.mirantis.com/blog/carrier-grade-mirantis-openstack-the-mirantis-nfv-initiative-part-1-single-root-io-virtualization-sr-iov/
wget -c https://launchpad.net/ubuntu/+archive/primary/+files/libnl-3-200_3.2.24-2_amd64.deb
wget -c https://launchpad.net/ubuntu/+archive/primary/+files/libnl-genl-3-200_3.2.24-2_amd64.deb
wget -c https://launchpad.net/ubuntu/+archive/primary/+files/libnl-route-3-200_3.2.24-2_amd64.deb

dpkg -i --force-overwrite libnl-3-200_3.2.24-2_amd64.deb
dpkg -i --force-overwrite libnl-genl-3-200_3.2.24-2_amd64.deb
dpkg -i --force-overwrite libnl-route-3-200_3.2.24-2_amd64.deb

service libvirt-bin restart

ML2_SRIOV="[ml2_sriov]
supported_pci_vendor_devs = $PCI_VENDOR_DEVS"

fi

apt-get -y install neutron-server neutron-plugin-ml2 neutron-openvswitch-agent \
neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent


filename=/etc/neutron/neutron.conf
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[DEFAULT]
debug = false

rpc_backend = rabbit
auth_strategy = keystone

state_path = /var/lib/neutron
core_plugin = $CORE_PLUGIN
service_plugins = router
allow_overlapping_ips = True

notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True

max_fixed_ips_per_port = 30

[agent]
##root_helper_daemon = sudo /usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

[database]
connection = mysql+pymysql://neutron:$DEFAULT_PASS@controller/neutron

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $DEFAULT_PASS

[nova]
auth_url = http://controller:35357
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $DEFAULT_PASS

[oslo_concurrency]
lock_path = \$state_path/lock

[oslo_messaging_rabbit]
rabbit_host = controller
rabbit_userid = openstack
rabbit_password = $DEFAULT_PASS
EOF
chown root:neutron $filename


######### set interface for bridge ######### 
br_list=($BR_LIST)
vlan_br_list=($VLAN_BR_LIST)
br_mapping_list=($BR_MAPPING_LIST)

flat_networks=
network_vlan_ranges=
bridge_mappings=
ranges=$VLAN_START

for x in "${br_list[@]}"
do
	if [ "$flat_networks" == "" ]; then
		flat_networks="ext_$x"
	else
		flat_networks="$flat_networks,ext_$x"
	fi
done

for x in "${vlan_br_list[@]}"
do
	if [ "$network_vlan_ranges" == "" ]; then
		network_vlan_ranges="ext_$x:$ranges:$(($ranges+99))"
	else
		network_vlan_ranges="$network_vlan_ranges,ext_$x:$ranges:$(($ranges+99))"
	fi
	ranges=$(($ranges+99+1))
done

for x in "${br_mapping_list[@]}"
do
	if [ "$bridge_mappings" == "" ]; then
		bridge_mappings="ext_$x:$x"
	else
		bridge_mappings="$bridge_mappings,ext_$x:$x"
	fi
done
######### set interface for bridge ######### 

filename=/etc/neutron/plugins/ml2/ml2_conf.ini
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[ml2]
extension_drivers = port_security
type_drivers = local,flat,vlan,gre,vxlan
tenant_network_types = flat,vlan,vxlan,gre
mechanism_drivers = $MECHANISM_DRIVERS

[ml2_type_flat]
flat_networks = $flat_networks

[ml2_type_vlan]
network_vlan_ranges = $network_vlan_ranges

[ml2_type_gre]
tunnel_id_ranges = 1:1000

[ml2_type_vxlan]
vni_ranges = 10:10000

[securitygroup]
#enable_security_group = True
#enable_ipset = True
firewall_driver = neutron.agent.firewall.NoopFirewallDriver
#firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
#firewall_driver = networking_ovs_dpdk.agent.ovs_dpdk_firewall.OVSFirewallDriver

$ML2_SRIOV
EOF
chown root:neutron $filename
ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

filename=/etc/neutron/plugins/ml2/openvswitch_agent.ini
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[DEFAULT]

[agent]
tunnel_types = gre,vxlan

[ovs]
local_ip = $LOCAL_IP
bridge_mappings = $bridge_mappings
EOF
chown root:neutron $filename

echo "dhcp-option-force=26,1500" > /etc/neutron/dnsmasq-neutron.conf
killall dnsmasq | awk '{print $1}' 1>&2
chown root:neutron /etc/neutron/dnsmasq-neutron.conf

filename=/etc/neutron/metadata_agent.ini
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[DEFAULT]
nova_metadata_ip = controller
metadata_proxy_shared_secret = $DEFAULT_PASS
EOF
chown root:neutron $filename

filename=/etc/neutron/dhcp_agent.ini
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[DEFAULT]
interface_driver = openvswitch
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf
EOF
chown root:neutron $filename

filename=/etc/neutron/l3_agent.ini
test -f $filename.org || cp $filename $filename.org
rm -f $filename

cat << EOF > $filename
[DEFAULT]
interface_driver = openvswitch
external_network_bridge =
gateway_external_network_id =
EOF
chown root:neutron $filename

if [ "$IS_MLNX" -gt 0 ]; then
## Edit the following file: sriov_agent.ini
filename=/etc/neutron/plugins/ml2/sriov_agent.ini
test -f $filename.org || cp $filename $filename.org
rm $filename

cat << EOF > $filename
[DEFAULT]

[sriov_nic]
physical_device_mappings = $PHYSICAL_NETWORK:$DEVNAME

[securitygroup]
enable_security_group = False
firewall_driver = neutron.agent.firewall.NoopFirewallDriver
EOF
fi


echo "##### DB SYNC #####"
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

service nova-api restart
service nova-compute restart

if [ "$IS_MLNX" -gt 0 ]; then
service neutron-sriov-agent restart
fi

service neutron-server restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-openvswitch-agent restart

exit 0

########################################################
###################### test method #####################
########################################################
## export $(dbus-launch)
neutron net-delete sriov_254.x
neutron net-create --provider:physical_network=ext_br-sriov --provider:network_type=vlan sriov_254.x
neutron subnet-create sriov_254.x --name sriov_sub_254.x 192.168.254.0/24

nova delete test-sriov
neutron port-delete $(neutron port-list | grep "\ sriov_port\ " | awk '{ print $2 }')
net_id=`neutron net-show sriov_254.x | grep "\ id\ " | awk '{ print $4 }'`
port_id=`neutron port-create $net_id --name sriov_port --binding:vnic-type direct --device_owner network:dhcp | grep "\ id\ " | awk '{ print $4 }'`
nova boot --flavor m1.small --image ubuntu-mlnx-dhcp --nic port-id=$port_id test-sriov


#######################################################
## macvtap (controller:eth2, compute:eth3)
1. configuration
apt-get install neutron-macvtap-agent

cp /etc/neutron/plugins/ml2/macvtap_agent.ini /etc/neutron/plugins/ml2/macvtap_agent.ini.org

vi /etc/neutron/plugins/ml2/macvtap_agent.ini
[DEFAULT]
[agent]
[macvtap]
physical_interface_mappings = ext_br-macvtap:ethX

[securitygroup]
enable_security_group = false
firewall_driver = neutron.agent.firewall.NoopFirewallDriver

vi /etc/neutron/plugins/ml2/ml2_conf.ini
[ml2]
...
mechanism_drivers = ...,macvtap

[ml2_type_vlan]
network_vlan_ranges = ...,ext_br-macvtap:1200:1299

[securitygroup]
...
firewall_driver = neutron.agent.firewall.NoopFirewallDriver
#firewall_driver = iptables

2. net-create
==> check vlna id : ????

3. create ethernet vlan
vconfig add eth2 1294
ifconfig eth2.1294 up

3. add br-int port (for route)
3.1) check ovs tag by route gatway interface
echo qr-$(neutron router-port-list ext_vepc | awk '/192.168.254.1/ {print $2}' | cut -c1-11) 
print==> qr-????-??
or 
ip netns exec qrouter-$(neutron router-list | awk '/ ext_vepc / {print $2}') ifconfig
print==> qr-????-?? Link ....

ovs-vsctl show 
qr-????-??
  .... tag=??

3.2) add port
ovs-vsctl del-port br-int eth2.1294
ovs-vsctl add-port br-int eth2.1294 tag=2


## change library (macvtap but only support virtio, model applied by the hw_vif_model)
## dont't need
vi /usr/lib/python2.7/dist-packages/nova/virt/libvirt/vif.py
def get_config_macvtap(.....
conf = self.get_base_config(instance, vif, image_meta,
                                    inst_type, virt_type)
model = conf.model
.....
.....

conf.model = model
return conf

service nova-compute restart
service neutron-macvtap-agent restart


################################################################
################################################################
## for ovs-dpdk (only ubuntu 16.04)
## https://insights.ubuntu.com/2016/05/05/the-new-simplicity-to-consume-dpdk/
## enabled kvm hugepages
sed -ri -e 's,(KVM_HUGEPAGES=).*,\11,' /etc/default/qemu-kvm

## iommu on
vi /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT=" ... iommu=pt intel_iommu=on"
update-grub

## for uio_pci_generic, vfio-pci (just cloud ubuntu)
apt-get install linux-generic linux-headers-$(uname -r)

## install openvswitch-switch-dpdk
apt-get -y remove --purge --auto-remove openvswitch-switch
apt-get -y install openvswitch-switch-dpdk
update-alternatives --config ovs-vswitchd
or
update-alternatives --set ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk


## qemu owner
## vi /etc/libvirt/qemu.conf
user = "root"
group = "root"


## Passes in DPDK command-line options to ovs-vswitchd
vi /etc/default/openvswitch-switch
DPDK_OPTS='--dpdk -c 0x1 -n 4 -m 2048 --vhost-owner libvirt-qemu:kvm --vhost-perm 0664'

## Configures hugepages
# check hugepage
# pge : support 4K
# pse36 : support 2M
# pdpe1gb : support 1G
cat /proc/cpuinfo | egrep '(pge|pse36|pdpe1gb)'
grep -R "" /sys/kernel/mm/hugepages/ /proc/sys/vm/*huge*
grep Huge /proc/meminfo
# support 1G hugepage and 2M
# hugepages=? is memtotal / 1048576 / 2
vi /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="... default_hugepagesz=1GB hugepagesz=1G hugepages=64 hugepagesz=2M hugepages=2048"
update-grub

## Configures hugepages
vi /etc/dpdk/dpdk.conf
NR_2M_PAGES=2048
NR_1G_PAGES=64


## Configures/assigns NICs for DPDK use (inter case don't need)
#modprobe uio_pci_generic
#modprobe vfio-pci
dpdk_nic_bind --status
vi /etc/dpdk/interfaces
pci     0000:00:xx.0    uio_pci_generic
pci     0000:00:xx.1    vfio-pci


## testing
service openvswitch-switch stop
/usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk --dpdk -c 0x1 -n 4 -m 2048 --vhost-owner libvirt-qemu:kvm --vhost-perm 0664

## restart switch
systemctl restart openvswitch-switch

## get interface types
ovs-vsctl get Open_vSwitch . iface_types

## add bridge (external)
ovs-vsctl add-br br-ext
ovs-vsctl add-port br-ext ens3

## add bridge (dpdk)
ovs-vsctl add-br br-dpdk -- set bridge br-dpdk datapath_type=netdev
ovs-vsctl add-port br-dpdk dpdk0 -- set Interface dpdk0 type=dpdk

## neutron-ovs
##apt-get install python-networking-ovs-dpdk

vi /etc/neutron/plugins/ml2/openvswitch_agent.ini
[OVS]
...
datapath_type = netdev
vhostuser_socket_dir = /var/run/openvswitch

service neutron-openvswitch-agent restart

vi /etc/nova/nova.conf
[DEFAULT]
...
scheduler_default_filters=RamFilter,ComputeFilter,AvailabilityZoneFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,PciPassthroughFilter,NUMATopologyFilter


# for 1G hugepages
nova flavor-key m1.small set "hw:mem_page_size=large"

# for 2M hugepages
nova flavor-key m1.small set "hw:mem_page_size=small"


################# ovs-dpdk #######################
##https://community.mellanox.com/thread/3115
##https://github.com/openvswitch/ovs/blob/master/INSTALL.DPDK.md#build
##testpmd -c 0xff00 -n 4 -w 0000:07:00.0 -- --rxq=2 --txq=2 -i

wget -c http://fast.dpdk.org/rel/dpdk-16.07.tar.xz
tar xvfz dpdk-16.07.tar.xz
apt install libnuma-dev
export DPDK_DIR=/root/dpdk-16.07
cd $DPDK_DIR
export DPDK_TARGET=x86_64-native-linuxapp-gcc
export DPDK_BUILD=$DPDK_DIR/$DPDK_TARGET

vi config/common_linuxapp
CONFIG_RTE_LIBRTE_VHOST_NUMA=y
CONFIG_RTE_BUILD_COMBINE_LIBS=y
#CONFIG_RTE_BUILD_SHARED_LIB=y
#CONFIG_RTE_LIBRTE_MLX4_PMD=y
#CONFIG_RTE_LIBRTE_MLX4_DEBUG=n
#CONFIG_RTE_LIBRTE_MLX4_SGE_WR_N=1
#CONFIG_RTE_LIBRTE_MLX4_MAX_INLINE=0
#CONFIG_RTE_LIBRTE_MLX4_TX_MP_CACHE=8
#CONFIG_RTE_LIBRTE_MLX4_SOFT_COUNTERS=1

EXTRA_CFLAGS="-g -Ofast" make install T=$DPDK_TARGET DESTDIR=/usr/local -j24

cd /usr/src/
git clone https://github.com/openvswitch/ovs.git
#git clone -b branch-2.6 https://github.com/openvswitch/ovs.git
export OVS_DIR=/usr/src/ovs

cd $OVS_DIR
./boot.sh
## mellanox in case
#export LIBS="-libverbs"
./configure --prefix=/ --with-dpdk=$DPDK_BUILD CFLAGS="-g -Ofast"
## --disable-ssl
make 'CFLAGS=-g -Ofast -march=native' -j24
make install

ovsdb-tool create /etc/openvswitch/conf.db  \
        /share/openvswitch/vswitch.ovsschema
# or upgrade
#ovsdb-tool convert /etc/openvswitch/conf.db  \
#        /share/openvswitch/vswitch.ovsschema

#ovsdb-server --remote=punix:/var/run/openvswitch/db.sock \
#     --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
#     --pidfile --detach

#export DB_SOCK=/var/run/openvswitch/db.sock

cp -f /sbin/ovs-vswitchd /usr/lib/openvswitch-switch/ovs-vswitchd
update-alternatives --config ovs-vswitchd

#mv /usr/lib/x86_64-linux-gnu/libdpdk.so.0 /usr/lib/x86_64-linux-gnu/libdpdk.so.0.org
#ln -s /usr/local/lib/libdpdk.so libdpdk.so.0

service openvswitch-switch restart

ovs-vsctl get Open_vSwitch . other_config
ovs-vsctl --all destroy Open_vSwitch
ovs-vsctl --no-wait init
ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="1024,1024"
ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=6
ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-hugepage-dir=/dev/hugepages
ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-lcore-mask=0xf


#ovs-vswitchd unix:$DB_SOCK --pidfile --detach
#ip link add vxlan0 type vxlan id 42 group 239.1.1.1 dev enp2s0

#ovs-vsctl add-br br-dpdk -- set bridge br-dpdk datapath_type=netdev
#ovs-vsctl add-port br-dpdk dpdk0 -- set Interface dpdk0 type=dpdk
#ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=c
#ovs-vsctl set interface dpdk0 options:n_rxq=2


vi /etc/dpdk/interfaces
 pci    0000:02:00.0    uio_pci_generic

reboot

##ip link add vxlan0 type vxlan id 100 group 239.1.1.1 dev mlx1
##ifconfig vxlan0 192.168.100.27/24 up
##ip link add vxlan0 type vxlan id 100 group 239.1.1.1 dev mlx1
##ifconfig vxlan0 192.168.100.26/24 up
##ifconfig br-dpdk 192.168.100.27/24 up
##ifconfig br-dpdk 192.168.100.26/24 up
##ifconfig br-dpdk 0.0.0.0
##ip link del vxlan0

##ipmitool -I lan -H 192.168.111.5 -U root power status
##ipmitool -I lan -H 192.168.111.5 -U root power reset
##ipmitool -I lan -H 192.168.111.6 -U root power status


#Ubuntu 64 bits / Debian 64 bits / Mint 64 bits (AMD64) : 
sudo apt-get -y remove iperf3 libiperf0 iperf
wget https://iperf.fr/download/ubuntu/libiperf0_3.1.3-1_amd64.deb
wget https://iperf.fr/download/ubuntu/iperf3_3.1.3-1_amd64.deb
sudo dpkg -i libiperf0_3.1.3-1_amd64.deb iperf3_3.1.3-1_amd64.deb
rm libiperf0_3.1.3-1_amd64.deb iperf3_3.1.3-1_amd64.deb

## netperf
apt install netperf
netperf -H 192.168.254.5 -t TCP_STREAM -- -m 1024

netperf -t TCP_RR -H 127.0.0.1 -v 2
netperf -H 192.168.1.3 -- -m 64
netperf -H 192.168.1.3 -- -m 128
netperf -H 192.168.1.3 -- -m 256
netperf -H 192.168.1.3 -- -m 512
netperf -H 192.168.1.3 -- -m 1024
netperf -H 192.168.1.3 -- -m 2048

## sockperf
sudo apt-get install unzip 
wget https://github.com/Mellanox/sockperf/archive/sockperf_v2.zip
## or scp -p d?n@1?4.?1.?0.187:/home/d?n/sockperf .
unzip sockperf_v2.zip
cd sockperf-sockperf_v2
sudo apt-get install autoconf
./autogen.sh
./configure --prefix=`pwd`/install
make
make install
./sockperf server -p 5001 --tcp
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 64 -t 5 --tcp --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 128 -t 5 --tcp --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 256 -t 5 --tcp --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 512 -t 5 --tcp --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 1024 -t 5 --tcp --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 2048 -t 5 --tcp --pps=max

./sockperf server -p 5001
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 64 -t 5 --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 128 -t 5 --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 256 -t 5 --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 512 -t 5 --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 1024 -t 5 --pps=max
./sockperf ping-pong -i 192.168.254.3 -p 5001 -m 2048 -t 5 --pps=max
