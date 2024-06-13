# Delete namespaces
sudo ip netns del t1device1
sudo ip netns del t2device1
sudo ip netns del t1device2
sudo ip netns del t2device2

# Delete bridges
sudo ovs-vsctl del-br room1switch
sudo ovs-vsctl del-br room2switch

# Delete links
sudo ip addr flush vlan10s2
sudo ip addr flush vlan10s1
sudo ip addr flush vlan9s1
sudo ip addr flush vlan9s2
sudo ip addr flush room1switch
sudo ip addr flush room2switch

sudo ip link delete vlan10s2
sudo ip link delete vlan10s1
sudo ip link delete vlan9s1
sudo ip link delete vlan9s2
sudo ip link delete room1switch
sudo ip link delete room2switch