module top_module(
    input logic clk,           // 100 MHz system clock
    input logic reset,         // Active high reset (center button)
    input logic [3:0] btn,     // 4 buttons (up, left, right, down)
    input logic vauxp15,       // XADC analog input positive
    input logic vauxn15,       // XADC analog input negative
    output logic uart_tx,      // UART transmit line
    output logic [15:0] led    // LED output for debugging
);

    // AXI4-Stream signals between modules and arbiter
    logic [31:0] voltage_tdata;
    logic voltage_tvalid;
    logic voltage_tready;
    
    logic [31:0] temp_tdata;
    logic temp_tvalid;
    logic temp_tready;
    
    logic [31:0] button_tdata;
    logic button_tvalid;
    logic button_tready;
    
    logic [31:0] axi_tdata;
    logic axi_tvalid;
    logic axi_tready;
    
    logic [31:0] runtime_tdata;
    logic runtime_tvalid;
    logic runtime_tready;
    
    // AXI4-Stream from arbiter to UART formatter
    logic [31:0] arbiter_tdata;
    logic [2:0] arbiter_tid;    // Source ID
    logic arbiter_tvalid;
    logic arbiter_tready;
    
    // UART transmit signals
    logic [7:0] uart_data;
    logic uart_valid;
    logic uart_ready;
    
    // XADC wrapper signals
    logic [15:0] xadc_temp_data;
    logic xadc_temp_ready;
    logic [15:0] xadc_voltage_data;
    logic xadc_voltage_ready;

    // Instantiate XADC dual channel wrapper (SINGLE XADC for both channels)
    xadc_dual_channel XADC_WRAPPER (
        .clk(clk),
        .reset(reset),
        .vauxp15(vauxp15),
        .vauxn15(vauxn15),
        .temp_data(xadc_temp_data),
        .temp_ready(xadc_temp_ready),
        .voltage_data(xadc_voltage_data),
        .voltage_ready(xadc_voltage_ready)
    );

    // Instantiate voltage monitor (gets data from wrapper)
    voltage_monitor VOLTAGE_MON (
        .clk(clk),
        .reset(reset),
        .voltage_data_in(xadc_voltage_data),
        .voltage_ready_in(xadc_voltage_ready),
        .m_axis_tdata(voltage_tdata),
        .m_axis_tvalid(voltage_tvalid),
        .m_axis_tready(voltage_tready)
    );
    
    // Instantiate temperature monitor (gets data from wrapper)
    temperature_monitor TEMP_MON (
        .clk(clk),
        .reset(reset),
        .temp_data_in(xadc_temp_data),
        .temp_ready_in(xadc_temp_ready),
        .m_axis_tdata(temp_tdata),
        .m_axis_tvalid(temp_tvalid),
        .m_axis_tready(temp_tready)
    );
    
    // Instantiate button monitor
    button_monitor BUTTON_MON (
        .clk(clk),
        .reset(reset),
        .btn(btn),
        .m_axis_tdata(button_tdata),
        .m_axis_tvalid(button_tvalid),
        .m_axis_tready(button_tready),
        .led_debug(led)
    );
    
    // Instantiate AXI transaction monitor
    axi_monitor AXI_MON (
        .clk(clk),
        .reset(reset),
        .monitor_tvalid(arbiter_tvalid),
        .monitor_tready(arbiter_tready),
        .m_axis_tdata(axi_tdata),
        .m_axis_tvalid(axi_tvalid),
        .m_axis_tready(axi_tready)
    );
    
    // Instantiate runtime monitor
    runtime_monitor RUNTIME_MON (
        .clk(clk),
        .reset(reset),
        .m_axis_tdata(runtime_tdata),
        .m_axis_tvalid(runtime_tvalid),
        .m_axis_tready(runtime_tready)
    );
    
    // Instantiate AXI4-Stream arbiter
    axi_stream_arbiter ARBITER (
        .clk(clk),
        .reset(reset),
        // Voltage input
        .s0_axis_tdata(voltage_tdata),
        .s0_axis_tvalid(voltage_tvalid),
        .s0_axis_tready(voltage_tready),
        // Temperature input
        .s1_axis_tdata(temp_tdata),
        .s1_axis_tvalid(temp_tvalid),
        .s1_axis_tready(temp_tready),
        // Button input
        .s2_axis_tdata(button_tdata),
        .s2_axis_tvalid(button_tvalid),
        .s2_axis_tready(button_tready),
        // AXI monitor input
        .s3_axis_tdata(axi_tdata),
        .s3_axis_tvalid(axi_tvalid),
        .s3_axis_tready(axi_tready),
        // Runtime input
        .s4_axis_tdata(runtime_tdata),
        .s4_axis_tvalid(runtime_tvalid),
        .s4_axis_tready(runtime_tready),
        // Master output
        .m_axis_tdata(arbiter_tdata),
        .m_axis_tid(arbiter_tid),
        .m_axis_tvalid(arbiter_tvalid),
        .m_axis_tready(arbiter_tready)
    );
    
    // Instantiate UART formatter
    uart_formatter UART_FMT (
        .clk(clk),
        .reset(reset),
        .s_axis_tdata(arbiter_tdata),
        .s_axis_tid(arbiter_tid),
        .s_axis_tvalid(arbiter_tvalid),
        .s_axis_tready(arbiter_tready),
        .uart_tdata(uart_data),
        .uart_tvalid(uart_valid),
        .uart_tready(uart_ready)
    );
    
    // Instantiate UART transmitter
    uart_tx_module UART_TX (
        .clk(clk),
        .reset(reset),
        .tx_data(uart_data),
        .tx_valid(uart_valid),
        .tx_ready(uart_ready),
        .uart_tx(uart_tx)
    );

endmodule