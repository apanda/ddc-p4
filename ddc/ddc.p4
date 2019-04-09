/*
This code implements DDC:

1) Maintain link-direction(In/Out) as a bit-sequence in a 32/64-bit integer.

2) Link-failure to be detected by pkt-gen trigger and update link-state register.

3) AEO operation will be initiated by Control Plane.
*/
#include "includes/headers.p4"
#include "includes/parser.p4"
#include <tofino/intrinsic_metadata.p4>
#include <tofino/constants.p4>
#include <tofino/primitives.p4>
#include "tofino/stateful_alu_blackbox.p4"
#include "tofino/lpf_blackbox.p4"
#include "tofino/wred_blackbox.p4"


#define MAX_FLOWS 32768
#define MAX_LINKS 32
#define IN  1
#define OUT 0
#define MAX_DESTINATIONS 128
#define DEST_LINKS 4096 // MAX_DESTINATIONS * MAX_LINKS

#define YES 1
#define NO  0

#define DOWN 0
#define UP 1

#define DROP 1
#define FIB_UPDATE 1

register linkstate {
    width : 32;
    instance_count : 1;
}

// blackbox stateful_alu set_linkstate_down {
//     reg : linkstate;
//     update_lo_1_value :
// }

blackbox stateful_alu get_linkstatus {
    reg : linkstate;
    output_value : register_lo;
    output_dst : mdata.linkstatus;
    initial_register_lo_value : 0x0000001F;
}

blackbox stateful_alu down_linkstatus {
    reg : linkstate;
    update_lo_1_value : register_lo & mdata.linkbitmask;
}
// Below registers' width are 32 bit, thus supported 32 links for now.
// For more links separate registers need to be used.


register direction_arrival {
    width : 32;
    instance_count : MAX_DESTINATIONS;
}

blackbox stateful_alu read_direction_arrival {
    reg : direction_arrival;
    output_value : register_lo;
    output_dst : mdata.direction_arrival;
}

blackbox stateful_alu write_direction_arrival {
    reg : direction_arrival;
    update_lo_1_value : ddc.direction;
}
register direction_departure {
    width : 32;
    instance_count : MAX_DESTINATIONS;
}

blackbox stateful_alu get_direction_departure {
    reg : direction_departure;
    output_value  : register_lo;
    output_dst : mdata.direction_departure;
}
blackbox stateful_alu set_direction_departure {
    reg : direction_departure;
    update_lo_1_value : mdata.direction_arrival;
}

blackbox stateful_alu incr_direction_departure {
    reg : direction_departure;
    update_lo_1_value : register_lo | mdata.linkbitmask;
}


blackbox stateful_alu direction_departure_all_outlinks {
    reg : direction_departure;
    update_lo_1_value : 0;
}

blackbox stateful_alu direction_departure_link_out_to_in {
    reg : direction_departure;
    update_lo_1_value : register_lo | mdata.linkbitmask;
}
register local_seq {
    width : 32;
    instance_count : MAX_DESTINATIONS;
}

blackbox stateful_alu increment_local_seq {
    reg: local_seq;
    update_lo_1_value : ~register_lo; // flip all bits
}
register remote_seq {
    width : 32;
    instance_count : MAX_DESTINATIONS;
}

blackbox stateful_alu get_remote_seq {
    reg: remote_seq;
    output_value : register_lo;
    output_dst : mdata.remote_seq;
}

blackbox stateful_alu remote_seq_out_to_in {
    reg : remote_seq;
    update_lo_1_value : register_lo | mdata.linkbitmask; // reverse_out_to_in(L)
}

// blackbox stateful_alu set_remote_seq {
//     reg : remote_seq;
//     update_lo_1_value : ddc.remote_seq;
// }
//
register remote_seq_departure {
    width : 32;
    instance_count : MAX_DESTINATIONS;
}

blackbox stateful_alu get_remote_seq_departure {
    reg: remote_seq_departure;
    output_value : register_lo;
    output_dst : mdata.remote_seq_departure;
}

blackbox stateful_alu incr_remote_seq_departure {
    reg : remote_seq_departure;
    update_lo_1_value : register_lo ^ mdata.linkbitmask;
}

register remote_seq_in_update {
    width : 8;
    instance_count : DEST_LINKS;
}

blackbox stateful_alu check_remote_seq_stale {
    reg : remote_seq_in_update;
    condition_lo : register_lo == 0;
    update_lo_1_predicate : condition_lo;
    update_lo_1_value : 1;
    update_hi_1_predicate : condition_lo;
    update_hi_1_value : 0;
    update_hi_2_predicate : not condition_lo;
    update_hi_2_value : 1;
    output_value : alu_hi;
    output_dst : mdata.remote_seq_stale;
}

blackbox stateful_alu clear_remote_seq_update {
    reg : remote_seq_in_update;
    update_lo_1_value : 0;
}

register remote_seq_indiv {
    width : 8;
    instance_count : DEST_LINKS;
}

blackbox stateful_alu incr_remote_seq_condition {
    reg : remote_seq_indiv;
    condition_lo : register_lo != mdata.packetSeq;
    update_lo_1_predicate : condition_lo;
    update_lo_1_value : mdata.packetSeq;
    update_hi_1_predicate : condition_lo;
    update_hi_1_value : 0;
    update_hi_2_predicate : not condition_lo;
    update_hi_2_value : 1;
    output_value : alu_hi;
    output_dst : mdata.pseq_remoteseq_equal;
}

//
// register direction_in_update {
//     width : 1;
//     instance_count : DEST_LINKS;
// }
//
// blackbox stateful_alu check_mark_direction_stale {
//     reg : direction_in_update;
//     condition_lo : register_lo == 0;
//     update_lo_1_predicate : condition_lo;
//     update_lo_1_value : 1;
//     update_hi_1_predicate : condition_lo;
//     update_hi_1_value : 0;
//     update_hi_2_predicate : not condition_lo;
//     update_hi_2_value : 1;
//     output_value : alu_hi;
//     output_dst : mdata.direction_stale;
// }


register test1 {
    width : 32;
    instance_count : 1;
}

blackbox stateful_alu store_val_test1 {
    reg : test1;
    update_lo_1_value : mdata.test1;
}

register test2 {
    width : 32;
    instance_count : 1;
}

blackbox stateful_alu store_val_test2 {
    reg : test2;
    update_lo_1_value : 1;
}

register test3 {
    width : 32;
    instance_count : 1;
}

blackbox stateful_alu store_val_test3 {
    reg : test3;
    update_lo_1_value : linkdown.port;
}


/********End of Register ********/

action do_fib(destination) {
    modify_field(mdata.destination, destination);
    modify_field(mdata.test1, 111);
}

action do_efib(destination) {
    modify_field(mdata.destination, destination);
}

action do_linkforward(egress_port) {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, egress_port);
}


action nop() {
}

action _drop () {
    modify_field(mdata.fib_drop, YES);
    drop();
}

action do_send_to_cpu () {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, 192);
}
action do_load_direction_arrival () {
    read_direction_arrival.execute_stateful_alu(mdata.destination);
}

action do_compute_linkindex (linkindex) {
    modify_field(mdata.linkindex, linkindex);
}

action do_compute_linkdown_linkindex (linkindex) {
    modify_field(mdata.linkindex, linkindex);
}

action do_load_direction_for_linkindex(bitmask) {
    bit_and(mdata.link_direction, mdata.direction_arrival, bitmask);
    modify_field(mdata.linkbitmask, bitmask);
}

action do_recompute_linkdirection() {
    bit_and(mdata.link_direction, mdata.direction_arrival, mdata.linkbitmask);
}
action do_load_remote_seq_index () {
    shift_left(mdata.remote_seq_index, mdata.destination, MAX_LINKS);
}

action do_compute_remote_seq_index () {
    add_to_field(mdata.remote_seq_index, mdata.linkindex);
}

action do_get_linkstatus () {
    get_linkstatus.execute_stateful_alu(0);
}
action do_load_remote_seq () {
    get_remote_seq.execute_stateful_alu(mdata.destination);
    shift_left(mdata.remote_seq_index, mdata.destination, MAX_LINKS);
}
action do_update_remote_seq () {
    //set_remote_seq.execute_stateful_alu(mdata.destination);
}
action do_compute_pseq_remoteseq () {
    bit_xor(mdata.pseq_remoteseq, mdata.packetSeqbitmask, mdata.remote_seq);
    add_to_field(mdata.remote_seq_index, mdata.linkindex);
    get_linkstatus.execute_stateful_alu(0);
}

action do_make_link_out_to_in () {
    // Make the bit 1(in)
    bit_or(mdata.direction_arrival, mdata.direction_arrival, mdata.linkbitmask);
    bit_xor(mdata.remote_seq, mdata.remote_seq, mdata.linkbitmask);
    //direction_departure_link_out_to_in.execute_stateful_alu(mdata.destination);
    modify_field(mdata.direction_update , 1);
}

action compute_outlink_count (outlink_count) {
    modify_field(mdata.outlink_count, outlink_count);
}

action do_make_all_outlinks () {
    //direction_departure_all_outlinks.execute_stateful_alu(mdata.destination);
    modify_field(mdata.direction_arrival, 0);
    modify_field(mdata.direction_update, 2);
    modify_field(mdata.out_links, mdata.linkstatus);
}

action do_incr_local_seq () {
    increment_local_seq.execute_stateful_alu(ddc.destination);
}

action do_load_linkstatus () {
    get_linkstatus.execute_stateful_alu(0);
}

action do_update_linkstatus () {
    down_linkstatus.execute_stateful_alu(0);
}
action do_check_any_outlink_up () {
    bit_andca(mdata.out_links, mdata.direction_arrival, mdata.linkstatus);
}

action do_choose_outlink (egress_spec) {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, egress_spec);
}

action do_check_stale_remote_seq () {
    check_remote_seq_stale.execute_stateful_alu(mdata.remote_seq_index);
}

// action do_check_stale_direction () {
//     check_direction_stale.execute_stateful_alu(mdata.remote_seq_index);
// }

action do_bounce_back_link () {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, ig_intr_md.ingress_port);
}

action do_update_direction_departure () {
    set_direction_departure.execute_stateful_alu(mdata.destination);
    // Clone this packet and recirculate in egress.
}

action do_update_remote_seq_departure () {
    incr_remote_seq_departure.execute_stateful_alu(mdata.destination);
    // Clone this packet and recirculate in egress.
}
action do_incr_update_direction_departure () {
    incr_direction_departure.execute_stateful_alu(mdata.destination);
    // Clone this packet and recirculate in egress.
}
action do_load_direction_departure () {
    get_direction_departure.execute_stateful_alu(mdata.destination);
    // Clone this packet and recirculate in egress.
}

action do_load_remote_seq_departure () {
    get_remote_seq_departure.execute_stateful_alu(mdata.destination);
    // Clone this packet and recirculate in egress.
}
action do_clone_pkt (session_id) {
    clone_egress_pkt_to_egress(session_id);
}

action do_load_packet_seq(packet_seq) {
    bit_and(mdata.packetSeqbitmask, packet_seq, mdata.linkbitmask); // FFFFFFFF or 0
    modify_field(mdata.packetSeq, packet_seq); // 1 or 0
}

action do_remove_ingress_from_outlink () {
    bit_andca(mdata.out_links, mdata.linkbitmask, mdata.out_links);
}

action fib_update () {
    modify_field(mdata.fib_update, YES);
}

action no_mapping () {
    //modify_field(mdata.fib_drop, YES);
}

action do_change_header_tcp () {
    remove_header(tcp);
    remove_header(ipv4);
    modify_field(ethernet.etherType, ETHERTYPE_DDC_UPDATE);
    add_header(ddc);
    //modify_field(ddc.remote_seq, mdata.remote_seq_departure);
    modify_field(ddc.direction, mdata.direction_departure);
    modify_field(ddc.destination, mdata.destination);
    modify_field(ddc.pipe_state, 0);

    //modify_field(ddc.remote_seq_index, mdata.remote_seq_index);
}

action do_update_direction_arrival () {
    write_direction_arrival.execute_stateful_alu(ddc.destination);
}
action do_test1 () {
    store_val_test1.execute_stateful_alu(0);
}

action do_test2 () {
    store_val_test2.execute_stateful_alu(0);
}

action do_test3 () {
    store_val_test3.execute_stateful_alu(0);
}

action do_remove_remote_seq_stale () {
    clear_remote_seq_update.execute_stateful_alu(ddc.remote_seq_index);
}

action do_check_remote_seq () {
    incr_remote_seq_condition.execute_stateful_alu(mdata.remote_seq_index);
}

action do_compute_bitmask(bitmask) {
    modify_field(mdata.linkbitmask, bitmask);
}

action do_recirc_to_1 () {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, 196);
}

action do_recirc_to_0 () {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, 68);
}

action do_set_ddc_state () {
    modify_field(ddc.pipe_state, 1);
    bypass_egress();
}

action do_set_linkdown_state () {
    modify_field(linkdown.pipe_state, 1);
    bypass_egress();
}
/****End of Actions ***/

table fib {
    reads {
        ethernet.dstAddr : exact;
    }
    actions {
        do_fib;
        _drop;
    }
}


table efib {
    reads {
        ethernet.dstAddr : exact;
    }
    actions {
        do_efib;
        _drop;
    }
}


table load_direction_arrival {
    actions {
        do_load_direction_arrival;
    }
}
@pragma stage 1
table update_direction_arrival {
    actions {
        do_update_direction_arrival;
    }
}

table load_direction_for_linkindex {
    reads {
        mdata.linkindex : exact;
    }
    actions {
        do_load_direction_for_linkindex;
    }
}

table compute_linkindex {
    reads {
        ig_intr_md.ingress_port : exact;
    }
    actions {
        do_compute_linkindex;
        fib_update;
        no_mapping;
    }
}

table compute_linkdown_linkindex {
    reads {
        linkdown.port : exact;
    }
    actions {
        do_compute_linkdown_linkindex;
    }
}
table load_remote_seq {
    actions {
        do_load_remote_seq;
    }
}
@pragma stage 1
table update_remote_seq {
    actions {
        do_update_remote_seq;
    }
}
table compute_pseq_remoteseq {
    actions {
        do_compute_pseq_remoteseq;
    }
}

table make_link_out_to_in {
    actions {
        do_make_link_out_to_in;
    }
}

// table compute_outlink_count {
//     reads {
//         mdata.direction_arrival : exact;
//     }
//     actions {
//         do_compute_outlink_count;
//     }
// }

table make_all_outlinks {
    actions {
        do_make_all_outlinks;
    }
}

table incr_local_seq {
    actions {
        do_incr_local_seq;
    }
}

table load_linkstatus {
    actions {
        do_load_linkstatus;
    }
}

@pragma stage 4
table update_linkstatus {
    actions {
        do_update_linkstatus;
    }
}
table check_any_outlink_up {
    actions {
        do_check_any_outlink_up;
    }
}

table choose_outlink {
    reads {
        mdata.out_links : ternary;
    }
    actions {
        do_choose_outlink;
    }
}

table check_stale_remote_seq {
    actions {
        do_check_stale_remote_seq;
    }
}

// table check_stale_direction {
//     actions {
//         do_check_stale_direction;
//     }
// }

table recompute_linkdirection {
    actions {
        do_recompute_linkdirection;
    }
}

table load_packet_seq {
    reads {
        ipv4.flags : ternary;
    }
    actions {
        do_load_packet_seq;
    }
}


table bounce_back_link {
    actions {
        do_bounce_back_link;
    }
}
@pragma stage 1
table update_direction_departure {
    reads {
        mdata.direction_update : exact;
    }
    actions {
        do_incr_update_direction_departure;
        do_update_direction_departure;
    }
}
@pragma stage 1
table load_direction_departure {
    actions {
        do_load_direction_departure;
    }
}

@pragma stage 2
table update_remote_seq_departure {
    actions {
        do_update_remote_seq_departure;
    }
}
@pragma stage 2
table load_remote_seq_departure {
    actions {
        do_load_remote_seq_departure;
    }
}
table clone_pkt {
    reads {
        mdata.direction_update : exact;
    }
    actions {
        do_clone_pkt;
        nop;
    }
}

table remove_ingress_from_outlink {
    actions {
        do_remove_ingress_from_outlink;
    }
}


table change_header {
    actions {
        do_change_header_tcp;
    }
}
table itest1 {
    actions {
        do_test1;
    }
}

table itest2 {
    actions {
        do_test2;
    }
}

table itest3 {
    actions {
        do_test3;
    }
}

table dropit {
    actions {
        _drop;
    }
}

@pragma stage 5
table remove_remote_seq_stale {
    actions {
        do_remove_remote_seq_stale;
    }
}

table check_remote_seq {
    actions {
        do_check_remote_seq;
    }
}

table load_remote_seq_index {
    actions {
        do_load_remote_seq_index;
    }
}

table compute_remote_seq_index {
    actions {
        do_compute_remote_seq_index;
    }
}

table compute_bitmask {
    reads {
        mdata.linkindex : exact;
    }
    actions {
        do_compute_bitmask;
    }
}
control update_fib_on_departure {
    if (mdata.out_links == NO) {
        // Make all links out
        apply(make_all_outlinks);
        // local seq should be incremented only after updating direction_arrival
    }
}

table recirc_ddc {
    reads {
        ig_intr_md.ingress_port : ternary;
        ddc.pipe_state : exact;
    }
    actions {
        do_recirc_to_0;
        do_recirc_to_1;
        _drop;
    }
}

table recirc_linkdown {
    reads {
        ig_intr_md.ingress_port : ternary;
        linkdown.pipe_state : exact;
    }
    actions {
        do_recirc_to_0;
        do_recirc_to_1;
        _drop;
    }
}

@pragma stage 2
table set_ddc_state {
    actions {
        do_set_ddc_state;
    }
}
@pragma stage 2
table set_linkdown_state {
    actions {
        do_set_linkdown_state;
    }
}

table send_to_cpu {
    actions {
        do_send_to_cpu;
    }
}
control update_fib_on_arrival {
    apply(load_packet_seq);
    apply(load_remote_seq_index);
    apply(compute_remote_seq_index);
    if (mdata.link_direction == OUT) {
        apply(check_remote_seq);
        if (mdata.pseq_remoteseq_equal == NO) { //p.seq != remote_seq[L]
            apply(make_link_out_to_in);
        }
    } else {
        // assert(p.seq == remote_seq[L])
    }
}

// control update_fib_on_arrival_oldway {
//     apply(load_remote_seq);
//     apply(load_packet_seq);
//     apply(compute_pseq_remoteseq);
//     if (mdata.link_direction == OUT) {
//         if (mdata.pseq_remoteseq != NO) { //p.seq != remote_seq[L]
//             // Need to check if remote_seq info we have is stale
//             // if it is not stale, need to mark it stale
//             apply(check_stale_remote_seq);
//             if (mdata.remote_seq_stale == NO) {
//                 apply(make_link_out_to_in);
//             } else {
//                 // Do nothing
//             }
//         }
//     } else {
//         // assert(p.seq == remote_seq[L])
//
//     }
// }

control bounce_back {
    apply(recompute_linkdirection);
    if (mdata.link_direction == OUT) {
        if (mdata.pseq_remoteseq_equal == NO) { //p.seq != remote_seq[L]
            if (mdata.remote_seq_stale == NO) {
                apply(bounce_back_link);
            }
        }
    }
}

control ingress {
    if (valid(linkdown)) {
        apply(itest3);
        apply(compute_linkdown_linkindex);
        apply(compute_bitmask);
        apply(recirc_linkdown);
        apply(set_linkdown_state);
        apply(update_linkstatus);
    } else if (valid(ddc)) {
        apply(update_direction_arrival);
        apply(incr_local_seq);
        // apply(update_remote_seq); // This is no longer needed, since we do in
        // apply(remove_remote_seq_stale); // place update for remote_seq
        apply(recirc_ddc);
        apply(set_ddc_state);
    } else {
        apply(fib);
        apply(compute_linkindex);
        if (mdata.fib_update == NO) {
    //        if (mdata.fib_drop == NO) {
                apply(load_direction_arrival);
                apply(load_direction_for_linkindex);
                update_fib_on_arrival();
                // Finally forward to the coresponding link
                apply(load_linkstatus);
                apply(check_any_outlink_up);
                update_fib_on_departure();
                apply(remove_ingress_from_outlink);
                apply(choose_outlink);
                bounce_back();
    //        }
        }
    }
}


control egress {
    if (valid(linkdown)) {
        // Do Nothing
    } else {
        if (pkt_is_not_mirrored) {
            if (mdata.direction_update != NO) {
                apply(itest1);
                apply(clone_pkt);
                apply(update_direction_departure);
                //apply(update_remote_seq_departure);
            }
        } else {
            apply(itest2);
            apply(efib);
            apply(load_direction_departure);
            //apply(load_remote_seq_departure);
            apply(change_header);
        }
    }

}
