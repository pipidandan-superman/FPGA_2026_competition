`timescale 1ns/1ps
module tb_task_coco_osd;
    reg vio_clk=0,aclk=0,sys_rst_n=0,aresetn=0,vio_active=0,vio_hsync=0,vio_vsync=0;
    reg [23:0] vio_data=24'h123456;
    wire [23:0] hdmi_data; wire hdmi_de,hdmi_hsync,hdmi_vsync;
    reg [11:0] awaddr=0,araddr=0; reg [2:0] awprot=0,arprot=0;
    reg awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0;
    reg [31:0] wdata=0; reg [3:0] wstrb=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp; wire [31:0] rdata;
    always #10 vio_clk=~vio_clk;
    always #10 aclk=~aclk;
    task_coco_osd dut(
        .vio_clk(vio_clk),.sys_rst_n(sys_rst_n),.vio_active(vio_active),.vio_hsync(vio_hsync),.vio_vsync(vio_vsync),.vio_data(vio_data),
        .hdmi_data(hdmi_data),.hdmi_de(hdmi_de),.hdmi_hsync(hdmi_hsync),.hdmi_vsync(hdmi_vsync),
        .aclk(aclk),.aresetn(aresetn),.s_axi_awaddr(awaddr),.s_axi_awprot(awprot),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(arprot),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready));

    task axi_write(input [11:0] addr,input [31:0] data);
        reg aw_done,w_done;
        begin
            @(posedge aclk);awaddr<=addr;wdata<=data;wstrb<=4'hf;awvalid<=1;wvalid<=1;aw_done=0;w_done=0;
            while(!(aw_done&&w_done)) begin
                @(posedge aclk);
                if(awready) aw_done=1;
                if(wready) w_done=1;
            end
            awvalid<=0;wvalid<=0;bready<=1;
            while(!bvalid) @(posedge aclk);
            bready<=0;
        end
    endtask
    task video_frame;
        integer line;
        begin
            vio_active<=1;vio_hsync<=0;vio_vsync<=0;
            for(line=0;line<480;line=line+1) begin
                repeat(640) @(posedge vio_clk);
                vio_active<=0;vio_hsync<=1;
                repeat(2) @(posedge vio_clk);
                vio_hsync<=0;vio_active<=1;
            end
            vio_active<=0;vio_vsync<=1;
            repeat(2) @(posedge vio_clk);
            vio_vsync<=0;vio_active<=1;
        end
    endtask
    task check_char(input[7:0] expected,input[7:0] tag);
        begin
            if(dut.char_code!==expected) begin
                $display("COCO_CHAR_FAIL tag=%h got=%h expected=%h",tag,dut.char_code,expected);
                $fatal(1);
            end
        end
    endtask

    // Pixel-accuracy font monitor (2026-11-02 fix run): dut.bit_d must equal
    // the expected glyph bit from osd_font32.hex for EVERY label pixel, ODD
    // ROWS INCLUDED. The 11-01 TB only checked char_code, so the odd-row
    // bit-range bug (font_q[15-x] read while data sits at [23:16]) was
    // invisible to simulation and reached the board as garbled text.
    reg [31:0] exp_font[0:2047];
    initial $readmemh("osd_font32.hex",exp_font);
    function [31:0] exp_word_f(input [7:0] code,input [3:0] gy);
        exp_word_f=exp_font[{code,gy[3:1]}];
    endfunction
    function exp_bit_f(input [7:0] code,input [3:0] gy,input [2:0] bx);
        reg [31:0] w;
        begin
            w=exp_font[{code,gy[3:1]}];
            exp_bit_f=gy[0]?w[5'd23-bx]:w[5'd31-bx];
        end
    endfunction
    // Glyph-identity gate (2026-11-03 font-base fix): bitmaps hardcoded from
    // an INDEPENDENT render, not from loading osd_font32.hex. The 11-02 blind
    // spot: expected values came from the same misaligned table the DUT used,
    // so the 0x20 font-base mismatch (file starts at ' ', RTL indexes raw
    // ASCII) passed every pixel check and reached HDMI as @-runs + shifted
    // score digits ("40"->"TP").
    task check_glyph_id(input [7:0] code,
                        input [31:0] w0,w1,w2,w3,w4,w5,w6,w7);
        begin
            if (exp_font[{code,3'd0}]!==w0 || exp_font[{code,3'd1}]!==w1 ||
                exp_font[{code,3'd2}]!==w2 || exp_font[{code,3'd3}]!==w3 ||
                exp_font[{code,3'd4}]!==w4 || exp_font[{code,3'd5}]!==w5 ||
                exp_font[{code,3'd6}]!==w6 || exp_font[{code,3'd7}]!==w7) begin
                $display("GLYPH_IDENTITY_FAIL code=%0d",code);
                $fatal(1,"GLYPH_IDENTITY_MISMATCH code=%0d",code);
            end
        end
    endtask
    initial begin
        #1;
        check_glyph_id(8'd84,32'h00000000,32'h00fe0000,32'h10100000,32'h10100000,32'h10100000,32'h10100000,32'h00000000,32'h00000000); // 'T'
        check_glyph_id(8'd48,32'h00000000,32'h00380000,32'h64440000,32'h44540000,32'h44440000,32'h64380000,32'h00000000,32'h00000000); // '0'
        check_glyph_id(8'd107,32'h00000000,32'h60600000,32'h60640000,32'h68700000,32'h78680000,32'h64660000,32'h00000000,32'h00000000); // 'k'
        check_glyph_id(8'd80,32'h00000000,32'h007c0000,32'h44460000,32'h447c0000,32'h40400000,32'h40400000,32'h00000000,32'h00000000); // 'P'
        $display("GLYPH_IDENTITY_PASS");
    end
    reg [7:0] m_code; reg [3:0] m_gy; reg [2:0] m_bx; reg m_en;
    integer font_checks=0, font_odd_checks=0, font_fails=0;
    always @(posedge vio_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin m_en<=0;m_code<=0;m_gy<=0;m_bx<=0; end
        else begin
            if(m_en) begin
                if(dut.bit_d!==exp_bit_f(m_code,m_gy,m_bx)) begin
                    $display("COCO_FONT_PIXEL_FAIL code=%0d gy=%0d x=%0d got=%b exp=%b",
                             m_code,m_gy,m_bx,dut.bit_d,exp_bit_f(m_code,m_gy,m_bx));
                    font_fails=font_fails+1;
                    $fatal(1,"COCO_FONT_PIXEL_MISMATCH code=%0d gy=%0d x=%0d",m_code,m_gy,m_bx);
                end
                font_checks=font_checks+1;
                if(m_gy[0]) font_odd_checks=font_odd_checks+1;
            end
            m_en<=dut.sel_label_bg;
            m_code<=dut.char_code; m_gy<=dut.sel_glyph_y; m_bx<=dut.sel_bit;
        end
    end

    initial begin
        repeat(8) @(posedge aclk);
        sys_rst_n<=1;aresetn<=1;
        repeat(4) @(posedge aclk);
        axi_write(12'h008,0);
        axi_write(12'h00c,2);
        axi_write(12'h040,100);axi_write(12'h044,200);axi_write(12'h048,100);axi_write(12'h04c,200);
        axi_write(12'h050,{16'd0,8'd87,8'd39});
        axi_write(12'h060,300);axi_write(12'h064,420);axi_write(12'h068,150);axi_write(12'h06c,300);
        axi_write(12'h070,{16'd0,8'd93,8'd0});
        axi_write(12'h014,1);
        video_frame();
        wait(dut.h_cnt==100 && dut.v_cnt==82);#1;
        if(!dut.sel_label_bg) $fatal(1,"COCO_LABEL_MISSING");
        check_char(8'd98,0); // bottle -> b
        wait(dut.h_cnt==108 && dut.v_cnt==82);#1;check_char(8'd111,0); // o
        wait(dut.h_cnt==116 && dut.v_cnt==82);#1;check_char(8'd116,0); // t
        wait(dut.h_cnt==124 && dut.v_cnt==82);#1;check_char(8'd116,0); // t
        wait(dut.h_cnt==132 && dut.v_cnt==82);#1;check_char(8'd108,0); // l
        wait(dut.h_cnt==140 && dut.v_cnt==82);#1;check_char(8'd101,0); // e
        wait(dut.h_cnt==220 && dut.v_cnt==82);#1;check_char(8'd56,0); // 8
        wait(dut.h_cnt==228 && dut.v_cnt==82);#1;check_char(8'd55,0); // 7
        wait(dut.h_cnt==100 && dut.v_cnt==102);#1;
        if(!dut.sel_box) $fatal(1,"COCO_BOX_MISSING");
        wait(dut.h_cnt==300 && dut.v_cnt==132);#1;
        check_char(8'd112,1); // person -> p
        wait(dut.h_cnt==308 && dut.v_cnt==132);#1;check_char(8'd101,1); // e
        wait(dut.h_cnt==316 && dut.v_cnt==132);#1;check_char(8'd114,1); // r
        wait(dut.h_cnt==324 && dut.v_cnt==132);#1;check_char(8'd115,1); // s
        wait(dut.h_cnt==332 && dut.v_cnt==132);#1;check_char(8'd111,1); // o
        wait(dut.h_cnt==340 && dut.v_cnt==132);#1;check_char(8'd110,1); // n
        wait(dut.h_cnt==420 && dut.v_cnt==132);#1;check_char(8'd57,1); // 9
        wait(dut.h_cnt==428 && dut.v_cnt==132);#1;check_char(8'd51,1); // 3
        $display("COCO_BOX_LABEL_PASS");
        axi_write(12'h008,1);axi_write(12'h014,1);
        video_frame();
        wait(dut.h_cnt==100 && dut.v_cnt==102);#1;
        repeat(3) @(posedge vio_clk);#1;
        if(hdmi_data!==24'h123456) $fatal(1,"COCO_GESTURE_PASSTHROUGH_FAIL got=%h",hdmi_data);
        $display("COCO_GESTURE_PASSTHROUGH_PASS");
        if(font_fails!=0) $fatal(1,"COCO_FONT_FAILS=%0d",font_fails);
        if(font_checks<500) $fatal(1,"COCO_FONT_COVERAGE_FAIL checks=%0d",font_checks);
        if(font_odd_checks<200) $fatal(1,"COCO_FONT_ODD_COVERAGE_FAIL odd=%0d",font_odd_checks);
        $display("COCO_FONT_PIXELS_PASS checks=%0d odd=%0d",font_checks,font_odd_checks);
        $display("COCO_OSD_ALL_PASS");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1,"COCO_TIMEOUT");
    end
endmodule
