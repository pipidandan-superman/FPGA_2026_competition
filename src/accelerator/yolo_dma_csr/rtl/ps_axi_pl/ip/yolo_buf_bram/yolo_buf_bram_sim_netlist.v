// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:47:13 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/competition/12_yolo_accel/yolo_dma_csr/rtl/ps_axi_pl/ip/yolo_buf_bram/yolo_buf_bram_sim_netlist.v
// Design      : yolo_buf_bram
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "yolo_buf_bram,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module yolo_buf_bram
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
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [9:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *) input [3:0]web;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [9:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *) input [31:0]dinb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [31:0]doutb;

  wire [9:0]addra;
  wire [9:0]addrb;
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
  wire [9:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [9:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "10" *) 
  (* C_ADDRB_WIDTH = "10" *) 
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
  (* C_INIT_FILE = "yolo_buf_bram.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "2" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "1024" *) 
  (* C_READ_DEPTH_B = "1024" *) 
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
  (* C_WRITE_DEPTH_A = "1024" *) 
  (* C_WRITE_DEPTH_B = "1024" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  yolo_buf_bram_blk_mem_gen_v8_4_12 U0
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
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[9:0]),
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
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[9:0]),
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 29072)
`pragma protect data_block
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
3xU=
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
