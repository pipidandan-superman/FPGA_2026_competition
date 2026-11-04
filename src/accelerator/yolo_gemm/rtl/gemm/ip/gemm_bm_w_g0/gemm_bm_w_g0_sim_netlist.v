// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:46:16 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/competition/12_yolo_accel/yolo_gemm/rtl/gemm/ip/gemm_bm_w_g0/gemm_bm_w_g0_sim_netlist.v
// Design      : gemm_bm_w_g0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "gemm_bm_w_g0,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module gemm_bm_w_g0
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
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [7:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [9:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [63:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [63:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *) input [7:0]web;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [9:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *) input [63:0]dinb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [63:0]doutb;

  wire [9:0]addra;
  wire [9:0]addrb;
  wire clka;
  wire clkb;
  wire [63:0]dina;
  wire [63:0]dinb;
  wire [63:0]douta;
  wire [63:0]doutb;
  wire ena;
  wire enb;
  wire [7:0]wea;
  wire [7:0]web;
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
  wire [63:0]NLW_U0_s_axi_rdata_UNCONNECTED;
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
  (* C_COUNT_36K_BRAM = "2" *) 
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
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     11.859801 mW" *) 
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
  (* C_INIT_FILE = "gemm_bm_w_g0.mem" *) 
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
  (* C_READ_WIDTH_A = "64" *) 
  (* C_READ_WIDTH_B = "64" *) 
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
  (* C_WEA_WIDTH = "8" *) 
  (* C_WEB_WIDTH = "8" *) 
  (* C_WRITE_DEPTH_A = "1024" *) 
  (* C_WRITE_DEPTH_B = "1024" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "64" *) 
  (* C_WRITE_WIDTH_B = "64" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  gemm_bm_w_g0_blk_mem_gen_v8_4_12 U0
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
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[63:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 48624)
`pragma protect data_block
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
xyve
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
