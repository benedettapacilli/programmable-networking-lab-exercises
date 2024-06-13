# Tenant 1 (red): IP network 10.0.1.0/24, Gateway 10.0.1.254
# Tenant 2 (green): IP network 10.0.2.0/24, Gateway 10.0.2.254

# According to the instructions, in each (physical) room there are two hosts, one per tenant. We create namespaces for each host in each room. Network namespaces provide isolated network environments, ensuring that network configurations in one namespace do not affect those in another. We create two namespaces for each room, one for each tenant to separate the network environments.

# Devices of Room 1
sudo ip netns add t1device1
sudo ip netns add t2device1
# Devices of Room 2
sudo ip netns add t1device2
sudo ip netns add t2device2
# t1device1 and t1device2 are the devices for tenant 1 in room 1 and room 2 respectively. t2device1 and t2device2 are the devices for tenant 2 in room 1 and room 2 respectively.

# Switches: we create two switches, one for each room, but we assign an IP address only to the switch in room 2. This is because the switch in room 2 will act as the gateway for the hosts in room 2. The switch in room 1 does not need an IP address as it will not be used as a gateway.
sudo ovs-vsctl add-br room1switch # room1switch is created but not given an IP address because it functions purely as a layer 2 switch, handling traffic within its local VLANs.
sudo ovs-vsctl add-br room2switch # room2switch is assigned 10.0.1.10/24 to enable it to perform layer 3 (routing) functions, such as acting as a gateway and handling inter-VLAN routing.
sudo ip addr add 10.0.1.10/24 dev room2switch # We assign an IP address from subnet 10.0.1.0/24 because room2switch is intended to perform inter-VLAN routing so it needs an IP address within one of the VLANs it is routing between. Since 10.0.1.0/24 is the subnet for Tenant 1, assigning an IP address within this range allows room2switch to route traffic between the subnets 10.0.1.0/24 and 10.0.2.0/24.
sudo ip link set room1switch up
sudo ip link set room2switch up
# Both switches are brought up to enable them to send and receive network traffic.

# VLANs configuration
# Room1: we setu up two virtual ethernet pairs, one for each tenant in room 1. The first end of each pair is moved to the respective namespace, and the second end is connected to the switch. We then add the ports to the switch and assign VLAN tags to them.
sudo ip link add t1dev1veth type veth peer name vlan9s1 # vlan9s1 is the port connected to tenant 1 in room 1. It is assigned the VLAN tag 9.
sudo ip link add t2dev1veth type veth peer name vlan10s1 # vlan10s1 is the port connected to tenant 2 in room 1. It is assigned the VLAN tag 10.
sudo ip link set t1dev1veth netns t1device1
sudo ip link set t2dev1veth netns t2device1

# add-port command adds the veth interface to the switch and assigns a VLAN tag to it. The tag is used to identify the VLAN to which the port belongs. In this case, we assign VLAN tag 9 to the port connected to t1dev1veth and VLAN tag 10 to the port connected to t2dev1veth.
sudo ovs-vsctl add-port room1switch vlan9s1 tag=9
sudo ip link set vlan9s1 up

sudo ovs-vsctl add-port room1switch vlan10s1 tag=10
sudo ip link set vlan10s1 up
# links are brought up to enable the network interfaces to send and receive network traffic.

sudo ip netns exec t1device1 ip link set dev lo up # The loopback interface is brought up to enable the host to communicate with itself.
sudo ip netns exec t1device1 ip link set dev t1dev1veth up # The network interface t1dev1veth is brought up to enable it to send and receive network traffic.
sudo ip netns exec t1device1 ip addr add 10.0.1.1/24 dev t1dev1veth # t1dev1veth is the network interface connected to tenant 1 in room 1, used to communicate with the switch. We assign the IP address 10.0.1.1/24 to this interface, as it is the first device of tenant 1 (red).

sudo ip netns exec t2device1 ip link set dev lo up
sudo ip netns exec t2device1 ip link set dev t2dev1veth up
sudo ip netns exec t2device1 ip addr add 10.0.2.1/24 dev t2dev1veth # t2dev1veth is the network interface connected to tenant 2 in room 1, used to communicate with the switch. We assign the IP address 10.0.2.1/24 to this interface, as it is the first device of tenant 2 (green).

# Room 2: configuration in room 2 mirrors that of room 1.
sudo ip link add t1dev2veth type veth peer name vlan9s2
sudo ip link add t2dev2veth type veth peer name vlan10s2
sudo ip link set t1dev2veth netns t1device2
sudo ip link set t2dev2veth netns t2device2

sudo ovs-vsctl add-port room2switch vlan9s2 tag=9
sudo ip link set vlan9s2 up

sudo ovs-vsctl add-port room2switch vlan10s2 tag=10
sudo ip link set vlan10s2 up

sudo ip netns exec t1device2 ip link set dev lo up
sudo ip netns exec t1device2 ip link set dev t1dev2veth up
sudo ip netns exec t1device2 ip addr add 10.0.1.2/24 dev t1dev2veth

sudo ip netns exec t2device2 ip link set dev lo up
sudo ip netns exec t2device2 ip link set dev t2dev2veth up
sudo ip netns exec t2device2 ip addr add 10.0.2.2/24 dev t2dev2veth

# Connect switches: we create two virtual ethernet pairs to connect the switches in room 1 and room 2. This allows traffic to pass between the switches, enabling communication between the hosts in the two rooms. A trunk link is used to carry traffic for multiple VLANs between the switches.
# Two veth pairs are used to create the trunk link.
sudo ip link add t1dev2veth type veth peer name tap0 # t1dev2veth is one end of the veth pair connected to the network namespace of the second device of tenant 1 in room 2. tap0 is the other end of the veth pair connected to room1switch.
sudo ip link add t2dev2veth type veth peer name tap1 # t2dev2veth is one end of the veth pair connected to the network namespace of the second device of tenant 2 in room 2. tap1 is the other end of the veth pair connected to room2switch.
sudo ovs-vsctl add-port room1switch tap0 vlan_mode=trunk trunk=9,10 # tap0 is added to room1switch as a trunk port, allowing it to carry traffic for VLANs 9 and 10 between the switches.
sudo ovs-vsctl add-port room2switch tap1 vlan_mode=trunk trunk=9,10 # tap1 is added to room2switch as a trunk port, allowing it to carry traffic for VLANs 9 and 10 between the switches.

# tap0 and tap1 are configured as patch ports with their peers set to each other. This connects the switches in room 1 and room 2, allowing traffic to pass between them.
sudo ovs-vsctl set interface tap0 type=patch options:peer=tap1
sudo ovs-vsctl set interface tap1 type=patch options:peer=tap0

#Gateway
sysctl -w net.ipv4.ip_forward=1 # IP forwarding is enabled on the host(the machine where the script is being executed) to allow it to forward packets between different interfaces. This is necessary for the host to act as a gateway and route traffic between the two tenants.
sudo ip -n t1device2 route add 192.168.1.0/24 via 10.0.1.10 # necessary to direct traffic from t1device2 to the 192.168.1.0/24 network via the gateway 10.0.1.10.
iptables --table nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE # Masquerading is used to allow devices in the 10.0.1.0/24 subnet to communicate with external networks (like 192.168.1.0/24) using the host machine's IP address.