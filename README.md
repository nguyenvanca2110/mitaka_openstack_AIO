# Welcome!

OpenStack Installation AIO

* **Version:** Mitaka

* **Install mode:** All-in-One(only one box), Multi mode(controller+networks and compute node)

Add *Tacker module* to All-in-One mode.

### default tenant network *"vxlan"* and  *"securitygroup"* remove

```
vi /etc/neutron/plugins/ml2/ml2_conf.ini
...
tenant_network_types = flat,vxlan,gre,vlan

...
#enable_security_group = True
#enable_ipset = True
...
```


## Installation:

Installation instructions:

https://github.com/nguyenvanca2110/mitaka_openstack_AIO/INSTALL.md


## External Resources:

OpenStack document:

http://docs.openstack.org/

Tacker git:

https://github.com/openstack/tacker

Tacker test guide:

https://github.com/nguyenvanca2110/mitaka_openstack_AIO/TACKER_GUIDE.md



