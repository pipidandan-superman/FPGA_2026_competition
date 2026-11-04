`timescale 1ns/1ps
// COCO multi-box + per-class text OSD. Display-only; no inference logic.
module task_coco_osd #(
    parameter H_SIZE = 640,
    parameter V_SIZE = 480,
    parameter MAX_BOXES = 8
)(
    input wire vio_clk, input wire sys_rst_n,
    input wire vio_active, input wire vio_hsync, input wire vio_vsync,
    input wire [23:0] vio_data,
    output reg [23:0] hdmi_data, output reg hdmi_de,
    output reg hdmi_hsync, output reg hdmi_vsync,
    input wire aclk, input wire aresetn,
    input wire [11:0] s_axi_awaddr, input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
    input wire [11:0] s_axi_araddr, input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid, input wire s_axi_rready
);
    localparam [1:0] RESP_OKAY=2'd0, RESP_SLVERR=2'd2;
    wire wr_valid, wr_rsp_ready, rd_valid, rd_rsp_ready;
    wire [11:0] wr_addr, rd_addr;
    wire [31:0] wr_data;
    wire [3:0] wr_strb;
    reg wr_ready, wr_rsp_valid, rd_ready, rd_rsp_valid;
    reg [1:0] wr_rsp, rd_rsp;
    reg [31:0] rd_data;

    axi_lite_slave u_shell(
        .clk(aclk), .resetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(wr_strb),
        .wr_rsp_valid(wr_rsp_valid), .wr_rsp_ready(wr_rsp_ready), .wr_rsp(wr_rsp),
        .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_addr(rd_addr), .rd_rsp_valid(rd_rsp_valid),
        .rd_rsp_ready(rd_rsp_ready), .rd_data(rd_data), .rd_rsp(rd_rsp)
    );

    reg [1:0] mode_reg;
    reg [3:0] count_reg;
    reg [9:0] desc_l[0:MAX_BOXES-1], desc_r[0:MAX_BOXES-1];
    reg [9:0] desc_t[0:MAX_BOXES-1], desc_b[0:MAX_BOXES-1];
    reg [7:0] desc_cls[0:MAX_BOXES-1], desc_score[0:MAX_BOXES-1];
    reg [1:0] shadow_mode;
    reg [3:0] shadow_count;
    reg [9:0] shadow_l[0:MAX_BOXES-1], shadow_r[0:MAX_BOXES-1];
    reg [9:0] shadow_t[0:MAX_BOXES-1], shadow_b[0:MAX_BOXES-1];
    reg [7:0] shadow_cls[0:MAX_BOXES-1], shadow_score[0:MAX_BOXES-1];
    integer i;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ready <= 0; wr_rsp_valid <= 0; wr_rsp <= RESP_OKAY;
            mode_reg <= 1; count_reg <= 0; shadow_mode <= 1; shadow_count <= 0;
            for (i=0;i<MAX_BOXES;i=i+1) begin
                desc_l[i]<=0; desc_r[i]<=0; desc_t[i]<=0; desc_b[i]<=0;
                desc_cls[i]<=0; desc_score[i]<=0;
                shadow_l[i]<=0; shadow_r[i]<=0; shadow_t[i]<=0; shadow_b[i]<=0;
                shadow_cls[i]<=0; shadow_score[i]<=0;
            end
        end else begin
            if (!wr_rsp_valid) wr_ready <= 1;
            if (wr_rsp_valid && wr_rsp_ready) begin wr_rsp_valid<=0; wr_ready<=1; end
            if (wr_valid && wr_ready) begin
                wr_ready<=0; wr_rsp_valid<=1; wr_rsp<=RESP_OKAY;
                case (wr_addr[7:0])
                    8'h08: if(wr_strb[0]) mode_reg <= wr_data[1:0];
                    8'h0c: if(wr_strb[0]) count_reg <= wr_data[3:0];
                    8'h14: if(wr_strb[0]) begin
                        shadow_mode<=mode_reg; shadow_count<=count_reg;
                        for(i=0;i<MAX_BOXES;i=i+1) begin
                            shadow_l[i]<=desc_l[i]; shadow_r[i]<=desc_r[i];
                            shadow_t[i]<=desc_t[i]; shadow_b[i]<=desc_b[i];
                            shadow_cls[i]<=desc_cls[i]; shadow_score[i]<=desc_score[i];
                        end
                    end
                    default: begin
                        if (wr_addr >= 12'h040 && wr_addr < 12'h140) begin
                            case (wr_addr[4:0])
                                5'h00: if(wr_strb[0]) desc_l[(wr_addr[7:5]-2)] <= wr_data[9:0];
                                5'h04: if(wr_strb[0]) desc_r[(wr_addr[7:5]-2)] <= wr_data[9:0];
                                5'h08: if(wr_strb[0]) desc_t[(wr_addr[7:5]-2)] <= wr_data[9:0];
                                5'h0c: if(wr_strb[0]) desc_b[(wr_addr[7:5]-2)] <= wr_data[9:0];
                                5'h10: if(wr_strb[0]) begin
                                    desc_cls[(wr_addr[7:5]-2)] <= wr_data[7:0];
                                    desc_score[(wr_addr[7:5]-2)] <= wr_data[15:8];
                                end
                                default: wr_rsp<=RESP_SLVERR;
                            endcase
                        end else wr_rsp<=RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    // Two-stage descriptor CDC, then one coherent capture at pixel (0,0).
    reg [1:0] sync0_mode, sync1_mode;
    reg [3:0] sync0_count, sync1_count;
    reg [9:0] sync0_l[0:MAX_BOXES-1], sync0_r[0:MAX_BOXES-1], sync0_t[0:MAX_BOXES-1], sync0_b[0:MAX_BOXES-1];
    reg [9:0] sync1_l[0:MAX_BOXES-1], sync1_r[0:MAX_BOXES-1], sync1_t[0:MAX_BOXES-1], sync1_b[0:MAX_BOXES-1];
    reg [7:0] sync0_cls[0:MAX_BOXES-1], sync0_score[0:MAX_BOXES-1];
    reg [7:0] sync1_cls[0:MAX_BOXES-1], sync1_score[0:MAX_BOXES-1];
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            sync0_mode<=1; sync1_mode<=1; sync0_count<=0; sync1_count<=0;
            for(i=0;i<MAX_BOXES;i=i+1) begin
                sync0_l[i]<=0;sync0_r[i]<=0;sync0_t[i]<=0;sync0_b[i]<=0;
                sync1_l[i]<=0;sync1_r[i]<=0;sync1_t[i]<=0;sync1_b[i]<=0;
                sync0_cls[i]<=0;sync0_score[i]<=0;sync1_cls[i]<=0;sync1_score[i]<=0;
            end
        end else begin
            sync0_mode<=shadow_mode; sync1_mode<=sync0_mode;
            sync0_count<=shadow_count; sync1_count<=sync0_count;
            for(i=0;i<MAX_BOXES;i=i+1) begin
                sync0_l[i]<=shadow_l[i];sync1_l[i]<=sync0_l[i];
                sync0_r[i]<=shadow_r[i];sync1_r[i]<=sync0_r[i];
                sync0_t[i]<=shadow_t[i];sync1_t[i]<=sync0_t[i];
                sync0_b[i]<=shadow_b[i];sync1_b[i]<=sync0_b[i];
                sync0_cls[i]<=shadow_cls[i];sync1_cls[i]<=sync0_cls[i];
                sync0_score[i]<=shadow_score[i];sync1_score[i]<=sync0_score[i];
            end
        end
    end

    reg [1:0] draw_mode;
    reg [3:0] draw_count;
    reg [9:0] draw_l[0:MAX_BOXES-1],draw_r[0:MAX_BOXES-1],draw_t[0:MAX_BOXES-1],draw_b[0:MAX_BOXES-1];
    reg [7:0] draw_cls[0:MAX_BOXES-1],draw_score[0:MAX_BOXES-1];
    reg [9:0] h_cnt,v_cnt;
    reg frame_armed;
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            h_cnt<=0;v_cnt<=0;draw_mode<=1;draw_count<=0;frame_armed<=0;
            for(i=0;i<MAX_BOXES;i=i+1) begin
                draw_l[i]<=0;draw_r[i]<=0;draw_t[i]<=0;draw_b[i]<=0;draw_cls[i]<=0;draw_score[i]<=0;
            end
        end else begin
            if(vio_hsync) h_cnt<=0;
            else if(vio_active) h_cnt<=(h_cnt>=H_SIZE-1)?0:h_cnt+1;
            else h_cnt<=0;
            if(vio_vsync) v_cnt<=0;
            else if(h_cnt==H_SIZE-1 && vio_active) v_cnt<=(v_cnt>=V_SIZE-1)?0:v_cnt+1;
            if(vio_vsync) frame_armed<=1;
            if(vio_active && frame_armed) begin
                frame_armed<=0;
                draw_mode<=sync1_mode;draw_count<=sync1_count;
                for(i=0;i<MAX_BOXES;i=i+1) begin
                    draw_l[i]<=sync1_l[i];draw_r[i]<=sync1_r[i];draw_t[i]<=sync1_t[i];draw_b[i]<=sync1_b[i];
                    draw_cls[i]<=sync1_cls[i];draw_score[i]<=sync1_score[i];
                end
            end
        end
    end

    reg sel_box,sel_label_bg;
    reg [7:0] sel_class,sel_score;
    reg [4:0] sel_char;
    reg [3:0] sel_glyph_y;
    reg [2:0] sel_bit;
    reg [9:0] label_y;
    always @* begin
        sel_box=0;sel_label_bg=0;sel_class=0;sel_score=0;sel_char=0;sel_glyph_y=0;sel_bit=0;label_y=0;
        for(i=0;i<MAX_BOXES;i=i+1) begin
            if(i<draw_count) begin
                if ((v_cnt>=draw_t[i] && v_cnt<=draw_b[i] &&
                     ((h_cnt>=draw_l[i] && h_cnt<draw_l[i]+2) || (h_cnt+2>draw_r[i] && h_cnt<=draw_r[i]))) ||
                    (h_cnt>=draw_l[i] && h_cnt<=draw_r[i] &&
                     ((v_cnt>=draw_t[i] && v_cnt<draw_t[i]+2) || (v_cnt+2>draw_b[i] && v_cnt<=draw_b[i]))))
                    sel_box=1;
                label_y=(draw_t[i]>=18)?draw_t[i]-18:10'd0;
                if(!sel_label_bg && h_cnt>=draw_l[i] && h_cnt<draw_l[i]+136 &&
                   v_cnt>=label_y && v_cnt<label_y+16) begin
                    sel_label_bg=1;sel_class=draw_cls[i];sel_score=draw_score[i];
                    sel_char=(h_cnt-draw_l[i])>>3;sel_glyph_y=v_cnt-label_y;sel_bit=h_cnt-draw_l[i];
                end
            end
        end
    end

    (* rom_style="block" *) reg [7:0] names_rom[0:1119];
    (* rom_style="block" *) reg [31:0] font_rom[0:2047];
    initial $readmemh("coco80.hex",names_rom);
    initial $readmemh("osd_font32.hex",font_rom);
    reg [7:0] char_code;
    reg [31:0] font_q;
    always @* begin
        if(sel_char<14) char_code=names_rom[sel_class*14+sel_char];
        else if(sel_char==14) char_code=8'd32;
        else if(sel_char==15) char_code=8'd48+(sel_score/10);
        else char_code=8'd48+(sel_score%10);
    end
    always @* font_q=font_rom[{char_code,sel_glyph_y[3:1]}];

    reg [23:0] vio_d;
    reg act_d,hs_d,vs_d,box_d,label_d,bit_d;
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin vio_d<=0;act_d<=0;hs_d<=1;vs_d<=1;box_d<=0;label_d<=0;bit_d<=0; end
        else begin
            vio_d<=vio_data;act_d<=vio_active;hs_d<=vio_hsync;vs_d<=vio_vsync;
            box_d<=sel_box;label_d<=sel_label_bg;
            bit_d<=sel_glyph_y[0]?font_q[5'd23-sel_bit]:font_q[5'd31-sel_bit];
        end
    end
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin hdmi_data<=0;hdmi_de<=0;hdmi_hsync<=1;hdmi_vsync<=1; end
        else begin
            hdmi_de<=act_d;hdmi_hsync<=~hs_d;hdmi_vsync<=~vs_d;
            if(!act_d) hdmi_data<=0;
            else if(draw_mode==0 && box_d) hdmi_data<=24'h00ff00;
            else if(draw_mode==0 && label_d) hdmi_data<=bit_d?24'h00ff00:24'h000000;
            else hdmi_data<=vio_d;
        end
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin rd_ready<=0; rd_rsp_valid<=0; rd_data<=0; rd_rsp<=RESP_OKAY; end
        else begin
            if (!rd_rsp_valid) rd_ready<=1;
            if (rd_rsp_valid && rd_rsp_ready) begin rd_rsp_valid<=0; rd_ready<=1; end
            if (rd_valid && rd_ready) begin
                rd_ready<=0; rd_rsp_valid<=1; rd_rsp<=RESP_OKAY; rd_data<=0;
                case (rd_addr[7:0])
                    8'h00: rd_data<=32'h434F434F;
                    8'h04: rd_data<=32'h00010000;
                    8'h08: rd_data<={30'd0,mode_reg};
                    8'h0c: rd_data<={28'd0,count_reg};
                    8'h18: rd_data<={22'd0,draw_mode,sync1_mode,sync0_mode,shadow_mode,mode_reg};
                    8'h1c: rd_data<={11'd0,frame_armed,draw_count,sync1_count,sync0_count,shadow_count,count_reg};
                    8'h20: rd_data<={12'd0,h_cnt,v_cnt};
                    8'h24: rd_data<={12'd0,draw_l[0],draw_t[0]};
                    8'h28: rd_data<={12'd0,draw_r[0],draw_b[0]};
                    8'h2c: rd_data<={16'd0,draw_score[0],draw_cls[0]};
                    8'h30: rd_data<={12'd0,sync1_l[0],sync1_t[0]};
                    8'h34: rd_data<={12'd0,shadow_l[0],shadow_t[0]};
                    8'h38: rd_data<={2'd0,char_code,font_q,label_d,bit_d,sel_char,sel_glyph_y,sel_bit};
                    default: begin
                        if (rd_addr>=12'h040 && rd_addr<12'h140) begin
                            case (rd_addr[4:0])
                                5'h00: rd_data<={22'd0,desc_l[(rd_addr[7:5]-2)]};
                                5'h04: rd_data<={22'd0,desc_r[(rd_addr[7:5]-2)]};
                                5'h08: rd_data<={22'd0,desc_t[(rd_addr[7:5]-2)]};
                                5'h0c: rd_data<={22'd0,desc_b[(rd_addr[7:5]-2)]};
                                5'h10: rd_data<={16'd0,desc_score[(rd_addr[7:5]-2)],desc_cls[(rd_addr[7:5]-2)]};
                                default: rd_rsp<=RESP_SLVERR;
                            endcase
                        end else rd_rsp<=RESP_SLVERR;
                    end
                endcase
            end
        end
    end

endmodule
