### Steps to execute a program in Tofino:

1) Navigate to the SDE PATH :
```shell
     cd ~/bf-sde-8.x.x
```
2) Set the env variables : 
```shell
     . ./set_sde.bash
```
3) Build the p4 program using the command :
```shell
     ./p4_build ddc/ddc.p4
```
4) Load the p4 program, and run the control plane API code using :
```shell
     "cd ddc/CP"
     "./run.sh"
```

### Command to execute upon tofino reboot
```shell
     cd ~/bf-sde-8.x.x
     . ./set_sde.bash
     sudo ./install/bin/bf_kdrv_mod_load $SDE_INSTALL
```
### Steps to execute a program in Netronome Nic:

1) Load the nfp kernel module :
```shell
     sudo modprobe nfp nfp_pf_netdev=0 nfp_dev_cpp=1
```
2) Start the run-time environment :
```shell
     sudo systemctl start nfp-sdk6-rte
     sudo systemctl start nfp-sdk6-rte-debug
```
3) Build the program using the below command :
```shell
     sudo nfp4build -s AMDA0096-0001:0 -l lithium -o <prog_name>.nffw -p nfp-build -4 <prog_name>.p4 
```
4) Load the firmware using the command :
```shell
     sudo nfp-nffw load -s <prog_name>.nffw
```
5) Load the design on the nic : 
```shell
     sudo rtecli design-load -f <prog_name>.nffw -p nfp-build/pif_design.json -c user_config.json
```

Now you must see the vf interfaces in ifconfig.

#### Primitives for programmable switches are summarized in [net-prog-model](net-prog-model/net-prog-model.md)
#### Primitives for smart-nics are summarized in [nic-prog-model](net-prog-model/nic-prog-model.md)
