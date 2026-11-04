//串行数据转差分
module ser_to_diff
(
    input  ser_data     ,
    output ser_data_p   ,
    output ser_data_n
);
//源语调用
 OBUFDS #(
      .IOSTANDARD("TMDS_33"), // Specify the output I/O standard
      .SLEW("SLOW")           // Specify the output slew rate
   ) OBUFDS_inst (
      .O(ser_data_p),     // Diff_p output (connect directly to top-level port)
      .OB(ser_data_n),   // Diff_n output (connect directly to top-level port)
      .I(ser_data)      // Buffer input
   );
endmodule