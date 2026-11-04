`timescale 1ns/1ps
// Double-buffered human-pose skeleton OSD. Display-only; no inference logic.
module task_pose_osd #(
    parameter H_SIZE=640, parameter V_SIZE=480, parameter MAX_PEOPLE=2
)(
    input wire vio_clk,input wire sys_rst_n,input wire vio_active,
    input wire vio_hsync,input wire vio_vsync,input wire [23:0] vio_data,
    output reg [23:0] hdmi_data,output reg hdmi_de,output reg hdmi_hsync,output reg hdmi_vsync,
    input wire aclk,input wire aresetn,
    input wire [11:0] s_axi_awaddr,input wire [2:0] s_axi_awprot,input wire s_axi_awvalid,output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,
    input wire [11:0] s_axi_araddr,input wire [2:0] s_axi_arprot,input wire s_axi_arvalid,output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready
);
    localparam [1:0] RESP_OKAY=2'd0,RESP_SLVERR=2'd2;
    localparam [2:0] ST_CLEAR=0,ST_SETUP=1,ST_DRAW=2,ST_POINTS=3,ST_READY=4;
    wire wr_valid,wr_rsp_ready,rd_valid,rd_rsp_ready;
    wire [11:0] wr_addr,rd_addr; wire [31:0] wr_data; wire [3:0] wr_strb;
    reg wr_ready,wr_rsp_valid,rd_ready,rd_rsp_valid; reg [1:0] wr_rsp,rd_rsp; reg [31:0] rd_data;
    axi_lite_slave u_shell(
        .clk(aclk),.resetn(aresetn),.s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
        .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_addr(wr_addr),.wr_data(wr_data),.wr_strb(wr_strb),
        .wr_rsp_valid(wr_rsp_valid),.wr_rsp_ready(wr_rsp_ready),.wr_rsp(wr_rsp),
        .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_addr(rd_addr),.rd_rsp_valid(rd_rsp_valid),
        .rd_rsp_ready(rd_rsp_ready),.rd_data(rd_data),.rd_rsp(rd_rsp));

    reg [1:0] mode_reg,shadow_mode;
    reg [1:0] count_reg,shadow_count;
    reg [9:0] desc_l[0:1],desc_r[0:1],desc_t[0:1],desc_b[0:1];
    reg [7:0] desc_score[0:1];
    reg [9:0] desc_x[0:33],desc_y[0:33];
    reg [7:0] desc_conf[0:33];
    reg [9:0] shadow_l[0:1],shadow_r[0:1],shadow_t[0:1],shadow_b[0:1];
    reg [7:0] shadow_score[0:1];
    reg [9:0] shadow_x[0:33],shadow_y[0:33];
    reg [7:0] shadow_conf[0:33];
    wire [8:0] kp_local_addr=wr_addr[8:0]-(wr_addr[9]?9'h254:9'h054);
    integer i;
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            wr_ready<=0;wr_rsp_valid<=0;wr_rsp<=RESP_OKAY;mode_reg<=1;shadow_mode<=1;count_reg<=0;shadow_count<=0;
            for(i=0;i<2;i=i+1) begin
                desc_l[i]<=0;desc_r[i]<=0;desc_t[i]<=0;desc_b[i]<=0;desc_score[i]<=0;
                shadow_l[i]<=0;shadow_r[i]<=0;shadow_t[i]<=0;shadow_b[i]<=0;shadow_score[i]<=0;
            end
            for(i=0;i<34;i=i+1) begin desc_x[i]<=0;desc_y[i]<=0;desc_conf[i]<=0;shadow_x[i]<=0;shadow_y[i]<=0;shadow_conf[i]<=0;end
        end else begin
            if(!wr_rsp_valid) wr_ready<=1;
            if(wr_rsp_valid && wr_rsp_ready) begin wr_rsp_valid<=0;wr_ready<=1;end
            if(wr_valid && wr_ready) begin
                wr_ready<=0;wr_rsp_valid<=1;wr_rsp<=RESP_OKAY;
                case(wr_addr)
                    12'h008:if(wr_strb[0]) mode_reg<=wr_data[1:0];
                    12'h00c:if(wr_strb[0]) count_reg<=wr_data[1:0];
                    12'h014:if(wr_strb[0]) begin
                        shadow_mode<=mode_reg;shadow_count<=count_reg;
                        for(i=0;i<2;i=i+1) begin
                            shadow_l[i]<=desc_l[i];shadow_r[i]<=desc_r[i];shadow_t[i]<=desc_t[i];shadow_b[i]<=desc_b[i];shadow_score[i]<=desc_score[i];
                        end
                        for(i=0;i<34;i=i+1) begin shadow_x[i]<=desc_x[i];shadow_y[i]<=desc_y[i];shadow_conf[i]<=desc_conf[i];end
                    end
                    default: begin
                        if(wr_addr>=12'h040 && wr_addr<12'h440) begin
                            if(wr_addr[7:0]>=8'h40 && wr_addr[7:0]<=8'h50) begin
                                case(wr_addr[5:0])
                                    6'h00:if(wr_strb[0]) desc_l[wr_addr[9]]<=wr_data[9:0];
                                    6'h04:if(wr_strb[0]) desc_r[wr_addr[9]]<=wr_data[9:0];
                                    6'h08:if(wr_strb[0]) desc_t[wr_addr[9]]<=wr_data[9:0];
                                    6'h0c:if(wr_strb[0]) desc_b[wr_addr[9]]<=wr_data[9:0];
                                    6'h10:if(wr_strb[0]) desc_score[wr_addr[9]]<=wr_data[7:0];
                                    default:wr_rsp<=RESP_SLVERR;
                                endcase
                            end else begin
                                case(kp_local_addr)
                                    9'h000:if(wr_strb[0]) desc_x[wr_addr[9]*17+0]<=wr_data[9:0];
                                    9'h004:if(wr_strb[0]) desc_y[wr_addr[9]*17+0]<=wr_data[9:0];
                                    9'h008:if(wr_strb[0]) desc_conf[wr_addr[9]*17+0]<=wr_data[7:0];
                                    9'h00c:if(wr_strb[0]) desc_x[wr_addr[9]*17+1]<=wr_data[9:0];
                                    9'h010:if(wr_strb[0]) desc_y[wr_addr[9]*17+1]<=wr_data[9:0];
                                    9'h014:if(wr_strb[0]) desc_conf[wr_addr[9]*17+1]<=wr_data[7:0];
                                    9'h018:if(wr_strb[0]) desc_x[wr_addr[9]*17+2]<=wr_data[9:0];
                                    9'h01c:if(wr_strb[0]) desc_y[wr_addr[9]*17+2]<=wr_data[9:0];
                                    9'h020:if(wr_strb[0]) desc_conf[wr_addr[9]*17+2]<=wr_data[7:0];
                                    9'h024:if(wr_strb[0]) desc_x[wr_addr[9]*17+3]<=wr_data[9:0];
                                    9'h028:if(wr_strb[0]) desc_y[wr_addr[9]*17+3]<=wr_data[9:0];
                                    9'h02c:if(wr_strb[0]) desc_conf[wr_addr[9]*17+3]<=wr_data[7:0];
                                    9'h030:if(wr_strb[0]) desc_x[wr_addr[9]*17+4]<=wr_data[9:0];
                                    9'h034:if(wr_strb[0]) desc_y[wr_addr[9]*17+4]<=wr_data[9:0];
                                    9'h038:if(wr_strb[0]) desc_conf[wr_addr[9]*17+4]<=wr_data[7:0];
                                    9'h03c:if(wr_strb[0]) desc_x[wr_addr[9]*17+5]<=wr_data[9:0];
                                    9'h040:if(wr_strb[0]) desc_y[wr_addr[9]*17+5]<=wr_data[9:0];
                                    9'h044:if(wr_strb[0]) desc_conf[wr_addr[9]*17+5]<=wr_data[7:0];
                                    9'h048:if(wr_strb[0]) desc_x[wr_addr[9]*17+6]<=wr_data[9:0];
                                    9'h04c:if(wr_strb[0]) desc_y[wr_addr[9]*17+6]<=wr_data[9:0];
                                    9'h050:if(wr_strb[0]) desc_conf[wr_addr[9]*17+6]<=wr_data[7:0];
                                    9'h054:if(wr_strb[0]) desc_x[wr_addr[9]*17+7]<=wr_data[9:0];
                                    9'h058:if(wr_strb[0]) desc_y[wr_addr[9]*17+7]<=wr_data[9:0];
                                    9'h05c:if(wr_strb[0]) desc_conf[wr_addr[9]*17+7]<=wr_data[7:0];
                                    9'h060:if(wr_strb[0]) desc_x[wr_addr[9]*17+8]<=wr_data[9:0];
                                    9'h064:if(wr_strb[0]) desc_y[wr_addr[9]*17+8]<=wr_data[9:0];
                                    9'h068:if(wr_strb[0]) desc_conf[wr_addr[9]*17+8]<=wr_data[7:0];
                                    9'h06c:if(wr_strb[0]) desc_x[wr_addr[9]*17+9]<=wr_data[9:0];
                                    9'h070:if(wr_strb[0]) desc_y[wr_addr[9]*17+9]<=wr_data[9:0];
                                    9'h074:if(wr_strb[0]) desc_conf[wr_addr[9]*17+9]<=wr_data[7:0];
                                    9'h078:if(wr_strb[0]) desc_x[wr_addr[9]*17+10]<=wr_data[9:0];
                                    9'h07c:if(wr_strb[0]) desc_y[wr_addr[9]*17+10]<=wr_data[9:0];
                                    9'h080:if(wr_strb[0]) desc_conf[wr_addr[9]*17+10]<=wr_data[7:0];
                                    9'h084:if(wr_strb[0]) desc_x[wr_addr[9]*17+11]<=wr_data[9:0];
                                    9'h088:if(wr_strb[0]) desc_y[wr_addr[9]*17+11]<=wr_data[9:0];
                                    9'h08c:if(wr_strb[0]) desc_conf[wr_addr[9]*17+11]<=wr_data[7:0];
                                    9'h090:if(wr_strb[0]) desc_x[wr_addr[9]*17+12]<=wr_data[9:0];
                                    9'h094:if(wr_strb[0]) desc_y[wr_addr[9]*17+12]<=wr_data[9:0];
                                    9'h098:if(wr_strb[0]) desc_conf[wr_addr[9]*17+12]<=wr_data[7:0];
                                    9'h09c:if(wr_strb[0]) desc_x[wr_addr[9]*17+13]<=wr_data[9:0];
                                    9'h0a0:if(wr_strb[0]) desc_y[wr_addr[9]*17+13]<=wr_data[9:0];
                                    9'h0a4:if(wr_strb[0]) desc_conf[wr_addr[9]*17+13]<=wr_data[7:0];
                                    9'h0a8:if(wr_strb[0]) desc_x[wr_addr[9]*17+14]<=wr_data[9:0];
                                    9'h0ac:if(wr_strb[0]) desc_y[wr_addr[9]*17+14]<=wr_data[9:0];
                                    9'h0b0:if(wr_strb[0]) desc_conf[wr_addr[9]*17+14]<=wr_data[7:0];
                                    9'h0b4:if(wr_strb[0]) desc_x[wr_addr[9]*17+15]<=wr_data[9:0];
                                    9'h0b8:if(wr_strb[0]) desc_y[wr_addr[9]*17+15]<=wr_data[9:0];
                                    9'h0bc:if(wr_strb[0]) desc_conf[wr_addr[9]*17+15]<=wr_data[7:0];
                                    9'h0c0:if(wr_strb[0]) desc_x[wr_addr[9]*17+16]<=wr_data[9:0];
                                    9'h0c4:if(wr_strb[0]) desc_y[wr_addr[9]*17+16]<=wr_data[9:0];
                                    9'h0c8:if(wr_strb[0]) desc_conf[wr_addr[9]*17+16]<=wr_data[7:0];
                                    default:wr_rsp<=RESP_SLVERR;
                                endcase
                            end
                        end else wr_rsp<=RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    (* ram_style="block" *) reg [1:0] bank0[0:H_SIZE*V_SIZE-1];
    (* ram_style="block" *) reg [1:0] bank1[0:H_SIZE*V_SIZE-1];
    reg drawing_bank,display_bank,bank_ready;
    reg [2:0] state;
    // Descriptor CDC and coherent frame capture.
    reg [1:0] sync0_mode,sync1_mode,sync0_count,sync1_count;
    reg [9:0] sync0_l[0:1],sync0_r[0:1],sync0_t[0:1],sync0_b[0:1],sync1_l[0:1],sync1_r[0:1],sync1_t[0:1],sync1_b[0:1];
    reg [7:0] sync0_score[0:1],sync1_score[0:1];
    reg [9:0] sync0_x[0:33],sync0_y[0:33],sync1_x[0:33],sync1_y[0:33];
    reg [7:0] sync0_conf[0:33],sync1_conf[0:33];
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            sync0_mode<=1;sync1_mode<=1;sync0_count<=0;sync1_count<=0;
            for(i=0;i<2;i=i+1) begin
                sync0_l[i]<=0;sync0_r[i]<=0;sync0_t[i]<=0;sync0_b[i]<=0;sync0_score[i]<=0;
                sync1_l[i]<=0;sync1_r[i]<=0;sync1_t[i]<=0;sync1_b[i]<=0;sync1_score[i]<=0;
            end
            for(i=0;i<34;i=i+1) begin sync0_x[i]<=0;sync0_y[i]<=0;sync0_conf[i]<=0;sync1_x[i]<=0;sync1_y[i]<=0;sync1_conf[i]<=0;end
        end else begin
            sync0_mode<=shadow_mode;sync1_mode<=sync0_mode;sync0_count<=shadow_count;sync1_count<=sync0_count;
            for(i=0;i<2;i=i+1) begin
                sync0_l[i]<=shadow_l[i];sync1_l[i]<=sync0_l[i];sync0_r[i]<=shadow_r[i];sync1_r[i]<=sync0_r[i];
                sync0_t[i]<=shadow_t[i];sync1_t[i]<=sync0_t[i];sync0_b[i]<=shadow_b[i];sync1_b[i]<=sync0_b[i];
                sync0_score[i]<=shadow_score[i];sync1_score[i]<=sync0_score[i];
            end
            for(i=0;i<34;i=i+1) begin sync0_x[i]<=shadow_x[i];sync1_x[i]<=sync0_x[i];sync0_y[i]<=shadow_y[i];sync1_y[i]<=sync0_y[i];sync0_conf[i]<=shadow_conf[i];sync1_conf[i]<=sync0_conf[i];end
        end
    end

    reg [1:0] draw_mode,draw_count;
    reg [9:0] draw_l[0:1],draw_r[0:1],draw_t[0:1],draw_b[0:1];
    reg [7:0] draw_score[0:1];
    reg [9:0] draw_x[0:33],draw_y[0:33];
    reg [7:0] draw_conf[0:33];
    reg [9:0] h_cnt,v_cnt;
    reg [18:0] clear_addr;
    reg [5:0] line_idx;
    reg [4:0] point_idx;
    reg [3:0] point_sub;
    reg signed [15:0] x0,y0,x1,y1,dx,dy,sx,sy,err,e2;
    reg major;
    reg signed [15:0] acc;
    reg frame_armed;
    reg [4:0] edge_a,edge_b;
    reg [5:0] point_a,point_b;
    reg signed [15:0] edge_dx,edge_dy;

    // Nineteen display connections over the seventeen COCO keypoints.
    always @* begin
        edge_a=0;edge_b=0;
        case(line_idx%19)
            0:begin edge_a=0;edge_b=1;end
            1:begin edge_a=0;edge_b=2;end
            2:begin edge_a=1;edge_b=3;end
            3:begin edge_a=2;edge_b=4;end
            4:begin edge_a=0;edge_b=5;end
            5:begin edge_a=0;edge_b=6;end
            6:begin edge_a=5;edge_b=6;end
            7:begin edge_a=5;edge_b=7;end
            8:begin edge_a=7;edge_b=9;end
            9:begin edge_a=6;edge_b=8;end
            10:begin edge_a=8;edge_b=10;end
            11:begin edge_a=5;edge_b=11;end
            12:begin edge_a=6;edge_b=12;end
            13:begin edge_a=11;edge_b=12;end
            14:begin edge_a=11;edge_b=13;end
            15:begin edge_a=13;edge_b=15;end
            16:begin edge_a=12;edge_b=14;end
            17:begin edge_a=14;edge_b=16;end
            18:begin edge_a=11;edge_b=12;end
            default:begin edge_a=0;edge_b=0;end
        endcase
        point_a=((line_idx>=19)?6'd17:6'd0)+edge_a;
        point_b=((line_idx>=19)?6'd17:6'd0)+edge_b;
        if(draw_x[point_b]>=draw_x[point_a]) edge_dx=draw_x[point_b]-draw_x[point_a];
        else edge_dx=draw_x[point_a]-draw_x[point_b];
        if(draw_y[point_b]>=draw_y[point_a]) edge_dy=draw_y[point_b]-draw_y[point_a];
        else edge_dy=draw_y[point_a]-draw_y[point_b];
    end

    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            h_cnt<=0;v_cnt<=0;draw_mode<=1;draw_count<=0;drawing_bank<=0;display_bank<=0;bank_ready<=0;frame_armed<=0;
            state<=ST_READY;clear_addr<=0;line_idx<=0;point_idx<=0;point_sub<=0;
            x0<=0;y0<=0;x1<=0;y1<=0;dx<=0;dy<=0;sx<=0;sy<=0;err<=0;e2<=0;major<=0;acc<=0;
            for(i=0;i<2;i=i+1) begin draw_l[i]<=0;draw_r[i]<=0;draw_t[i]<=0;draw_b[i]<=0;draw_score[i]<=0;end
            for(i=0;i<34;i=i+1) begin draw_x[i]<=0;draw_y[i]<=0;draw_conf[i]<=0;end
        end else begin
            if(!vio_hsync) h_cnt<=0;else if(vio_active) h_cnt<=(h_cnt>=H_SIZE-1)?0:h_cnt+1;else h_cnt<=0;
            if(!vio_vsync) v_cnt<=0;else if(h_cnt==H_SIZE-1 && vio_active) v_cnt<=(v_cnt>=V_SIZE-1)?0:v_cnt+1;
            if(!vio_vsync) frame_armed<=1;
            if(vio_active && frame_armed) begin
                frame_armed<=0;
                draw_mode<=sync1_mode;draw_count<=sync1_count;
                for(i=0;i<2;i=i+1) begin draw_l[i]<=sync1_l[i];draw_r[i]<=sync1_r[i];draw_t[i]<=sync1_t[i];draw_b[i]<=sync1_b[i];draw_score[i]<=sync1_score[i];end
                for(i=0;i<34;i=i+1) begin draw_x[i]<=sync1_x[i];draw_y[i]<=sync1_y[i];draw_conf[i]<=sync1_conf[i];end
                if(state==ST_READY) begin
                    display_bank<=drawing_bank;drawing_bank<=~drawing_bank;bank_ready<=0;
                    state<=ST_CLEAR;clear_addr<=0;line_idx<=0;point_idx<=0;point_sub<=0;
                end
            end
            case(state)
                ST_CLEAR: begin
                    if(clear_addr==H_SIZE*V_SIZE-1) begin state<=ST_SETUP;line_idx<=0;clear_addr<=0;end
                    else clear_addr<=clear_addr+1;
                end
                ST_SETUP: begin
                    if(line_idx>=draw_count*19) begin state<=ST_POINTS;point_idx<=0;point_sub<=0;end
                    else if(draw_conf[point_a]>=50 && draw_conf[point_b]>=50) begin
                        x0<=draw_x[point_a];y0<=draw_y[point_a];
                        x1<=draw_x[point_b];y1<=draw_y[point_b];
                        dx<=edge_dx;
                        dy<=-edge_dy;
                        sx<=(draw_x[point_b]>=draw_x[point_a])?1:-1;
                        sy<=(draw_y[point_b]>=draw_y[point_a])?1:-1;
                        err<=edge_dx-edge_dy;
                        major<=(edge_dx>=edge_dy);
                        acc<=0;
                        state<=ST_DRAW;
                    end else begin
                        line_idx<=line_idx+1;
                    end
                end
                ST_DRAW: begin
                    if(x0==x1 && y0==y1) begin line_idx<=line_idx+1;state<=ST_SETUP;end
                    else if(major) begin
                        x0<=x0+sx;
                        if(acc-dy>=dx) begin
                            y0<=y0+sy;
                            acc<=acc-dy-dx;
                        end else begin
                            acc<=acc-dy;
                        end
                    end else begin
                        y0<=y0+sy;
                        if(acc+dx>=-dy) begin
                            x0<=x0+sx;
                            acc<=acc+dx+dy;
                        end else begin
                            acc<=acc+dx;
                        end
                    end
                end
                ST_POINTS: begin
                    if(point_idx>=draw_count*17) begin state<=ST_READY;bank_ready<=1;end
                    else begin
                        if(point_sub==8) begin point_sub<=0;point_idx<=point_idx+1;end else point_sub<=point_sub+1;
                    end
                end
                ST_READY: begin end
                default: state<=ST_READY;
            endcase
        end
    end

    // One write port per bank; clear, line and point states are mutually exclusive.
    reg bank_wr_en;
    reg [18:0] bank_wr_addr;
    reg [1:0] bank_wr_data;
    always @* begin
        bank_wr_en=0;bank_wr_addr=0;bank_wr_data=0;
        if(state==ST_CLEAR) begin
            bank_wr_en=1;bank_wr_addr=clear_addr;bank_wr_data=0;
        end else if(state==ST_DRAW) begin
            bank_wr_en=(x0>=0 && x0<H_SIZE && y0>=0 && y0<V_SIZE);
            bank_wr_addr=y0*H_SIZE+x0;bank_wr_data=1;
        end else if(state==ST_POINTS && point_idx<draw_count*17) begin
            bank_wr_en=(draw_conf[point_idx]>=50 &&
                        draw_x[point_idx]+$signed(point_sub%3)>=1 && draw_x[point_idx]+$signed(point_sub%3)<H_SIZE+1 &&
                        draw_y[point_idx]+$signed(point_sub/3)>=1 && draw_y[point_idx]+$signed(point_sub/3)<V_SIZE+1);
            bank_wr_addr=(draw_y[point_idx]+(point_sub/3)-1)*H_SIZE+draw_x[point_idx]+(point_sub%3)-1;
            bank_wr_data=2;
        end
    end
    reg [1:0] mem0_q,mem1_q;
    always @(posedge vio_clk) begin
        if(bank_wr_en && drawing_bank==0) bank0[bank_wr_addr]<=bank_wr_data;
        mem0_q<=bank0[v_cnt*H_SIZE+h_cnt];
    end
    always @(posedge vio_clk) begin
        if(bank_wr_en && drawing_bank==1) bank1[bank_wr_addr]<=bank_wr_data;
        mem1_q<=bank1[v_cnt*H_SIZE+h_cnt];
    end
    wire [1:0] mem_q=display_bank?mem1_q:mem0_q;

    // Person boxes and Pss labels in the video domain.
    reg sel_box,sel_label_bg;
    reg [7:0] sel_score;
    reg [1:0] sel_char;
    reg [3:0] sel_glyph_y;
    reg [2:0] sel_bit;
    reg [9:0] label_y;
    always @* begin
        sel_box=0;sel_label_bg=0;sel_score=0;sel_char=0;sel_glyph_y=0;sel_bit=0;label_y=0;
        for(i=0;i<MAX_PEOPLE;i=i+1) begin
            if(i<draw_count) begin
                if((v_cnt>=draw_t[i] && v_cnt<=draw_b[i] &&
                    ((h_cnt>=draw_l[i] && h_cnt<draw_l[i]+2)||(h_cnt+2>draw_r[i] && h_cnt<=draw_r[i]))) ||
                   (h_cnt>=draw_l[i] && h_cnt<=draw_r[i] &&
                    ((v_cnt>=draw_t[i] && v_cnt<draw_t[i]+2)||(v_cnt+2>draw_b[i] && v_cnt<=draw_b[i])))) sel_box=1;
                label_y=(i==0)?10'd0:10'd34;
                if(!sel_label_bg && h_cnt<48 && v_cnt>=label_y && v_cnt<label_y+32) begin
                    sel_label_bg=1;sel_score=draw_score[i];sel_char=h_cnt>>3;sel_glyph_y=(v_cnt-label_y)>>1;sel_bit=h_cnt>>1;
                end
            end
        end
    end
    (* rom_style="block" *) reg [31:0] font_rom[0:2047];
    initial $readmemh("osd_font32.hex",font_rom);
    reg [7:0] char_code;
    reg [31:0] font_q;
    always @* begin
        if(sel_char==0) char_code=8'd80;
        else if(sel_char==1) char_code=8'd48+(sel_score/10);
        else char_code=8'd48+(sel_score%10);
    end
    always @* font_q=font_rom[{char_code,sel_glyph_y[3:1]}];

    reg [23:0] vio_d;
    reg act_d,hs_d,vs_d,box_d,label_d,bit_d;
    reg [1:0] mem_d;
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin vio_d<=0;act_d<=0;hs_d<=1;vs_d<=1;box_d<=0;label_d<=0;bit_d<=0;mem_d<=0;end
        else begin
            vio_d<=vio_data;act_d<=vio_active;hs_d<=vio_hsync;vs_d<=vio_vsync;
            box_d<=sel_box;label_d<=sel_label_bg;
            bit_d<=sel_glyph_y[0]?font_q[5'd23-sel_bit]:font_q[5'd31-sel_bit];mem_d<=mem_q;
        end
    end
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin hdmi_data<=0;hdmi_de<=0;hdmi_hsync<=1;hdmi_vsync<=1;end
        else begin
            hdmi_de<=act_d;hdmi_hsync<=~hs_d;hdmi_vsync<=~vs_d;
            if(!act_d) hdmi_data<=0;
            else if(draw_mode==2 && box_d) hdmi_data<=24'hffff00;
            else if(draw_mode==2 && label_d) hdmi_data<=bit_d?24'hffff00:24'h000000;
            else if(draw_mode==2 && mem_d==1) hdmi_data<=24'h00ffff;
            else if(draw_mode==2 && mem_d==2) hdmi_data<=24'hff0000;
            else hdmi_data<=vio_d;
        end
    end

    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin rd_ready<=0;rd_rsp_valid<=0;rd_data<=0;rd_rsp<=RESP_OKAY;end
        else begin
            if(!rd_rsp_valid) rd_ready<=1;
            if(rd_rsp_valid && rd_rsp_ready) begin rd_rsp_valid<=0;rd_ready<=1;end
            if(rd_valid && rd_ready) begin
                rd_ready<=0;rd_rsp_valid<=1;rd_rsp<=RESP_OKAY;rd_data<=0;
                case(rd_addr[7:0])
                    8'h00:rd_data<=32'h504F5345;
                    8'h04:rd_data<=32'h00010000;
                    8'h08:rd_data<={30'd0,mode_reg};
                    8'h0c:rd_data<={30'd0,count_reg};
                    8'h10:rd_data<={29'd0,(state!=ST_READY),bank_ready,display_bank};
                    8'h18:rd_data<={24'd0,draw_mode,draw_count,shadow_mode,shadow_count};
                    8'h1c:rd_data<={12'd0,h_cnt,v_cnt};
                    8'h20:rd_data<={12'd0,draw_l[0],draw_t[0]};
                    8'h24:rd_data<={draw_score[0],desc_score[0],shadow_score[0],sync1_score[0]};
                    8'h28:rd_data<={21'd0,sel_box,sel_label_bg,sel_char,sel_glyph_y,sel_bit};
                    8'h2c:rd_data<={13'd0,char_code,font_q,label_d,bit_d,hdmi_de};
                    8'h30:rd_data<={12'd0,desc_l[0],desc_t[0]};
                    8'h34:rd_data<={12'd0,shadow_l[0],shadow_t[0]};
                    8'h38:rd_data<={12'd0,sync1_l[0],sync1_t[0]};
                    default:rd_rsp<=RESP_SLVERR;
                endcase
            end
        end
    end

endmodule
