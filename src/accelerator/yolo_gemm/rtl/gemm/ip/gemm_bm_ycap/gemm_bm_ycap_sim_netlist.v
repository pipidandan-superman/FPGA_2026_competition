// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Oct  7 11:46:16 2026
// Host        : HC-202510241838 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/competition/12_yolo_accel/yolo_gemm/rtl/gemm/ip/gemm_bm_ycap/gemm_bm_ycap_sim_netlist.v
// Design      : gemm_bm_ycap
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg484-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "gemm_bm_ycap,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module gemm_bm_ycap
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
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [6:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [7:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [6:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [7:0]doutb;

  wire [6:0]addra;
  wire [6:0]addrb;
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
  wire [6:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [6:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [7:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "7" *) 
  (* C_ADDRB_WIDTH = "7" *) 
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
  (* C_INIT_FILE = "gemm_bm_ycap.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "1" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "128" *) 
  (* C_READ_DEPTH_B = "128" *) 
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
  (* C_WRITE_DEPTH_A = "128" *) 
  (* C_WRITE_DEPTH_B = "128" *) 
  (* C_WRITE_MODE_A = "NO_CHANGE" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "8" *) 
  (* C_WRITE_WIDTH_B = "8" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  gemm_bm_ycap_blk_mem_gen_v8_4_12 U0
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
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[6:0]),
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
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[6:0]),
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21840)
`pragma protect data_block
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
YnpTs2SWBX06
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
