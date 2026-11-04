// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:47:23 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/competition/12_yolo_accel/yolo_dma_csr/rtl/ps_axi_pl/ip/yolo_ring_bram/yolo_ring_bram_sim_netlist.v
// Design      : yolo_ring_bram
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "yolo_ring_bram,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module yolo_ring_bram
   (clka,
    ena,
    wea,
    addra,
    dina,
    douta,
    clkb,
    enb,
    web,
    addrb,
    dinb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_mode = "slave BRAM_PORTA" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [3:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [8:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *) input [3:0]web;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [8:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *) input [31:0]dinb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [31:0]doutb;

  wire [8:0]addra;
  wire [8:0]addrb;
  wire clka;
  wire clkb;
  wire [31:0]dina;
  wire [31:0]dinb;
  wire [31:0]douta;
  wire [31:0]doutb;
  wire ena;
  wire enb;
  wire [3:0]wea;
  wire [3:0]web;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rsta_busy_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [8:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [8:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "9" *) 
  (* C_ADDRB_WIDTH = "9" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "8" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "0" *) 
  (* C_COUNT_36K_BRAM = "1" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "0" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "0" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     5.9299 mW" *) 
  (* C_FAMILY = "zynq" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "1" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "0" *) 
  (* C_HAS_RSTB = "0" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "yolo_ring_bram.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "2" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "512" *) 
  (* C_READ_DEPTH_B = "512" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "1" *) 
  (* C_USE_BYTE_WEB = "1" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "4" *) 
  (* C_WEB_WIDTH = "4" *) 
  (* C_WRITE_DEPTH_A = "512" *) 
  (* C_WRITE_DEPTH_B = "512" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  yolo_ring_bram_blk_mem_gen_v8_4_12 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(clkb),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb(dinb),
        .douta(douta),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(enb),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[8:0]),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rsta_busy(NLW_U0_rsta_busy_UNCONNECTED),
        .rstb(1'b0),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[8:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(web));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.2"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
YqH9kwIC39+qbZg4PSfFsXuB9k9wnuxNryS/CfnEri6Ci9fSC6fsrQ/T/hnt3u/yolbJ8DJa1Qu6
Qnm24A9jLbA+fu3Nsmm6/rM6a4vU6OfVl/gTFd/CiWDutv6Dhn6Lim4uUNPahoOR/A2Yc4Zo2tdI
kMLO9gn9WlH2l3O2oXs=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
XJYO2VHd/cnMxQd3i7/2qRhl57dl+doEKuhAunQyv3vpGRG/jlNxj8PqrgLoF0HMdqE3qJUVE/oq
kBSapqjVjLDMOrNGQ+Tc6VGsKMZH8FE/TXHQJ/IM5Iuiu2eozEwwVUomF+7cfqn+9OsVsqCONQ1M
g0oRlangiqasJDhhMfnlGGqwAwmgWRGQA6dmhTuua1s8zdvIv540zY6p5au8cAKVhqyyKK7wbxEE
SGuFqX+NYoyRV+rfWCcWM+hJEmnWS8LNAKkd13YE2+17sPYzUdZ23DmTxXK6KlAxKFW27CBySUfg
qdNXp2DSs2KAQYih27pBNMuHfGbM/ATFPWFvxg==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
lYoEi/e8HsDTz6N11EDe/B/iitERmeYndlCklmCluwgb0N4W80JUGVlkd7NlRZHRNhxaNBJPkcjC
n61nO0tb17NwsMwjbY5TF8JWRYTNw1JXCFacvQYrdKv4/7QNQEtwVGiCLxFhOA8aHlWMZIrc2fri
VRMVWaEBcPwCGorlVIM=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QEw9fEsWFbdX0OQLvYs/gl+zyEOW3ak9TdQVaq+0AXXOT3LIqF7wDxJ6ZBnlf9mNbdsUVH5tAz1o
H8u7ihJl1L3THEvugW+TS8hkvVbEA9rKO2vV15KAj4Lla7UdFT/xDfe79RFarlLI7yGrubjgdoRi
QWy//UKsffG7IWNwmoSuppWiWB4ZHJtkunNyIkm70JPGyZF62VxJg1MTT+5LUbZG5vZjjuHZud9w
xJaKv1tFP/x8RVqLU5gPOqGqTW7/nKO2S+450Vo4D9vAmBVVcXpaL1EbSmCvQ+qJmcQKtf9qYFRV
Zko08hbpHjPxstqvTDro01jRzB8592m4xU2TWA==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
TC7q853CWBPPJgbRfgDV1lmjUwSAtliljShAyNFg8sfRfwDzchthzoSPH1UCHV++E2JXacEKq1lB
UWsNP92U4Xh0/Gu+6esOI0pJb8I+TRTxyBN1I4cRQEfQHcwfhbSdeH3yX9OV3opLEqYmT37hWU+J
zCawYnxVESI0FtRzEXve9gdEWlrKKckrT/hp4mvxxOjvOkOSQBvy0elgUOqh6mEOZl+JnUbsR+Wm
CoZLE1eefMZy3FnVmyDNPv3JPXi88aLXMyimal0MYFkTiS4XJiGT3eAIMIbksehXY+eYi/KFpZWQ
GHpX+lG3UmiWWLwyPakFwKEHbrBc70AlJ2eV9g==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
j9nmCKgjPWNChPbpSW6EWLrMA6oCG2JGPoum8px09v0PEAh0DRXZi0J8HPzXUsZgOEMcKpA7X54u
YFcDDCLAQ+urha/eSPbQYHQh4yGCursxAQ1C6LEyNQ2wJ0eLlO2bJeAl/gof06zqsYVM2lLJVNv5
wao1k2bmgPdfpfY3c9vPD0fSMuZPS41EoRS0cQhO5GTZnKdjxm6tEUL3GnTjB8ynSCIbCJUsMtAX
4FRHNa52gudx5B5fagR+lXgFhE7e++rWTJELr7SYB+r5Es8qZLTpCH8TrQxEkV0rY/+e4sAjNE2D
gHw8GD7VcUtc15B8y1BbVmh29qc8Nd3V2i/miA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
UkCD6I/Vye4qNoNoa3hIexBXG3xyKUJPAHAjIo7UcNVCDXpMQiYEtPDqExZMfiPlJn2nswCYIfIJ
FYWqMCloKSQyyI/7yZ2EtbyWEklb/P5IyZyvGi6hhFUo/JFTb12b4bK0gZPr+bCDdlVQKTx5GVHz
wptdUJO2omSj8axVMPbLRRtVzlJIZ29dTJ2ATXVXAcBxPnFfHRAMnYYKLeeLExX61vQvpqrkLQHm
XG7hpVzJi56gYKAzxa2BLq072OCVpVS70bfWlhlSTVcSlCrUf+EcarEk4FD8+Ih2NCvrqremG6yn
TtcBn8Xr8M/6zhOYvLi6AD6eArDMKA8n+Ccv8A==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
A5y5QVZU8yjPexRVPioSiAGohCHD5DX5FVobuMyhcgQRExLUhPvnnS8HOtxTj/2IapEcz68gFMGG
Hpi+m725u85/om/Vze9pGIW9Mn328Kz2FIg3W5EvGstfGwY+48LiAGAmTR269JS4lJGVYWYOz7Xk
S8cEsFd2m7j8iyKtARJzD90+UdXq/cIIh725jC9i8nbgxB364zddvm1Z/DF3JRw1qFp6GGcuRai1
KNcJ1j8c9wtIgktpsteU3e5+bxHEw8NT3gWXUFYjm00NDq97Jals8Jjktmum2nQxoF7ivPacfEey
gnSF6jRMkTsZObzc30hAhs0CEtc33hZLhPLHSn8pQ0WyvKJLHdd5s2yckgTZtqxC1Sbwe7WEgNXe
ZMX3pIkz+aoXsAL7GBLyVBMVQcyMoF0w8QGAaTe8sqatABwPqXidYRqNROTf62IYcMpV89XYgaTv
EwIn/oni9KOFd2BFVxRZbFGGC4IjvigsTBUijI+Dk6kVnDh240clGcc4

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Omtp+lCaqUx7Z4qdFj2zrN8LpCkit2eX4hlMtig+ielGm/x4FSZkpjoFmiqdKFPi2eg0pg09MSai
XyGH68UzAR7Xrj8f1jlIoUmMKp4GcxfdqfTeuu7kWGOJEP6cvgTjSJFj2gawDv7f4yZcltnK2x0L
e4GW/rBTmGvZtKWb2ahjINLxPuh3dDaSaWdb+zVgbtyrI5FrjxBkq+aOxSjyNsqnCx1L0uWbxnkl
88NbXN3dTaECXHNm/fsleayM5hKis7kTv9BFajJMGy+BhQlmIYpE+F5zchnTTFUFJZCz1sX9Fc8e
HcY7irB8mR3ajdzjUZLBQEMktp096Nheq3U75A==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
hpeBLwN9x2ZFDwroYLlUe5GjjDepHik2l0c2s3/6S7JPCRkzQSyt2V1Ad/JewAs/QNp5SXSbYYB4
rQl0My1LDMF3xw43r0g2IbcyHVpPhGp0W5msuQdF67afnsRv90iJYWLMI3QkYGCTWAzl4HrLxFSg
3z8XZRK670IcxznOrlvgHmIKsvubZrBkuc1EynrVb9Nw16QnIx2rc4WgcEXeFf+4i1RoYLDd3gXK
NFCNMdtaRYUThunFP6Z4ViZ5UnDmKq+IMhd31jTaqIlWOBDxPI1+v5RJYxIyTbn4rxlKR2fNbl5/
z4OUjBTd+1GH3I2OXlqmAOvIhpe2Z2HH7nZu/A==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Mt2RhTSUwEIEWeNARbyL+EdfS1UF6nPaL/fKl/7oO2gina93egwCWDLl1fbBtkfaPco0cu4MJ9K3
OraAsyHRlY+MNShmJ1LzAIA1LjZx4y55lu9dlQqSUXR7AW7wVbkg1864mK+hM/1XygU0jvebKNW9
B7xSER+asLO6pxi0mt7uC2PHxLPAYEszFhmnap82TtbDGdQ2qtyekY+ngs+N2fAdsblxVwJruiMl
e6XJ127M8N1mYwhWU2HtRpBOSnnKoHgD9fG51XK/rhk8DxT66QnX9uLPB+H25eDupBJGi1Y5o6x8
hOwZiSUVlBLh7brfzevh7+eRn+7es6wBas0+3w==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 29008)
`pragma protect data_block
Ky2Y9KBNoK4CV3U+7ql8vgjblT0mXknsZiZhXD56n4vk8ynj+N1PRMrGd8sKtc3Y2VtzsrzWmEaA
836bP3+HHtKrpYC9N7S297fB7JCXgnizt/lu/r9FLjhfYw94Tmhcj22RTYngvsciBZqt6mY6ycdb
50lfFfvpcDE1ancAIuBVtstR+0SAibJ1MjxDA9JcNb7CdQGUpAjNQv3cFabgLrGsj5SFl6+fo/0y
kbs0ZMusAVWXWVVcCtJ09rJ6y2FHQxD2cdhz7iViVZ47V6WPXPae4aFClEV8aJJjBukRiazQKEsq
kMKI+0OQM9WNKPB45W5PDtZEtSNIfRHl6qCh+/2nL4wH+XRJpzW0qrG2V4Wl4a+lvo0ZmxVNg+3y
XSxNX2od6Mkb4luGJZGvyH284VytKZYpU1hbC4BM237IZk01mYHk+G3E3MAahEHFRkm3LRwM+QEi
cjdEcwjdOazrWijYMg0ngecFTT4xdr+Ydyf2y9iuEXWlvGfFZZa7uEFe8FgAIJoGtKE3YxTopnPf
1k7SzfRKrubADJepyQoN5sJmZAlQAWmbuKsKXkVzsrUdZCPQovl6bqP/KYIUyU9wTA+ZilepqwaQ
eGWXBT86W/yZDEdbMpgWCoI12DzS+GfbddZ9nujNLkGQuh9egp2BKcfJnY+18Tnf0O5lMj/7HMwJ
lOGR5ir4p4OI+4TUAlAJhfwQWZ+MMTqB3FZdqU7LUw7On0/NbuJ6PsSTbop2P2vsypJnNu81Qusd
GIMZQ9iQjC0HJfx9e+VvkWYU6G8iLf4o9NcHxJv3e6xtaxB8L2gMzmgBET8AXis2t3QVJ5TptNja
uI1CPVf9gMPJjnLF91PjbtlEFk282ZyZyNA8qUC6Dx15ywPXk7vkQCRmquySjb/2q9Z+NX/q1O+n
yjNsrldZgyThgAUGKi5BLbrYMVGiCH2O9oN0tDFplkEEOt2LfZftGWKLgBt5+krJJasEwbsnNmaD
Xu+6g1qI4xlpEhGxsM/DZAEZxas8Eg73bwyQE85hlP4AUe3ENvPTAw5Dgm6/vKCohpJXK3gJ0jY9
JlA2ytRrEPDXmQTLD74OM3Qbv+KVXUTgyrI/g3mA54g2wtWv4MWqw0ntu2J0NSa4FZ4+3aYekpnb
aSm5RLmVH9ztoDblEKZ/iqyefp+Q7C+quN6BS9ocoNkNoGm1HckyPjsTpY2PSCHWm6k6tLzCzgNx
MHVghjxHV16J45QtTeZ7k9cfDmKEiQ0REb85PPrayYxBkCIc81QcdqfqB8kBaNyhd4/9Kc/HhNH1
XqWBudRuQu18iaEUq4nxJu8Tju85ie7VMQP2ntXeaHRcu512jN5V4CwynxoSsfOfDsEKyUUYuTUS
N0P8WWSoiKAyeZ61o1bF/bzAhK4sS+91FueuIpbHUnMYZtzF0azpJHt/7nVffPSpJU+5Mn3lPKuu
OE2sRCd3ElaQLUCuN5iTyoTOjcg7TIJLfj32Kf5d/PRTSZbOaA1p/Qs3KATA1jpz7TaBqvapmbNb
DyxEy/0/si5OojBTWGff6BychRJ4miCtns4fts4TADXJNUbOr6xVjcy+P2sDtkHtXmvYWJtoSzyP
5HQdqa2WXHY667riarzye2MairuF6kv0vdnKB/nOqiH1fn7usGQg4CiMMjYJeBXGKHkh4bNXi9rl
lqJu7mCkac/JHHQEGkkDT3r2VQZgVyhERndTwvoR0Vc3i1C4M4KkKDXeOu5bAzL4zhoromR/dfpt
BWCaiCwcXRQWKPv1oOmDquRSTHOOrZvWvR0OfIkUmxR4/ir9jgbAlw4f84bZZzD+X32sFHVtKpo3
UE+u3KVFb+cpA/kqUZAYZBJNw4okC5bN8X+zUBFxVhZyV7pdVapmuc9s2zCq8oBPkQu5NVPX7uVI
+WABf24tuAC/LTp+vRtkILA3UujGMUG0RAjpfIInf+ACUh00hFzthyQKnJGejAWy6MzK1nNb5LOA
YOSIXHPhPhFp958/HkUhfSSj6u3sRcIAsG3sK78U2guoSIh8bMzmK303tTmxzPEmLcx0rC0pSNgu
p6LqLxaj8+P5RLHs9MGpnCVh9DRSN7YSwaiteQr5Wgi3ipqeWC/0k81VSh7cqltbLgjjkaDgOliy
lERCPy7h94JjxbrJH7JJgoSO/hiN9cLBSsrep/as4lE18I606vOzhS8Ch3GUHs62fwISZZxPOm+F
2R3d9coRFy8KWtSiK4uqZSqpVU1VRuRZZkO4DDYRq+SwOZghovCfjOiLYsXQ/c7OS6djrayu38aq
bjpqIz2GpiKgSjQafpap65n/k87h2zJOSHFZpZnSPPQY8Wi97GbLXyBqFbdcmYpj33iOCDkWqwmR
fuGSPIJQcJf0m5JCTei0cmm8V6GEkRrOJZeDulsVWqVWlk+XuH046DMk4QJ0JvOih/UOgs9b/dT9
AJnZVJpHyrwdCYry/p9xaPw+RbOTIshggreoUtYT50VZjPQCB0hE1oi36e0pR9AO+IAHD6Qlw2Jo
TKsfpEI0RE8MG1uiqlcX4K/PbZDGMAdl/dptiuhZg7Gi8/RNocCfCUQOLIafzSYxAdU3v/zXHQET
Wa1JdmBsCzj1cUldpiCJJrYRQuqzDpfqHYOLaiSdOee1eU28nI2YqmpaRMzJ/uMeH7apFgC3SB8Q
TQvgvuoZrR+jLpAS98fIFB2YmbBM9UmFfuPc9bgC6F9HA13wpqKBYjcyiFlYJDKvMYWX0lmf+7fS
JbJg8cPmUdRY4tGGMvY0KOnHdS4EkUKysosGh1HSRxuxeACCROWLZAQi8mWKjg406BuToxg1c+da
oHimn+7kW1ylMHqXYo6TTza6gEEaoRZBOwhQYNYH8CKMG8pvEyN8ZwZm88TZcGXqGgDzNlhVdQP3
einjCuF9Nda+9juL0IIjddFmJLoZ6MukKqIpI2NcqAKMgV5IncZRFxM9H/PShOyVjzPwElmMsWuz
VchI6i45Lsbedzcwxc3meUORg+l+gi9xUyRZVrlb3M6mYj3tz32Gq3S2P3BZYj5vtYc+ACS7Rr4n
yV6XReMmgDaMFXoEwvO8h4wxhXY6aovSyWjtEWzwfmXK/mVK66mRkO6CoDd+V/qmxd6uw9QHPpy7
2AZDBoVfUcsmb7nKyAGAELZBDA6rRBLJtgPOS3SlmkdlorBIbaGlGmMCFC9gYsINxjM9DsFaPFoj
kiLIvVxan9VwVh8TUDtyDelK7/Xur8xE37Nyd2JWW9lRXRzXIXgViqSXUZbgHrXN699KkcPA0ElS
3Raq9xhFSi6xzid5STyHBiP6r0B1mRNsjmJ9G6DqN+UzPZfct0/+Hb7Z5koUNjV3zjgrnxSXiEK2
n6tSskq3Jl/Jux/0gvxHoLaQ+mGo0RUm69KBiy6DF+FGwloNZNPdViozRZ49wc5EMHj0wIteqdso
NZyzS0n6PS6zxL9e7nNfnCTSptogLlvUWyND+vigTsOKyfQZG3yIWtjWw3ckbM/YWUd3vxJwEKSK
DOP8CQnm3n5U86iHZfDCUVIUwAavvfkMeDU9Mg9yf/c9TRLXYPUUoKmCc4A50K9DHL9dA0fzgDBt
hBK9csCcQQe2gNgyO52k+qUZU5UO/ILE1v2vXA5NbOiZeYLDlEktmZ1L9ZMWR9e1OzHo/1Kdl9dI
rK3tqKDRXHqpScmnZoT8/p4iLQ9U2xDjKyZyeS+UOGHwVaFQ8g7Guj32y7MOcPEhX/8m7lIErTOi
QNBI/iQzDkK9YOVVYAWH6vogjPcz+b3koY5FQjUQWi0Gm1Jdv3GYwt/517izZlimeoIi8Vly3ZT5
/dhwdRczFE7SLPxrSECKkv3EAQF0RSnCzTntb7Px46w6s0sb7fU2p9ra5p+rD53MlsW8w4jYdosb
H09hHk1G6eZxvxxxKebUxfS22P+cgkOS5T2dKuFhEV1fBA5pDwubPElNolPUnXQCkdwCKvRUKjyu
A4leLU0teKRcWsFejUjth0ridzJXkA38QDp0EJyyAPK8B/iZQZKOfBBMGNpjNgGVrd+poMvbic+0
0lclFnx9HkkV3q+txmKAUQ+4Kq6QFPwkWIRNrxmCZG5/uAgwmwLQJPHMUAUf7iuC7byqg0ZIGnvj
vUxuqTGtBzVhAMRpaeSCSE1G+Av7E3ofhTIK93WacJGAaEnHwHR1XsAE49WnKpsaD1t0kbYs8r+r
2GKcMeKKLA/zJk/7z/BxNTGCCM/+yfFtqJ7v9YTDETPJvMBivxBH4tDKIcZbKjzOJCagWoS2KVFS
I6Jok7eRF7iiknUqkYEYtEOC56Y3+orhLfklyTn2AO3Fr6tTfGOQdIxuclLIveK7IOG5xsCouE3Q
XDEY1LqfluiV1gCSVdVwucDLu/RLi4bdx9u+QLgzkTEj/j1sO/9nU/ycnBzJ002kuHStIWjdZp6S
ijzqbHREf5BumFuRQRybaVoekO7bDjqxTu8UiU6CNulCTQad0iYAPHlnRUeGbC0FNMBdX/JunRpe
O4Lhxurk4Atx/Q7rl6VJtLW1FzELlqorTVUsMmp9qk0U9Iv4BUTWjbBY3BXXdZneTi4zrkDld15h
ACGtpUIwRt/KCo9XvIV7PfUqOQQ4Yq17IANcBBPaJpd5oaf8tWuaQsF8Cn+5vDVtyIowO03BcFc5
ZMo2wVUJysL2FFaLIsa8GPUc94nnsTRSFMSNQePolHtzbODP1iE/XIDbFWXZrz6044fHD5Vg6Ryp
mcsiQmbZbbg3Hb+GjT+vM8nU4SfYa/72TyI8Abwk51UW4pv2c2U51bQYDQEepoksECzpVhsibfpK
rtD/rrM8HQ61hJVepDY5oddTvpGAO+FXRgY0YsedUwUfhw7o20M1ArVJUAhjytpzLhKPVidGHbES
tBrnGucqhaWqORZJ/qj3CHlrnXiPO9ZE97eLieBAm3nwYfAEtEZEmcP8Twg1NrYcJlxV7WxFpTgb
G5m8gmNMAeo9MQbL1+Y1u3qwZavTyjxddlKSo2mvGH0cpSPwAaDFYYtcZZkQKvLngUdyTVTueQtF
0qpB7oJOwYLmnGDYS6qEhXwkDcAk+koBkVbc0FqgISlAIXPpzqNyYOJ3Yp3eHhjiy7yat+ZMUJCe
gJ1Ma/Q93JepE4bHFeW5GAOrQrZmby4VkN5focQekmhu3RpxvYm2NmEURo0EHvEINhfXIEuyI21c
dOtqwAfsRIEz3boIWyvBnTVn88ws38HR1a4utvJyWdKD5Oh1yrO2zhMGHAwX7O7i04HIMBjMQvsn
NKTN1vubibpi7RrKty1VQJ8WAMB/dM6GtK5NDm11cvKDug0uL5IIs3utN9UplRI85yS2c5SBbwjV
IL9d7YWaBHTaZNC7AOxBGY2tjUwdpm+rUilacEjZQ18k55uG7nCwNSA/4X1r+8j9bTUz2g3/AubM
uUOMqVv0wXJiysCdAY6odz/bo4h0Mcp673LfzZ1xT6FS35geHLTUqi94EORCKezVf3UDMdXtMUss
fJqtQ51ql6fQBRypp0L3DVbmaCme3QMxsUYSjrQfRkHSyvgk8rtO6MHaq/uZXNUyN/ZT+Jxv7owm
6s682k58brSZbYUHdaPWGbf+4wIxGKtNZoL97j2GqKFrFQJwDkRFL6f2ES6wd0McXBo77JLljSo0
Lik0pFqsKYQg2adVJNZjS0aQJYHtUKX8p8sSgasUy3bbvD97ip8HbUDKjjUZ/MlbkWMOooGl53dq
/LpJuLB6kAd4STR8czqOUDP5COYWG/Oq7mj3fgLnSmJr3wiTqgwipsRa3bRqqt8mHEzb8Y9CCJK2
BHXyGXe4zcoeaovFTrjsgLTIHMGno/5ZOeE4LU7a9r9D6udVZKlpyrv+tcvgBXyn+FfCrUy0/1n+
Ws2fXCmlFo9pm3kYxp5o3RY++zicY2sdgwHpogFlLVFvw+OYYrZBHZEpBjz14PVGV4tMR844pWBI
erROoQBvY2qtO9F5dc+Ri4Zrp7KQrJv2C+nteuNmAXOt+vFh9PNhHARtCADxRhtM3kdWyKqXH335
dsuWgFiQEXlAnnhZ2IKJYbXM8pRy5Dl/HKhw3x3ebr4dR+M0pWp8QexFzKa2U9mziFLof0EntTgQ
zy/GYYqTt3inRSETqUckds40Q4WKDMHh5fb32w98BMFZVD/ZRjhzFxLD537qjmVZzyuQ7iJzKMAr
sAoPTKcjaMpeiVBNLHLOxpFKlKoAdL9bprFHZ/STrQf9l1weYMnrp4FhwhCUlfXB9t7lKxcuvoh/
yVHhcpeUAKAlyZyPjZojyxA1FBnDawb4+Xfe8pbtwYz92yuKWqsjeym+a+yXBTQOWCAfU0MUQfHP
55jfc/YbFq6seitFmWGXk8CGcy8l+0i9kxrNIuHJSW4UVBy3Lb3Jp71/SrWAVm/9oiFmDopJKXjt
JnO8aR1rsGfwPzz2/XJ7z+r+043/vMm9Xz93DDG4Lj6IZvfLVBT+l6O9qB+CFocrzC5wvdCpk1xH
gET5zSgPGMcI//ENlgxnnLLEjIP+8dHVDCFHdgAFGuH/jy0wc6dk2yck2sJ0qfp2HZPcfnuR2SG4
JdOv3/B0bXSVQQo/zrBCGD4rxvExyU6orGtd30oUxZHTESBJ7MYTaCuD5+W032fFh8lap2rlXhoi
+4OxxesQQkwtQQuzL3QmNNHP9IJKWCY85RN1ZU2fQdYPoaSaUyynLVEdhx5/1t7HYzGV7dfl/s+e
chpK3arTys5jicyjkujj+al018YPUArDgICHpIa1YnjJvU75qNfTiKjCq9/OwYr6Y/cpx2cwlYkq
yDF3ySANuPAQpzQtCb/5Qw63IscjZURbo2mHOVMtf7wXsUazISvJX0KV37Micu5nNAn3ta2NbYg2
5CRWm24Ls8Y33Vd8QliSvtpsy8bj6l38LbEteu6Qvp1yzWwFEhEKqJTT7HfGvMhsaoK/VYXks4A1
cV/lg54fw3IPlcDH8Jpxv0mffULN+Lyy/kqZBctoRfHGMmQRv5OjeTzz1nySRGqiUtixjFPP0bxL
cyhcTrTPhWaVXthzdBYT4l04Mp37HvdRXsPJJO0ueswytb7CIO8dF8Rg1bPvwX2FVPXz0ZzWxRjk
QKFokIily4XSlKc2F0SigLiK6C+VbDrgJbvxyR821QkjOiT4aiymTjAf1Rt9q79NZWLCxqq1KHt7
5TJ7gllpEVDS0sezpzZTrBoDmHepkuFltzHuUmrfkyk1KtEJwABhAg3Eiq1LBJwaKXFKohUO+MEg
bq4qG1y377TwtCz09RfkKeOARQy8U9I0i6VEGiTd8r+Fa61wUQ++7r3xAGw+FFE0TQPEr/YNYE7R
LSf/90aRCpgzCoGquJ4cJj/1IRDe08s8iV1ClMFVClHy++9otGC9DT0D+K8bf1+COisv40hchUj7
XMfTkE4Pw9K9PncaR5aIgnD2ryTVpT3CY9HraFt0SWB3cGiJySGkwgNpTjmLrt4/14fU2BVZVyFC
YazP2HoKt7MEwQF7nAY/nGJVk7k/z1wUIKbI3rxp7qbQe9m7QP2GwowRAgHCx9pduD+XZR7+bJPi
OWEucXVtXxuax/SuuF70wcfDiduRhMKUqP7g1Imi/jCQcmhNbkJ1G/AlgV5izHOajXAPE4x3lsya
z6rbN+08vx+pOmpWhZVMHRKISly0yXsN6jjLCK3QoZDKZoLmxcqFAKPHl/Zma2jlIZHJDHwkCB2N
Mv578lhY6Yrgk6JdZ0xxM1zH43dPiAoOAu4QZbfy/FocDW1mwPHXkBkVLhjfnqG6XuqFTdNW+OHw
BLrwmcFzSGLOf6fhXgp//j50hB8GoYfBlBN+pCFpxyPEzWcrR0vkIf7LCsuwtbxr144O2UiG12jr
mv2tOHLEwnlYJCke1LOody3B+wLMtHNUfMvc8GitsrcEMZF0pGlCM+d85nuIh4NoFqw7yjR4YikN
VyNlqiC+1NlKaIwlfYPkeFI0JKOZQgOER5vwo8lamxusjk6l9TGt8RwYCVQ6RyJ9SApU4wn7EkDJ
b7NUFsx/sUsOQZOBfoWkJekbxruIwx18x0nnkKwtO54e4Pmh2Y0Tyx2hH9XgqztxcDyk5dfdRTpU
iFqURR28H2slw4WrlieOgZ+ehKRTd3DCpDTyEtFYPaFb3W0CwbnKMCQFiBEgQ2v+N8HYdBP7sTDk
L4THsit1XmauG4pnuRYSp+atzFEnR0NPG5O8s1mykfJxm20eOtcLUmEYJEr6Z/iFzBMHdPEs+1SP
E/W2idI0i4uS8XbmnBnefAQ3+lWHArASsGmB/uj/uTdEUWq8icGhv+Oi/NPTmPqL6ggTO9FZSYYC
aFdISveRBH9ctFFtG8v5YkncnbkB2DIbbAaCFgwMrdt2kd4ZR54Bz0Hr8gcAzhdxaoLmBJqInHkZ
e0T1AY/g7lHxT+UzSHdF73RaaZ0GBy2vRsdtKJmFhKPG1W2TmdQcvY1wPrFCoDLFejK0kIf3bdrE
cnVG58dls20iGu9xRrXny0mpwBIQPo2wlnOxBXvWhMeTuwcZIJcrZBfec5oGujF0jNaqdvaTDJeR
Cg2iihlpZsa8phjOQ22hbXbROvW+Y8FrHHc/9mwd/Lh+ua1UQtp4YJujhxXMpQ1IMAKIbuerOYIh
ayBs4WjWGivweb7gexAAWRnnx/Ik4Wi+wXM9QakgrUVkBkAuMDNLUqD9y9tTfPv8ms5soNZhj8vA
E6z+dlt6onFmC7EvcQirX0KBtwG60n/dNgXSqBL6MvicQw8ICSVEsSALjdSnm89vl/gWz/+V7aAJ
hXBDOmgWp1nBHa8O0FyHz/H751tYMGykfkjvVOZPSi58gvxtxru0+Y8b2A5GV6mZcI+5ncFGfFaS
ZSWKP+And1WVvL/uESepx5wKVIK65ibP8+Ffi6ZpUgKt1HD//M4GzjYhPtkOmFAuem7Nby0ir/3w
0ZTT6O0Wl05Ym1KNuNltTTGeS1tVd1VLW02v7MA2BCS9Z4YfHpSrwQMY2WwxxucK85DWL5plfTDg
6++qBxfOWMfPvQsKJmEjg7/iDEA8f+Q2rlFqCPZ7WPBQ8w8GXM2qSHT9wI6U6BvB+xlmO1eXyLo+
RsqbpSmmP8w3gqj6amdpB0KARISG11tu+ndlIqUCkPbc7L/xR6h7j7jUhvs4Pr7jANfoBAiAT3xN
QgwQvEs9El5vOE4tGdL63aMhI0oDeeA+bCRGCmyyez3ia/Yk/BY3Unu42lKXjLpe3CpuNiS1V9B4
jrRAO3FtT8AMhw+wuxL8Rvtg7lCHS8AT3F2uwEi4UCMV5ytYP4vBCB+ab7vxQXEHh0dWFcbBriw/
PlF6GOB9iSrEU3CV/KGGAyG1leRp7shgNXUCh2TglrJ9O+AnGWQeQ90z2rGEFhd5UFpxPtbscIio
YrAcFVFKFdvjt25q4F1T8//C38vYHhuhFuwnULF+kMMJnjBUfwGlL/4mg+nVAKX/FQTk+BK6W7Xi
nWA0awwjKRsOk7z8ZPvnchwXSul8mzWlUCUMCiK0yYzWtAIEykdf6zmWiwclYqAc6cuMZ1n50p+q
XkeZjisomhM4l7f49S/tzx/uubvI1W6/GgoKEurHE7gdjIMQB85RkbXEZWmHdtdCdT2RawiFrLrc
fnDR1j7XRlrMX2RNav/PdWMAX7i5ihJmeZGICcnq/PJJuq2IcTiQoU8lA43DshAtPzXC0Y8WdLd+
ThXzjiNisWSIwpMXPTKbwzrjCuRTuiWfn6oRUvLKm6gtmtya8fGNNcZnpKMNYL1hurPGjUZydPHn
7FWkAhbtaQcWGK223rwvN9T1T1wnGeh9zuy7keLE/wsTF/KlrqEoPpflQyNkPol5TduqzuihX2hn
z+h89B+tCxoH7m0gkXTEl3sKdkq0PO3ajU91XXYrdiOowmFeJYEpwQBH5C/EBe2OJViZeqjdHau+
eFZ+nThIxRyM/4TKA5nXysSC8BzZbJNZ8SfE12XhMPE0yyiYLoW8RDPo5J3Jg/ZhkF9ZyUIzDKQg
UoP92JsX7FB+pVhvEGS0U2tinQfg6lcP/WXQAZjcixz0A7jru6pmlA20mmeB1g66k1QCViVgmJd6
A3ILS5QLWnxqHCPPw3fUkCxfyUj3GReSkFaxp+UUe73wheqgrhfznopuUhK080brzykD/GOnY4lR
phUyDPuWdam24xjU3BFCBbmH+/mfxqdyZTdUvVDd4JU2CNCs1iqMW44wFg46AardRVMaa+9j365r
WpZj3z9Nn33YnTGRC3tBwcUvAFnSdnYIp/eh5R7am7ccraEwuS3fAQjkX572lBemhT8S0LIahNTs
r7OR4sIZt3gtvdcPi6lvlKsARznzrJ5efbSNFwtR59t9HCmul0y8XD2mMVlbYJaSWTqL/kLAh6L6
4279Z9a6jH+sj6/PsUVCUCJbere2F6Ac5fuaDGtIUCCjx1FuNRBux9q5gLEiphChmaAynccEmHBv
fYzcoMRzjHTBEBE4yZejjfZ3l3MRHdByhxjKb3Jf6Vn5oebGXCYDW1tfhVWfrBexQtUj1RHcaF+v
QmK3eeBVrSm+uLsQs5D0onkZlvr186UWju734MzUoKxjZSJLMH6V/gjSFj55bC8k2lyq+9ZfAEaO
63lyYZZd02pr5vaK4jX/TclLfpJrV+3rmaNcNoXOlzFrQnFifBPk429nYgC6Qk2WkoSvVJSidzrd
X8DAzFrMdsbU1NOAk8SoD39SBZGaVndY7gKqpMCtCKF7PU8ww1zrdJ/7f7FXA74cmaduQjhb5/HG
A0ssIAonD09r0xNHkKIW9ielRgnoqNPJgHbfuocCYuM5SdeAAhiunM31CrBVwmNXAkWbK6zv5Yu3
waQWy62cEiiPxuaavLQm5nAvM2Qx1KYgo1E3mE++hYhLmpNrUB8dCr7Gkx1pdzI7Wa7OD9TrKh0p
xR8Z991Xuz7tx/Qy8ffDFJd05znDZfa0ylYAmzrCwzi6jEXa3JnFP9+KN8+I5cRKhy7i94sAFpBl
hEPoXL7xjY0RhgDqCyEvwTh1oxfOMoITJXfY6WNvBe5RagvcAuMMD/JGEZwgbq3VTO4jwNKaQ+AE
n5//lGbb3LCE9M97GFxHNt+DJXIEqZsrL15GG92ItAS8ZDoF0lfBkQ8llvYQ14uBPmlBT57V833w
+53SBMoMSkJ75Ytx65M+4ilGI4/N3LLRIUPLGMfC6HzBO3PYJ4MvfpLC7GHMmzJr/juFjXldbnZ8
lIxatkeRa705ReBQfz9OO9qWNxyJKa8tRpVhfr/K2YHaTV5wqI9SdZL+N4g/nc4tV2b5QhsDlJNQ
yh5zutqQ8XCb/KX+X8kfp1WY7DOPsyJ84wIfwbhCDGgjlD9kd/KReXmhygTXNAho3aKhK/Qdz7Gq
aiLgOrnc5O2SNZlehuUCcB/Qa+qMmmlSiV0r1e0nO9X60odtd7vg6atbjjxH0gAHDw7ElPiQjrqz
AijogXuN4/Hwl9GyO8yySRd0dGudw9z1HCvqv56aM3Iql2Mi4OI5UaiQBbvF1T7yZN/cjs3fU/kh
swAmXZ53wUg0Tj4t5M3ABx/kPN5V0nE0MqKbuy53Hyw65C6+MgNGxhWFr6c7Iw/CWQWswvrEWJP7
mYRjFD0zlx3hzFpHys8bkQlEYACKx1Q235RolTs6QhvfEypFfMhSRURjZSQm30jcrTtX9ZlWhQBF
5iyJfWdIzmhE7eqM5cmnws50IPnxboukrgYpE2keb4AVrGrGWiH5HFpUK7yVGt+NUqaeMIt8Nxoi
7KRkyy7s9FftfD1T4ZJDJhjMqhNcUaM6ezktD2isD5W/aaMOKqGRgZDPDHa25QAYPA4Qdak0P0rv
srfU0x3+vdGi8hk0cl0bQy9kFuYtsYp0ruNNrjW3Sl8o1Bj7aT1DL5A+ULY0LFPqGvPzKNJbuaRa
wVnwHeKGE/dUhoOxVWm1g3RZvrfZjSLFBUzLOMZ+xh1i/8vV/tC0IwtpVawFdrvg7NqGQ1tZLuaJ
y4vPTHFqGem7UUEjd3a5SV09VM79yWetZf4TyxE40fp9k/8F50FKCFARiDVvGDw/GXYOY9Dryouv
Nm/Kc1Kn9L7UXmiB6pI3dhlQQpJlI0WGyCVY2nv65KqHQn6jyoYRnp9VnEWePOezYqJh0fszYb8i
MuX7p7wt7Idcsq4RSCMaHQUDkyG7vwHqLTH/iLfTIc0th40k4A+51xsQorFJZIsK1ybIE4HHScf1
w041Mz1Dt53a8E8F1ObtW+Hl3YMEldwsSzOwRlPYXBGymwK7+40xoVt9WK73YwMrYKKB2AZaWQKa
xBa02YEuL+flQzNmLW5iAJ9XnVdGHBcPk5rD3kQIZwrhswYnWypJPpz2gkw0L1NZS+zVXStcOqe1
snulQKvpbBM0UF/O3LUkU9Kl/CjPGFtFwxWHId0efIGSsKWPBlKDNZq/9Xbl40YLzPHZPmkBuwEf
R/Ja71GrcURlZgF15ds1Cf3UOzctH8HlkTjT6X3unfX1lwG2yem72kdxV7gBCemJN/uB7Ijf/lur
yBgVKMkxhrL6Oh1mr9Ikw7fACGtCxuC/7t7TcdG+6bxh67QSvYSC408xnoijUCZg4ZZuDwlHLDDj
PJyRbDkKE5HeWtHwDMTJFYo51eCk3EtSyBCoabzniZkeBuitYS9RzKqWViWNyoclFfAqZFD27fAP
IwYJA72Pi1M17RpC2Z/RCMi7eXE/Oj1mlzzMBxhF8N7zzVHWcvdz5FYDDxESD0x+O0k0WU5aB1HX
3XutT/5W6SnlmoTdRKBpwBPs7e4iwJrrzPNUEsKYSYiGtKwswz+KIUEZmEfzc3VsW5R3vKU8D5YI
bMsRJhhdZCeuP1e87XScIe7dRchSgXnJBqyaRbO4I58J7yIBzB/D2wWX8G1la34ozf6GUmLb+Ei+
J7NPys52w/Dm+MEeKaUWJkvg3CSqEOKCsJ1h4b/oAmD/HC0Sz4OzHM2VpxQCpEdZIZA6gc595YsL
hUSunCoVdlsr8xirhSNhRTqc2hCMehBTAxyHCExrn2SMArhpzaAp2K9NqPp9cCDcZxQBdv2DNEjX
xhkiteZiadgsh9JoLFQ5Ce4JY/mkNLF+O0DIzKmA5r6XPlGc/Ck28uEGLeWGP48q4sMhbALCqU6l
N7nbIy70Gx7Q9afnzmLzBXhIFZaYGMB1qglkDcQa+CzfVCeDqJGQVn54uu+ryxN+JwTV1EtE0Pmi
M76zPwHt69zHHjXWzivZ6YKPmJJXowVKO5mZ82lfnXPaVbJjpd4z9DfO30rSbQzmgn297uh4XZaP
mcNi918II8L7rUu1l4QqZKtT5hvGdGDIMDQkuRec5zYJYDKrwCi2/mIZO0v9LNwFRxPR6CLhl7Qi
qjr2yZc6KU6h1P8/Rfxo1wyhrQ5U6I4nXljasQCoBG0sfEHF7zp6/ZDEsoCZbQ4G8j3ETojHwHDn
L5z+KStomdCM+1vP4wvlnbquVY8OCnxQZZ4HIbrd2ZJu3+JECBZFYLsqn9TanfNMZqDVT3c+RDq0
BtJOQvm0wFOckfGOdoOR9ZPqLVuEYWO94AfkCyhsf4JQJxrZRX63D0UWjBssKJejXJ+V/atcvA3S
Q4bexcLWPBHCTsdRXxzloYfoOdeU43h4TLz7IPYC6oQUBktJiLbPay6fC73pA8HmkMipH43YE+TU
UZAu2cqAHhDrGyTcFGCiCsdmLJ6QIvSl3OfomcL9U7V+oSA6a3hIgDhgqIHg6oRdc3v9OBsJy6Mm
3jx18TOORuOc5GObFS9/0eLeYa3MG8xHwEPsi3FUCajGq0Iq3IDBVl3CsfItB9/QV+GtkAuj9rOS
mHhTfgA0E/6l0BNpeXrOPbcAEAp0e1Of1qN/59yZTwNpGpAQCFrSvTcxw2xJ6GSV+Wb0elZwVb0l
YHP0bnCMcycB9H6Kzw4L/LXNdv68CO4XuP4Kmd9gOGcqwEq95AKDxb24sB2jnaMT/R5IP/jNdFev
Ip9hnXA5li/8cMZBIOD1yf0DLlkYmn2bAknQ92bbFC/OX48PEBaNaHSjGkQVMcGtFd4wi7uqZqds
n5Hns9YgTsqkGPMDQQBJ9W8JzB3XSg25YhX3CGzXPpBQjcfd3enfw0mxs/qPlV0gw1x+XEaLrvK8
e0j8Wb/XCGbjP/6BvFRt2vLbB4+mqet76huxDCi/BBUvTz3d6LVLPcPRsi782f2ehhLVnKm2s7hO
ZaKxiKHwYQTdj65HHwGSRekEfPZSR18CTT83+zkBdNNHBWqC5tMsR5CyVLUVkEIVYChaKy6h0jyV
r0XWlBw/V3XvG6It97o3TiXbxyNhrH7Kj3R0dbDB35pqADLE3zBs8fkjv27BHPBpZlnMWxYqfu+q
JDl0Sn4Pqzgu25Tn6364hnmLsqoJbOqUCqIxynviKfd8j3mYzJa56rXktt9ePsSMdfoFNnYx5juw
77J4Kkc+JU9NHGfZYjwqswgQAT5KGWD5V7P4rE8aMP67GA1TC8Eb7ODrx/oEOMevOpUjK7y35He5
+MP97CN3lMsAGYIhM2iv+Ey5wHtmjuR6UoiHsmxNPWxEV+0Id6TpTh+ohn6NLL2+Iu5X/L5u1t2a
Jhlb4+qxMNPupKNwhftWrUwOG1s4gebPeBS7gopG4F0Kg2RaoWrgwdlHpzlB3LwlILp9JqI6k31m
8h+Kg7EWl9xx/vlWDnjS0Df2fwLasyC6gJg+l+wETKjhWdvkfK4X2NW2VhZQzd9DKI2NC4zO/ANi
GdimO+QtIec/t5OHOPEN8KNuyw6CoBlZvDHPNrnG0935V27Z5bj5eCy/tCG5X6JU1krHX2WHiog8
Xcoo+qCqvtCIRJDpyUpGdtv6h3H5GJnd0snjT+tRQgGmcCKgze+x8c6lJO6HUs8JYpdizrBLAW3Q
kOVJGhsjJqg9562ssrq+ucLmdDoArCO1KLSPLzvVZJbeVcSr6rnvzCZUZIAbgErrs0grj/ye8e8W
OMTMrbc4eEmOlKYJ2o0acr83q1sA8qIMK9Wp4sMWXAukoW29gW0Bmu/EEabQLjykr7MPl/1jucRl
fxq6VH6QPu8VCEb3YkSUAVFpIgc+R0r0Evz7neC20w1UwerkF3UE4srIlMns2HFoWa1xS7GjhErh
0ldSS930r2VaWdtf3ShKBe0zeN+T8u2NnxniXF4UezOndkfuyDAjweJBBbjYk4WjcK5Wiu5uDfa/
gAXDjlxOJYFXspbbFXu0rzmcoW+xrLhEj6GXO17gT+uTtmU0w/VcQRH1iBo5jXRM5YTea8Bz+jJF
4eOPM9bKuewqQk9SRIH8veaom+S0y/zRAtZw7Bj1hhgoDlLFuU0WtlTlDfoBxIGqvIkJGbQrnPMk
e5+X+FLtKmaMJDbwMPjCs4Y+5iMwOzzc6+5Vuw2JHOtTx52iKf68eyRXUam1yLcPlXRK5Is3atZ4
WXqVGyPHU8X0uhWO48P13R72UsAxfv0617ajMkpsd9r2cHLM6KfVJ3w20HZUjvzKR/QUR6BhcAUO
cFu3W4AbUD0Lhw56xsKgsjboPFEMgSEpiqi6au7sQuMLwboNtGfcBP7LWjaHj+EkDzGx+7LX0Yc7
1RCNq538sab4LeKkMikRuSpF0eAW/A+MmLxD9K1dt3fCAynDXTQeObpJ9bTs3R7IFhmsKUBvoZmR
FfYlRPBLWRRWhpyyOZMjLVjQFjmZRxo5t9Fr0j1NboCdzJU5gX5IC3nBSUt9m7RMzz8931v9HsHj
QKEH2LinJe2A8hoZSi+asgG5HFhH4KmO0XjSRIgBkXDzZM7B0AYnoVMabWtRC3Kmc24GemMLfLwI
TNWdBmLuH1T9RnTzv4FNLlkkur6PkCR9SkQApRMIg6crGr049qTC2oZActhUPcqqlduT9NoKZVBb
q2ffmw3mQ0wWjvD82Smlza7nvFgBK22bix88aOwFZ2sBnn5jy1Lk095+GFqA2zizCA0BZOvMh0p0
HLE4RbxLtRzzGl+oHL1DoC/hZsfxZ/G9Xliei4ai8cMiTX+5g+mIxGr6m5HCSF6YrYWOMTvjE0CD
krdrbIKVNp2r+FrcH0iBOtqGowniKoRB1y5wbypWbiyLbDj6oWAwYQbmuoovx5cwaGKuryiP0ae5
2aCfKmirUNiHExqSzM5Gwilm+RqbiXv8fEwj9w7jkp3fL6RNubSXz+kYzbI0SYaJHaq5yKC76hgq
yjkxcLFwkjB8G8paweozipi7JvB00SVSvLcSrpYEfmpnlrjfLZ0OPOY0+NfYn//tS6Gef7qqaxbb
Inu1WX42exxAorMrk5Oer/wK1EmiFsiHFShqBqqqi1xj2yiDDhVkKmF/S4t4R7P05RCboyVAzmso
x7d+t/CqkPfSDG7pum9AyVLYbh4lKafaXLNjMkXmCJWqjAraMKk/siW87cBS2Rl91RYcByaCqjNC
8M2TdJGtTzNC3mr9v7YbHk2g+ByXFVwgh6zRnF/VbWb+leM+IpQSbbVgiqHnfSrV8VO4KbkyAUAw
kB0cOMNJvnE06575lLglBAYd4r9W+DgvuEcwigBuCoIgJ3hVEqGQLa6B80SOexGZOqcX/bYpplHm
1kGeC9foSpJhHoTeWl99TpW0jZgQHtU5Pef6B0vBDC/dHBdCNYzZUBHZ3W/lRQvHuwDLwfUaEZiL
csBzMYJChaxibMzfiquM0r5SB260mtk/WixbvhEFPTSBwVveEjmdXvmXMnr6c5WtdQNFOVQAZzlW
nTOzuC2scqRnRRq6F/POoqy+bm4+HQyHuaFlqikpngJqS2MkUPUvxkj063bzuaqij7jiYf/9ANn/
YfZd/RwgqL6wEnPWGvm2neGXPyp6LCAAzHsdxzccHrwh/AKiXH+58/dTl5vPfbAxzSTgMsRM/Mg9
dKCks/ZxS8/YUe3fKYvsZ3Ct3JD8q7lV8QRTl17EvVW40QGc/3jqM2csKWLebFlqkx9GwWlubUJ6
KUi4lVfR1Fjjq8GJUJovxwfmOn3lTjqyabNuC8AclepJfaEpgGlNzmHp6DjrRc/1R1NxtAvGoa0i
Aii+464I5RAzsWEG7V8+N9M7ewiaXn+hqNpRAfSPjir1sjKXnTCA7wcqHwKg1u+mrNLdOmbCnHly
s9HLADb0iru15dkf8CFw8qCJSvVZTb/HBIEmkc6nz87nxQvQC3j5FfpgAEcf2jMydIUsXpv8PGI3
255zQWy3uTlate92ugfp+Ac6gVUOV+mhnuz/YgUveySz/ZA1n01jqeH4f8rd7dAWcWDgT/erk7eU
PjuOjvlcB0MAzF7o2k2ql1M45QoP8ZL3WEFJDSqB1AysOMlhQ+neFsNSklVwuNeDQQplynEzhKPU
awPgJrN9d6WiQUXoK40YrKpmGJqxSgvZE+dmGZPwOWMpyX4Hrh9RFogEalQ9LqECXoXM9Q0DC9IE
nEPJamXPWcNPY4C0RbP0xlx7NVKAdAcKvMrCBOKtarjXwRe2EqRwqUI/Vh5azOIzQ32MQIuSfpTQ
xJzoIcaSwUB99yrv1D/Grij3ojFQXS9nlVYrT7qO4RICcY2+freKLIkENDv699PRTE+Mrq0TdfiG
qj2rEf579vfcFraET8bjm8Tdhh6X5V4MDb65k24wwEQ5sr/vVCK5l+ozDpvkXRaDw+jAMwKJIC88
nhl1Cvt0VnrvMiO9HP95kb6RV4T+/v2Qq7M5Igqo/6JW6JxulpSbRfiiZTStlRvEWrNnv37bqK5m
M258fJdTy8nnRO/svbWncqaKOIaF+Bg4QG9KbqFASviEilDl7uC//xIgj/4S0MCosP5su+FQgTyt
svHTOhADXpJ14ngz/dHRUCI3c/Z3i1AgprolKnT0cASICCFh4+41Nd7+QMEs6+cDHqqIdiPHOt+5
e0/XvavfE2476HAjUadficuCTSzJyIxYy3v+FVjkZQKjeZtA/qCd2QMFnyN4v6II9smAQcKeYT8H
o7r/26KZN2r3LZPa/Q7Jg3oQtQ3mtiv0Zn7o1w3ZnQE8K6GAKoAdVvSyaOFifQ8y5nv4982oG7j5
sYLZRxKNSkaQ6TbXvoM7tlm0erbzzNad17ikb63ca96Z6nFugnNgbPtT8lZiT+qjC5ByGxl/lZSZ
t1iJpd11aLsAHfNnHkv6Z/QA+GKbWU92HmAdAFz4GdZzwwX4PLO94DhN+bwoXlo6i1JIPJYdHTfx
EC0pdMD+2VV9ZQP77CV0voGSQwpaQsCVbjmBVdHpmu+Dq4RF45qruqKfNj8SGe61LRwnN7jFN8hI
/3EsBTrPN+x9cvhfXmV2c7E2L8HaE5e/CNeQNQpJ6sfv4iHWBsU/Bc26KvlyZfHGspfan23Wf6gv
ycEQcyyMKwYYoENOaTb5gLWP5D8nzpy+6nHI+YMBpuEvGKViKcSJP65BCu/dQpFMTruDH9ZtQ5xV
wAgKrUWsF9mB3WIpJKFEgFrjVs4fXhc9wuk0vZnqaAdihWvAZRxq01M62UdEgy+vEQVIGLj9MhHv
EF6YG+PRxgcPJ8pY5pT0miOaR+B6lYEqEVDDh5Lcat3cSwwPLKqfoXAJgU4iuK79Ht/a55ZTh1Fn
twjl2MdMKZPTE3GyOQxLq2csiLgaI6xUz8AuoKVa9QqPu/je++6tQInBgDpJ2CyaKVo3F14WDqr4
tbknnw7sLv90M87m+uXRy3PEtdmAi7bokabMT9zkuDE8W3QUWLO9m31ae5jWirFm6IrWPR2roFNL
6015/FuX6UYyotrfQe94TOfUSNkXK6D00ZpnZuwMXL7dRUKLywtwat/TeriEKPhDnfvL+tdkFcyi
GYdkeQKDlz7QSqnaOMuderG7xaMyGj7xugbvjOjrTb6KiV4n/bCc8vJ9Cz5YLzp6nXvPVXvAMwjy
HVCuTQob0gFnG7W+LMAUnFPAieDD/CKckSnq5XAiQWg+WjTudgwjsvbd0vwt7F3eNvM9OztLY2Pz
f9OIbYPFeleY+Hv6Xm30PvqU1wPGFy2ehAA8vDkxvXFT48wubCwyh2l1UZRnO51MjqVbvps1rETT
gw3eXDcMCEnFOQlSKpHrwpZ4RrpvfSlMySHhh4uLGMnttusQ/ER6L4YnHKisp/tOUSNDh6K189UJ
W0pIP6QkN0zEllE9gsFb9Kya08zp6AXU73wDIpdeT0RmxYwuGM2jrXqCDR75nvp5cTwIFRcBTsWl
9hS2C252iwykXHhaCwhXsss/lpxtIumjTR8bMva85/A3HaDYZiGqnEQ2p4h5/M7NoYrXYL/C8LoS
zpjFvQ0JsVmpkyqUfin5P73tZFnQtt6+mVSdehygr2j/+618DGngm/+64UTRBwhrJArAyS6yQ8h6
O+FWq82JL/TRdpxx0bQJdrex2Cmb6WVcEvO0/X3e8wuKTvHpwmiwezXECllOJggBrKPDRhJHgDF9
4s8b+rWxdQlXTzp5BTgYBBmFB3psFqsMakLln3crDyMGAbQ5F6Dtn2YseoX1sbcy5XkIH62l1syt
vcjmZigjvkq0SDXaztjG49+q2yRniw2v4nSp0JaEOwQanR87bO76ZkNUjVJXjAOIMS8EJTKiKTJG
BCX5zg3Ugq+dF7uGGznyDeu2+BfzHEwgw02Fuy9Nw2uPJJSAYwEODjOOpb7Aaw2361VP/W5W6G/0
OBV3wdBeFak47J3s6RQuQVEoRxfnmkqhmrvnq9/SW+SJIco9MS5mSe8kaCwWIzUtXEIZYh0RvCXG
GrO7e/Njs9e7t80iPryErE5p9X+IzYVts15RlTij+tlsPwCbsiqK5ZuUo61vvfOlvb6wIY8aGuOB
Tn/hC9USFgN81xmuSEnAgslR2sKXJWCJ8jdt17uuJbZkwVb1lEm5/krTS41cFxfyBL267bPTuxKI
ii5e1R+NhDrqlSV64Y35fKKOwoPZU69Wq7w5jfkIHzgJXszvbIoJlFE8ScVTsVDO427Fa1OUlECz
4HtTUOxm9917CXSZN2rE3FrSjLg5RdDkBINz6Jgyi/rEL2lpQTgbH4MZzIYtm+ppI8UUR7ky/Ji2
9Wp/vILXmPTf4CSw7RN4HscW/3n8o/F5jPBfgJY0bs6IheCmhX82aoLtdIOjVLj2OHwlLr14O/tV
NjaHajwaOoPcPkumAELMRd2uUzvOB93a+gGMw2Xetp8k6w/Z0YL2YUXtOhQTnheXRv8c14LgPd+p
2+1OMoZd3YOtLBG+ghfENwoL8qx0sIyJwoGACLNuxTIudYAWcFTq+0GZOViuLiXGFFNRz2XrvhEh
ZB52HGoDXgB9xI+96yuhnd94jcZMQJBikJ4TcQ6Jr9VeLWtQiAiNMZ/eWlspBkQhvc52b02yb31m
O6+6csLx6h3IFIAq6wPodC8nXR4eNxvVjLqGupiUhHA8JDcjg8ghXAUTHcZlG1hgKw8OOsNUZ6h8
x0gsfphOhSBbLz39E+QJAQHrjKK8AESZpMKPvf9xS2Z9G3cbTD0oMjNeqBqt8pji0ghgIVtLbdYE
+cK6IJh96GbayLwRVhJj5Wk0jF1f6W5QvDPcu1QO6OX2Dw/d1QezqXB7zdOaOWysuaG/w2pTFH2Q
+6CuPKIop+PSZtJLwvoBlQEJyfOifQHYziNKuT27PYb1AKJpXbNZAAmbvhU9NAQ1P7Yff4YQMoEH
a6Oytwslu/5BnuTt9IpjF8V5gbuMNVnmsSFCqCImWP9rqyIFh8EJCFGscrR9VdbEg9VYqwMfxFkc
NvQuMXw/Qg+tntuanAZ62NpW0dUmKqojdyeHwZOtz0EujNkmJvHCn9A7V8R1OuCmkrKQhzYtaZeN
dcrDODLLm3PCtU1Ho6kBwYIQRxSGHnYEJOUOrDVgo6x59uCbBSGggKrGio4P28CuVh6PpPyVUGog
UIeteTX5RLuQwhaNwfN15qIB0Scz2o5cZBQfSKP7kHM3rF3lNJKDDkecXA8/JuIlKcJ6XU5YA22o
QUzC/pISyefk7Mwimfvs6EKaECdQQop9pcva9Q00p3ViNNmBxjMm50v4nmLjYbz0WCdZ5rhIrcC1
+STDgZcU8+IJ5RJYmo2nH4FTXSM9x6lBtSdFsK2knYB0bd0MCozvoRJ4dxgMY6LM+FRwtYC6++dH
TF1/kLujyzj8xggF5BMHAzbK7AbY5IJ0pcF2No88cyxUC+FGKyaajO4NCkxVf8g/9+zlHeX0yZS5
PIpVrBaKw9E8hAgaJXJ5BdsBHrD8Urm88svplVmMxm68G5BTp2fPIU5tIBo3diCqoNO9uFpWVCCR
JJ0zoynaPCjQl5ldsGMwllFDg5tpzel07VN3rSNsc+QrfDbGHOQMZukz/EAhuI7Ghm10koVktw52
SHgc88enIO8t7CMViXQvlaelvnh0FDL9NLrKdxFQvLR4jdiVWeNgcnggPqViN5V3E+w3FulqBZvq
RdVBY1quH29h0M3ROFGqgc6TEQmX4EM33+9/Uq1I+9I32yNtYxhMP58V548uxXDxICvhVNOjcI5Y
TAislzpJl/35yaUifqskoCrJGQtlcWBDESHnEeYWtx21WU2XYWq9XLuGx0Z9NLQ6OHjzz045YuLd
ZqNru22v/b6C3Fs4xijThw/XlLjbBVnKk6Vb3BBvssqyqFXfrnMRBJpTQOjEMb0ZZl4bSyZ1ywJk
IvjV/YzVDOj1KV0cQBP+D13FRPQKUTzAEgTU+vf9sutNhEw6z8/5GaDKyaJzeFXEEqtow2npDcxq
6HHjwg6h9bCWoFPMvJ+zesIWzI6x0g4zQ6G8OZzRhEJAPq43fbOKWTNpUbsO6mCM59fPBJfwXiwG
FRqxY7kDKgTz/JnXQDlh05Q4QENTcBS089Lv0vBpg5O5tiRg/OY8JCiwO8BrRlvL/Pm7eV8Jw7QZ
svVrSUK0KyQpV3HCOSN5ovMkT+GN47Pve+ha7odAoT+3Tbfr2bk/wB/79lxTEJwHIkXmR9Hqe+lV
89PLuKSRLUJJqQoRd+Ctmc2iQxF+Glwr/HkQS4S+IllSuMJ1wkfGbxONu8RV4WDBsjW/wSCfPG+1
4bbAEbJZ4TRosSoWPQyjIWuYgRE7jVqnWH1EGf9l7QY+QlPzRshrfw2OTCv6ynynEa4L9IR89t5w
CTdZI1arxE3sdKEHwzTla5ba+4ugnCEzDRJaqFJpTe0UQ8KZIbrQEjITHrO2ZWc/ffINU7KNMpm2
AGGxpB8xYQfofV3TZu1FqwSiBXR/RpmOhF/AsxYoMtk9YRmTIQqETBaodDodJjytPE/0/JXEiA0E
38XWonuzoqp4ikE7OWuf703zNfK5B0lpJfPkT+Mz51iC6/otYc3xEGiVzOSUo2OLEsrlcfsadayt
C7R1x+lyAjjjLvpIcXIlRYRAvAUU9VL/xWyOKCEzT/4XkeEo4wyKJ+19et6gE1jFCiNkBksjVnAk
HaE7RJXl61M8XDhBSIz+DdDaUL4FwJoMnnMYOgIpPfENANX72NqQUFbSXfvECR/5NhY8hdPk66W1
UHtQJpQ8IokBJxwHKdm2pVqj6JZ1DVhC63hpLK9geoxQ/g0IPzM9ad5gLd7HWofaX2x/Yd+3tCym
hCw8DZJS9+sUdbG1hAdgPjNLSXoIE1Fhk+8QSsRAFuK+Bnt5gtN3Vxw5m+Qhf4dOVTZ1pKpnEJaw
vAJFh2Fdf+qQAJE661eLl68qv7Ohv4d57rMEoPcV4fMAA9ENMnMRJwO1S5389UEF+lRQa9W07YQb
sNlHLw4TCDsYfu++4ABYfAHGYwmz3zoamgJQeKDgmtsPnAXeSRLhMwwqgqZ3VEF6MMMbpbSsY8XH
8M3NsogIMpo4etSlGArQahAhc7JVQNy1xjwaz+w6lEcpUZz+nelnNp8CMjZHTf6Icv3aTzfTTX9H
A6NvjYKM0czTZI5NXsbVOtQ+bwxXH9FxT3dKCpae246mCdRb0rtDcEp54EFzOF2inD1Fll0jfKAA
GvDwb7Iu7LJ0YMvyF+be502gH8RbLiyFktbXoZECNuCczXGfn7Jiat73wxXpF6YfVdnKEJpMi2KW
6P6xwaBerkGcgEL8P5jtk7YIFlzWXNJ6aZynbGxb2mGFiSV/i7W3aqitSuBbRez82HAQKbHP0yEN
ti8MyoPusrZaPQtiflambNrmomd+l5J7FQsmIj4BO0H2lWNXVLK4F0gJWRumK3+ONgwmpsuuda1h
WvntsCeAaDH9c4Oz5X2UvVJeywXJktdgvL1IrjZjaKeVE0zSqdieexfcDNz1FK2J2xp+7ySLUsZM
7gxym/UVnIa487cpKqc866k1xu5/X+TtmRjHUn3WWiblm3poZGTTZ+zrQjoWGLT4Q4udcVEW3mcv
RxukwtqQBQHxBuH3vmDoxXebG/Q69AV4SXE5WhCGEOn88C6ixMv72sUWrAQpx7PrlKLZovEiNX++
a7aFJJJQCfS81HZg9HwIUPY3IymJKbhr1dwyEhQ9vgpL3szdy487GMM0WkJe8ADaYcS773DZuORp
ylREwh/t5nlnwyqm/fprlU+W/9xwy2y4qXwfGFT6Ch7yZkIJc8NqPTs44TRlfq5vhYhmMRI6v2mV
ZW5SgxkRuwFK1ou4zL9Zlzdzhe0p9uan/0WNMQ1XMkEQaG5Mg7G6532fFXszE41DRg6ZCHH9/0zM
dQLCRRlLPbWZIeGPAH38xPF9MMX1uJ1LbPUKh+fedns6U3zZvLxmy+N0kVJLFEvwIBQgX4b4ckVv
JMQdIf7pgvWft58bFzIl7Zf+wesLrtGd9jrD1sdTasSLS8uKsNh13sXAy1tuzmLmxS8XT3OyeQIb
GUEHn69iLIn3PzBmJuESUwrwoJNxs1ElyE2Copr5/Ik1/mBzpluWojTYpRz2WanHkD8PNZrittIv
il0kNQtYBd4ncBMMzdGwjTGsBSO5e3YVwblejN3IUWAuUid58CQM1Z2RB2xfOP6OdF5qjxi6xdoq
5WKwEM6S3hMcV6PF0wjNk965MKiQYcvJrxcDVdejxbKjfO8kZpyGw58Ca+DQPd7fG5OxLZJJJO6C
PHnhR7Ou1sPXrdhyG+HgX23vjT7PeYC7uhTo1ei4IGWmsZ1r9vsvACOt+zEmZa1bVPRwpBkbvBUY
0AuGhkezmLqd0USeS3wdW3WaVxAtl4KKheyiLV5y7Z9o3LcgWsrlivIvNWBGf4mXqlKcC98EX6hi
3zv9aiwCg28taArwDJ3W+1vTCVBXdPGQiyZChTSDYBtgGRTYZVP8CD1PwF21h5i8wEbcRqGTNgYM
biLAYIaMh6pVz1T4vUH90Cq8FYElQ9CH5Ktav05OzHekoVryA9WljELmgvFBIetgj8VH6y8SYkOB
TCYWXCmdSr1kd8odeLHVsuaBpgb+kjIvdzMlFRtYW8diByw1zHyqcoDKdCC44LvkQhAoaHkoiJ63
Nynh1PsGp4yV46wC7wE7/cZVwi8xifd5l2SMb5fU/X+6dKip9F0fS41wnGb/PfHjj/5toXM2ihtP
4WPvx/W4gO7PYTeqZQGzRrSuiCMXx5ft28rnJsahsVDb89yYSsEFLhtPKmPRAnO9nl7n0JEcx5cV
mMmtWbO1B8+1cES4+X+LY882n4RbE6GEq+OKy64YO9gWz1ocdfeOB3MYE+Htjmr1gZkoAi8yZLYq
5mzAZ5eEHq4n73siIPmQyeqBmU+VzgjqgLI4o43ls6BP236R+njcRXY7b6auOB+qJxIwvvp4UUd9
dIWw1/GBmfc4jDxOHQeuugW7P6U4dz1zC/NLa9ZQymUk1Ful8IBBP4mQL+NjP/oAPa+LOeFRfaxB
9ySpgPgXD4GrJ7E4v07yK38Qo7IxEv9+uaFB+oUkWBUj9QP/lSWN5jGJDuxj7Eibnafdw8Q61Rmu
bXtic77G6O+IV5+hpP/GLOaGChO4vZiwT0nHAKk/v4X0/EntxOecefUdLa5xMWwlz6AT3jsNGDrY
MpaTOsIuIOc+mNp9/chpswjLyZCCCqodG3KV9FuOeo9A+rXg9+iye9U+u8RQ+9ygxvfIiBr7AXe3
y7yREBEzdFSvbIq/NREovWTnCQ34j1EOZzuq1iG0dDNHlhf5dUIKHBR2bDxT8Kgzdo6/Hn+sgqxE
cz/MzxcLYSA7HW4tQatP7GaRGwB9oe9SESTiNX4pIHydGvptbX81Jj/v77U0RJLOgDM5ROVgKUet
FUK52EMBB81aWWEV2rmZGFwTlj3i3A0IwMH1OiBGOnGs41Q5JOJyOExs/mONFsdzND0DMXNIYL2a
Np3AE7wiPGQH4XlFUoQTPF5zaAwZaAhoTG43pArGzwIxoxuotgApZ72BWnPo06TF+PyXB7GRNGoY
FgYLwmmB7PZ6YKwJeOeewhdzmFg5YP/4Z41c0WY4v4DS+h7SrtOBoG4VWM9fV9m+cCWoTubmPIc4
+5as8k5beY9JHxF4rLiXeVLpeQOiEz/i5V/H3snsaUlvklCJ7sUjh03ASMqzKaKT6hbgs2l983YZ
lMpbIhymB7JnjQ4FonvFhS4uvDyz1sOEElffahyU/MCm04pI7jiYIlHtpX9ClUjI+Sr0hmDaHERz
Qy7Ar2m7CQQfb/SiQaBUIEGbMOH/rT7fhEtXWGojAj4mnzyht+r4qiHpqpiGof2TASca6ff7O3hj
y9lg/zH4j0XZpJ44VYZdWeG0npYNS0LtpUBSX5LnikEYEIqGiZUzZt6zwdqLpqnNYY0hDzpZO0Od
r5ew4+Hc5+PgagvVZVts1yofARmYlzA9aBslnTe2OUk3EZduzpTp+V5yU1BxxTyanLCBRIov6Iqb
qFoDcx3p4MiKBaoG9Fflun6J0F0iYpVlfAmzX2a5pzVpypOPBysfkRYv/tZEZA0YSESpQHP7+TX8
GNoYmbNLn2ro8t+ickSwJQkgcfI+AnzGcfg3phPLuq/VnjIlbNHfXVtiEPn+PsH3PvYOxcAMKGcI
YDmYLBMgzKfpsI8GVuAXRP0Ukute3qOnDDQ7Q2sFxsAPc4CcRZdpqyA5JBKBA0tbgY4KqRv8PqK0
n306PSKtcbdhKCwHEe7qymMJ0V3cyEr4PtYEiDXXX/Pd5qNhslgo4uyiBnGspX4PvE4JErTg3MH3
izCGbhOyPCWIR1eKq05SEW8cZ63zN7ibigy3B3bEYOykHRovpwEjeo1MIJdY9odWPs7cfPEJhD7L
hlnn7srHaQPMC3gQiiAgO90Y1qiWh89FtXSyOlFDnnOHc9O+SHcKjj6gk0PrsYD+CJgY9vlhT1VN
ms6ur2vjYLXL1S+GeX6z848fb7K0GcoGQbr6u5rAvesq20wdRh056eg67Za34oUF24pSvo6E6l7d
0KkRR7XkM+cpWHwcN1uyWY+gmBf+mFCpqDzwHLIAFnnoBCLkfrgd7V6eZh70Cq9tuoqe2VKuKV83
JMYyJu2F/FQso+tSHHNPQNGCb2D+P/3ieRMobUegwX5rNKaf4seboLz2mP7JQRCwyt00vdHnO3fS
qdxOtt+EjNBeEHrNiugmH5elUx52MMjuEfvYLec3Nb+P4ONJRcO38Kd6QgKJX8CtUmNxWS/57kBF
cZ6zoFkPxx0WmAKgNgUG8ppSNIAstPC2acRX4X0rXd3rXxASrj8KfeakcSJLs8Jd3fPnm83HKXmw
mOnu00HTx4mUMnGyvdUhpwtY8SnLTrSG1GRLltOzTfU+xXjR9NYHDkpo4I8hWlYebwjaywN6hdeV
WL9oNFkJBfoAvuvxqHhN8P0QIsRV3PDLZGZ6qeA9QGTXhrIS/8IY5vBlNJfryOiLoEh/yYDG8Pdb
5X+hRNrlGVgqPGfup8m+1UILwRmPPuf/ZCaFUsZJlSOmdpA7kW6s9gg7QgjRT2kNuC5Y9I0DnXOJ
kfQM+JSzDJZ5GyNh3Ki7pysE2J0Jpdgcu3xUDzz+6w1SdVkSm6lox8m7he3MocXayOM172u5aDiN
NoiuOB5hocwCcKNFR1PLbVL06u3VupUiRcZFiz6WPS3ndi9z2Gfs31a/yeIT2YbGY2PsjBirW5dY
GUSFptTeVKZAaaPWPosOxH/+dpi7pCn76aNi+LAODP0OZQLA28fEGzTKcc4pnhDCbBUrkwtX+Ln2
XYQfFCpJDZ5HKYqf3XiqWMs5/aCU/jPioYGbCISlVln34nSOLVBc5UNmXzI6IJOWo4FFzQIg8WHe
nQ5ctoaUZ6yt+xQDMqZ2LBMfSo+U7GL3W8LL36gXI+xz5pam7zix3mKVEaw8kmy4Vb4eOANZHxgW
UNLq+43seWB4eCWd5yuLoaPOtOqjwm3XcSCNeqMv2k0VCqiu2HUNnb5J2WfzCk8xQYVnwvvlBgiV
Q5chokFLpV5RaR6zRF1Q8V1pqFWvqfN+GC8Y3ITwYi//9id2HRO5h5ZC7pKh5acxmmabiKbRP8Id
mK2DIFVhiHPkwQfjapJ2bugxI16USt6nytoRqvQivtbll+jP5i6uKgvHjWsR+ArlGJfaxgleVOHU
u2qcRAWwWqdZhq5yY4R1JpLbNOX5RGi8cnpNlWbf1Fh8Y7RBltYGAP8q5hXtfVu77o4+6HvqqM8Q
VznKclzdgQWHCrJRhuLPDzmIT02TJvF/crC+BpXouSyUG9asdtK3hbONwHYnwXpI7wVUToq5SDGA
vZIL4vjo+rXLf4EXewOlDpwzoHGtoIDt1Ja1JeyIYimI0R2PKH6CngnqPC/+VSq9dgSL+uxycKIY
1keczj6f4bEBzlQvM4RDZAr2C5yS1ynxudK8DoCkjr7JKVkKPnJkGkn9um+8X7To2wsJcx5VRZQu
SX+27v2IIkl7UDHajeldb8kzRNNBfT7Jp1aZp1+5y7yHKjujJ+XActa10vMVcrbnfjP1UgCdh3lR
E4dM1zEDqLR2PmRgWDoLWpZomLS8Ds7BiV5+kfcNTKWjUN4liqZ45RuEylMOd3WaeC930qeOdPZw
iBeJ6OJvTpAUNKAK+52/PnuyTRdN/PrlPxsuttv3zaiAhHW6UP1I7rF56yFdUshfXezY42XP6ZcE
ewj0mLGqKCh34OMyay6pprjC6r5QAuYni6Tx4SUcQQ0Xyh1W3Dvr/ANbTdd6JaW50HRDTz3vTVAY
hM0MIz3B+bS7t2yE7p6aVpWzg9e5XPHa+x75nLw0ZwE+mAoAAzFoRJ8F+Mydt7569IpxE3e5LdEI
A1dendKt8VAQu/1lskYAqwQrOt/9faQyztoK7LbwGZXCBdtHf9FapEFtYykCO/D19+67j4dPszVJ
VMC6bqfVcQbPjTXi4Ge1QddLbZ/O2cgwv6C4WG4Gq3r8GHzRZmNRVJ45xcIwe+I9Fybgi906cXvl
re6kQwdSCgJTmQvoVBGZh095i0RivNPMUlWhgBrsC4OWip8mUYPMYneHmzir9EYb4w0+EBq4QQcb
s4BUAPp+3bEaSxgipLAfsoRFACBfCAf5TMDuJKKlY2iaDA5c9gHGJzDyqKx3qWSTp2YHMjhjVPeD
+uVrML9S6Cw5OPxzfr5HMldiJNdMfq81R9E3XYW8tcWZNGlFz/4MMN0y5Eu+mFMWKxVwXYmJ+dY+
gaM/FqoGn76IrS0YxYhIaC+lAVbBLIceLYa2w4WwmosMP9O82QddLIWkcYpLzIo+gC2ySJg1FQds
+ktAjcqpuv8me6XQfcsBJ7S2Lm13AOvkn1IlrVhAkCD+A69D8g5BXbMsC5+w5k4jsStHb66dFz7R
RfZuI+wMBgi281QJ19j3OmNfVAmG47D5MCUqTcA5oka3rLK9LaFMXamoGvfo7yj4rUSSW/FyOSUi
6SO4CA3y2BnMyRkQxEMyJxXPANdk52TskFpqVBRx656F+No8HpAlCZewQl20FMfDL5PKP2B3QeUH
xNXDD7MIYMjCeRtnHUTVQCuRj+0eU3jNW7pSTW1rXYxRjDwxn/MfPO+efuUPZOKtyYXbRMalU3+P
5Dcw9YAdA/212Z0JKDxsZgtg5rkY7nj4NaCVb37sNpK8cAjIYUa568Q1Lgjv1443oePWVroon6Ev
GZC5tsZg7MJi2AFc8Z+dscBmRcD+9VorVI2wMpcKJKffC5Nzo2UfSQy47GoudRSJffqvy7263Rbx
ZhhFMs2YKZtf8dCYEGdvJdOfPNGo2njY7cboaN4KLRAkFfzkwB9vyTwLudl2ZWH3OSx5krRHd6jF
MWtSTdm9X13PW3FxGg8GQewhEkVOeMd9kCEclMJu+ZypXnEJ54Qj85eTJ+MwTa4yTY+0ZfSCLtIH
8eDj6lBStVmkXu2X1gXQkolmnAh8K+D/RO3FjMb5yJdyNqfN1OLAkAgwfCM9+Wal3tZi0zNv+myx
8lGx2CEpWR8Cyj3IoDnBJKs6fz1UjcxPb/CuCjNI87W1CC+QcwPKRg9RcMLb9XLgdEhpVc+f/3o5
TFcSUrBemzFV3VjsszgHNWQaBiBBvTjWyfeFBtRiIrY/quyn3jX7A1KN7fkA8961N2MfLiP+XcrP
ml7i/D+qL+kL0PN6nmODWWtIvbdzg71q4ahLHVaTve7TCQWbwMASBrH1x4EWXn5k5ozOYPg4Lzt+
dE2Hw5CbbiitxTH4FbvEaZtJt4PFryQS3LUANIRfXw8L6P3/Va66HVFVE7dIagKCMB4Lkz2p427/
/rNT5mdBH4ubkhbtf+qwfksaI86R2QoKOfwtGL9imSFh17NR3UHY3QRhy1RHF2xc7ZXU/Da5ho1B
DWZvr5b99ggVVoS/1FM3T0ND9AZstv6GacL1B7+gz2oitl8ewsx/U5qIj1sn45ChyhASG1l/GmHQ
eMxWn9MZR/q6gWZAu1e3lAeieRldllRj4Tgxtxi/zu+bI02+WEAEirlNDQTHWfOODgDPO7pYZaK8
snVoKqrDpA51B061exrcy6ciqNfR1BF/vI+3Yz3oUKTffLmqnk7RYr7L8axGYU3Ed06x2wxy0R9/
L03U7KWa+FLwrSLjNCXE/I4FKg9T05bQ9Y0/VAVWEc3aGHz6qRs3wPH9uzTSGNbULB44zY5KzjPU
6vkan5hMUzCmYELhXlTff9gkJJajgCgVm5lhXztkY6+66Hz3e+FSIGTbLxNL5Na1Y2ncnkN/5+u+
+XBMsLrBgVHGL4yAMm+fjsCHv0DwtqDcnb0s2AtDHnwz4flxeQyU3FXvYsDlhhKs4xiwC/9cV0ug
9RDErOoBOe4j8PI5ySlXLYh/FBEeqz65JOy68Aei6jMj+nMuiGy+D0KaKCXCL5frqEG8/7TPIb0W
+LxfCZbLFGljvoqJL8gEvXal2C0PeGyQZJ7KRjZwxfEI1oQlhRPS4U/LsFIjCd1cxNKUQndg8NE5
wK+7ceYFk16RJGqBoZvmRi4fZv8TzgfYuMROy2ddiF79AYBMp8ljGhm6qi55T1fLIfKvvOIZriJb
zD49pYvQCNTqW5Fpk5+0tELaYrrw5XqYr3rJZxafrneMy1atIUb29rnZtghh8QigNuWHLfLN7oK1
+EcyM22m+5nAwrGn9aQlmlJzEMZTcVdLFfOY1MIkczoA2OMORr/iXH15ABsRU/f/1ZwW6H5ynbCx
2rtQLeCk8H+QmyQ5eB4dFMilzQCenr0sVS95UVhT/2N+tIDKJr8Ez0jx1L9I1/VhkrO0Il7SBT2l
rPpyllp8VOg6Dotl4o6g/sgbZSWAZ3wpgqthAsLEoS8A063pr1gJlv2AYu2TUdzVeRN+Cq9FKsS1
74tScyoHsn6aB9VR09cF+xYpk0reb1u4RXBqkkND7N+qBwYGK3tD2RHURHhaNY9X8Kml0kSLk1yy
vYBWpH9IwBsvpiMc5j1nv6zO24PUeg7/goBM+C1f3cwGJeg7u2a1NFt+QfnH6PTV+DF+J45to8AP
0BOR9GzT+wI5CmPY/noxng9cBodX9BCeuS5LlWBL0K9dSBrljZb6dsBClYYz7wS+KnyKQCXO8J5n
zQRoDvpUf4MCELUXJGDELZv07snIZFjf7ofw8RN+HeWlpBU96BMvDJBmFRcBVFirQvZjddnYiasa
GWbIiQ+KQs+BajT1BPAHC5+w1swJKiJF92rhvTQUMmf3x6X6sU0zbDTL+eAzxNDhsL65n4RYz/My
bjaB9xSL1J7clv9QPX1x0HAoKkvrvsYDdV8pN2s6IMOmInNsGckRz23H/8FL4E2JVVTczvu1xxRa
5l5Rxz1QcSQocvouA1YAZk9ZDFvs8wFQtJjNWJqh+yzkWt+cgsiXZRXWjn2Nu5fCnVTgcgmDTxBC
xt/ybHJtrM1mS59TxEQF4tVtFSYwNOH4Yv0GHPMt3KUngN07MyAFvF0p3wdMz8rVkReBM3Qzonh+
ukU5Tuaju6avaZmpKWOTQVffgxzyqEt+scpLF/uxA1uC8zRRmpfKbkYkOP4dZT442qbp2CBK3Qsa
xOsy2S85DYqiCBzxBeMUIvZ0mEgwk04EFI7bpiRnpfYTOCKPTQME0Jh4yZD/+HxOYQC0CvdBxWSY
XFZCMFLKAnUnvHbWQP3eBaFVqxtE/Mu2QI55+r9FSrArseSddHjIMpkzbdaQgArf2q5YTzkY/6EG
X0gEDdh6Hn7nYCvV3b1L3+LOccU8VM+fm1kq76VjfT6WHrGaZ8/i7R2oxgUApnzUArI9a5DoIw6T
MbRJsRwuOTQanfOsqce+BIHY6jnjww5WKl/JtR4uU0fJRbS5kvu7hMdvrn0Ei6RTJ74zE6jGNFdB
AP7CWXG0b3wSCQHU245piNAfGKZR3ztJsv/xLMeYg96n4Yy1ZVt1XN6ojOFrv3XiWTMxItq9Ck+t
kP1cwJ0RhmCreHJNufOWAsH+J/4smiVrjfBta7q8JQ3SCWipTolhIkQcGPWAGk3IQFzejqaJ0R9a
V4Ie0HR7NbgPmlot98LVERAP2A8JBTfOEGSbzCwkU4SkeyU6VqrlQJRfesL4NSswtTuFCwtPxn98
3Ltd7q33LNNVsZ0CRMJ9BS4EGcT31QPHtkH1IpjOScJW+Slyuqc8njqfZOMVSp754BEMMHAnDcYP
0v06rG9+4H0LTDdzFGYDfYqcF8xgvKGVRaBRzTI41Zcl/yfrF7nTEI8DzbNVHpHESTmBNarJITPF
wGaCs8cuh2SabiIG2Xsw9D8LzVZzmQkONZpj6VmC2EDjoxNpQI5Os4V70ipDvdo1czwgYEJkDMEK
n2P0ly+AB/JrEedzU2juy/qJsm1Ph+wi1DjtZlK7byHhPNLNQfXijx2xCV5PHDr1O4VjaFEUSCON
dSc2bH0ncNjHiPd6aCcqBZ7SmK0iYW0C7F+mi4Xb3+xJ5nqCx29Q/3yaS8gzWq7/Cng6YKmVRGqo
JBxKWgQ7Kfbo5sIB/IxU5mZ6c8EMWPFESFDgDrgk5Tiwapa9DdDYs02/yFt5W4nBWd6XT+syMr/O
P0icQWRUfxlTYkHeMGhn48DtjVnt+G1IwLcGRt1A2v2YwLsYYqWFttIxVnD+6uOyBTUHmbq6252F
c0TFNsC3qQ9NGUUcjNYE5f0u3rU5IUZ5VWSea0o498VFglu64dpvAjJzTFyjqNmcmfFffILBrTJg
GAipN0YH+fvyAIyjylFAq89DQ2/NQLgXfvGtkwezVKfBba0oM1Qy2FjiPI+oJvzsutPqra3Wg2JC
ICVJo8Tya4KagH66tcENu3NC/5p3GyDAyRCCHr17iu4+n6+JwIYMEC2Khv7mG+0taK2Huwp+/Yf2
Ivbqk62FC8kQSWalk/z5DmiqlSj2ZpP1bPcFJayAAlp2JOEL80scu6F1ykzfXSMRRhJ/my14tiRw
Ab50SJMfKz9AM4Y9EGYoYBenW1lpzx99rj1e2ZQj9/V74HbeeUpiHjgvG4ftZ2rAfrJ+UHuP5V3+
abGqWMsJDmk9S7QGFRVZZOCnY5OOdcxU8ORpHmOGdDR3zCEswpro03s8saglQApoHKFDkHqkxWFr
kWBvucX9qLzv8wUHQywGLOK2mSOHinON024vcVS12EnAO90c2DDM5lKG3rFs5vV3HzwcOK4SOwwD
Pox7GMUWqAgCl6KsAJZ3SMrbX4MI/aOGz88gNKKKIO+V9kyG3j2WEy9PD3vHIVUXNAO4WFAkU4EE
ubAQgc2I1qnJCtU93wcrGk4utkTRswBtpJhY82Ds+yxxr6WY7nVPEMP/8JwlWZTmvG0MS/ShsYRH
oOeu7+fE9keRCSyHBt19qSK+bCcNeDipsLoTO/RtYu3laRddeDewg7PWeXr2sxgctsOIgmanWDqt
HtziCtc8sCI58y684DBDJOQTn0R6QnzT7pXm4eAFL6+WTtzoXo/qARKVzx6h3aXus7YphHmC7/a3
4bEyMdE2ZQiWL0kda2qyitnKwjTu3Qx3XAuxf5FBLgpI1wowkPfovlCRlIgO3BZwmEhDPxfHgGyv
29Afmyd6d3lOELnxjFXxcZxFPyJNeZAqwOCKOZLk3fDp/Ty7N7eREHMde6czhDCufmSzWACk7JLr
CCfYuHQKel0AIPMEeV6jdmwY2DoPueMdwNaPv6fyhLHHG/IcDToeI8wBAMZbBonQZHdQ9wqKSz5A
4fgRxZ0mwwXg5O9pWklSWMZBDk2/xbTxUcgJmmKOY6C51WDbt7j05qslTuXEOk8fQyh9Y46PADfv
xo2j4QLLDElNfiboLV+DQ0yYrN+hrewzt5lKO/Tngma/N1/sJFvkyGLOYA4NTtCXsoZV88Ewar4F
ItQUCzgQcBGq2XU5XJXyTVza8z69ktMrQ1+osIFlWheF5albHUGyM2Ml4bCScTa+41D/mcTCTbMr
tjFUP1t6EuYR9xDux6bF0iE83lbqL3RWoIcw3XIZ2PEzSUssBG+3ivYzgpkD5QOVyNmjWkzvY7no
UOVV0kSuuPv3E5bvqPxhrfmWApLhhb8Lw72uKjgBfMdGjj1YZXGSRM2AYuD7DGDq86MLIZgOjTxg
c+hNwN4dj39iifB3SJx3dCZzmo+bCKs9iiOoVWqYXXbp/rLEfeupsFYFOpVHjJreXtyG3bxM0y74
vGmMAnoElT+lzohdfMg8mc3Bxb3TbnT+762io6Yy3TzDl7RDrpX3OtyP0uCMO6MYDVpX8MzBP28c
WrKuZGFHjH4kkDmahXvwxpZn0tHlg57FBObq8TMufvyUg6gSqowYKWMXyMcLy/+dES7moaX39WaJ
hEzz7nHcnYl+5aC76YeqIFG7rgS2gpZgynC0kTgEcwMpFGEul6H6F72Up84wWwFgVNyJuv7/TrOG
rsZYlQ12p1htlhPno3h8oNQJlu1bEJrnRzlvzUnBu9FR1rai6azV49YCnOubMlyQbk+D7Xq6SQx1
hOMNTdMCibm+JVjl786IGi2o+d0Pxhmof8x732x5qp1xaO+3CNOqVqW4bG53BaQ3ATVITJrWe/sM
+c81kGAyQE6Tv0LrQRuI+naSTH/tZsRxasoovOIlwxn7esrNvl0ewIPTiT5sSsYwZQR0Jt/sYzCu
TGvjCvx4m+eH694PXk0ss06QlxEciOVwJnSlJkPMmefcQFmbVqMihU8JUmZUVNZSvRcvORoumA7t
SY6HhF7pKpdDwRyOOMY8xnroG+Qd6VOpmmQktFNKaKNP5AkaStVnlAfe+P1mlIgRTWk99l8j1IUa
vY+Dx2KuMVTB+PWJXYauPew4KaBVZ774Q3pUR/PSgyOnSu0hUkK5jRWuUkNuDpXkSKMIcfrex8CO
F3EIDxenYFnXyAq9rH1AFprElqDf0AhFMDvXuHmqmQcomHeIVZvw8sQH3NYw7cjzQLJUkOhV0E+0
NiII9c++ZRyHF28ESoRNtClgv82Oc/GjdqKRHhhKvqaQ7j4vwtBqxXQaWroZNu4905EoORSaZoEZ
bQWVnRDb2Kyl1rUUc9QsgXFOnycY+MbqtXxZGmH6/zhraDRJt253/AMhDW++fcRlFNs9hTnSAyBE
EJC5zip7e0ahppuIMhhv5J+EphSIhxEWsBQYRBc24tgFXYR4KkOvJHvn6v6rbIPwsU1M6iZlHzTG
i8utOcspPXAnbec/v5njVw65ZxHx7ZJF/zxKbBa63M6QfdtFYhED7YqDOzKyExEZn0f0/AUkFsjp
Q5+IufWU/pjFvZyBYjCFB/qSBLTyTWA4+ckNyu9R5575u+ZOQmkgczXVCqdK1e0f1bDHJU11XQ8J
aMZv209m5kwFq8mafi8txpVYRRH8SQ8JgqEDMeOUSMnHw+iB7fUCNAGfv0aoJy0nEBhgBUXLPbnI
S3hLXtSDCiJHgFo5EoyzGleckm0FNFYOlBMIPkAvFnqU3yyTtT15WaMvNLI0kATjSCa2zX9nvY0d
Tb1H+MdJHD6X/kbRrRx4Tdmhav4GMICVnEEWXMcCnaZ/82my9DFcluI8s1OgdbGbdR4dcHhfhiSE
8ZXngsVod6nWhAusy+ew3O6oDFxT5tVCdRDHPXMA53z9fEN9+jNK+uHOj5EEHCJjd022MMK5NllG
+OHAz1gXv3cWY3IYOjUE+rGArSom9NmL4i9UUdhsLZ+n7BwYnoOl7bdShCG7U/1FG8Vq49Jq2Gbx
ZbrUhJ06mf4TMvfWQ1kyLdPr6dUTBrOkHLEVAaU/z+GacoCSiDz7TzTYzBMJMJacsDhGSH9ETYS0
FgZxux+3f0WInTHuAi2gv8eVrxM0HU/gvmcP06VNqMhLCOINoggV2mAXII2wpwY7NztT6Epo3UP2
fBVsq2ZM3jgABpGaWvu8YqH92R4mejkeZTSeCyHFK8qophT7NuN7+g3eQpN68xSHH46TLxFM46kH
D571DRloJyyOP3QCwOkut09dG7pVh9mx7bgxW/3rAe3T02Lt3XvLGs6K4ORcgqeHND2NfOm+80Ja
MXWCivjKU24T6fs0Oe1LYoImQPpNB+LfhNNob37YDFRr5XRzkm1+LLdI+8HJ1dJdHtdiCXaNh7HH
DZ71gPcyUOb9uKI0NFzpcqWejHh2TYSUQ8At7poe9+BOdUvcTywY2c/9s62qqJR08lVKKK23hVlF
12sCdNFkpyrZLaW5myAPOfz/MEynstvcu49CnRiw986MVhyl5i68yc4tjWUpnDBFSII0VuvQ2LCX
y37bIY/UjVXdXF7I7ffFyKhAO8IkxQFRVAMGbQ4x2DwrLU1ayh8sd8Em2CgsCREPVJszVaex4GOA
tUuSQDz48+kbNONCzchUpkHwITKQNoOD0aITJNEnsmToLW5qIKAiiw34TJ56eHk4MHZoShDHowvr
u3e4/6qEl8BPdeJOo7f3b+iSKDWdW721MvYD7GKDgK9Z6jZ5pmCC3hTQgGkE1uf7MbsW5l77zAq3
NRLzO+J3hqhBRdniAzsOPVFsE0vMlD+dDSViuoYAupLrVWobnfjm+jzBz1spR+W1csz6puObwYZn
rkhHyXAUufEYhxASmkNReC+XmmOwS0f9/GQssHp6w/5uPUXCM0jlkQua2Q4mShaUMZmaFEI791h5
k89LQFgNzBe0oD4WKUFmMHQwq7aITS+yUqVDIt6/eYrswORk1HhpP0CQJ3d+Xq1mZkWa0oxg3+eD
7gkxCLURaovIm/lj5r5oWLC/Q80cfk0cSZr7cUaCcB5CJHNP54E4wxDFPf4hPbUzps2X8WLsrJDh
q1tgZArfO73KOeRWfrtRO88rfKagr3t8ffNIgG0f7fnnf/e3aX5fnKdaFwW2gb3gq2+L2OBy06MZ
nchAAD6ExfRw388VG7EYWnjYR2xnlKdErgO1n0pD1LtlciYri7PfMv8BxL9LYQclTrsv8TiMWRqQ
QqgkPKd+DRb0vDce0Iv8TDpYr6SHmkK5nezmMkHHQPdwpr07oBA0E6Ggl94a162b4/r+7Q8Fg8ZC
CgHdybaaj5OZ1C2bgSrf4lQr/TTPqAnk9SaGBOFQf/+ny/z2qFCrmfGLiTPckSPWOThVqkHiHyVn
mpeUW4QNxm7ByguYLeNwnim8i43+ev7te3Ad8jd1U9cKE6Cfj3i28T0HXRpF7e5LDt1DcURmmEvX
Uhu1O7U5Byq6QRGAqbct/tArMXGLZHQl6vqhNayNWM1Q0+KUfMkVFaGn+Gyr/svjU4vjHiowiP3A
hjZFOk15z4orm3e9yy8jNXI1eCvL5naYeAAjI5lpiYL0TB1KB+78RtoQxVzbBUVLwr87p+g8bGCe
/zBHQY7ScmqlHO+XejCzjxF8luEtVyFyVQdjeJmGt0NAEfa53B+v/tWMTrydTvuIdbtGOIOcBBUL
5Cyzg/R811XP91g5nBesaxdkocLe8f+NOC5AKqBiO7VDQKHM9kTuDAHorC6X/l592zfuq3nkAgmA
dwpj11QNbBhfA2AX2X6dDbpF+b6qZ+dINl2vNMUOlEG2kkG2eJqnRmk2A5aAuirZpnza7bFSnrug
hmHcDdJYT+/CQHPjnFhbGLGqswOou/JtBN0Geg2H9zMtb0GxQJ8WhFL60PreWVHNZoDYtYaBlqp5
I2+bx/fV1RewintrvbEmPQvQrYVY9vN5sBrFh/aQuDDuULZkHqTCsus4EHDnitPHU0xiC/bHzlUH
5rNg8dbVmeB1OOckhrt4zAA4cKOY7gF5GpBDTGGMKU7N2hqkRPAUa8riq4nMo5PsQZ8Ch9R9zwD/
PBB8IatntwAuOh/pErw9Cpo4xD7EZ2SL1x2BfTNSHTzWr2oVw/DcKaH7rri9u2EXns8Mn5kJ6Y61
h5Rczlb516yUNLqRgmopcVLAnXnsSzaVJSDKdm36grwziOBBBaYq/G3yQhmDYi1vkYe4u8bcZ5C6
hhZYiBcrMHOu2WD1n7UlKY3f9MZXB2o/JRhRidEiHoNOzxX7y0jLAiy5fLgbT/x63pPpAzLw/on4
pxIbrEhNJoPJRjsMKROvA1ZaTySK3rJBldnznzPL/hk73N57ULFtmsgMLgWUuhBu1HxPEOPZOtE1
z0u7pnpnfJXVU0NDexNxPvnoEV2nhvf+PyCDXpzmub0051oQEvd5P94lJKHFICjSrzslkcmuaDal
2KUp99J8WMXzDq3xNQF21d3LzVtrP3ESNIzLQ2xQrEt23apwemTll1T2y+quk99JrGWlyl24Re0T
6jHXzyKEo0f+Gf7T2svu9ZXisSOqGQnACdBu7VPlAb3sJsZVYRCCaeFgj01Od58m2ljg9qMun3bT
+5ttcTdpZpntXbBu0qQpQZC07cEp8ywFCf0uID61/nCKgjZUdvmuV7rOHBXuD+3XQ+bQg1BLKbn3
sQ77zDhVlV9Xh5UZLyuRrN4WgXBz25+v4UbcIqlrGAUuF9YdpoZrJHbI0JPA94nzOx4paQHUTP8m
wLyEJxTKU7Fd6kvhO/S48mRghyJSoDyl4DEwVxWUKZGbW7zDvgTLhEMvP31vfxifgYkDrDY1EDXt
L7G8qjhSZ0W8EStrpfisJSTjnAw9WAU5K9FKaJwsjIvfJ/rtIPxdU98zjvo+vj83L6E1IE9QmUnx
MX68kiVzWBzfUN4rSXF2w9bYoxKgBlJE2oR4QQ/fbAYuOUfBiRdwxBDrtKb1v7EwUXZ6qGQpa8Kt
1pBgqIAq9pJ3NLOAYqSuD1apSWOpOEiEiNtbRawnGAy9KJMt8GajxJfbeFfhQ9pZf4hUZfocK2NW
FPGzYfYIQTz93+tjiPXsue/O070daaelOqh4PUq2Gy8jINdljNKKldG40qnunLiEdqIGPky3Yfvb
HNfV1rf5IzCjLo4dHo4Xo3M6CdpTtSvx9gRnGzSnnDgHoGNxNLST9hDJCol0QljyHA1sfC0qjn7m
m65PWj8CN32FMt+FgnYgd4+oHt54hT81MdLqcsM926XbGbktg1jLXfd98XONorvGW6rmXTLH2jL7
syTV13sSVFYpqF5n4gPT8ek0pqjjtK/RqCmWhwexHRw8oW2oUiYrr+5BrWFXcpVxTWNp/OgB4Doq
GeEI5/WeHXSYlCNHpzKFXWnqri+YF5RWkOVRKRcqHIDMKOmZK14oXtwP2nRpD+VIxYQtJA==
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
