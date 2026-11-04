// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:47:12 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/competition/12_yolo_accel/yolo_gemm/rtl/gemm/ip/gemm_bm_lut/gemm_bm_lut_sim_netlist.v
// Design      : gemm_bm_lut
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "gemm_bm_lut,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module gemm_bm_lut
   (clka,
    ena,
    wea,
    addra,
    dina,
    clkb,
    enb,
    addrb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_mode = "slave BRAM_PORTA" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [0:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [7:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [7:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [7:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [7:0]doutb;

  wire [7:0]addra;
  wire [7:0]addrb;
  wire clka;
  wire clkb;
  wire [7:0]dina;
  wire [7:0]doutb;
  wire ena;
  wire enb;
  wire [0:0]wea;
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
  wire [7:0]NLW_U0_douta_UNCONNECTED;
  wire [7:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [7:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [7:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "8" *) 
  (* C_ADDRB_WIDTH = "8" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "1" *) 
  (* C_COUNT_36K_BRAM = "0" *) 
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
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     2.68455 mW" *) 
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
  (* C_INIT_FILE = "gemm_bm_lut.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "1" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "256" *) 
  (* C_READ_DEPTH_B = "256" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "8" *) 
  (* C_READ_WIDTH_B = "8" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "0" *) 
  (* C_USE_BYTE_WEB = "0" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "1" *) 
  (* C_WEB_WIDTH = "1" *) 
  (* C_WRITE_DEPTH_A = "256" *) 
  (* C_WRITE_DEPTH_B = "256" *) 
  (* C_WRITE_MODE_A = "NO_CHANGE" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "8" *) 
  (* C_WRITE_WIDTH_B = "8" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  gemm_bm_lut_blk_mem_gen_v8_4_12 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(clkb),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(NLW_U0_douta_UNCONNECTED[7:0]),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(enb),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[7:0]),
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
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[7:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[7:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb(1'b0),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(1'b0));
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21904)
`pragma protect data_block
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
tVH2EMglzjuCjcj0Zz4yBg==
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
