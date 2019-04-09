/*
 * Control Plane program for Tofino-based Timesync program.
 * Compile using following command : make ARCH=Target[tofino|tofinobm]
 * To Execute, Run: ./timesync_cp
 *
 */

//extern "C" {
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <sched.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#include <unistd.h>
#include <pthread.h>
#include <unistd.h>
#include <bfsys/bf_sal/bf_sys_intf.h>
#include <dvm/bf_drv_intf.h>
#include <lld/lld_reg_if.h>
#include <lld/lld_err.h>
#include <lld/bf_ts_if.h>
#include <knet_mgr/bf_knet_if.h>
#include <knet_mgr/bf_knet_ioctl.h>
#include <bf_switchd/bf_switchd.h>
#include <pkt_mgr/pkt_mgr_intf.h>
#include <tofinopd/ddc/pd/pd.h>
#include <tofino/pdfixed/pd_common.h>
#include <tofino/pdfixed/pd_mirror.h>
#include <tofino/pdfixed/pd_conn_mgr.h>
#include <pcap.h>
#include <arpa/inet.h>

//#include <linux/getcpu.h>
//
#define THRIFT_PORT_NUM 7777

#define ETHERTYPE_LINKDOWN 0x9047
#define ETHERTYPE_HEARTBEAT 0xFB00

#define CAPTURE_TX_CORE 2
#define P4SYNC_CAPTURE_COMMAND 0x6
#define P4_PKTGEN_APP_LCOUNTER 0x5
#define TCP_PROTO 0x06
#define XCP_PROTO 0x07
#define UDP_PROTO 0x11
p4_pd_sess_hdl_t sess_hdl;

typedef struct __attribute__((__packed__)) linkdown_t {
  uint8_t dstAddr[6];
//  uint8_t srcAddr[6];
  uint16_t type;
  uint16_t pipe_state;
} linkdown;

typedef struct __attribute__((__packed__)) heartbeat_t {
  uint8_t dstAddr[6];
  uint8_t srcAddr[6];
  uint16_t type;
} linkdown;

typedef struct __attribute__((__packed__)) tcp_t {
  uint8_t ethdstAddr[6];
  uint8_t ethsrcAddr[6];
  uint16_t ethtype;
  uint8_t version_ihl;
  uint8_t diffserv;
  uint16_t totalLen;
  uint16_t identification;
  uint16_t flags_fragoffset;
  uint8_t ttl;
  uint8_t protocol;
  uint16_t ipchecksum;
  uint32_t ipsrcAddr;
  uint32_t ipdstAddr;
  uint16_t srcPort;
  uint16_t dstPort;
  uint32_t seqNo;
  uint32_t ackNo;
  uint8_t dataOffset_res;
  uint8_t flags;
  uint16_t window;
  uint16_t tcpchecksum;
  uint16_t urgentPtr;
  uint8_t payload[16];
} tcp;

FILE *fp;
FILE *hist;
#define VAL1 255
#define VAL2 128


void init_bf_switchd() {
  bf_switchd_context_t *switchd_main_ctx = NULL;
  char *install_dir;
  char target_conf_file[100];
  int ret;
	p4_pd_status_t status;
  install_dir = getenv("SDE_INSTALL");
  sprintf(target_conf_file, "%s/share/p4/targets/tofino/ddc.conf", install_dir);

  /* Allocate memory to hold switchd configuration and state */
  if ((switchd_main_ctx = malloc(sizeof(bf_switchd_context_t))) == NULL) {
    printf("ERROR: Failed to allocate memory for switchd context\n");
    return;
  }

  memset(switchd_main_ctx, 0, sizeof(bf_switchd_context_t));
  switchd_main_ctx->install_dir = install_dir;
  switchd_main_ctx->conf_file = target_conf_file;
  switchd_main_ctx->skip_p4 = false;
  switchd_main_ctx->skip_port_add = false;  //bf_pkt_set_pkt_data(bfpkt, upkt);
  switchd_main_ctx->running_in_background = true;
  switchd_main_ctx->dev_sts_port = THRIFT_PORT_NUM;
  switchd_main_ctx->dev_sts_thread = true;
	//switchd_main_ctx->kernel_pkt = true;

  ret = bf_switchd_lib_init(switchd_main_ctx);
  printf("Initialized bf_switchd, ret = %d\n", ret);

	status = p4_pd_client_init(&sess_hdl);  //bf_pkt_set_pkt_data(bfpkt, upkt);

	if (status == 0) {
		printf("Successfully performed client initialization.\n");
	} else {
		printf("Failed in Client init\n");
	}

}

void init_ports() {
	system("bfshell -f ports-add.txt");
	system("echo exit\n");
}

void init_tables() {
	system("bfshell -f commands-tofino.txt");
}

tcp tcp_pkt;
uint8_t *tpkt;
bf_pkt *bftcppkt = NULL;
size_t tcp_pkt_sz = sizeof(tcp); // 1500 byte pkt

linkdown linkdown_pkt;
uint8_t *lpkt;
size_t linkdown_pkt_sz = sizeof(linkdown);
static bf_status_t switch_pktdriver_tx_complete(bf_dev_id_t device,
                                                bf_pkt_tx_ring_t tx_ring,
                                                uint64_t tx_cookie,
                                                uint32_t status) {

  //bf_pkt *pkt = (bf_pkt *)(uintptr_t)tx_cookie;
  //bf_pkt_free(device, pkt);
  return 0;
}

bf_status_t rx_packet_callback (bf_dev_id_t dev_id,
   bf_pkt *pkt,
   void *cookie,
   bf_pkt_rx_ring_t rx_ring) {
     printf("Packet received..\n");
     int i;
     for (i=0;i<pkt->pkt_size;i++) {
       printf("%X ", pkt->pkt_data[i]);
     }
     printf("\n");
     return 0;
}



void switch_pktdriver_callback_register(bf_dev_id_t device) {

  bf_pkt_tx_ring_t tx_ring;
  bf_pkt_rx_ring_t rx_ring;
  bf_status_t status;
  int cookie;
  /* register callback for TX complete */
  for (tx_ring = BF_PKT_TX_RING_0; tx_ring < BF_PKT_TX_RING_MAX; tx_ring++) {
    bf_pkt_tx_done_notif_register(
        device, switch_pktdriver_tx_complete, tx_ring);
  }
  /* register callback for RX */
  for (rx_ring = BF_PKT_RX_RING_0; rx_ring < BF_PKT_RX_RING_MAX; rx_ring++) {
    status = bf_pkt_rx_register(device, rx_packet_callback, rx_ring, (void *) &cookie);
  }
  printf("rx register done. stat = %d\n", status);
}

bf_pkt_tx_ring_t tx_ring = BF_PKT_TX_RING_0;
uint32_t seqNo = 0;
uint32_t rtt = 100; // in us
uint32_t cwnd = 10;

void bftcppkt_init () {
  if (bf_pkt_alloc(0, &bftcppkt, tcp_pkt_sz, BF_DMA_CPU_PKT_TRANSMIT_0) != 0) {
    printf("Failed bf_pkt_alloc\n");
  }
  uint8_t dstAddr[] = {0x3c, 0xfd, 0xfe, 0xad, 0x82, 0xe0};//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4};// {0xf4, 0xe7, 0xb7, 0xfe, 0xfd, 0x3c};
  uint8_t srcAddr[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x11};
  memcpy(tcp_pkt.ethdstAddr, dstAddr, 6);//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4}
  memcpy(tcp_pkt.ethsrcAddr, srcAddr, 6);//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4}
  tcp_pkt.ethtype = htons(0x0800);
  tcp_pkt.version_ihl = 0x40;
  tcp_pkt.protocol = TCP_PROTO;
  tcp_pkt.ipdstAddr = 0x0a00000a;
  tcp_pkt.ipsrcAddr = 0x0a000001;
  tcp_pkt.srcPort = 0xa;
  tcp_pkt.dstPort = 0xf;
  tcp_pkt.flags_fragoffset = htons(0xFFFF);
  tpkt = (uint8_t *) malloc(tcp_pkt_sz);
  memcpy(tpkt, &tcp_pkt, tcp_pkt_sz);

  if (bf_pkt_is_inited(0)) {
    printf("bf_pkt is initialized\n");
  }

  if (bf_pkt_data_copy(bftcppkt, tpkt, tcp_pkt_sz) != 0) {
    printf("Failed data copy\n");
  }
}

void send_tcp_packet(int interval) {
  memcpy(tpkt, &tcp_pkt, tcp_pkt_sz);

  if (bf_pkt_data_copy(bftcppkt, tpkt, tcp_pkt_sz) != 0) {
    printf("Failed data copy\n");
  }
  bf_status_t stat = bf_pkt_tx(0, bftcppkt, tx_ring, (void *)bftcppkt);
  if (stat  != BF_SUCCESS) {
    printf("Failed to send packet status=%s\n", bf_err_str(stat));
  }
}

void* tcp_pktgen(void *args) {
    printf("Sending IPv4/UDP Packets Out..\n");
    struct timespec tsp;
    tsp.tv_sec = 0;
    tsp.tv_nsec = 1;
    int i=1;
    //sleep(30);

    printf("Sent..\n");

    while (1) {
      send_tcp_packet(i);

      usleep(1);
    }

}

void linkdown_pkt_init() {
  uint8_t dstAddr[] = {0x3c, 0xfd, 0xfe, 0xad, 0x82, 0xe0};//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4};// {0xf4, 0xe7, 0xb7, 0xfe, 0xfd, 0x3c};
  uint8_t srcAddr[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x11};
  memcpy(linkdown_pkt.dstAddr, dstAddr, 6);//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4}
//  memcpy(p4sync_pkt.srcAddr, srcAddr, 6);//{0x3c, 0xfd,0xfe, 0xb7, 0xe7, 0xf4}
  linkdown_pkt.type = htons(ETHERTYPE_LINKDOWN);
  lpkt = (uint8_t *) malloc(linkdown_pkt_sz);
  memcpy(lpkt, &linkdown_pkt, linkdown_pkt_sz);
}

void linkdown_pktgen_init() {
  linkdown_pkt_init();
  struct p4_pd_pktgen_app_cfg lcounter_app_cfg;
  uint16_t pkt_offset = 0;
  p4_pd_dev_target_t p4_pd_device;
  p4_pd_device.device_id = 0;
  p4_pd_device.dev_pipe_id = PD_DEV_PIPE_ALL;
  int buffer_len = (linkdown_pkt_sz < 64)? 64:linkdown_pkt_sz;
  p4_pd_status_t pd_status;

  pd_status = p4_pd_pktgen_enable(sess_hdl,0, 196);
  pd_status = p4_pd_pktgen_enable(sess_hdl,0, 68);

  if (pd_status != 0) {
    printf("Failed to enable pktgen status = %d!!\n", pd_status);
    return;
  }
  lcounter_app_cfg.trigger_type = PD_PKTGEN_TRIGGER_PORT_DOWN;
  lcounter_app_cfg.batch_count = 0;
  lcounter_app_cfg.packets_per_batch = 1;
  lcounter_app_cfg.pattern_value = 0;
  lcounter_app_cfg.pattern_mask = 0;
  lcounter_app_cfg.timer_nanosec = 0;
  lcounter_app_cfg.ibg = 0;
  lcounter_app_cfg.ibg_jitter = 0;
  lcounter_app_cfg.ipg = 1000;
  lcounter_app_cfg.ipg_jitter = 0;
  lcounter_app_cfg.source_port = 0;
  lcounter_app_cfg.increment_source_port = 0;
  lcounter_app_cfg.pkt_buffer_offset = 0;
  lcounter_app_cfg.length = buffer_len;
  pd_status = p4_pd_pktgen_cfg_app(sess_hdl,
                                   p4_pd_device,
                                   P4_PKTGEN_APP_LCOUNTER,
                                   lcounter_app_cfg);
  if (pd_status != 0) {
    printf(
        "pktgen app configuration failed "
        "for app %d on device %d : %s (pd: 0x%x)\n",
        P4_PKTGEN_APP_LCOUNTER,
        0, pd_status);
    return;
  }
  pd_status = p4_pd_pktgen_write_pkt_buffer(sess_hdl, p4_pd_device, pkt_offset, buffer_len, lpkt);
  if (pd_status != 0) {
    printf("Pktgen: Writing Packet buffer failed!\n");
    return;
  }
  p4_pd_complete_operations(sess_hdl);
  pd_status = p4_pd_pktgen_app_enable(sess_hdl, p4_pd_device, P4_PKTGEN_APP_LCOUNTER);

  if (pd_status != 0) {
    printf("Pktgen : App enable Failed!\n");
    return;
  }
  printf("Pktgen: Success!!\n");
}

p4_pd_mirror_session_info_t mirror_info_pipe1;

void init_mirror(void) {
  mirror_info_pipe1.type = 0;
  mirror_info_pipe1.dir = PD_DIR_BOTH;
  mirror_info_pipe1.id = 1;
  mirror_info_pipe1.egr_port = 196;
  mirror_info_pipe1.egr_port_v = 1;
  mirror_info_pipe1.max_pkt_len = 51;
  p4_pd_dev_target_t p4_dev_tgt = {0, (uint16_t)PD_DEV_PIPE_ALL};

  p4_pd_status_t status = p4_pd_mirror_session_create(sess_hdl, p4_dev_tgt, &mirror_info_pipe1);
  printf("Created mirror session, status=%d\n", status);
}

void pktgen_trig_port_down (void)  {
  int ports[] = {128,129,130,131};//144,145,146,147};
  int i;
  sleep(1);
  for (i=0;i<4;i++) {
    p4_pd_status_t status = p4_pd_pktgen_clear_port_down(sess_hdl, 0, ports[i]);
    printf("Pktgen clear port down for %d, status = %d\n", ports[i], status);
  }
  p4_pd_complete_operations(sess_hdl);
}

int main (int argc, char **argv) {

	init_bf_switchd();
	init_tables();

	init_ports();
	pthread_t pktgen_thread;
  pthread_t histogram_thread;

	printf("Starting pattern_matching Control Plane Unit ..\n");
  cpu_set_t cpuset_pktgen;
	CPU_ZERO(&cpuset_pktgen);
	CPU_SET(7, &cpuset_pktgen);
  init_mirror();


  switch_pktdriver_callback_register(0);
  bftcppkt_init();
  linkdown_pktgen_init();
  // // printf("Starting pktgen thread\n");
  // pthread_create(&maint_pktgen_thread, NULL, read_pkt_count, NULL);
  // pthread_setaffinity_np(maint_pktgen_thread, sizeof(cpu_set_t), &cpuset_pktgen);
  pktgen_trig_port_down();
  pthread_create(&pktgen_thread, NULL, tcp_pktgen, NULL);
  pthread_setaffinity_np(pktgen_thread, sizeof(cpu_set_t), &cpuset_pktgen);

  pthread_join(pktgen_thread, NULL);
	return 0;
}
