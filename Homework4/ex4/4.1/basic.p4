#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;



struct intrinsic_metadata_t {
    bit<4>  mcast_grp;
    bit<4>  egress_rid;
    bit<16> mcast_hash;
    bit<32> lf_field_list;
}



header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
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



struct metadata {
    @name(".intrinsic_metadata")
    intrinsic_metadata_t intrinsic_metadata;
}



struct headers {
    @name(".ethernet")
    ethernet_t   ethernet;
    @name(".ipv4")
    ipv4_t   ipv4;
}



parser ParserImpl(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".start") state start {
        transition parse_ethernet;
    }
    @name(".parse_ethernet") state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }
    @name(".parse_ipv4")state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

}

control ingress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

    action drop() {
        mark_to_drop();
    }

    action forward(egressSpec_t port) {
        standard_metadata.egress_spec = port;
    }

    table phy_forward {
        key = {
            standard_metadata.ingress_port: exact;
        }
        actions = {
            forward;
            drop;
        }
        size = 1024;
        default_action = drop();
    }

    @name(".do_copy") action do_copy() { // clones packets from ingress to egress (I2E)
        /* TODO CLONE */ ;
        clone3(CloneType.I2E, (bit<32>)32w250, { standard_metadata }); // we clone the packet and the standard metadata as well. 250 is the session specifying the clone group
    }
    @name(".mycopy") table mycopy {
        actions = {
            do_copy;
        }
        size = 1;
        default_action = do_copy();
    }
    apply {
        mycopy.apply();
        phy_forward.apply();
    }
}

control egress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
        mycopy.apply();
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {}
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {}
}

V1Switch(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;
