# Single source of truth for node identity, addressing and VM sizing.
# Consumed by Salt states/templates AND parsed directly by the Vagrantfile
# (YAML.load_file), so this file must stay pure YAML - no Jinja.
# Node order below is the Vagrant provisioning order: builder must run first so
# its artifacts exist before the controller and compute nodes consume them.
network:
  domain: lab.local
  interface: eth1          # VirtualBox private_network NIC (eth0 is the shared NAT 10.0.2.15)
  cidr: 192.168.56.0/24
  box: bento/debian-12
  box_version: 202510.26.0
  salt_version: '3006.27'  # Salt 3006 LTS
  nodes:
    builder:
      ip: 192.168.56.10
      role: builder
      memory: 4096
      cpus: 4
    controller:
      ip: 192.168.56.11
      role: controller
      memory: 4096
      cpus: 2
    compute:
      ip: 192.168.56.12
      role: compute
      memory: 8192
      cpus: 6
