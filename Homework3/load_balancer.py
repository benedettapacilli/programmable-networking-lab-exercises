from ryu.base import app_manager
from ryu.controller import ofp_event
from ryu.controller.handler import CONFIG_DISPATCHER, MAIN_DISPATCHER
from ryu.controller.handler import set_ev_cls
from ryu.ofproto import ofproto_v1_3
from ryu.lib.packet import packet
from ryu.lib.packet import ether_types
from ryu.lib.packet import ipv4
from ryu.lib.mac import haddr_to_int
from ryu.lib.packet.ether_types import ETH_TYPE_IP
from ryu.lib.packet import arp
from ryu.lib.packet import ethernet

# Controller logic is based on event handler programming
class SimpleSwitch13(app_manager.RyuApp): # app_manager.RyuApp is the base class for Ryu applications.
    OFP_VERSIONS = [ofproto_v1_3.OFP_VERSION] # specifies the OpenFlow version

    VIRTUAL_IP = '10.0.0.100'  # The virtual server IP

    # First (physical) server IP, MAC and port
    SERVER1_IP = '10.0.0.101'
    SERVER1_MAC = '00:00:00:00:00:01'
    SERVER1_PORT = 1
    # Second (physical) server IP, MAC and port
    SERVER2_IP = '10.0.0.102'
    SERVER2_MAC = '00:00:00:00:00:02'
    SERVER2_PORT = 2

    def __init__(self, *args, **kwargs):
        super(SimpleSwitch13, self).__init__(*args, **kwargs)
        self.mac_to_port = {}  # MAC to port mapping: A dictionary is used to store key-value pairs (e.g., MAC addresses and ports).
        self.current_server = 1  # Initial server for round-robin selection

    @set_ev_cls(ofp_event.EventOFPSwitchFeatures, CONFIG_DISPATCHER) # event handler: EventOFPSwitchFeatures is triggered when a switch connects to the controller. CONFIG_DISPATCHER means that the handler is called when the switch features are being configured (post handshake)
    def switch_features_handler(self, ev):
        """
        Handles the switch features message, which is sent when a switch connects to the controller.

        params:
        - ev: The event that triggered this handler.
        """
        datapath = ev.msg.datapath # The datapath is the switch that connected to the controller.
        ofproto = datapath.ofproto # The OpenFlow protocol used by the switch.
        parser = datapath.ofproto_parser # The parser used to create OpenFlow messages.

        # install table-miss flow entry to forward unmatched packets to the controller
        match = parser.OFPMatch()
        actions = [parser.OFPActionOutput(ofproto.OFPP_CONTROLLER,
                                          ofproto.OFPCML_NO_BUFFER)]
        self.add_flow(datapath, 0, match, actions) # Adds a flow entry to the switch.

    def add_flow(self, datapath, priority, match, actions, buffer_id=None):
        """
        Adds a flow entry to the switch.

        params:
        - datapath: The switch that the flow entry is being added to.
        - priority: The priority of the flow entry.
        - match: The match fields of the flow entry.
        - actions: The actions to be performed by the flow entry.
        - buffer_id: The buffer ID of the packet data.
        """
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser

        inst = [parser.OFPInstructionActions(ofproto.OFPIT_APPLY_ACTIONS,
                                             actions)]
        if buffer_id:
            mod = parser.OFPFlowMod(datapath=datapath, buffer_id=buffer_id,
                                    priority=priority, match=match,
                                    instructions=inst)
        else:
            mod = parser.OFPFlowMod(datapath=datapath, priority=priority,
                                    match=match, instructions=inst)
        datapath.send_msg(mod)

    @set_ev_cls(ofp_event.EventOFPPacketIn, MAIN_DISPATCHER) # event handler: EventOFPPacketIn is triggered when a packet is sent to the controller. MAIN_DISPATCHER means that the handler is called when the switch is sending packets to the controller (post config phase, waiting for/sending messages from/to	switches)
    def _packet_in_handler(self, ev):
        """
        Handles packets that are sent to the controller. It learns the source MAC address of the packet and installs a flow entry in the switch to avoid packet_in next time.

        params:
        - ev: The event that triggered this handler.
        """
        if ev.msg.msg_len < ev.msg.total_len:
            self.logger.debug("packet truncated: only %s of %s bytes",
                              ev.msg.msg_len, ev.msg.total_len)
        msg = ev.msg
        datapath = msg.datapath # The switch that sent the packet to the controller.
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        in_port = msg.match['in_port'] # The port that the packet was received on.

        pkt = packet.Packet(msg.data)
        eth = pkt.get_protocols(ethernet.ethernet)[0]

        if eth.ethertype == ether_types.ETH_TYPE_LLDP: # LLDP packet are used by network devices to advertise their identity and capabilities on a local area network.
            # ignore lldp packet
            return
        dst_mac = eth.dst
        src_mac = eth.src

        dpid = datapath.id
        self.mac_to_port.setdefault(dpid, {})

        self.logger.info("packet in %s %s %s %s", dpid, src_mac, dst_mac, in_port)

        # learn a mac address to avoid FLOOD next time.
        self.mac_to_port[dpid][src_mac] = in_port

        if dst_mac in self.mac_to_port[dpid]:
            out_port = self.mac_to_port[dpid][dst_mac]
        else:
            out_port = ofproto.OFPP_FLOOD # Floods the packet to all ports except the incoming port to find the destination MAC address and port.

        actions = [parser.OFPActionOutput(out_port)] # this specifies that the packet should be sent out of the specified port (saved as action to do)

        # install a flow to avoid packet_in next time
        if out_port != ofproto.OFPP_FLOOD:
            match = parser.OFPMatch(in_port=in_port, eth_dst=dst_mac, eth_src=src_mac)
            # verify if we have a valid buffer_id, if yes avoid to send both
            # flow_mod & packet_out
            if msg.buffer_id != ofproto.OFP_NO_BUFFER:
                self.add_flow(datapath, 10, match, actions, msg.buffer_id)
                return
            else:
                self.add_flow(datapath, 10, match, actions)

        # Handle TCP Packet
        if eth.ethertype == ETH_TYPE_IP:
            self.logger.info("***************************")
            self.logger.info("---Handle TCP Packet---")
            ip_header = pkt.get_protocol(ipv4.ipv4)

            packet_handled = self.handle_tcp_packet(datapath, in_port, ip_header, parser, dst_mac, src_mac)
            self.logger.info("TCP packet handled: " + str(packet_handled))
            if packet_handled:
                return

    def select_server(self):
        """
        Simple round-robin implementation for server selection.
        """
        if self.current_server == 1:
            self.current_server = 2
            return self.SERVER1_IP, self.SERVER1_MAC, self.SERVER1_PORT
        else:
            self.current_server = 1
            return self.SERVER2_IP, self.SERVER2_MAC, self.SERVER2_PORT

    def handle_tcp_packet(self, datapath, in_port, ip_header, parser, dst_mac, src_mac):
        """
        Handles TCP packets directed to the virtual IP. It selects the server, sets up the forward and reverse flows, and filters packets based on TCP protocol and port 8080.

        params:
        - datapath: The switch that the packet was received on.
        - in_port: The port that the packet was received on.
        - ip_header: The IP header of the packet.
        - parser: The parser used to create OpenFlow messages.
        - dst_mac: The destination MAC address of the packet.
        - src_mac: The source MAC address of the packet.
        """
        packet_handled = False

        if ip_header.dst == self.VIRTUAL_IP and ip_header.proto == 6:  # TCP protocol
            server_ip, server_mac, server_port = self.select_server()

            # Route to server
            match = parser.OFPMatch(in_port=in_port, eth_type=ETH_TYPE_IP, ip_proto=ip_header.proto,
                                    ipv4_dst=self.VIRTUAL_IP, tcp_dst=8080) # Filter packets based on TCP protocol and port 8080

            # this action sets the destination IP address to the server IP and forwards the packet to the server port
            actions = [parser.OFPActionSetField(ipv4_dst=server_ip),
                       parser.OFPActionOutput(server_port)]

            self.add_flow(datapath, 20, match, actions)
            self.logger.info("<==== Added TCP Flow- Route to Server: " + str(server_ip) +
                             " from Client :" + str(ip_header.src) + " on Switch Port:" +
                             str(server_port) + "====>")

            # Reverse route from server
            match = parser.OFPMatch(in_port=server_port, eth_type=ETH_TYPE_IP,
                                    ip_proto=ip_header.proto,
                                    ipv4_src=server_ip,
                                    eth_dst=src_mac)
            actions = [parser.OFPActionSetField(ipv4_src=self.VIRTUAL_IP),
                       parser.OFPActionOutput(in_port)]

            self.add_flow(datapath, 20, match, actions)
            self.logger.info("<==== Added TCP Flow- Reverse route from Server: " + str(server_ip) +
                             " to Client: " + str(src_mac) + " on Switch Port:" +
                             str(in_port) + "====>")

            packet_handled = True
        return packet_handled
