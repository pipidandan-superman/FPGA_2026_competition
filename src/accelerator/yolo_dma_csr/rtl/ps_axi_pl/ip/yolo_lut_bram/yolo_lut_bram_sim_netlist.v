// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:47:12 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top yolo_lut_bram -prefix
//               yolo_lut_bram_ yolo_buf_bram_sim_netlist.v
// Design      : yolo_buf_bram
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "yolo_buf_bram,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module yolo_lut_bram
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
  yolo_lut_bram_blk_mem_gen_v8_4_12 U0
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 28784)
`pragma protect data_block
+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
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
