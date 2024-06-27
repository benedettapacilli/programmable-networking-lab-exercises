/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800; // constant for IPv4 ethertype

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t { // Ethernet header made of destination and source MAC addresses and EtherType
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t { // IPv4 header made of version, IHL, DSCP, total length, identification, flags, fragment offset, TTL, protocol, header checksum, source and destination IP addresses
    bit<4>    version;
    bit<4>    ihl; // Internet Header Length, used to indicate where the data begins
    bit<8>    diffserv; // DSCP (Differentiated Services Code Point), used for QoS
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

struct metadata {
    /* empty */
}

struct headers { // Structure containing the headers of the packet (ethernet and ipv4)
    ethernet_t   ethernet;
    ipv4_t       ipv4;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

// We need the parser to extract the headers from the packet
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        /* TODO: add parser logic */
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet); // Extract the ethernet header from the packet
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4; // If the ethertype is IPv4, parse the IPv4 header
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4); // Extract the IPv4 header from the packet
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

// We need the ingress processing to forward the packet
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        /* TODO: fill out code in action body */
        standard_metadata.egress_spec = port; // Set the egress port
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr; // Set the source MAC address to the destination MAC address as the previous destination MAC address will be the source MAC address of the next hop
        hdr.ethernet.dstAddr = dstAddr; // Set the destination MAC address to the one specified in the action
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm; // Longest Prefix Match
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

// We need the egress processing to update the headers of the packet
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
	update_checksum(
	    hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

//TODO: Implement the deparser
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        // packet.emit converts the headers into a byte stream so that can be transmitted over the network.
        packet.emit(hdr.ethernet); // Emit the ethernet header
        packet.emit(hdr.ipv4); // Emit the ipv4 header
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;