`timescale 1ns/1ps
module tb_task_pose_osd;
    reg vio_clk=0,aclk=0,sys_rst_n=0,aresetn=0,vio_active=0,vio_hsync=1,vio_vsync=1;
    reg [23:0] vio_data=24'h234567;
    wire [23:0] hdmi_data;wire hdmi_de,hdmi_hsync,hdmi_vsync;
    reg [11:0] awaddr=0,araddr=0;reg [2:0] awprot=0,arprot=0;
    reg awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0;
    reg [31:0] wdata=0;reg [3:0] wstrb=0;
    wire awready,wready,bvalid,arready,rvalid;wire [1:0] bresp,rresp;wire [31:0] rdata;
    always #10 vio_clk=~vio_clk;
    always #10 aclk=~aclk;
    task_pose_osd dut(
        .vio_clk(vio_clk),.sys_rst_n(sys_rst_n),.vio_active(vio_active),.vio_hsync(vio_hsync),.vio_vsync(vio_vsync),.vio_data(vio_data),
        .hdmi_data(hdmi_data),.hdmi_de(hdmi_de),.hdmi_hsync(hdmi_hsync),.hdmi_vsync(hdmi_vsync),
        .aclk(aclk),.aresetn(aresetn),.s_axi_awaddr(awaddr),.s_axi_awprot(awprot),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(arprot),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready));
    task axi_write(input[11:0] addr,input[31:0] data);
        reg aw_done,w_done;
        begin
            @(posedge aclk);awaddr<=addr;wdata<=data;wstrb<=4'hf;awvalid<=1;wvalid<=1;aw_done=0;w_done=0;
            while(!(aw_done&&w_done)) begin
                @(posedge aclk);if(awready) aw_done=1;if(wready) w_done=1;
            end
            awvalid<=0;wvalid<=0;bready<=1;
            while(!bvalid) @(posedge aclk);
            bready<=0;
        end
    endtask
    task video_frame;
        integer line;
        begin
            vio_active<=0;vio_vsync<=0;
            repeat(2) @(posedge vio_clk);
            vio_vsync<=1;vio_active<=1;
            for(line=0;line<480;line=line+1) begin
                repeat(640) @(posedge vio_clk);
                vio_active<=0;vio_hsync<=0;
                repeat(2) @(posedge vio_clk);
                vio_hsync<=1;vio_active<=1;
            end
            vio_active<=0;
        end
    endtask
    task write_point(input integer idx,input integer x,input integer y,input integer conf);
        begin
            axi_write(12'h054+idx*12,x);
            repeat(2) @(posedge aclk);
            axi_write(12'h058+idx*12,y);
            repeat(2) @(posedge aclk);
            axi_write(12'h05c+idx*12,conf);
            repeat(2) @(posedge aclk);
        end
    endtask
    always @(posedge aclk) begin
        if(dut.wr_valid && dut.wr_ready)
            $display("POSE_AXI_WRITE addr=%h data=%h",dut.wr_addr,dut.wr_data);
    end

    // Pixel-accuracy font monitor (2026-11-02 fix run): dut.bit_d must equal
    // the expected glyph bit from osd_font32.hex for EVERY Pss label pixel,
    // ODD ROWS INCLUDED. The 11-01 TB sampled only two font_q words and one
    // bit_d!=0 witness, so the odd-row bit-range bug (font_q[15-x] read while
    // data sits at [23:16]) was invisible to simulation.
    reg [31:0] exp_font[0:2047];
    initial $readmemh("osd_font32.hex",exp_font);
    function exp_bit_f(input [7:0] code,input [3:0] gy,input [2:0] bx);
        reg [31:0] w;
        begin
            w=exp_font[{code,gy[3:1]}];
            exp_bit_f=gy[0]?w[5'd23-bx]:w[5'd31-bx];
        end
    endfunction
    function [31:0] exp_word_f(input [7:0] code,input [3:0] gy);
        exp_word_f=exp_font[{code,gy[3:1]}];
    endfunction
    // Glyph-identity gate (2026-11-03 font-base fix): bitmaps hardcoded from
    // an INDEPENDENT render, not from loading osd_font32.hex. Kills the
    // same-source blind spot that let the 0x20 font-base mismatch pass.
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
                    $display("POSE_FONT_PIXEL_FAIL code=%0d gy=%0d x=%0d got=%b exp=%b",
                             m_code,m_gy,m_bx,dut.bit_d,exp_bit_f(m_code,m_gy,m_bx));
                    font_fails=font_fails+1;
                    $fatal(1,"POSE_FONT_PIXEL_MISMATCH code=%0d gy=%0d x=%0d",m_code,m_gy,m_bx);
                end
                font_checks=font_checks+1;
                if(m_gy[0]) font_odd_checks=font_odd_checks+1;
            end
            // 2026-11-03 geometry-gate fix: code/gy/bx are derived from RAW
            // h_cnt/v_cnt with the SPEC mapping (16px cells: cell=h[5:4],
            // column=(h>>1)&7=h[3:1], row=(v-label_y)>>1), NOT tapped from
            // dut.char_code/sel_glyph_y/sel_bit. The old monitor echoed the
            // DUT selection regs, so the >>3 8px-cell layout (each cell
            // rendering half a glyph, columns 0-3/4-7 alternating) passed
            // every pixel check. Stimulus: person0 label v<32 score 88
            // (tens==ones=='8'), person1 v>=34 score 77 ('7').
            m_en<=dut.sel_label_bg;
            m_code<=(dut.h_cnt[5:4]==2'd0)?8'd80:((dut.v_cnt>=10'd34)?8'd55:8'd56);
            m_gy<=(dut.v_cnt>=10'd34)?(dut.v_cnt-10'd34)>>1:dut.v_cnt>>1;
            m_bx<=dut.h_cnt[3:1];
        end
    end

    reg stream_check=0,gesture_check=0;
    reg [5:0] stream_flags=0;
    reg [1:0] font_flags=0;
    reg gesture_seen=0,label_yellow_seen=0;
    always @(posedge vio_clk) begin
        #1;
        // Recalibrated 2026-11-03 (16px-cell geometry fix): label strip is
        // h<48, v in [0,32) (person0) / [34,66) (person1); cells are 16px
        // (2px per glyph column), cell0='P' h0-15, cell1=tens h16-31,
        // cell2=ones h32-47; glyphy=(v-label_y)>>1. The 11-02 probe points
        // h8/h12/h16 were calibrated against the broken >>3 6-cell layout.
        if(stream_check && dut.h_cnt==4 && dut.v_cnt==8) begin
            if(dut.font_q!==exp_word_f(8'd80,4'd4)) $fatal(1,"POSE_P_GLYPH_FAIL got=%h exp=%h",dut.font_q,exp_word_f(8'd80,4'd4));
            font_flags[0]<=1;
        end
        if(stream_check && dut.h_cnt==20 && dut.v_cnt==8) begin
            if(dut.font_q!==exp_word_f(8'd56,4'd4)) $fatal(1,"POSE_DIGIT_GLYPH_FAIL got=%h exp=%h",dut.font_q,exp_word_f(8'd56,4'd4));
            font_flags[1]<=1;
        end
        if(stream_check && dut.h_cnt==0 && dut.v_cnt==0) begin
            if(dut.char_code!==80) $fatal(1,"POSE_LABEL_FAIL code=%d",dut.char_code);
            stream_flags[0]<=1;
        end
        if(stream_check && dut.h_cnt==20 && dut.v_cnt==0) begin
            if(dut.char_code!==56) $fatal(1,"POSE_SCORE_TENS_FAIL code=%d",dut.char_code);
            stream_flags[4]<=1;
        end
        if(stream_check && dut.h_cnt==36 && dut.v_cnt==0) begin
            if(dut.char_code!==56) $fatal(1,"POSE_SCORE_ONES_FAIL code=%d",dut.char_code);
            stream_flags[5]<=1;
        end
        if(stream_check && dut.label_d && dut.bit_d) label_yellow_seen<=1;
        if(stream_check && dut.h_cnt==100 && dut.v_cnt==90) begin
            $display("POSE_BOX_DEBUG count=%0d box=(%0d,%0d,%0d,%0d) sel=%0d mode=%0d",
                     dut.draw_count,dut.draw_l[0],dut.draw_r[0],dut.draw_t[0],dut.draw_b[0],dut.sel_box,dut.draw_mode);
            if(!dut.sel_box) $fatal(1,"POSE_BOX_MISSING");
            stream_flags[1]<=1;
        end
        if(stream_check && dut.h_cnt==140 && dut.v_cnt==220) begin
            if(dut.mem_q!==2) $fatal(1,"POSE_STREAM_POINT_FAIL code=%d",dut.mem_q);
            stream_flags[2]<=1;
        end
        if(stream_check && dut.h_cnt==160 && dut.v_cnt==220) begin
            $display("POSE_LINE_DEBUG major=%0d dx=%0d dy=%0d x0=%0d y0=%0d x1=%0d y1=%0d mem=%0d",
                     dut.major,dut.dx,dut.dy,dut.x0,dut.y0,dut.x1,dut.y1,dut.mem_q);
            if(dut.mem_q!==1) $fatal(1,"POSE_STREAM_LINE_FAIL code=%d",dut.mem_q);
            stream_flags[3]<=1;
        end
        if(gesture_check && dut.h_cnt==100 && dut.v_cnt==90) begin
            if(hdmi_data!==24'h234567) $fatal(1,"POSE_GESTURE_PASSTHROUGH_FAIL got=%h",hdmi_data);
            gesture_seen<=1;
        end
    end
    initial begin
        repeat(8) @(posedge aclk);sys_rst_n<=1;aresetn<=1;
        repeat(4) @(posedge aclk);
        axi_write(12'h008,2);axi_write(12'h00c,1);
        axi_write(12'h040,100);axi_write(12'h044,260);axi_write(12'h048,90);axi_write(12'h04c,270);axi_write(12'h050,88);
        write_point(0,170,100,90);
        write_point(5,150,140,90);write_point(6,190,140,90);
        write_point(11,140,220,90);write_point(12,200,220,90);
        write_point(16,320,240,90);
        axi_write(12'h240,300);axi_write(12'h244,380);axi_write(12'h248,180);axi_write(12'h24c,300);axi_write(12'h250,77);
        axi_write(12'h314,400);axi_write(12'h318,260);axi_write(12'h31c,66);
        if(dut.desc_x[16]!==320 || dut.desc_y[16]!==240 || dut.desc_conf[16]!==90)
            $fatal(1,"POSE_KP16_DECODE_FAIL");
        if(dut.desc_x[33]!==400 || dut.desc_y[33]!==260 || dut.desc_conf[33]!==66)
            $fatal(1,"POSE_PERSON1_DECODE_FAIL");
        if(dut.desc_l[0]!==100 || dut.desc_l[1]!==300 || dut.desc_score[1]!==77)
            $fatal(1,"POSE_PERSON_OVERLAP_FAIL");
        $display("POSE_17POINT_2PERSON_AXI_PASS");
        axi_write(12'h014,1);
        $display("POSE_AXI_DEBUG kp11=(%0d,%0d,%0d) kp12=(%0d,%0d,%0d)",
                 dut.desc_x[11],dut.desc_y[11],dut.desc_conf[11],
                 dut.desc_x[12],dut.desc_y[12],dut.desc_conf[12]);
        video_frame();
        wait(dut.state==4); // first draw bank complete
        video_frame(); // swap completed bank
        $display("POSE_BANK_DEBUG display=%0d draw=%0d state=%0d b0=%0d b1=%0d kp11=(%0d,%0d,%0d) line160=%0d",
                 dut.display_bank,dut.drawing_bank,dut.state,
                 dut.bank0[140+220*640],dut.bank1[140+220*640],
                 dut.draw_x[11],dut.draw_y[11],dut.draw_conf[11],dut.bank0[160+220*640]);
        if((dut.display_bank ? dut.bank1[140+220*640] : dut.bank0[140+220*640])!==2)
            $fatal(1,"POSE_POINT_FAIL");
        if((dut.display_bank ? dut.bank1[160+220*640] : dut.bank0[160+220*640])!==1)
            $fatal(1,"POSE_LINE_FAIL");
        stream_flags=0;font_flags=0;label_yellow_seen=0;stream_check=1;
        video_frame();
        stream_check=0;
        if(stream_flags!==6'h3f) $fatal(1,"POSE_STREAM_COVERAGE_FAIL flags=%b",stream_flags);
        if(font_flags!==2'b11) $fatal(1,"POSE_GLYPH_COVERAGE_FAIL flags=%b",font_flags);
        if(!label_yellow_seen) $fatal(1,"POSE_LABEL_PIXEL_MISSING");
        $display("POSE_SKELETON_BOX_LABEL_PASS");
        axi_write(12'h008,1);axi_write(12'h014,1);
        gesture_seen=0;gesture_check=1;
        video_frame();
        gesture_check=0;
        if(!gesture_seen) $fatal(1,"POSE_GESTURE_SAMPLE_MISSING");
        $display("POSE_GESTURE_PASSTHROUGH_PASS");
        if(font_fails!=0) $fatal(1,"POSE_FONT_FAILS=%0d",font_fails);
        if(font_checks<500) $fatal(1,"POSE_FONT_COVERAGE_FAIL checks=%0d",font_checks);
        if(font_odd_checks<200) $fatal(1,"POSE_FONT_ODD_COVERAGE_FAIL odd=%0d",font_odd_checks);
        $display("POSE_FONT_PIXELS_PASS checks=%0d odd=%0d",font_checks,font_odd_checks);
        $display("POSE_OSD_ALL_PASS");
        $finish;
    end
    initial begin
        repeat(10) begin
            #20000000;
            $display("POSE_MONITOR state=%0d line=%0d point=%0d sub=%0d x=%0d y=%0d dx=%0d dy=%0d err=%0d count=%0d",
                     dut.state,dut.line_idx,dut.point_idx,dut.point_sub,dut.x0,dut.y0,dut.dx,dut.dy,dut.err,dut.draw_count);
            $display("POSE_ENDPOINTS x1=%0d y1=%0d kp8=(%0d,%0d,%0d) kp9=(%0d,%0d,%0d)",
                     dut.x1,dut.y1,dut.draw_x[8],dut.draw_y[8],dut.draw_conf[8],
                     dut.draw_x[9],dut.draw_y[9],dut.draw_conf[9]);
        end
    end
    initial begin
        #200000000;
        $fatal(1,"POSE_TIMEOUT");
    end
endmodule
