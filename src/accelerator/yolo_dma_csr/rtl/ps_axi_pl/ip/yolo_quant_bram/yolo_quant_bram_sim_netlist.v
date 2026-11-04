// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:47:12 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top yolo_quant_bram -prefix
//               yolo_quant_bram_ yolo_buf_bram_sim_netlist.v
// Design      : yolo_buf_bram
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "yolo_buf_bram,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module yolo_quant_bram
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
  yolo_quant_bram_blk_mem_gen_v8_4_12 U0
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 28800)
`pragma protect data_block
ZOxI4ng5krr97l6t0YOmO0BRg0DuqHx0iztYhzpIyqts932cAHOwJmVLCDI00JrkB6d9QIuHz411
SeOBvt4mhcVQysuXnjDcRT3neMusV0GBWJbbkmgx5ohbUoZ/trHKWJ3MPJnb3H8IOrfVFWTb1qmv
zQ9a+GtP0bwaFuhM7eHKKMJHaWIOn5VCSgyIxSYTFu7NY1wwhLRPwYZrniGK4KF3/RQoQ1TVRlZR
VARAEIDveS0mPj22AdLJZBAdu3i2uIm5ccAV1+gl+z5wGBWpTCd+3UaYwXAfROUOdspjj2gctWNL
wjeN62YW6yu4vMvgb2een4pF94yW8MH6tfKAEJ4fd8NLzb4OenqUVbiwv7mn1SpQ0rTkpibWhsEc
A9dF9ntF1nOTN0yJ9eeEjADeIImMFZyJRSXXJ4x1f3COPtCwUC8jVpe2YCBaPNooMRzPKiXSR4Gn
CVSmFKMIWZquX6+U5tI4psKmxsBNPG1PTBmA+udwFprd9OsFnEgsB73B08a5OHNXZ/9oOaAl6/s3
75boMFY9lDvag54CAaFOB78Cum9WvDy9QMHDTmvXb/uy27TdVTFl06dzpn3eF7IKMds24DJVOJbP
is6EmlRe3PKDX4vP7xD268gCilgPkT5R1htUpxd2A/qqYGHV+JTMU2uwW4+AmsC+PJRu5EO/4KB6
C0QSllotUm73LOWEBfOifs/j/9LUKrM4tRWiYYSehX24RkSyyzNYahv+F2PmXcR7/1V1+prqPgGi
uPP8/LDUuexRw9uXz27KSirH2qZaBQJAHBz74Pq+cNE5tnZE3mf7uzCQAHpaHnxGfFbHFchEX83I
8VfevDH0Zq9li9cpHjWMX+/8mN4K18aU0MkzYOK8MJYKsUN+MBwfDEKJQxWk/XnPmv+pOjGaaFnF
PwzceU31RZpamRRezDJFu1BZUqOhEoZz9f+Oj3LnyGx2ukYDdWXbkX3/c4qqZ5Psb0H/TsJhTTRs
hAUy188g3PgXXVIJPhpAb5w6CTIB1z5P/kL8wvwq0ni9bhrz+Hy2L3RTRvB+pQVvPNnXb4WdXBhk
+9ucVD2tX0IgC7myDFRZrQiG1aTnSKSwIAhufCpJ1pkD4HUrS7q3Mj3EVgsz/S4k9h4GQfu38/3q
8eI2AW+n3JmTWfYp5EVGfCrnA1FKMaqCm+t1Vk2ZPyZ1sLwx7b1Rb2AaSpxiawv3cS7cSuJ7MANh
7Wqvfq/b27gkgS1R05OD9CWcdLy16yxPLiq3VExiAz7xWuA+TZakFyJv6w2JdqZRbnOTJmMi7I8W
UPSWdLktG1VYLBdc/qAwK6I0hylhfmIHTJ0vQEOzFzo9hfOYVXHqur9w1MRfli/l5jgP33GdPtVt
UxwQAUWGMeJLne4aWpff7Rg6TRI2mHhN0xP5HhVSrke0d4kvBvOwHYiSUFOFptDkQ+1OeetyI6K0
7eSooUchYpQv2Xz5UaMvjMlwVgnj+VbISB/aKh0jkLSmWnajzBgetNgPhe0SmFEIVNl6skQcPKeD
RBtE7209zFrFDknRzwT5iH6dH/r516KD1V0fnnPQtzQ1wDpz/AVq0In40sQTMRRtCwHxlkRUXDih
p3PruUr9fs4/i+fah2vEDB+gm0mmz5BgLQ5DIIV5ylbfmJwtuUAzm7qXB6zE0pYQb88PiDmvPKru
BVjD0ISsxhwEnKwfMfSuPXH0aMJuXXqzMl6/gpqrzsc95ilNKAZySxAAO7827p6HO1hd+36T666u
HTMam4ekuYYCcMNrioi8YvB+X+gR50T6rwmvJoXG8xn+AbeznbOnSpT2uSJIq5r0hk03X6biLfeO
mhU3Gxk6SoYRiATNF/iSBB1o1RzI1ylscOt3XDu79KE92YKhTCefmqzTLDntcOZJEbSM/bNlxom7
slowrwSlWAN2b1jGBVfCxsDumU1V/SdZbtLS5Y8OUAqT46rGGGCLqtmA39FMkwN2L3W6W6QRsN1A
7UCoS97x9H2BRwp7td2wQF8iSlYMaY++3BH6zagNZCk/eti6GGS4qmkpt+9hCWPLbQrEtZ/eZnH0
hBxaCGx/BUbx0z1hKL855Q7A4M3f0Y7iB+SeFpieXhk9cU9Sj5TzTxVgeRpTk0G2xKFB7j6OFUBL
bdn/85AvY1pGe4s6ZbwSUNAYm/94o1BT1TwqJLfflFFSeZlRo9tYRERV6KhIiBIHQcWdUILCUQpG
wHhNAqcodLrgp7cDJL5CDBoAsRuO2RzAsIzy1dP2ETqooXrH2MBrsb17Sy9jEvtau5J4YTMADrMo
RvsYO8KEjWYt1JL7CFNEC7zUcj0Sa3yvthlNFck3G03Lf+hManEmTQOznbIpSumUwBuLvq/Mr6bI
F0iRJ0Z8qgHAh4egH46XXkQys1IOV0+dzDpzt0si3N1Vmlyh5hfzP3ixRhN0fYz7o8YIj4eoAPzd
8u762mSR3Zxp+lPYW1eYg7p5+DPQcVAIlZQ9WkCpPhJnPl0hEDGU1ehcUOJYQ5LD2iswcamTxGga
pa9B/lBw7yNET95Q0rQ7Hi1njCdiytQsB9sLBei+ZZk7JYYYMQEDgDRowny0gk8Zn/MG3UZXw0f0
nHldnzojDl5XQUPY9YEZIUBJGzMzVExO/Crkhc+PPpvrhlUjYWWt+SgixadcEwVarkSLcV5eOr/g
06dBPqCGbYD7J97SZlggYmurYWiYScdsLesSFR2yzapwSbVXuZWrcNCmjlKI9HGLFOvFWAa6vh+z
4GJesaxYBdSUR9B6sLtUuDtJVg70o47kp6L7BJqJWu8Zoa4keNEGNYJkoJacTqiwRebS0Pya6Fxw
44eRvHF+KHgjMepcHJDGymAV91+aTK0evxK/l0xYiF1iPsC9ly3Us9E8Q+/hW3ig6dmDx5eyhsUj
Ai7RAoTqNB054SKCHNSi3rVqleaivN7jkjvi6kGkEU5wqE42Pq1QpAArZsrHmxPlpP3UAUEX4aWr
Xp2mrogcFMFautXUBASYKQRWdfUO25VJ0CZwRWi+v0K6/mDiGUy6mcDv/Lv/wSkh7kSZbcW1dFLv
JM/6j8PzvfRfdbEO8E28w3iCZJHthqtX2bPbVaYogTnJSeN9jKdQW+6HdjbKHzjN9Ttn5BjeF1Et
FJuQ9LZhy4YJJ8pS85rihI8zCMTIe+mdEW5pP1z/wtbglvIxABM943KsimkR9sofCIHj7+4L6iyA
dea/BMW2HvU89hdESL79IVVEuF9irWSKnZWgt4OHJgrz1ECXr8x57n6khf8ecQ8oiey5ERw7N4CM
NMZewrqC0cnvzo7fWmoAGaO39sSjmD9bFl2fE/yrUPCeI2aH2nRfN5tbN+mfb1dJdYERE6z9Qzlk
34zjjQnwJaqa+HpVQk90OtrcPtMyTsV6gGEGCHGNJenOmTd4eU5Zjo3VupaEdcmnT0XzkJz+hrlH
b02V7neza5mljw3ZSrG40V+Ft2fpTSI3+5GcI5sgXnHXNL71Y2CIB6e0FczOHIe5kQ1bLLVInSUP
RyOqRQFQCIzVLXy/sT8zrLM9fG5u1nojggS91vkHo/IK6tipkOl5O7uaXndctS7SUtUAMLFPfJRv
wo7riGRn/uWkOid/jOUlsZv75qSCALA8SDeo7H7cbJEYgGq4/ZhedWepNHyV8aTDE5g2tXuDzu2E
1Ts5SrVo1kNlos54v+ZoxFVf8kY2qdEzWl4kl2ByPU4W9PxfaTk3DXPR0Izw7hgIjgHGis7ZPQaJ
8X/n4KrCWSut2BuybiPKgvcJ8EOHbfkeV2vJoY+dQ833eWOkHYjo73CTX+i5P0PtjGkvohXA7uwF
Df6Ed9j7n3kdMg3gYI5A0R93eZ8SybqIMb0aJFtL5aOaJWO/mDjwTS9zerJSUQzKChCBRIAkM1p+
4LqtC/H1QKtBH+nGkTXABATOLnm4hjls3Fd7Fpe0s4CyTvnXA76xcKMGIOwdaBj+0x7cLEnf6sWT
GTr0ZJTNGTSwi9p024phGIv/KJYz82YOm1XKpuKAfsPOVvyZysyvuAl5dUGbxF3OAWjpzwK6C8U/
F7Ey1ms+te6TLKFGUO0Q/+7ktaciE9Zdih+4G72i5mH8g8moykd9u0FOftN5EInUL1Jq1Uzxq9B/
GYNN0VzDWkQMsoDRH8yveFzf92HxYm9ATcYggqV9GUAbxY7V1ymuKXfYkmfqR/dx76gsLNgX+jgI
anlFbDbe9JAcq45j1fcFXRNzDqeP4shTRb3dEWuBf9ut99Npu8gBPCFFsTIz3GITPdLaz/f/P9a7
W1mC4RgzyrNqvCAcOuSOtjZ/zywGapdQKRmvFRR9BP4ZYarrRXqkNNf1HMYrNF7wTtIO1M+RpQoH
QkkGavMeOUQ58XiF+6UhgrDI4qpen+Nd4KaTJ3wabKF8T07YeyVwp4mhoTXHzM6OZShKAcTKi/8M
OP16FtHgj+JcutVUcKy4iNW1IBa88rqPnNRfNKuLuXeVT63KtSlcQZw6Ii9ZXFUL2/m+Y6+CP6xq
zvXXGYiko+sq4gVoB3pV/6Ck6GT61APHT99pmfZfMqjE0yi7kG8KcHlccy2zs0AjYdZi+RC0Mfa/
IYsWgBScbZQybFqxKH8Yzd0k6iRLfZX7bOmNA8bg46Kk9U8srm0WgEpe8vnIRLDPsDqUOnTNRGxi
P+ZdiUSqTQcCN/QGh4WSbLiziZ8xqkC8ZSZ3N0mSkhlmm2V2dDr8ZZDtwkadnBTKDjGSlIUCY878
8n7O77TdB0Ed0wGfvYMXHvMfeLQxtSwpXJkW3IXR7m7/cFrwHwcZkaKZ5u8mbX9Em9cAI3gP3tMV
WWSd0IPNbC5pT90Yq1TSfVSlY9rxuudcMiidAtcAI01IyWaTJYpqgKYfKqM+8mhTl49Clg3zis9R
w2aha9otLsMg35SjfgSgHtw5jNQ6m3MFaQ58hUuUlLKdfEZW3YgRf3oi1CpRw8eczyD9WqGYI7or
EmeYdOVcuP7HEP4MgUGbXVEDSlz8rjeZ1MvH8FuuK0kkZAHkzp/N/TACZEsLhLjmSI2AzYtyO/mO
pWl1XdMAymVCxU8zPKBLiKvPlAqBjZsVrkYhdCwGtD7AH+fxYnr3zau4eCWEvCpnILYCYOouM3uQ
02VnO9rLUHQcab2R1fzSB38fqltj6EAPpsn01dRPsESpd3W5k8TkFqWtDIF6ojF2KECi+OeQZFEo
+m2RI7WYj3ZdKC0Gzz65DE1lv0SEgrdkrDyI5In1MxZ8uv+f9vrcK3LSC82X7Dydj8+5WDQ3rAry
9JgRQqt8WyN5E5ziQAtl9hBmqKkHPVU/ysg3MBI56QoI7pEbluhUE3ILiYIVKmsUl88tylkCX9yB
vuqkGZv6h0Snv9j53YR8EIlfHSRxQr8blMt1ecCxTUbg6dRJ+Zow7YnaaPLl96posOMYC7iFe4jB
Oj3yrtb5suygkUhzvtH4oClcyg4xnOhCOodL0tEFIcrGuRfY9qg0d6oamkdXFcnNzxMZBHGGPzNe
wyodv2BEhBzcBguESGS7AMZpzP51GrWfZDjg3plP7Sz00uf77CUOCEANZg7AsNmPuTcIXvL89qqk
WADGlmE+N7OYlCMzpJMIn5CmEE+hgl3X7BmJd8u+vMoyqckyvuDn9GLNaQaCVDIYtzzh+g+qFUVO
Q6ophL4XD7Fkl3F7o0LdprjBgKoF4mkK0jCekNCLFz4DAtoMabXe8pMd6IBcITawKFgKIusJj+jx
bwUxH8OUabmLPC/pL8lwD3XglrqOvZ8z7LCsklqbQcllNZm0FEiLeoPJJxd+GDvHdqbTAH3ewh9M
FQ7LSC39B3ewKIJNGbFAzSC2Jie06i33jdLgyI0npIZy9NYun3mIZxBu0/U+Xdo+kVNyCaZPNQZb
mnp7QygLLHLBugjE+zUUpwjW3zLwl0d168ubxY01DtRg+AqAYtNrO2TmIHv686mUGdHWx11JC0st
IY+H19bP46M2Mtmi4SJjCtelqehM2NHHxPB0FSeUD5SD9fAnyLUjPA28yqkTfJea4qEyamMl8ukt
OuYkO8QucoTXi1YNO/veuzUVPAGN93NTI+rZomQVnObjWUqqaSvwhsZVXtcQ3HRoyrImdkOXoGPc
Xi7/wcey19vGklbKcztkjtdHDKAZbB7VyFy4mpJc6UT4koWyYGscVB6omxIO+OXLCBRRJ1xfYd8Z
SR7o+aJ0Ai63kIyPIaMDGt6Z0EyI4RMK/oCTkzScjlKKyCAx3dEGS47h4AZLvj98YsOHj2PDgUVD
gvvSvQTvJErf44YZ77Ds1yF3C51pn5nnKkRzEzMqaF6vUoHL3oLx4lv9snXP5+vm4slFh8yXAUBX
sbKh5UTYXu4AGrZoL1Zk6XeKxVG6IzN7o5xOqaJE/PA29EmkMc3n+sCYoTp53QXzQlDrUsZoTzPo
m8ozwGHwj+HTqNWmdWO0GLq5IeL1aqsTdzfCHA6th6EO8qeUspsatJNpumHVujAfl4a5ZN+pLdAx
jsc9bxzz7l4fyc+diSY6SPVcMKxYxf/U7ON0TOjS2OKXvmJAULXd5pSdW+b1zXi8vxh6txwLk9gJ
1IQVY8h3CLMhVT5wzEReR7qcC/opjPrRLAbPnhldNe0XdHOqKogj0Gio5VuQRPmEIMsLbnGuzjgV
qKVmp6bASMVOTlsFPsjceQeO/gDpFoW33iQzbyZHSl1v+4ZpwsR1/ifzk5BYQOfeI/6cHVLW3yb0
bkMfYBMawIGjOfLjIKpv3yDsjHODmf9IfqgMkjJz7X1oz5WJlnfO7fCFb4Ezhwa5g7v7kE8SKbPq
jinkxlfRJXExcEv/JL8lgrg27WfyIX5+zmh4cIQNpKUb8GyPKDNBVvy438BogzQB1mkx9J+gHZ2n
Jb9HUPUE/tzTl8jyC6Hi7yATgv5NcVNCkVPNEnWajthtlRWjP4sUicM8yko/WkDY1N8yPQ5iP+Cr
8W5gSexpBidYb4Tv3/9L12A9ku755t0jisIetG+T0zKkkYEgcY1HXCUDSRLfoV3ExDEb/6z5Psbp
2RCYlfHeRKC5UGCQjaeJc+e69mJfbYeyK5LGJn9giE68uFoWkfeyRxSdv8LO+HoeEg9aHsfSPBRj
XSIfbXcrRztZEp6szK1k21Zn0sO9lw89F4e2Yea/SwsnYt9vF177wqC1arPOWbGqNo2GUa1a8laP
c8AvqyJiAXHqHvF0avPe34c/GMwY6veNV+OBZrBBrF+Hi1QH0Wj9titGSeWtXeoCJqwTjC4CJYbv
IP8KOd0y4STJqJCnSAF5itz2bW/KoJ24MLCaZU5gZidv5gLSNTT2MsPJ9KN80RYOs/u5sKMR3XgE
5GEpigGdVuF7NrEUKDsaayZquK2a27hEpKjAE3XTLxyW7SLQY2IZS4k+C5PL9EgQb1zNSxEbi5rh
IA68sCrPtyM0i+7p8rdMQm5COSnBpzk1kSh5Yd9y2D3RyPue3smTX1AdcpZCslIsIIWb7aYKMBbM
mzHsktbR+HenQuW+tOm9N3F87htES6oZ8hKiJL+tns903YRKOQMa/XMWsj0eeCh1l+TZTdiqox5n
0jrn4d+aBu8iAtUeTA5HgZ5T7Uu0MAdpRhitF23nHMVeYPvQcWPF79/BcLcjYbtBiGYe8WAskqMZ
AwkFfo9q0e8mZHTJ+4s13W9/BycRNeWdC6JqLlFoWPUmev8WTlT0qNR4AioigPyH/gjBoDpvGTT6
RaPA8JNCM8yVrKnj/ogj+aYEG07djcdfugKRg2gAzsBKSYaOYXlrEs3YTiZsdr9lX61ROxnSi8iF
HYO6JFHMYcl/rORz4NpHrOnUNH9M/Cbu6Y3cb+IFJAawbC2wXjWZwETQWVIJMr40Wk+NacIzQDMK
intu5KEIWH+aa7Rzy4II+506KtWxxG9zaWvLw295EKv+gaDxsNWaz8lkpbkTi/IkxE6+2uv/sC7n
gUHju1YRvzaAV/hksRoEDLxZcNiBwFQzQiF63HWIxGDGOiNPTdIwJZ2ZNsxqHdcWEpikGy/TwBFq
jiRA51iVGG0VhxQIpR21e7iqH+gUDOFmIYZcbVM34J0dITjGKm9JNya3Nj6lMDn9PUGsEeZ2kTWI
mqp2hRUhY5aOZT1YXowbs6pNFkN0U2UZTWb+JLHhHS3ljiY01scnD+CuaILJly9AmBfSa/dSzMkX
BRSUShJjWqaMrpKHuY6QOyYz8ubRzL+7B12T9zBaYOshYgJ44dqPldqKXwoAWCTSG5vw8cPhTBcA
EWJbIkY6q6IkUNirb5L2so8ShG8jKMF3kIzOJs3X3dZ47a3F/T0LL667VzDHT4+Kz5nrtl7a4TFt
z3ZKelE1lUfaN02EGJRO31jVd3apG2analuMQQnoRBDYQyl3l90E6Z/hPAca2wZX4L0h45vHJKCB
Rscz8FzrwSZHKRGEtnadlJd7FQVXYv6vh+7k9pisUX0nv7WaCtPQMCs0eOTmB/9WTOnLa8jdYlSU
2PIMJy1py4Y+6bKTco3MY9Um5PXl29+w5YySchmHXnrRpca7I2FHxoDO6sL0wrEWgSwF+4XFXIil
iz920aplqhWMEsGQoaA7C0yeP2lmUGkL/Q7t/vlGco/Z6ilU7HHOZs0K53CLN/IYbNFbtr0ZYKIH
EgrdfcXUrqG5ztsir7Dgp7A2JyWR8EV+rBb/T/u2cUt7/7FkIWIlj3DwNEE5c1MeAUsNRoFGVcGy
tkBXEmPjp4WE/Yx0fc64zKi1cX4smVnn4ryjPpRpal5Hxow6KLBYfLNwDezEkm1HBVj34viFTJVL
u/bnmiq+mSO6/iW/eZ+g1rNj2FtV4aR9qov56o0W1BvuIsCKQz50GypLpUtCmLxmWfBaUcPyKU9t
su8C2n2wtu4ARgt+RQ95I2EVkTibUJuftCT3OPnCsa4CnbIJFSamj7EVSQW0JPt30nyZx5nv38CG
LzJ5iVrkXnfQh2+sG92VBO9lCkKUds9ZGEaRjFDOrXlYnMaV0SCfZ64zIjJluAV17buv20KVnryL
SbzUhD8ajIu8RgIyEszQdkxE/IRCTHxHx0ReftFtMV2CfrHWvRo1Pxqmj74CR8Q66Kf/priRy57+
yY7z9EX/lh9JFev7BFUMyAX0gpvk+aIsp3gDALltJWre4cmBgKhn+C+RiEBTXValUP6cvzqlCl94
B9FBAzsmqOyJgMXStP/mUkVntCuu2IDUjbcCVQPJxSqTRuBYXyRCjMDyTJAQN1kr+puggtigKuw3
zguUMdR7R+jhMzljeEx/ORE4eA4AKmGFp6T+T9TZWrLBkZviwGtBgqXQrbxMd+tEUgyBW999NsIV
1nsnCgL1cguaUTvEsEqTJ+h3KbNcGffWreMsPTQEtfU4vQ1Z/0Urp3XmVIa0Ft+dZyGW8v9Eg6RE
Z4iSC/UYWxd4YTrzwjTlSBdqSubu2oZE/SWRD2WhdtGnExdfJX7jzBKU5eTl6CiqdTXS5UnTFUMn
R9xtRttdIwGLTcGt/F6MKtygEnGGCLfSXCOxIedSneonYoIPIkmtGOgMQffzrrGzDyGUPh6fwsAl
akaTDvVMdR5xLJo8/s1TsHNGwi05oBj8iGknU7qxUQBQ9qdRKQ9AhxHjB55YKqJRXgGUmI5ed7DH
M52fGHCtohr3OoUCa6yhiMIyNeBNaMsNkwPD+n/DUPld2FnoVRZQ/eH6qKxwnUaJ2Yemn7I/brNz
XnBNFhLDhMvBqwRq5GddNpnT6WKi7xNjyfFNnS1f1w2Z5joD/4CQ703NSnQt5U7gfdzxFRm3AXzc
Z1hqc8ik9b8i9x2cjD8D6MZ4YrRxLSfTq4z1YIeuPH0L/FYUeDA87dO9+to4pYWMg5QMmUYTux2f
I3t/8aWzU/4Bb/JvXdQn/MYX8V3P8BpJ/IajJH/7DH2pxoVZZ+RFBDdJBnxw+VAYc2BcngflNpYB
mUX9iFyj/WztiAnDF0Tn2+OQDhDLG0Tft2VXbMbExHXQFm6BI30kiaDr8dBgc86QlcsJWguZKpcP
5N3WKc2Ih4Id29GGq4vMzUyekLvDRu02e/Dnx3Ar3CWhRZZnhLalWyh1XKE96Bw/cN2NLNHkp8jv
x9uez0HekBJk+O0hs8CAP3XIApA0yYT9yW8/1ix+E3yJoPpK90I0D+kHqme2zFerMylcuXRD6EH5
KPZya89KYhdCoClZR+hpBOKx2l62XubNAtvf+3TJtYWW+lLGMrAPnt8BTzH/7djhJ67lBUrVYszk
d6flNKFZBpeZJDOYxd09Yg2obRfayxQTF8wzmd6hzDb/0DgmH4c34YUPEWBtNZJ76m7OP2JfXNW0
CmgVciphYbKFHSMCRG0024YcapYsHEM4wx+SL4WQqMIlI216jTljC4qjMifSQWIvoHtWVLMyu4YA
94hmemxmihh6C0bOs78x3ViU0YZ1iy5X+iSgbwywsxs2/q/pvy9SQYzfT9y+mfmvZui+P/Vm2GZC
hAkLWCQFTCivJkk1zSn8+TPMBbP1sb4C9KkfUYSeHrXzqtctfbd/x/o6kW64zOQsZqpAApQLnVMV
Eb65TiXdFfEO49d7dDXO17Fv7vDfpe3StzcjOKJGE8aM3WB4TZXnxOen4Z2WM/5/kbavfCAQjFwv
QA+LlZ56AB0QoSUYd3r8FDF6RecNyf8eb4EfU1Ced7wI4kLTArlP60dfyYcUEan7OhAv4EdyNKJl
obm//Dwdm+ueXZj8Fgy6B2VpCRj00wk/o+NZv9r2V7dLGxQsrlGx0j/H/0kr2cjCRM/dYuDnzY8+
en2j0KO1OQi6GBGj2ucEnAHJRjvPDrfe70kJAp+IjD56W6Po1WLg68tacBbvwMDqs1fDDfGk63WC
MxlmzGEa4VMsvpd/cEeZbhMpfCuuNMI4Vm13SlB41o59cVL4UvuHHml70BgqEHnxwU2dHgIOkrDA
ul60H1Zhh9J04HDCG2ADrTwEgj0bL6vLfAecKkfU1K+HJhdPgVS0OIErg6YC9DsT6D6eb2OjQ1JO
tCMkbKnCIqWPnqMLuwzFkXKvB3EG0YL5iRXQJwiEoE2whgzMn3JaoKuvj9lXMfCZpczPsJK2vHbA
NzzXm5+9WqC14Dh8gYLjpXkHBjHdLKyNvJo1/dYIh1zHCxEUM/2HMO6n+vTmLY786pmq9ZIkOr9f
UZdJ9hcdUjaF9AmE+pnnDWBGB1eWA0iD/rQ6JnbJgOY6Yd+0DXgrT7Dz13XgSNqbs11coZSYbvbd
B8iQGx6aMbTI15EBpnyRkkI6YRv9ilFqJ/NrQcVm1kkKT04UZSGYDYuuqeXCPM+dSKeMXsLXCaKx
6W53qHfo+2JRH3O4AY+rE1GTPavqto4cwbZ4XWB8neWkOKM7gYao4m4h95TIChpAR+x/3pk5xwRf
KVfRYHpVbZ6N+iu6//taWa+z/2cu6hNRn8PcFMaqiaYx6qqTUwBb40X1rnYKl6KmCXWYnIZa5y3G
/oo3IHCDbVBMsJxW/WUsH2Wbq8ArREIEhJ+1SISB8NdppEmBIfoZ+MebNHi42cj0jX1Pjy4+fDBM
OccAGg4S1nwAH4mcekray2AgJ/bTdNxQ4KTMifEs0CFJabmi/o+7+Aj+56+e369VJzd7UkngI0uY
cFzACPyapVQRrcIPLn3VeSW71WWO07y234QTVAE18K0/JavLKtfVt7DptgJSzy/tzVbRtoEFSa7n
9aAZVQRniZr2bwgEPfF0aE33MbCeiYcFC8e4NWsHtQ7xTh71lBGHMXaST+VK18BOTDQx6UnCPTdR
9g/n6DLsZtzlDVoVIuWPkZTPOgxE9N+yM/pUUO9EPVSoNl3hWeXwrKAgfdeqbpmJ9Gsh+ZZ0iih1
kxv8ikfj6hRL1hPo/LOW5Xb+ycGXyDZChBQOAzMQczo7mzGQ+81YbYA6g+mYDYG1+00xqV782zyJ
lhZUGZGPwMN4GV7tao5ulEanysyFCbFrGTzxTRfktUD8KHgkRadV/xHmfA9dp8c/3ZsfM+mKoMzR
bqmLCPGZyOSoNlBUIDrBduiLhRb145etoGhvahVMSVWdFdzfCWbG7oliht0vN0h9h7lxd6uJdk+C
XXU7mihT2AArq25Hk7gbqoTqKmEsJ3YlTeeY2KUwGuLp8txiu4h08xGBLqV63x4ALCmkbsMT4422
jzjS0rwB9gjmtTDuZwpjWhLIa9LQ5UzszbTR4/FoRVEHePyTk9/8bDzniv1+XLbpnwyq9xQa/uqy
1l2E2Ig6zqX+YuBccuq9KPiuX/JqnjrxB8ggiklA91P/p0NjEBngzK1sprKJQiV+KrN0k/zFb41v
GIDI0ahhrycQcZx0ORdALXbKqYw6yk0uOJIDXdL/B6rMz1/4hMdhbyyXJj0/3jVTmqjR0kDwDMVQ
ljRjLOxb09aVMEte/OzgwdfhenERLSHUzVVhot3NpIBEUKh+AN9O3dG8/4GPw+y/DHG7qVwLaBVw
9VyKnbbiFMu3a1RVx2vIgTbpjaFXux/xyJOPt8Q00ddJZhHsQ+TfCxKPimdDLroseV3RImqPwifz
vuxrPK//Seej9a2dT2hnco6nyHHN9bOFLcqTwKblQPFRv8xvN0S3W+VBrAggbM9ik7a74WLsJXaA
D+wityqrigXw3YEPY341Sq19wVzk9Pa2UOQqF5mK02wge3gARdqhNmKaWjYtBbTxEkV4jAZn5x/L
Xv8yom6MDO2aCuCuLKIBvzPlQU8iL7yCtGomIdehAsWzMQ4kbGGDJmhOPjLCjryTrCaG7clEmP7r
YG2oz2DmK58QjxCjMH30wspEQy8MihJ3qJGLjAuaSoEzH432nrK1peR6yFqxfPOt+6zi4HThRtWD
gDTcXd6o8Qbm0fm3Rb8NpZ4UUQyjDiTp9sjwoxsBB4eC0sr5D1XGg8hB1bqkOYPwy+Ef6B4kgcl4
HZfivaaM6KUDWcP0VqNMj1fpyCR+1tk4YzpkfNhH9/Gtq1xnYjySvBVJmMWkhMXTKY8PuE9E2Uil
FKEINmQxpoaB5sF1ap1WIAowyTTg1k+eWFb+GPo1ey0N2nxw3MgLNeg/j1rfaQdyNVXopw9ZNvYB
Mw0YHt85YmZJ6bZJhLGfasbmEZ/8gwTsA8BT11WpwicfU5RWjpPBUqJ/GzX7h7xcxU7LplN7tiUQ
dGFGJlTzjyL7sTzvVxiQiTcwlpnS8z7EstZqEN1G0ZMPgTQXBW+97vYQXYVCtQTgmteBHhJ8vu4n
CgWT8DAGR84DRF2CpM7UVJ0PlKz3n1jrjHdIIXUmx/RLiI53blQk9ZYoizi/taFtXi8OaQLLBQVy
3gMR5PmOVJZ84pGbEOam1U4TtrrNDg5IywYFSm72WqsTyXA+wwiVVlYk2tWhtwMG8FEqUczGol7N
rvwgKU/qkWnlkB1QxzT7YuSV8lt9JB/pNexOQGxBlDH0xrAoJvD1vctJdvo+Xmxi3lvS/PMJM5Lu
uFqeBCwoYdBCAyH3ANS3E8l2Cn4Pgb9OUA0ZhaE3kTOZvd9WfubdXArq6PFXGHFohyYXL6o2T/Tn
e59KI8lVtG5I2JJBJAuB+gQj79cIYT416CwNRMfzgGxSDGf/KPfvD9HeJPqPOTzZ2l9MOnt9UxXp
EO5+ZljSuleMp21wDCkbd3iCVoxbdwXCKI5+DlcOr4OoFbqHzadSn/eqxuguNriQ51xofs349Hy4
uykj6AQYyXq7NAO5Baryhh+OfaCGXevTFBk3LVD2EOtwylVOxs0ZKcAHUOxZgA4oB/oKfn76b1IO
URDpP/NRqyj4sXJD/u3UDw9A7d+PCCHTZlo/xrhP8PzCGmaTZqcsYQoj6l5AJOY+nFRWy6NmeKnO
dxIvFAfKiOFaUaSVamueo7GJ5EyiOIBvOWsH090iI1c1eJ6BswwxcDrlPToKnYbw3xHuiqFUqRO0
FoEI+nXCuQv+kd+gVzHfYyC8eAd66asocG5oOfmQDTx3ZXnkp8J5xVW/20tws36ZU2jkB6K7o1m8
OZF4EgC0wc6eD3nF0Axp+kkyicpggYGPcgj97RV5FgBHTsR0xnS4220K4Z0KJxuUxZbixN5YYsd9
kWARFS5CRkGsBTtHDrNWRNCWtyjqZW1F7c/ps+d51XboVhZzk2bgQPQF7ebCY8SexeUXu25XFz9d
6SyVYDPEaVz7Z92vKnlu3lM+pWEpsLT2wBnG/CfdpgsLKKIB9es9EQw9L2HmsKZ5RQo+3EETOotn
kZOO80ACcWq81gxzhCQtq07OI8icjI27giQS4LoGSgsNb531FS5qfcILr+x9u16w4ispyiZWhuEv
dKW2zZCYOAJhaY+XXTwP3Jz2QQ6RCgbemBQ5nN5pYpMYe+gzISXsqHtoLGxOYdvztV7ne1MKqTaz
zVuMprU1Z4S2lw3/ESZ3OQJpIOX2uSWSp6y361pambeJzjfurpBYyvqrL2by+nfQ6IRyhUb1UMYk
CxIHgH9BAxphwBOYVDJIa/3H3yPOjk26N0YiI+ChT+/+E0kpR1QtDiS7KZb2OIONoc9pdnPoZWFj
D04RzjCWlftIFk+fqVBqb+c5tRFmbWr/xGgcwJzrIiYlHOjIlbXnyJ/ByJ5dlgSp/wJpJIv9V6gi
DoIgKDEo1djMWNfVrJGvVziY99bD/KHwxk/7HiStpNoudN90uawZvnS6gE2KspYDti8S9l5NpreM
kqBxKtZIJw6+SwV4NaBYQaqC69QwaKpO2CbAPsoURbaGb/QcmExoJmLdQ2i+rzKzdFR18uIWdzp+
Yfxu7NGVl+8aTFlNLU3vk4qhjL3UtnuYNcab6JGzmBNStJBI/bbmBWIX1EnGY0ecb2S2Ft8wxlw4
Vo4x0w830+Isr9wBVv4aGveOKkFTbN4Rrc4mBTryxs4sGDQvGiBSe0XWRQDpPxGBSpOKd6ElUWsk
p+wH155XFzLTJkCqRIy/HtmRyxUTvgxZhAv//PtvrwNtvQ3Jzsp92WHA4YODiM1edDa/mgsJqV+n
B9pzB6mWT+RwP1IhegxBHZHm8660xhxzPD9PmCbUBgUQe3XFfUk2EkoxJKcpIxxsgeSytATffj0d
pvsduwm2PhomwtHS4SGoH8vP8Gic6OHwo3Xpi+GAKwa3tjroIiSfUeMlbV9jv7kf8A640ome1Bhs
msamaiJsJXNe0CxUBp5JMtvkl+3iQYvjuyoq5F11Ds1O4N9khyJlC9asNxzr42v/mKCsG3iYYntd
EakmK35Hlos+t6znvyXexrWKTDcmE29MCAlq7bD3nxQdxtFE2bbv0WDQP/UtjzPmqPlvj7lPQb9H
Sg8SY47RFe4LDNWJD7XF/10ljcnNmHKcrdtXvDh/+/v6smTgBEwJOMd7gWRUADfF7zuG6cUmAPKn
qLZsNfvjCfr1xBCDtzB4lFtIwU447sqwNXi2exi4zuh1v5aP1bAoJaxhAa649VuBfAGjqcyOCw5T
mtkEuYStG90GhBveLFB1pu5M7s1oQAOtI57ZO0C5ZHRFZ1ExFgvxJWxRRGVjyYI/JpqmRUtP1moB
rOSOCVvXLV/0SkJBe7UIE/lF6P2arFm2vse1mQRBgQudZ81SoqJ8lvofLfE2/vAgUmMcQJlYnXlO
TzcL4S7sNhGsmf2Ajt0/WYccJHgqFDwKSUokpkT05PWEQI9cITsxNuvfy48R5RrfP5MJWt9fMZA0
aBUTEkUdEg0f5bmxHL0A3gglYiom2IvfVaTAquxfFTCHDaA7DfhtM1uUziB5EHPRS6G0t3ZxWNcp
F5p0TrNAhDceSDOjdzPzN5fAnoHec/mDWczvoiq0oS3ptQ6su+ac+MvttKlKE0p+tFY4/64Axp4m
Xq0evjTdKG7PYjpjGLQbFfXlS1BWvO9hcC1HGfWNskbbVIxXemJyCdxiI22xHfxHOcywUiA+AUAp
cqQmdoSI8k84jDPK53jQhYrHHb5cMGizEAnCXnyLj0VFYXloYtdXyLy97l8vbOeb99ZXL12gfGA+
aALIz4M1H90y0iTZx3J1wG/2KRU6SbnBiGbkScOb38WyqD4F5lbsZCZSFVc8Ya+lkRgG0Jbso97P
8dCkVeOd9DiFTyjQ4O9s5dsTBvKNtM0hrHZBVDqIGNeCxluSgaaw2Wn1/VH9LSc8qBMoPvuHieRQ
oqz6fldrCC5DKHn+0Ji5swKf8L1Wrhhc0RD4Og6veBKqjYOKGdwjKQUhBSzpF3HBO8jJFOMHA/JN
TZfVWn0zhfVOn/LtzT3Ln/1K+u+mEibFr3Q7IOrpciT/QNIHRU0yQ+EuRz5VYN8rXI1JuOrvtttX
IbWbJEZ3GKKsHxhHukJ6eYnS+oc31mauzGmL+7ilEmsrje1EQOPbJ8ZO65vtK7ppZz1GrjOoPYtM
CQptfQUoJceNW2blMoC9GLpS30SMiBlDXPvrghbazYcQfdLsRcanUR6pU68m2m+TuglWlwUEVYhK
WcXH2CwpUwIQx159udWJawXPs38UxuSBjIO1lj8u/LcPlkBQrU0Ci2VvkhRWNTvYvMIn+pvEhvjI
Swlk9Ajp9FWRxx61igrbIPqSvGVcHSErSW6MEDMFeWfOB+3K62C9abcs0UOb1UuLTOHykNQ+necu
AVRnSQPcccBp0W/Jd3TzWjTCXmTLeRDRakjX6W3SZoJzZQJo19tg9yQHUMLq/nKXEtJcwJm0Mu3U
PP9ov4W2LL8HEgFzjWzTWgUzFCd0szRRQuco8XfjU8UHct7gJ3xYQXonrN76Hsy5wCM4iI5L9l8n
S7tsLb5zSbinGdE+zYuqloHPd+jNPm+PrLm8S3taSLITifBrgwez8e+3VOPfNOPXRvKllE4av/mO
33qMnHHKG62J4XXoGpzdjurtmsbogXMm2UKSa+7c9T+KbIvVTxXuW+jPsh8/XZzdAbD732qDRiWF
PitrfBuw6oc3A4B4EW2vRowwuqUCg+CxcHRHixY1/tYQZ5yC2Fs01ob/0qPZsF5GRB1rk7d0c/Un
O5TkhJq+8ZGQBPao83OOYMaYlOQazNWhvDp69QlX710SgJ5AUuoSBaC3EKPdvhedJiZSqOqUn0DJ
uy+HkQTTVlf+IaWLBYKbea6PUSjA04Vueub5Md/zGqzgYw6F2STKSnF0Fs5lxsOAmBq1Q9uxU4iF
bMEZWZ1aSGfbO+xXN6ykzUA2D2xbWxJVSWgpCKQmsCD8jCjOXQhB1FIA1/m1nuMMNlSakAbwJwWT
6T2/Ff9kmuKPGghsQykP9MIQw+lQVQ3YHpaKcQDPrNC4STz1Icq4ZbI3zzyfOfHValr811k/eswc
KGyV+y2v8R4CqHnkTDZBwgZyUo2D2bJw58vZyeqK0SetjYhZQmXia2oKxoXftnyQQiwiuw2tqgAD
n8VZy69OsdzhEjma6ppThJKr21CdAn1SJ1k6GCFzvzuNsxJeI8N0gvb2D9ayQeXvvTk6DrPayvMN
bh18gEfeZ25uJfrMCHjk7u6333wBvl4Kl8ZG23gU+lQ3AENgngWUKxj/H8eDItRWDOrB/y2EaSZ8
sOfeFMsgzcTXWBrJw1+J7L7IsnDwk1Ybkwk0hXlZpYVEIkotf/WN5TtZZwkH5G8UeVkxKoEnAakJ
xGh24toM6Ot6V9ntRblVCfgq64kVob6y05ldLnEYzrv++W8cJyh82CJsvmzGK+YkYVV2RVjm/jq4
CqjQaePzNzmJWNfZYtSt3HmvfQaN5z4NST8wwWSrty1gYFI88jSyHCjaZfYfvsYgknp1qvfT255Z
FbSeYEoNb2u0N7mRKHjAmKnq36+Ql+i37pj6mdKFQOZcjz6VynZAKopeYSg920B1qpqB1MgnWbUR
zS1Pz0+PMnnjb25mqhwiW7As5gJJolFliS6jDndmFe2Y4Y6FF8CZ7Ns9ZMFwK3lbIM9C+JAVP1wD
/pIO53um09Nd35/glAcmk8K+NjPfscpMi/sH05LAybHJAHwW6CBjiWsJXzfmNztbRpATllJad6LV
T+KwIOQDfb6J1Xi3EOvhcls2Y0zJ+3+42UzEAQFCz2+1Kdt9sD5Vk9oUF3urBDZyvQu5U0gOopLj
CpYe5V0jtYBV9Gnbh5lBE84LsvYXVtFsub8sCQ0VHLfalcwbw8VH7D0lh1T8R5t2rdO6etk0yfe0
tH7OzE/0CzVK5qrsHJkrtpZY7Da5zldpwd/Y7F+qecYrUtlozAtsZUfXYOK7sUL0UYp0OLl8miQQ
XzyLCLYFAEzdWR1QvNhMpVMxeJgzVFaevO68DcyT+GtN51Pm0LKd83E72coAfKZIe4xCbTwBDxkE
CyAPzS4WmeiR6k6+vxZH8TEE0o7dCAR6Si59W8xswOJJABUtyGQteroX5gAGAhNwqxuTYaVYKAxU
0pL0LhJqB6TD/ox5WRFHpqAYYGZ/SldydRnQytBGax2RROiMjl9OkNlSXbiqXIBjgNc7iLbm6esU
/JxvDwSOM26FT7tHXv4yr3JSoCGD3F+l3e5O0x9N9lCTfaY8/NJHH82Vck6E8Msw23Vr6s46xcrG
zsSV8O+Vul9vBEtUI9IxT9qpgCXtAw3tRholklyxuuuCabhbnIXqBhcRPTBDDvW3gjnen2BBy2Tf
YJEZezW3jowcl7/wLif2HFM/Vu7x8TKtR7P5mmWOibCkbFVAhnfki9ms5HDYgeZM2aZA4Zbikxt4
uGbEiYD0TQFbQjm7AUepEOXZjzJJ3kZMHQ+zzjgqPFxL6hvX4tZjvhIS8fpQNP1kvkXymqLW2Xio
AuJ1Q/xnPnJutM4n/eE7PYZuEUyYUJkO/0ESR5LsPXxjtEo554x7UiEq4IuRowlx80vfeye1zPV7
p/59oKLo4/pXlrr9jMuBoTZ7/3r9Hw4V6hJlOG9Ir2qsUiYVunTnx2tSXnmzNDzkC7/kp4qqeP7H
X44tBDmyz7GNDyzPtdDSo6ecm8LW86tL7P77qHflfawakeq4M9pBAGm/RTNQiD4k/GGfK+EBeboP
9YkW0Ucndf5rcqYxvmZRqW+SOHTmsuHfhKzviHnakXRYDzjiJGmxTYPROWPvmA5qKmREObUirNF4
qSlsK9fP4cYfqRwj2zROr7iZN7LAuMiGO80oWgtYB4qzD1dbyF5mU7pTjGC3CzRwzrt5nEmS6qWb
HdDkocVJoZ3PLOXdQTB7vWsWCHXlz5V3ADZhlxH/VB55mb3/KpTzhg8F6eWP1Ys4+gtg3pSpb3BU
mkRPCPGRQRKH0+KsoafHaV/tpg1H2wAI3TLikrYVJNAf9yivb+3xGhLVoHpBakyi+uxQVcwfmiaQ
GZzeD281tRHsHouEQkY7OLBBJoaPbyBgBYbpn5gxgPZkkszSpyIJR9zIw39q6TLPtL7Mh0dI8wYt
Q8hx6dN6fK6Pm8T/Um2wSjsyGwlPoz6hk9Txfx3KBOzWQJhFhKsdciTQmoKY5zAgFc7ouDqNWO+y
Yso31Qq1e2mr5R3t1hpY0voCZzwXaqVj4Ik3GKDfcI8fYZ3cOgu8kZnx1pmWYPdQ3PzracYd58a4
NwGJUcoW+lrlACsTy1sFRF2tzodGtvfiRcgxEYc/DVyaNQ9RFZSUgDAohtiaQTBEgC6K9J89T2cF
ClZdqdq6CLPuWQQl8zemG+UzDP3a0e5GPBumJdwh+aiwz2Yvy8kYrL3EulFvKIMbovGWTtf5QJIU
kywmbVHqFdamr49Q57o63OweoImy3kAi85xpNYxEn8GMEcKZD/iXyLt0RCax8d3s0CzhgF1b3Pzu
ZH4RNmrOs//VbH+kcLBg6rqCsflJ3s75m2VNY0xRH0cdhjJ0zetn2YWw828eRfwb9eZ+mTgfj1WQ
Vqr66aGJ6R6qWh7Xc0wZmCqi+VcP4phifPgTnzzOj6CCJQ3ZUonUv3DHfD4Wnjb+0TFMPg+OtJJB
4Nx6SAe1AsbMag0mfv9Ii6uXQFuWlCjTMLooKYIaE0FzqlrQKjDysQ6E8z51OppHJeDl71pDebM1
z/DuGMlhXTmrEWHWM9j67ec4sQlLP9DdJ0oRMNc5Y7yv+fKeuv9sT00lv9pk2AjmSwL5YMDXRINz
9qJPfnQu6bUtCSHY/0ix0OR3rpGSRgFl84YegGMwsw6pNqMYyT1GdpL2gM79e4W9/t9e1Xp49iIE
E4qM8FnODoDVyET/XT/B9mYhnNmM6jLixbnGvjsvi1ny/lV9PjL3TL3nb1HuvdgdD4dZNYBppoK6
pinwZWjOlU5Win1upiHIgHWNWpihXFZYdqvOie1wmuQQF4dxW2xTr1F1Qs6EiFPpqixM+2R07raa
jnp8Rapy/4TX/GexW3pHqtMrIjEESZlXX3XJBQn2nIfdFtLwmTwvUU/vHSAz0A9dKvNy8wR6QkXb
v8ceDHvHFMRfmCpmWyKmjZfMDPIPFKr8iZ79bVb7PbEXV0Gt3uq+/H4+FevWnYAMHRs93qZhVYiK
higva9i8hsx5DTUbWojyDjqvbG1OSbH9OugDUQcOIb/727TzPe0ijNB9ZC9xZAWVLednd2gX4ccT
vEuOueo/VfSLMb7kEgMi0VqcAnKsDkcXOvHTM7zLnW30YnR8IPol8jxNBggDZ8igdty7m7Z7pQI3
1Chr9gOGJe6clhqkaE1ge8aUzgd1jfUgYiYQHtwuXc/lTFoIz7aZmCBAkKjv2gbS2adtYWlUfg/P
a+aNxFwedDOzfrBfHTZA7teo9yXal04KdofbSafWtFBgtraFW76mq2QUzz8tSe+dE81doLnWTkhW
byhbTW3sTCUX/u0lZ1KCYi4wU3DSSsptxsTPPBLnN/4OlTmMegpC6hC7m5+ghiR24Wp1UUZjI3dO
gj5Yk/YBuNBQOsG1FW4OYrBKZskMh+qu44RJnmrdgz50Cr3Lq68w93ae+JPec815gJK4PKGbXH5Z
9mGD4mEr8p/8DYFG2RBR4Yrf/8LaZvMx1T5YhyK6ygtJgnevbBtFag2u+iDMSIxalPpllFBta+i7
y+x7tkhacUmj1em3v0u3SdOwDCfvRw66MUmisuxmL+KlGB7/mJ72UnKq5qJKUkOMsHawLg0ueEn7
8wO/lOmy+X6hjkXmuVsVeCrZ2sGYlVfGLAzb4CEJChGmSCiAsaPC3h9i6/adHNpaPfsB369g5N+z
WdXolOcwyQyHzeBS1N4xhBzEQlhbuyLoz/IuqjuygFHegIh9jdgYOSkQLfFzzJX98KUAOblanAtF
hti380zrKVbEw3Gfz2tNVR+RUoLOV727vn4VFJJAHjwtgtL6ZuNnYOASgZ5wdUCSxhUnBUTGDihd
RJMbKPQ4p8gXoDgbjboN5gS0W6y3CjF8xfPDUr6Yz8nMxDR7xjnXvQp8ePv/GME5/BTAavdpwL1r
UBcTGDDSKHeTm0oUNFA6UYiMT7cQcpCh8VqPV5cu6V2iODUFFtCgqHUD4VwI9X0LBJgwV7ZJrGdL
bce37A4w6eO8trwBKTCRrVzaAA/UKok5VZzpLikDRF2vn0Xd0edL2UZRfR4AlIyUcNQmL1L/+A/3
tERr3gC6pz+DEcQKGjeOT2iyyX7fo+RzCMTCS4aGzCVlr39sfoKLR6eJK6mzLrNanod9B/vEDPdy
+AtXGngf6l7+OZ/0/DnTJjmF0ABayB4Gr+C5zd5ZwcO7SiJcoYWhBn5b8wtImmDlN8XgoXnLThfI
q4H/AzN7HAxPAuEJot9MAbGmVrphnOcKc3CpmwlcKEC/vAzpijOtvBbunr4nyqeEEvkOLIujKuEj
u6ZF1LkuHOufEDcQgNz1QlNbeMGvFPS5eKX6r9AMy8Aa0pon4EMmYwi+uS3BaLSH+9JJd0xrQauZ
SsNmO4jEu6fjEcQACy/wwMVdpfDUTNd76XjwF8sNx1jhmNg74L9bsdPSlwX50GAYAaX3d+nrIvdX
JiizZfPlMfyB/+xXMDccvuOnfPXlHjlEkNXQYaCcPbWTTDwzIJduJbi9X+rzN0m/Uwf09/DzN0Mm
nrwD/CpwxrQddnQEbIjWAdK5eN8lemtSZSFR3Q5hRBQ32hBCTxyV3Vzs6WzrdxX7dkX0ZC2/6egO
iKQSuvU/5bgLK41n4dPdmrAWU5W52G3MhNggbbnYfyRQQCnWCqR2ornFTMWYsKPjJs3jrxYsU6HO
h0uewKX/EgHywRug1UzNsFiDbDZrXxibrq/rwEhznKrXiYG0tdGxKP79TMn/4PyUpH0/ErmZN9+V
dvuXwOwGnCmt0l1rqEIZYAcvSdI56TDRTMoE7Lo7auf8ofUNDHlehvedPR+t8dp0KFBoB/ia6Hqk
9fJllljmgrhblppmWuF2bK2tHVy2BYgHaCI9yeOoV8irTce/hohilsOI5Dx5nk90GcEiJpFAKumr
zAD5hGX5lTvbTT/ATO41uDTAuyY1ikBJ1PCxzQP2hx8MKkHAyRz8oks3xOhejbYx4EAgFAs+mBui
aTdsRJMbQJqeTrrjX0/+TpyudflwqJusHmZmGAsuXATARYTJrvuOqjriFWguu//+bEoJyMgGXLLX
1SPvps+G5p9sdjKfl5tJJ2e0smQtQ0K+bG05gV3ox8cdqb1zDp7B8A4Fovi+wiK3nOU/nIp4zMRS
TgGgFmMxdGHKmqjcjNTTBMeO93QpSR+8QeSHWb9N6Kb4U3nIzuT1IeGpGXk854cjTyiMrAu8nvKS
H9pXEGtPQmT8cf0HuQqsBGZbgG+co/spVpOnaGOT91yvINGC/TpMAQQxFaiQTPpyMK+T1i9AFMhW
W1rjvJy4ZVO8jsCwa9bPTEINZnDZDcdEK5BcSe7XnV7V40SiwmXwzlRi/JPpi4bqU86HnPm30ILw
pI9ws7/uc6iWzueMVqIFBrpFqRows5lVY4cFTURHNkfy9QD92Rtj5wrtXXbwB0GVqzn+KiivEFVw
VXa3sos1MRZBe/h5XzXqZHoeVJ4AOgEnYL43q6QvejKFNk4K4rzMlmvNU6Fk94+9arLQ39FNj0bN
wt9WTLGu9e5tdWG612ZcwNxd4hF83kBXziq3a2xP/zvXFxO8FY7Z1kY4+mVFDLlJ2jA2bRJFVUkr
MdTSYls7kUnqDFWS456NjBttrfoAWURkzaiy+d/2a1XOw0AWTQIG5HBfhA3PMsnUxmXV2b4k/6aa
wimtoGfL6FOkyZYH25ak8F+wTVNKzTSls8t+InuLq4Cb0rWJUCNSbFoZDmQ0brbrXYV3o7ZKFNVt
VOkUjHjfI+6mgRinigX54T7xZCZAPqDv9CPURPIb4fiBZTaE1GMDuHonZGKbu5vEGJxLo0nxpM1u
yLxx1tDbrGRBfUdpzXhu8LT0GHQUpLF+P9ct75Ej9R8+hZx+hHHpsQNvXurALnMyS6+Po2ZF9gQF
G+wvH6MOEOUSoIIpThb43Qgdt5KOQ7rBpFbl6E3M7+Ql0fh/15HlajhgljPK7G6PZU4mCRfckjMx
s1pO3A+Uxwl9jKIhWxkvF3OZlPJpDr69FR4FbPjRJKAKW2BtgazCYhuak/lculPGEpBJId068ywz
wkyItdSyzBW/oJx5GHtbty9z3I+Y9nxKwM3bp1uPzOjPn8RRNh5hZy+1GObFQTUIBX+Nwh5oY6OP
psKbQkSARXUkUFQCvvFMAmWzG/EAtf/bYrMOHbLD1ySZ5q+WYAHf0fMPs+YprPC/fPvxg0EJ3QVU
ZT1+LgczK6nWwmbMV1k6y/gCW8w8FP+595BUT9lniAehojPhWLVllNgnc2fNV3XQ8phKlq7QGhD3
/ihOo1Fmopk6N+IUJa6x1vYbiKPHgOMFbEMNL6AHz0HEyFq6grZvGb46/6/jiSOTv8I5msOxEFHh
suPQWQjXDMx3IISBjLsz9hf11M0sr0ie5d4PoNokBRwWm89+9AtI+7EoTxBThC98FHNyI1AMsP+l
3eITVm5ReC4ezgR6TkLY4aboF5LeG9efNLXe8a0oFeVXTMK7XidGgSSQrL7CzmXgBBwIOCBmInMf
LAkWxH3+ZZoVZGsiztcOxKtzwUsr5+SJjSRR+F/+XqrzaeOlSiV82bC5UJdbQu9IsuuD5kTpiHPQ
5TyeJZPT14hCYez6ShDgXyBwNveWIiRGDPRFUOSFNCfSQP3+OU8kD5tRfG7hYEI+Uf3d6XX3Ye94
vdGvCk9ZnRS+gkIVhTdlLX1OWYOrKT8ScGWK6THUCa25TM9qeroNGslcV1681+j5eY8Hlnk48YPW
P15K5oaUNjzlI/bWmFJ9TtZecGV9z7y7STpYT0QnDloihpeDMdw6H/ewgjZFAc+hn9/Bfu1itjuQ
sGifBJmSFIsr5WD1MEnqGVADovJOrH8tZOdR1absghqUHmv4EzTO6/PmtqrxMGVcBcSYPGVtH0+Q
CRVsFekhUo/NDFqHZl41QilXNWJbhapezrEkxiipZRLKFHV6nbYC3BKvDs13WfMnnTbWXqYRgJs9
eAcKOnzlJQMgmOsy5JhNB9j776xWKSVxmZH2dFXg0pCtOjyn41b4Qj3NSitfrt+QUmKIFo44BdoY
0LTiArXAFe4sVJKQ8IPuFrJ5u10CXXPtZ9N/xQ0ILbz9DWcsvHnViDnOWy7PQUzbdhBPw27Ajjgv
D1kDP9ypfedcA55x+460eKCjIgMjCVILQO8RMOrkgP8TG1foVq0oFE0J1j7SPrHpyWgFNjWwNQx7
AcTn3yQIaqMjw7JcM6wJqWqhHcr/JJvoCwX50Q2+dheMjvGIjtPLFJlNMwQL3NsTDxoHsXEHCmf+
Vs8LCIcOJ9W63k4teyG2O86mkgncQGRh/Y1+Aku5PX3rrwkXTWoGezJmrWiCkF1kFNPc7vHWFDkB
6k9m/q+hmGPa2MueYkUt61OhBwNCqZg13FGhcuR4egUC4IYo+6R9+H0NmfOTB+h2QQVfPP3CH0Ei
GvxZf1qle671ENDuuTSnhQYuVlaDOnE+3qqrlksxntjVjDC91B3KAPQqWU1OuDoYpHHzG9hnfGhp
UD4DJVBKNmf0b3p/rjtemwSJu16r2WDEL8AWuIgi1oQqfMfxCM46+Kl4bY2C51M2AkJHO5oxerD8
ySczY/vWXUuk8T3vW0ckHQ8dFAPk8ICKcZtVeWYkJP/J6nO0PjlOFzT7TNzjLQFV3ujthTFr0eXA
eJu9JXhvhQKWUfhamkRvITXSsIGvqTU0+bRcOlbEMCKSPyIO0cmAV6fM4nvyGsu0LlKvxFN3E8S9
mrSHGBcP3VjruM+eUsE1jf1bf+YD+tmCH5Mv1hlx88T6Z3MUh3/f8urD9lznWmuZgUOR6vhqxwYm
0IPPOqV8zLHRqzalNXqstlq4P5uZtlXfe0jV9qHqSmH4xyDhW1Wij1p7ozHzQTOLQYQpWrRLQZhQ
9Q2W9j7g96WqAESVa4RXGqw4DE9qqU8VVd0He7V0li2Ypiy5h8w9zlb9lCbp0uAjLI/gjyDiY0v3
xoRWz/JuaBaSkmexw2pLvyoIxVGvyPNy/tg2wGrsQ31z3aoDoXW7POvZnXiHNBdo8kOkD3MSdbVE
nAnKpgKhWVGWVFEXQE0hoiMyOizYpgsv1jEReH7nrnj4UvMd73SxOyiGcb4CTrSg5ueSpg04dzQQ
Nl7li3T3g9gF8Cn6ZggiDQAnJdqqML3YJrCH3GtflJHV/7ByVqM8JhjEfUDPArA6Jg+rjfDotpp4
XcnU9dEvqD56cgYxgXm1717kVvuyDnQcc9vcCFxizzN83MjOg5rDlCIfTwIWOptbw3WCSNYxlPHx
9zc5qy9qdHT4OT9it8lJxjyKU+r2Ni8/WyO5hA8z+JvQXSvhVeg4MZHuaGKLf+Jl1i0Bqr2+7Url
bbl0HjMj5KW4HZaq8ZJ9wtuNwIR1MJzCwNPhWyu0I5OX+ezRM9mlGj00RlZUBzwjQ1HVzd/2wGKW
D7HcTbOAPv/TtxI3N4MQvpNcmWkRpnSSNrcLYZF3zA5/tayD+ortgGuKRoC1EfErRzcWvPW7/aOq
fElPRmE+ekh4eeGuqquZl6pZJxUyPRyTt7YQ5gCdnd9XXJ2FINdV3OoCQH1VzfhN4d+Kkz9Gl5pc
//ixWYvJZAOYTXxkNIjzMFpEYhF53+6TiD9jBN6NoL7l9cApmUG3fVL/eQYRItQ97zi4zYSjqrSg
zuUQAETkf57g0LGEK+wcRVERzVExXwY2QM0t7oEl4BUEQjUVV2S0RjK6dv/REOB1GEpa9BRQPguM
cVN+nMsEO3kiONXARDkkXQXSiRleziMDM77SkMuKbTzz2nl2UFOeHFIlrvanBEBiSh76ZEQPNNo5
sgg4TGCnBnfG2vWyyYGH6uITm5qHyG/7LBwPlMHLWOhWmpx/QrdbUh+Mn8okmjUHm8wSLe7H9lWK
T6EeZGk+9AwjlJjy7UlooR7OmVJY6QkfXzBVrH+htqsxCFofwfQUU3HVzv+4r3dSp5GVKMPoq2CL
jC7eCvJTQ+FckYex+0HrvM86NwAxtSBlo4mHHXyhH40gPbyNhhnACoUNO7iNNu2gSWaWEJaS5eLg
OE2WqqekVkkQBtVMN9kqoDGjdo4xOdspbDwQwwgLSKx9KmDp6K2/ON3PEZgH2jVRSvxJWHbgopwI
6kACIszyS5A3A8GbCklMzQOSgoHR56rM/uqyJkDcTh/0fiZ0dZNCDP4CB0hc/+YHRU6W7z6z7S7q
EfMPA/bunC3SKCrjkAcnDVtU/unqbJ/V5gfmpKoq3i2KyFB0/nsXR1Q/GAv8MzM8YB9CvGb6OVFA
3bf3cxmexunFCqKugeE0ww9Xv8/v2miREqN1Hm28H8XCsNfFPPdX6COI7oTZ9EO4x1jbIwFlOn5X
GLKXsJskUL70U3kSOCgenhvjU4YIE9JrKRnUxcbQrviNVkV7T4f5AyhuPwhn3xzCxkAr6qfdRnyy
UA5tRemfYXY2Y06ZTn7O+SVg0PseeFHeOyPX7vlhxB0aB3+edmSdQLd8nO4aweATxwUpUCOjwg7U
dKJWTsz2GpzV2blMd/M/BjwazzqArLF4Fg+l+fxILS+9pqZKmZ0uQ19WQTd4+XOoE6ZhcQJUGtfd
EhPZv5ZCWtPLHMXbalxQz60HAyx93V8hYdta4DlmNijQtKubBvqxhouBaznSsJ5t7pt8OIC5LEuw
fPhkj1Qh/fAeyKCd6oyHK5z9h3f7BEjVll2uyx4L01ROxLRroDGMF6tP02sgczxUPG6df+nC6CFw
5r8D9vLmJV7KFm2lDx4uewP/VZgaJYFZ0OZuwPYIofUsrofwGmindn2Z6TFyGzXJyb0TOvVHo0fa
OoREWVFC/QB/nEWA4GwLBli6pqlaGKmeVPYccwexKvTEb2IuvbfuYsY7XNJUGhxkr/lkZeJLjg9Q
3Ef5SoLCFLYGAzpfDxA6inSzKZkA0ebpk+hPt5u3raOT9Smn7ubR5XnfWYmkXLyIOKZpXcFA4d1P
HQThhq05TrLvLWpEBXahBt3LJo3+UqNk7zBizJJtz5IiurG47NSo8AWZVVU4qQZ7L5mXIw9dRAi3
ib8xCaHE7tZ2YvpjZvREkKW5gqo3f9K7Yec/Hp3KOXyGlJKXW9lTOXUL0NmUgT43t7pqRKPZf4MY
inrwEUUteoIR/PY1nQfi41z3tEaW2bBC8k43jZ4VipdzW0q7P62dYGkGlgUBsXQjdhAskNLc5aWj
fJctCvN5m2bdycfV/0AlW/tEBGo2bMLM8lhOrrhpy/ZDw459TSGDMh4n5nTX7h4WP4fTnUSmO9hw
Ax5s4HkrUAo0VWVRgJ+316DblFVMb1Ah6tyNPOYDu9j69cT1DnUVKpwSwgqBn/N6IkXpQh/kiK1Z
6x6Lt/3ES1RhdOVKqTKlXBMKn1o2DHt+0h53Snch4smRL1u5iY+vLVIvs3yAlamNHW74DvTNOY07
MpUhwrbe8Yczlm1vAexLhx9alpvOUMg4O46E5E+9e4QqzMOwWdiYOCYIZ0z6yRUO87D3Qda/tLDf
9/Wwnnx8dNRxTLxdfmQDkYDef6GVDvfJ2LP3NNE0v2x/0IVgEB9DZ2qFVoo0dEH5qdFLI6tMe4hr
Cp7YZ/EqQD+rftWJ0Lt2xLCeXQrO//fHo+QDDzjldFOkRt9vd7d4Yg5rU/jTYqbekec6leB/mG9O
6Upy9i4Z4k3X0UvGUaJMnU6ZGyVX1PJ5yfB2GqjuEHZngab7unpkxyjOZPjQEOML88P2oR78Jlgt
p8tklebtWGQqSRUEA3odpcfjKDcZ9z7e11H7mSQHldxye2H08coz6HZ3dM3d5TUQGxyFtoDik6SK
0XndOgQUj9VoMIoc7Hy8zc+IH9cnnj4+nyKJYnmTqxp5ZJsa6Wm1JZpR5kvXmzoOh//9YBYhrqjo
/xEIfr2xGJzxfousgLmH/KG9omdNjCNdKSBQpQzBEJF3fD895xvVCCla5JeohUoYV+nqBT5H0Roi
1eULxZ4OV8wzIti0mLbgSSYumGIO5tQKKlqGYI1ORh3GZyDZuLAjIlrRCG0xvcGLHmT4EgmQtjJg
lgDwrCz/3cUwU6YjdtGwld4DeUptXcOvsTGfYJ+668+2LD/qCi9AglnigQ2IUZYA4uypU8UnD7BK
71muLNhvFWwI9z7kgdAcz+414UMrxS3MOCd3NykMa7l1FdWNyb1BBDhK+fjcsB6Lsfn1e6PUO7WG
PrQNMNRgLQ+lR7zPbQzM0+9XQMdc5iE3FWbFDekN1+8CRnZ0spmdxqGaFUZCdO8hWwT/UgrpaYfX
0XRO/Z0VodTur2F+WriRDUxaMszaejQZmWEea5mKi9RzDNXJL7u44g5J/LSHwzj8Q3C2/SLMoKKh
THkLBytCBJgmHXWs9OD9pQ2QYWu2TmcQjoqFKIr/nMdDrJDTTp+ShNkaHocOS82wG5i6dR4iTNhO
7TlyND4lidH3aDaa+lt+AkkTGVLJLJ64W9+ZbRbS2BIHi2KOvCZ2W003xrwpFN7/xQtgDT0ytSz3
OqEOnCfmWwp54WlLDmN7G9e5SHbU7Ij1JIJgnqqAeMA3AYfnk+N/K65qWUyiI2on3yZdeuqIpP/o
73JA3KhLs7aFPGNPfi0cG+YHpf120jY/e0SOl8xNeE0bg8QDlaZ1XpNTb7wSk3gn/S+9Oji3kPYQ
zLzMFdrRYoPAxdg8YxRitwJWLHet/kQm4LO10a9zVn0nZmjkffzUThwxe9N4tUb38M5Jrwgi5OvI
6fvZb0y3fZIBnaHcPIDoxaQXwCpcYmcBX+A7f5syuRHQbicHZPBvTtm/wt7bzpbWERv+S1pJy5ED
zWEqLrCMnjgPrbJaBdqYrivh2VgaiVBtEngIk4tVh4iCxKNz7AgfcdIpl4O75xqeLwJeyiXNfanC
t1kJzk2aeOxWXXK4ZAzDwYy4xAs8Bec+VYSy3Mx+JzHNmiyV6tLyHe4sPC9VTq2dK1gJkjDfz7os
j9J3roMLvB+3tg21vwRf2St0cwv3F8YRlSF5Y24f4hfZFfMVkFgO0ZbzQ8YReDi6C12noksmNdyT
GH/ktBHMsFaKOgVO/VH95M8/N0bHpGJe0MXzr7jBvVWcsS7kU3nId7Os6DKiaBhmxo30Xvh+MfwH
m19cdyLugl3YOmNCDY6h1D6tI74DMtXQj8Zb8uHBLxudU7GpFL2yoFyQ4N1QdzErHT2Y++aM9F3K
qf6bTofMD+3cG+Cs6bHVDe7D8D6b9oioQxQfqaSJN1Zg6n7fLKKE7NjwEfqYNyP5pYzTU7ngeZZE
m+xEa1PXo1mvB91gLz4jbV+suxnlLqIbtlTfD9gGVo63cC6jjA7BqSEUhlIWAbNeFXO7VvzJZtiy
bYJXlOx7ZP7N7Imug31fepKuhSqlnM2Njqoao1t6E+Puzq1rutjg2rCGP7WChr7TMMk9blQGvZ4P
S3r4mfaWm1pSqKvSh1vH7nxXwfXgpSdVFyLf0hsJd8fz/0pxfOjb4YgmOsnHlB54UT8LnPmQpba3
JYFd1lL1xSSPL71ri9bE2gLwF1N1FL6avT8Sy2+cCoT4NgLEzF2UtbxyLreEjLAnoIbIXzljAF+k
43gCvshWSTs4hwL0070HKCYBjLwA45DlVHZ4RLhDKzQFrmBeh8ZiTK6p6U2Eq8Qym073y9qHNQ3O
XVKDad/PCCvHAHsnSIaV4mNY/vDX6bJnKbmQU/RehbrEI9bfBepp/Dkoumml37U4zeXR9ooBpTsc
tubyBPIAhY8f4yx4YIalKYIU0w5z8AK6M9OqF5kpj1ScgyqRrN15aA7ERFBO3DR3qyHFaqU6jRds
MYmuoad1WuMRCHnmDtkGqxlWY2NWgn48Zxeh73Pi/L8Nr9zy4ZXrZr2DtY9dMSbUdpaCsInNF7GD
qd7Gjcxo0H5M+/nLa9DtaIO3X/3SQlVaFzl+Ct9Q1pI2SsyhTEHhdeyebS+L/+YMoGI6cXK45bZh
VRBVf1Tfic+zaJRgaiqhzrsd98dCXXLYcjoeBB6/wqaTk/5jZXuCnO32NEL1faCpUIcMLJwpRNos
gRYXrS2C80a0h8+8CUdctvgo/fPzu388pvGQ0HdFmNTt5UbEbXPjcEwS8UDrEpNZigMSqRGVZriw
OrE4y5yYKU7+AVX7rtudA/4pE3WJ+cFagh30pY0Cul7kTJobDWHj1bBLatYhrgxskXFWpUdFia9O
H3wzJUleYTKAvuHH7E4OfGA0FGW/k+t70DNf39o3nyLwMyfSY2SDHDqzmOyQRNbN8LSJEYWj4Isr
2HzK877RXvIEFj8YDPRngBzHOAk4sLpWKHQzEx+tAaBgKamhkOm7LgZSD/NFIahrwfXB/X4tGwiL
JM0l45/snTN380ETZxMj1tfw/cXKW0npE39Iib4uG8D4SxWa2BZHf4Snut5VYSavaWlYXXw93jYM
t1z1moaGY3XmPnE02d436ae4SWwlY/4qt1oe26CbYfySBQaB2kdpy28bIegzs0Sh9cac0nt1JfQF
NpFiw0aC08r03VTUKgPRa+1HIedOadfFP4D41iNKi/WbHawG3JoseWpySpdhxaTG6bfPGoifCA98
bccUZARFU/EpLXTvzzFLz4WqJ/Me1Ixqni7+t/J+SzUOAaRsnErJA/V5PEevK/AqUBi8cbqwzNvV
0cHlzLejJ8Y23dI+KzWO+6IFP7/52DQ+bm1t7Sp6achSLSB8AfDdj/04GxzC4VhCWdsEIzSj/bjj
2NV2EM+z5amtaskzHupYCC8IPBAML91KRVZTemRwSNjL79ntbxz6UgFFv7vuYGLNBrZu8l04I0NZ
3jAhnRP4qNcpevb9uPTeP36eheYhVYIJyzotW41GZH7fiPGphNALBw4YFL0GWOlUS7HByYezpvVL
9GPpoYUOVUKDeGuFcWPGtr8Gz0++kgJJtpJGMbt0JRqj2HypSknMFeok1diN2ROvShKyS2jaC6mf
qKMU15Glj2JCUpWc5/T6LvJRfBJaupDui7xpOXjJ8voHBiokTy9+Zw3kRpYVUJ7nBuCZgwTXsj5r
UuT4W67HqSE3sGD3BbzlyPF1/d4RT7UYJSwrsb0PbDA2BoEgTQay4qhr2Pj0ad6VJqx8CEKNWghR
V2Pgw0F4R7n2h6MWRWz76Pv+nqZUOuCivoDFEjl499JXuBTnFOsg5j+ApkwPotWFX8XHcJC4iy7K
5EZ+1NedIblad8hfzOmZuJk4A6HkLoHKaT8YLI4mcQBHUFd9DQvHQ1Bop5h4J6S5+lK9sNHe7ztG
8W/5hlvtHPf+wTJTGlwnEZ3OP3v2Cf2Vf3NKZW4aOAxn76q5uM4JRtez6LTVlWfCSpjC5MiR9jUf
O3lujGEw7AkZQJ7sBlizd0MPS2imjtacde1c2pqt6UhtxgZFfOXo0MNCyntHCdEzmE0E2UgkzHPu
BBZh2t1dhLsRDvIoA5xNeBzUUDRAxnh2TUjbJyyF9N4LaIVtazvy42lPg/Qe0NdGa1+TFY7XoYLt
zQ1y4ZHMpkegDy+dx5QGrE6cacW29dqC0uWLxxebwCYKW22Qy713Q1Z+OxrPEn4ZiokXw9kI/ysB
17R7QLZmn2rZEO4qW7EEwMbEo8oSo9z2AyGBxG5hJ4pjL+8kjcAvz22RrGHYtJh+u6RzKS6eL7er
5HsEzHaxSPklpKCLyOVLeHznYXDcDX9AqfDgMzQtTiEvey7clNY9d1E6DRHsoPpbQPc2N2V4+vq+
3JhtOHXAZDJEWaUNDhsLbyQLoykMTitb5YAFNFSimZZZNCBAqyKHO6/xaBwGN4mBgCgr48hlCHvj
AOzKrt61gjBJC6F4rq9nvJEm6P3UZferrPV+cRsQMZ17CwJq6crVdoDCd7GCU+fEJOmVw0nLQmwk
UXHeJgsVj3vETCvEh1tmm8xajR/E4PK4H7LHW3tlyJEtBs95Z4irkUu5x2wO7iaSyzkVsIpHeuvt
435/R0qbU0wigSz1bimSJIRP6usKL027iuGYcirwCzIu5HydAMK7OodPZnoceCtO/NvsdHKH/4Aq
8dshUPxHPr0rcvKtRVL6+0GK61esbgYwZc/222E9pMhov5U5hlIARWYh5JpUVlTZqp/R+grrzYsy
lQYzD5wjaMvuPUtepHk4nlroUWdN6y/e8aK4lsIIbmyufKZ3OmDgM7uPfFz5tYgJ7AyoCoT3fBkd
kN22b96pWPLx59d6PnalMiGiQ7TcMfJPC1W84flNq6dzK5azld9iPxlPexveAkRBkRL028ZBcY03
xzu38Dd8fB2rsUJMNHJNuzoloLN+2ezvebsf8qX/dEwVpKtdXNWqUH6I3azKHbIXsMYx6cyQu9hj
tWJsq8e3Nl5fW10KKag3ut3SsPWS8b1Ebo7iuV3PbiH10jQlYJqp8zfXQvV9vZBoC8GMGZKWjYof
mL5i5eTIEWXNiRDtrBkR/mOHSaK5oJM0BCTP0Y1oeBI3GRe6zqBC0WNqBWPEFdRPtEaWPCLgETgi
riq/EI3/fWglqCXBE7SdQzivgWXFU1g4IrTdpRwIB8sFACToDKL9hyReGdIS3plKsrxOFU079C0k
mY+b/sgGhWfbW7KocWKan6yh316yaNfvEBlLWD7KL8pHT/E1+JyKXKufZ8eM/HP251wfKaE25Q/d
rJxv5tZ+wLNndOBOlH/aN86yeCkuo1qPHufM6uH5VQIHtvw93R+L+fLkvCWECh5g8jQA9X2J9AJo
0g7PR5E7bmLILN8i5TvB+HadLv/uOgm2Fs4AmXc+vQ3VyavBAlLyqKRxc6lQB5KCkHhF1QG7j+xN
t24+OEV3mKi9auJvF++2vkiEySOkQdjxd5h5kWtTTLmq3dp+cgQLobBmCr9UKDWbEKnkXzZ/TqN/
2g+LBu1d8G6WBIg79hSFFahLw/+2lqtAplXKGSf0WWgUIZqPAU588YsGxHUY8bYjzjCxA++C3gIj
BjkF8+wcJLX/A8fAU945Fnb7HYvCq6CRMFQcYDKbxsnYTP1K0LcTlYpGAykLuFUB6JPrZzXQP2hm
ZTU9h+4FGsm/pvFu7QxAz+tG6H1GGPU5zS/omBppiRfATWo4ChZfUKCrhsYTZssFPVjq8Fph7CUq
+8ObqkZ/EGGn3nhWPmN0am4mDBB0ijz27jWa1jx0AmzTRmC96Uotkwhs4oio8G6OABQtahMohOvD
2SBgCLnskbsKqVCC2Z3pwK9xGt7DgrAF7m+G0TXrFbMbI/DEs9Q00qkNVZIJcahljul08Nb1QQsE
Oa9pyiBpvnvYhW3BG2JuG+kBjjU4sTgpueMEWyC7cosD9iJCfanT05rgSxqp6v8IPUcT5sZpf0oS
6vkSEm2kwvR4wD+08kS1i7Eh14vGUgDgr7vlq8dTX1tnii25HSqqufZkkriUHIF2VELlDP/zyuL7
cY0k3B6dTDnNOVMe2+o6aTaY8Q6Zr+iZnXfnNolw7UMYx3mEPKrnQxRcMyyv40QVNjR1Le5prm1X
HoRyUNegO/lkc4Ydg6iIxT8Fg+v0TDK6CmviEd3/2W+lvdePOxeQzBafDqCIEi8GYxEKCgh3pkDo
cmsLb69tdIddNE8P29qh5HK7hmuOpe9e44lB6DiJkky8wOeQg7rW4UaGa2k5kTi5EbT5nVqViFyB
Hp84z5HMjyF0Cw2BBIexF75aopB/t3BSDR1etkuf7WnUe7vJxAi6FRKP0+azUkXPYgWIdbmeciPd
zAlWG8UYQe4k0mgpRmYvJ5vgiFyAPk0ROKxQnhO+liinkwndfh+RUt0sTh2RR2wUsrCyZgzCBn5+
cHYh6dj1JX/qqm6qYn79P7X1Kuia1+rMpCOu1l8RL3094MdROZ508jOGS0x4sEM/ysvlOpSPw2j1
3qwmevh3m6n797lwqY2Zja4KL5g7Mznp2wQjHZYhfaLKn3zrIjoIPcIVgCtW3o++jeQOBP5er3io
AA72GkkjU3VmoCZCTbBVGc7OUZusxjBnlCvW1WdYpE9w42WSG47jlDn3OsccKvGDKNmOyxLDWXfy
btJJj1scpAB+jWMQbB1kL6JHciRLVn4izvsAd1VozQWDwOXIECBZQ6kIzjQ1NDT5aMT9GgriX4x3
VcWmmsDu1brJxOiAv8/nEOTcSzkV68Uganx1hQNm1UK/zHt99zvuw5p60PWAk+3zQrWXB+nhKCBn
8x1TVDrjVPrdK6zb20Q6gPUHsrEkXriI6dB3Nxq7QRELimY91oimL4jol9Km4RQiUdSN10RWB7Sp
W68jmgV6k5xuYx5haeC6ihliTYsVNY+c0bcRRuIumZcyGlft0dwQXmyvs/jKI9yh1Guinn6P00ni
Vh6Ui1Kt1CwYheBh8HhV/QoAaz71eY2RsBzlsGqUKxbSTfwGSDNLKmxSa93myX8XXTufZSKvwLh/
9cSuf5gRvm83t38OPncAfxBRsIWA2ziXhvzNXHFHt6yBvpNoglAzwRXwTH96LBRPa/KdpSCMJk2z
luxC4Fdcm3lRsa7cmb+47sV/kglJ7trijpS36KiQuGu8PmR1+lkTrIvQZLkD3Ff4020PfGVXSyCr
7XNJCkFgcIx0/W1Y2e+j8fMFYiaeVoZ8OwDik9/CbTpWXLRBTqtEi9AQtVi1DWSFf13/sL9mNs51
9Sce/ziZOBFzZBgydwDaWiAvGkpXreUK5kYQxoDeoOmTAm1J8uT1snb3ErjwfYnXvlu/viUPTbCC
AV56gw52W2IqiKjvkV5bzOgbg3rHxKQ5xvZPpX6Wdfe9HmO5vhebmE8r1CDGYod5CWaxa1m+UADw
8mjHJ9FO8OvaEbVaEe3jEcsznFZ70Rt2J1lyqVaT0Q2Z/J8geDcYqLwCsVFHremyuBtAnxAGEm34
Yc6YTAnRSSX4ankEmEc+MYWsqkbjZsetZcVLsqvjh0o5aDAp/zkHJGMT0pIhGOk68MH/xie/67Cg
8OKnFIsrOQsLLLt+8KCA2/PNO4MUWNfgLQwJAMnFjT856CbSdzZZeAzBcn6jY2MSw77i/frP6tfI
12gY16IjEWZTmCTxtqW85xBV6E2Fe4re/3foCUUzlwknitwgnR7Za1+8zKdbVr8nDcz0Pyl8g2/7
5j/ugdB4lbGkQnOZIQ+OL+UqHK64TDX2WyAN6omXPCV5Ftnttd50dB/tRYRR4E6Rr0Un7DbyMfaX
/hLbTJ72Tzy96LMvyF3HGHmzxroaVqyP/EY0EpJj3Wt0nOcfW0NzBW+XXTUfeurAMjK1gOpj2gPH
HREb9ZlOvCTmlbg032bhOBnF5YY6Z+CezoXQDZN/844Zl7/uupg9rrH7bMNfEVUKOFs0kWabz+Xz
M1z/Lr5tU60PeMXj9zy2JZMIe2F5UQaixvdNoix5+TcSfghNa6vueDeXK3yTpzmAefee0qm+W7hz
mIItLeim/N/GmQlrLqnUOCzfA7XjS/MrbeOv2nUMwStEcaiVp5EfqKe1WZfYepdifUYF61zjUY6E
G4I6rrsgaxSnDmVM3LtgLQaY9V5Wu1oA8TuJwr34w4GYdOdpjOkmSB04KszRbq+kEfLMxHeqjbtZ
Z11N524v6mDuxhIGc6dTvF/5oi8nAcKL3GnvykdHCau58RoalO59taZtCTVGwQkPmA4xvLXMECvH
0Le5QSeN6C2Qp4D0nte0FQPeIB3CFZTOzjjaePHQyPVIvhan2FlcmRv1EoqiQAFOV9/EmqDfjWQs
1T1pPGmjtUHbHzKbpxBIekjtisK9JtnZADvCvw3zNhkQJu/sjx7FBn52p4OrWdq5S+fYXhx/g7vb
y7RJLWJOzDzDe7T2Zupu9+4mdRjA4F+dNSc0lJ7SqDs536BWnH5ZKEDd97gFEFqjMk6/LytiL9cz
EsgedOaY9L6qh0DpKF6uiPIta63cOjKssyo6rsDvRLsKceh3SRSal2E4TJA7/zm/pafsrgRRCBIf
sZHHYbbAUzmFelxIs+Vz6/de9dNexuSWXA4K5e8d3A/TmDRv10YmPDIr17FN1SLhCHTb0qSDAzcp
ch0F6mkzfSqhQ46EH7hqxsmVEhYuiJBr77Na8AUq17djb3UbIm4yHWsqq9RkBRNs4Vgm2NYKb2Sf
LUrWDPRc8Ip3MhOwo/7tmYBFk+NMzmxCz/veWmeLc/bWAyoxu5Hjj/B1c5wuSCjd6qG6V6nONzVo
/H3MF+Aykx9jQ7yc53CANFtddN3Ff9ohXQi8V2cuXgVSQUcQk/ygLrqyQfcpz4iqwkxhGt+5eyUo
bcEB6Ep1ZAogDASubGlVZRnYIyzimgteuGAcEpKW2qr1RH/qXjWe1gFZey+CVSTMSzuoCZ5JSt/L
rueFXrW55JlWUT0SYUnyjyz/b82U5sTwwb9QD2rUIbWg2KPsB93z9C7kXuzg/DcoPO4HYRY+y70L
4PIjNvkXSMRLywCdX6V0w1p4Rnb2a9bt9K33fgGWRH5bu2F8xeETrRnStK0Z9KIgH+vsyjifMUzA
ls7toSbA80z/2i/m0zsrV004lK1cqvb4KesZ4+T3x860IeX6RFmst6qFurOeD0QqZAAIvitxCQ7F
NJHunY55fUVqoF4bZ47JpZO1MFnp2hr/QSVDvi9tR7uok/bBp4/vuk1nJhbkFRXVcYwYRE2SbgO9
DhLsna5p8O8oRQ7VJAHhNBwfBh9qNIRzRoSLSM//qMZ9shvLlpclswC51geYDmZw1RpZMp5R/919
1sEIG06LESpV6SK3GHsUoORRSi++FBBjiBhsYfEtXBXjhL7GGRW5q6rWJOFC69MlCLL9GqExeiUa
lXHnQ8ru5oWWRz/eSuopd9p2/t7Tu6lbSEJekjr5bVRxn6KsiGOo915nuSpzd4mFLkOJpYAqXgPX
fwNuiH2s2ila+XnRbaX+nB4uPkTb0aBgzwfVU3l1GRVEaxC11qpkcrzTFNol0NoX14NgzMynVwVv
a7KHfv6QrQoejyspsN01JZHDvdbG9JzyTgZjn6N9IDNa55fLKP/fgGxg6ij2woFHIJf7hCt2/ay9
PSmdsao2ADaIABCTFlfRE6DOkGl0EXo4MzEUM9AJCNMMAhafylq70qWNnsf646F7CK/9NBb8wI59
7B1RXOlFOVuMJ6pTapQW+CpIKMFY4fOgqJ6n5QliEYLgSwqUnHG901C8UOFrsX+FlXJrCeagJ1Ba
my5xa9E8RegktCFCOEqeJQCJlQVscIAvqIzfUiKTbsXKKCWyBjXWHv2QORTXn58yhlDEEYX0QEB5
xlvfIOZjYOpezx3PurqiPRmrWCBWI9xDH4VAIKHGw511uhSFvh+3K/Oa9xiPinI0azp1kH6UKkoN
4Xm+HNgmYSZXh3Hpy0o/g0/k/hEeU41bh7HUI5gLF/3CQNMleosiJHrlijFGexJjRvxmn/fGHtTq
/dk1z8ViVPa2mICBIe6YqyMWIka4p/s8aPbf+VsOVquWeqWbbqHQM5KwN0jOCzdN/FCbaotL2yeQ
qOvzLYQgp4AhxL1SWEVX6RGarbOsCCfLgQDF9/43TXjn4jNj5C61gnHLIjRhH4I2C+ba38pqPVN7
1VBdSqJxkO3clwHDvbeMa0UEjiGp/sWXgcIuVXyN+T0nD7RWvk4eCqMT4sD8HHZbJHCv2WyRRxmC
eyq69GAjbg5jEjQe9ac79MV5vU/op1f+rGIKLzXLfejNSQKKTkqrkfvBe++HJ47yf9jX3peRt5TN
/gj/Uv/1gWwi9VHTCw1TkGCayCHCWbry9HZHyKya1IcKheh3v45+Md/JqGtpjVWVn7s7+bHJtyeU
0asl5qF3u1Ae2aKQGe5NPD+j3cLRA4CFyjMc14H5Q2YWPLS6upgDMa/nuTYV5ccBO1t4deZlWGib
KDY5ez90cMUMGZ1CnzKp2SFwP8RPkQSi47jOUkdW+9RrIP1kxTBncpFXz7C0Jar+CW/qRfTKZOSc
7qtNiPlOW4z/wTv/GGmqtt6hPhWvVRiMjwds3b5vtRL2/phE2Nbw6p+IeI6lxEtYPgp+grR0Q82U
qMB/6tr5RbHbHcXUp71LZvgWMSBVRMOV+iWNAb4c6dVM87NlU7Ovr4IehsGSzPkAi2UaCbFNpVXi
rNu8USBhS3Ct2eys+YLZ3GV1ykDkzRGIVejpZrXieIH6+02gBbJ7cL97ahWau4k1n9yKB426LYMQ
kDABJzZ54/TaaA1lDcLDdo67AqeKDSphOBOxWie6Nm2dwFkN2XnExbJlWKktVlHVDWrC1fv9A8HR
BI+5qJDoWnminMGsJ7IP
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
