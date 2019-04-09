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

// Template parser.p4 file for basic_switching
// Edit this file as needed for your P4 program

// This parses an ethernet header


#define ETHERTYPE_DDC_UPDATE 0x1234
#define ETHERTYPE_IPV4 0x0800
#define ETHERTYPE_TEST 0x0fff
#define ETHERTYPE_LINKDOWN 0x9047
#define ETHERTYPE_HEARTBEAT 0xFB00
#define TCP_PROTO 0x06
#define UDP_PROTO 0x11
#define XCP_PROTO 0x07


parser start {
    return select(current(96,16)) {
        ETHERTYPE_LINKDOWN : parse_linkdown;
        default : parse_ethernet;
    }
}

parser parse_linkdown {
    extract(linkdown);
    return ingress;
}
parser parse_ethernet {
    extract(ethernet);
    return select(ethernet.etherType) {
        ETHERTYPE_IPV4 : parse_ipv4;
        ETHERTYPE_DDC_UPDATE : parse_ddc;
        default: ingress;
    }
}

parser parse_ipv4 {
    extract(ipv4);
    return select (ipv4.protocol) {
        TCP_PROTO : parse_tcp;
        UDP_PROTO : parse_udp;
        default : ingress;
    }
}

parser parse_ddc {
    extract(ddc);
    return ingress;
}
parser parse_tcp {
    extract(tcp);
    return ingress;
}

parser parse_udp {
    extract(udp);
    return ingress;
}
