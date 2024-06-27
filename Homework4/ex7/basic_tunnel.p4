/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

#define HASH_BASE 10w0
#define HASH_MAX 10w1023
const bit<16> TYPE_MYTUNNEL = 0x1212;
const bit<16> TYPE_IPV4 = 0x800;
#define CPU_MIRROR_SESSION_ID 250

/*************************************************************************
*********************** H E A D E R S ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header myTunnel_t {
    bit<16> proto_id;
    bit<16> dst_id;
    bit<16> flag_1;
    bit<16> flag_2;
    bit<16> flag_3;
    bit<48> flag_4;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
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

struct ingress_metadata_t {
    bit<64> my_flowID;
    bit<64> my_estimated_count;
    bit<1> already_matched;
    bit<32> nhop_ipv4;
    bit<64> carry_min;
    bit<64> carry_min_plus_one;
    bit<8> min_stage;
    bit<1> do_recirculate;
    bit<9> orig_egr_port;
    bit<32> hashed_first;
    bit<32> hashed_second;
    bit<32> hashed_address_s3;
    bit<64> random_bits;
    bit<12> random_bits_short;
    bit<32> ingress_timestamp; // ingress timestamp metadata
}

struct egress_metadata_t {
    bit<32> egress_timestamp; // egress timestamp metadata
}

struct metadata {
    @name("ingress_metadata") ingress_metadata_t ingress_metadata;
    @name("egress_metadata") egress_metadata_t egress_metadata;
}

struct headers {
    ethernet_t   ethernet;
    myTunnel_t   myTunnel;
    ipv4_t       ipv4;
}

/*************************************************************************
*********************** P A R S E R *************************************
*************************************************************************/

parser MyParser(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    state start {
        transition parse_ethernet;
    }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_myTunnel {
        packet.extract(hdr.myTunnel);
        transition select(hdr.myTunnel.proto_id) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
    state parse_progop {
        packet.extract(hdr.program);
        transition accept;
    }
}

/*************************************************************************
************** I N G R E S S   P R O C E S S I N G ***********************
*************************************************************************/

control MyIngress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    register<bit<48>>(1024) flow_count;
    register<bit<48>>(1024) proc_delay;

    action myTunnel_forward(egressSpec_t port) {
        standard_metadata.egress_spec = port;
        MyEgress.apply();
    }

    action set_nhop(bit<32> nhop_ipv4) {
        meta.ingress_metadata.nhop_ipv4 = nhop_ipv4;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            set_nhop;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            // 1. Capture the current time at the ingress stage
            meta.ingress_metadata.ingress_timestamp = standard_metadata.ingress_global_timestamp;
            ipv4_lpm.apply();
            myTunnel_forward(egress_port); // Placeholder action to forward the packet
        }
    }
}

/*************************************************************************
**************** E G R E S S   P R O C E S S I N G ***********************
*************************************************************************/

control MyEgress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    register<bit<48>>(1024) proc_delay;

    apply {
        if (hdr.ipv4.isValid()) {
            // 2. Capture the current time at the egress stage
            meta.egress_metadata.egress_timestamp = standard_metadata.egress_global_timestamp;

            // 3. Calculate delay by comparing ingress and egress timestamps
            bit<32> delay = meta.egress_metadata.egress_timestamp - meta.ingress_metadata.ingress_timestamp;
        }
    }
}

/*************************************************************************
************* C H E C K S U M    C O M P U T A T I O N *******************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
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
*********************** D E P A R S E R **********************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.myTunnel);
        packet.emit(hdr.ipv4);
    }
}

/*************************************************************************
*********************** S W I T C H **************************************
*************************************************************************/

V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser()
) main;