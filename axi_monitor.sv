// AXI Transaction Monitor - Counts total AXI transactions through the system
// Samples at approximately 0.5 Hz (every 200 million clocks)

module axi_monitor(
    input logic clk,
    input logic reset,
    
    // Monitor signals from arbiter
    input logic monitor_tvalid,
    input logic monitor_tready,
    
    output logic [31:0] m_axis_tdata,
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    // Sample rate divider (0.5 Hz sampling)
    localparam SAMPLE_DIV = 200_000_000;
    logic [27:0] sample_counter;
    logic sample_trigger;
    
    // State machine
    typedef enum logic [1:0] {IDLE, WAIT_READY} state_t;
    state_t state;
    
    // Transaction counting
    logic [15:0] total_transactions;
    logic transaction_complete;
    
    // Detect completed AXI transactions (valid && ready handshake)
    assign transaction_complete = monitor_tvalid && monitor_tready;     // True when arbiter is ready to transmit and UART is ready to receive
    
    // Count transactions
    always_ff @(posedge clk) begin
        if (reset) begin
            total_transactions <= 0;
        end else if (transaction_complete) begin
            total_transactions <= total_transactions + 1;
        end
    end
    
    // Sample rate divider
    always_ff @(posedge clk) begin
        if (reset) begin
            sample_counter <= 0;
            sample_trigger <= 0;
        end else begin
            sample_trigger <= 0;
            if (sample_counter >= SAMPLE_DIV - 1) begin
                sample_counter <= 0;
                sample_trigger <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end
        end
    end
    
    // AXI4-Stream output state machine
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            m_axis_tvalid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;  // Clear valid when idle
                    if (sample_trigger) begin
                        m_axis_tvalid <= 1;
                        state <= WAIT_READY;
                    end
                end
                
                WAIT_READY: begin
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign m_axis_tdata = {16'h0000, total_transactions};       // Top 16 bits reserved for future use

endmodule