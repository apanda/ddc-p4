/*
Copyright 2013-present Barefoot Networks, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Template headers.p4 file for basic_switching
// Edit this file as needed for your P4 program

// Here's an ethernet header to get started.

header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header_type heartbeat_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}



header_type linkdown_t {
    fields {
        pipe: 5;
        app_id:3;
        _pad0_: 8;
        _pad1_: 7;
        port: 9;
        pkt_number: 16;
        srcAddr: 48;
        etherType: 16;
        pipe_state : 16;
    }
}

header_type ipv4_t {
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}


field_list ipv4_field_list {
    ipv4.version;
    ipv4.ihl;
    ipv4.diffserv;
    ipv4.totalLen;
    ipv4.identification;
    ipv4.flags;
    ipv4.fragOffset;
    ipv4.ttl;
    ipv4.protocol;
    ipv4.srcAddr;
    ipv4.dstAddr;
}

field_list_calculation ipv4_chksum_calc {
    input {
        ipv4_field_list;
    }
    algorithm : csum16;
    output_width: 16;
}

calculated_field ipv4.hdrChecksum {
    update ipv4_chksum_calc;
}

header_type ddc_t {
    fields {
        direction : 32;
        destination : 32;
        pipe_state : 16;
    }
}
header_type tcp_t {
    fields {
        srcPort     : 16;
        dstPort     : 16;
        seqNo       : 32;
        ackNo       : 32;
        dataOffset  : 4;
        res         : 4;
        flags       : 8;
        window      : 16;
        checksum    : 16;
        urgentPtr   : 16;
    }
}

header_type udp_t {
    fields {
        srcPort : 16;
        dstPort : 16;
        len : 16;
        checksum : 16;
    }
}

header ethernet_t ethernet;
header ipv4_t ipv4;
header tcp_t tcp;
header udp_t udp;
header ddc_t ddc;
header linkdown_t linkdown;

header_type metadata_t {
    fields {
        destination : 32;
        linkindex : 32;
        linkbitmask : 32;
        packetSeq : 8;
        packetSeqbitmask : 32;
        direction_arrival : 32;
        link_direction : 32;
        outlink_count : 32;
        pseq_remoteseq : 32;
        pseq_remoteseq_equal : 32;
        linkstatus : 32;
        out_links : 32;
        remote_seq_stale : 32;
        direction_update : 32;
        remote_seq_index: 32;
        remote_seq : 32;
        fib_drop : 1;
        fib_update : 1;
        test1 : 32;
        direction_departure: 32;
        remote_seq_departure : 32;
    }
}

metadata metadata_t mdata;
