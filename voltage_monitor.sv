// Voltage Monitor - Reads voltage from XADC dual channel wrapper
// Samples at approximately 10 Hz (every 10 million clocks)

module voltage_monitor(
    input logic clk,
    input logic reset,
    
    // Input from XADC wrapper
    input logic [15:0] voltage_data_in,
    input logic voltage_ready_in,
    
    output logic [31:0] m_axis_tdata,
    output logic m_axis_tvalid,     // Master has valid data ready to send
    input logic m_axis_tready       // Slave is ready to receive
);

    // Voltage signals
    logic [15:0] voltage_raw;
    logic [15:0] voltage_scaled;
    
    // Moving average parameters (matches your original averager)
    localparam int POWER = 8;  // 2^8 = 256 samples
    localparam int N = 16;     // 16-bit data
    
    logic [N-1:0] REG_ARRAY [2**POWER:1];  // 16 by 256 array.
    logic [POWER+N-1:0] sum;
    logic [N-1:0] averaged_voltage;
    
    assign averaged_voltage = sum[POWER+N-1:POWER]; // Takes upper 16 bits of 24 bit sum (divide by 256)
    
    // Sample rate divider (10 Hz sampling)
    localparam SAMPLE_DIV = 10_000_000; // 100MHz / 10_000_000 = 10 Hz
    logic [23:0] sample_counter;
    logic sample_trigger;
    
    // AXI handshake state
    typedef enum logic [1:0] {IDLE, WAIT_READY} state_t;
    state_t state;
    logic [15:0] voltage_latched;
    
    // Sample rate divider
    always_ff @(posedge clk) begin
        if (reset) begin
            sample_counter <= 0;
            sample_trigger <= 0;
        end else begin
            sample_trigger <= 0;
            if (sample_counter >= SAMPLE_DIV - 1) begin     // Resets counter and send trigger high at 9,999,999
                sample_counter <= 0;
                sample_trigger <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end
        end
    end
    
    // Moving average (256 samples)
    always_ff @(posedge clk) begin
        if (reset) begin
            sum <= 0;
            for (int j = 1; j <= 2**POWER; j++) begin
                REG_ARRAY[j] <= 0;
            end
        end
        else if (voltage_ready_in) begin
            sum <= sum + voltage_data_in - REG_ARRAY[2**POWER];     // Adds in the newest reading, and removes the oldest.
            for (int j = 2**POWER; j > 1; j--) begin
                REG_ARRAY[j] <= REG_ARRAY[j-1];                     // Shifts all values up by 1.
            end
            REG_ARRAY[1] <= voltage_data_in;
        end
    end
    
    // Voltage scaling (applied to averaged value)
    // Scale to millivolts: (averaged_voltage * 250) >> 14  which is equivalent to multiplying by 1000 and dividing by 65535 (FFFFh)
    always_ff @(posedge clk) begin
        if (reset) begin
            voltage_scaled <= 0;
        end else if (voltage_ready_in) begin
            voltage_scaled <= (averaged_voltage * 250) >> 14;
        end
    end
    
    // AXI4-Stream output state machine
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            voltage_latched <= 0;
            m_axis_tvalid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;  // Clear valid when idle
                    if (sample_trigger) begin   // Triggers every second.
                        voltage_latched <= voltage_scaled;
                        m_axis_tvalid <= 1;
                        state <= WAIT_READY;
                    end
                end
                
                WAIT_READY: begin
                    if (m_axis_tready) begin    // tvalid is already 1. Once tready is 1, the data has been sent and tvalid can be set to 0.
                        m_axis_tvalid <= 0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Output data format: 32-bit value in millivolts
    assign m_axis_tdata = {16'h0000, voltage_latched};      // Upper 16 bits reserved for future use

endmodule