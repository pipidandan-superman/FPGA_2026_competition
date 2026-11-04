// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:46:15 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top gemm_bm_w_g1 -prefix
//               gemm_bm_w_g1_ gemm_bm_w_g0_sim_netlist.v
// Design      : gemm_bm_w_g0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "gemm_bm_w_g0,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module gemm_bm_w_g1
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
  gemm_bm_w_g1_blk_mem_gen_v8_4_12 U0
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 48336)
`pragma protect data_block
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
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
