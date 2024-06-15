## Step 0: start controllers and topology

```bash
ryu-manager /usr/local/lib/python3.10/dist-packages/ryu/app/simple_switch_13_patched.py --ofp-tcp-listen-port 6633 --wsapi-port 8080 &
```
```bash
ryu-manager /usr/local/lib/python3.10/dist-packages/ryu/app/simple_switch_13_patched.py --ofp-tcp-listen-port 6653 --wsapi-port 8081 &
```

``` bash
sudo mn --custom 2switch_3host_2ext_cntlr.py --topo mytopo --controller=remote,ip=127.0.0.1,port=6633 --controller=remote,ip=127.0.0.1,port=6653 --mac
```

The following command is used to show the state of the switches and their connections to the controllers:
``` bash
sudo ovs-vsctl show
```
Output returned is:
``` bash
2e6eabe4-a72a-438c-acea-7902c107347d
    Bridge s1
        Controller "ptcp:6654"
        Controller "tcp:127.0.0.1:6633"
            is_connected: true
        Controller "tcp:127.0.0.1:6653"
            is_connected: true
        fail_mode: secure
        Port s1
            Interface s1
                type: internal
        Port s1-eth2
            Interface s1-eth2
        Port s1-eth3
            Interface s1-eth3
        Port s1-eth1
            Interface s1-eth1
    Bridge s2
        Controller "tcp:127.0.0.1:6653"
            is_connected: true
        Controller "ptcp:6655"
        Controller "tcp:127.0.0.1:6633"
            is_connected: true
        fail_mode: secure
        Port s2
            Interface s2
                type: internal
        Port s2-eth1
            Interface s2-eth1
        Port s2-eth2
            Interface s2-eth2
    ovs_version: "2.17.9"
```

## Step 1: C1 requires to be SLAVE for sw1
``` bash
curl -X POST -d '{"dpid": 1, "role": "slave"}' http://localhost:8081/v1.0/conf/switches/0000000000000001/role
```
where:
- ```"dpid": 1```: This identifies the switch with DPID 1 (sw1) in your topology
- ```"role": "slave"```: This sets the role of the controller to SLAVE for the specified switch
- ```http://localhost:8081/v1.0/conf/switches/0000000000000001/role```: This is the endpoint of the REST API for the Ryu controller on port 8081

We can verify the role change through the following command:
``` bash
curl http://localhost:8081/v1.0/conf/switches/0000000000000001/role
```
Output returned is:
``` bash
{
    "dpid": "0000000000000001",
    "role": "slave"
}
```

## Step 2: Set C0 as MASTER for sw1

``` bash
curl -X POST -d '{"dpid": 1, "role": "master"}' http://localhost:8080/v1.0/conf/switches/0000000000000001/role
```
so that:
- C0 (Master): The controller at localhost:8080 will manage switch sw1.
- C1 (Slave): The controller at localhost:8081 will not manage flows but will monitor the switch sw1.

We can verify the role change through the following command:
``` bash
curl http://localhost:8080/v1.0/conf/switches/0000000000000001/role
```
Output returned is:
``` bash
{
    "dpid": "0000000000000001",
    "role": "master"
}
```

## Step 3: C1 requires to be MASTER for sw2
We need to create a JSON file indicating the correct datapath ID and role for sw2.
For sw2, the datapath ID needs to be identified through
```bash
sudo ovs-ofctl show s2
```
which returns:
```bash
OFPT_FEATURES_REPLY (xid=0x2): dpid:0000000000000002
...
```

Creating the JSON file *role_master_sw2.json*:
``` JSON
{
    "dpid": "0000000000000002",
    "role": "master"
}
```
Then, we can use the following command to set the role of C1 to MASTER for sw2:
``` bash
curl -X POST -d @role_master_sw2.json http://localhost:8081/v1.0/conf/switches/0000000000000002/role
```

We can verify the role change through the following command:
``` bash
curl http://localhost:8081/v1.0/conf/switches/0000000000000002/role
```
Output returned is:
``` bash
{
    "dpid": "0000000000000002",
    "role": "master"
}
```

After this step, C0 (8080) for sw2 should not be MASTER, either SLAVE or EQUAL.

## Step 4: Host1 Ping Host2
```bash
mininet> h1 ping h2
```
When performing ping from h1 to h2, the ping should be successful as the controllers are managing the switches correctly.<br/>
C0 controller is responsible for managing the flow entries on sw1. As the master controller, it will handle the forwarding rules for the traffic between h1 and h2. <br/>
C1 controller will receive updates but will not actively manage the flow entries on sw1.
<br/>When the network starts, the master controller (C0) sets up initial flow rules on sw1 to enable communication between hosts connected to the switch. The switch will learn the MAC addresses of the connected devices and set up appropriate flow rules to forward packets directly to the destination without flooding. <br/>
The master controller (C0) will install flow entries in sw1 to handle traffic between h1 and h2. These entries will direct the switch on how to forward packets from h1 to h2 and vice versa. <br/>
Both h1 and h2 are connected to sw1. Given that sw1 is managed by C0 as the master controller, it has the necessary flow rules to forward traffic between these two hosts.

## Step 5: Stop C0 Controller
```bash
sudo pkill -f 'ryu-manager.*6633'
```
as C0 is running on port 6633.

If we ping from h1 to h2, the ping should still be successful because the flow rules that were installed by the master controller (C0) on sw1 remain active even after the controller is stopped. These flow rules will continue to govern the forwarding behavior of the switch until they are explicitly removed or they expire. Additionally, since C1 is connected as a slave controller, it can take over if configured to do so, ensuring continued network operation.

## Step 6: Host1 Ping Host3
```bash
mininet> h1 ping h3
```
When performing ping from h1 to h3, the ping should be successful as the controllers are managing the switches correctly.<br/>

## Step 7:	C1 requires to	be	MASTER	for	sw1
```bash
curl -X POST -d '{"dpid": 1, "role": "master"}' http://localhost:8081/v1.0/conf/switches/0000000000000001/role
```

## Step 8: Host1 Ping Host3 again
```bash
mininet> h1 ping h3
```
