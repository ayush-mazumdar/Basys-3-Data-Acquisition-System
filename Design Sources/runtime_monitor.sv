// Runtime Monitor - Tracks time since last reset
// Samples at approximately 2 Hz (every 50 million clocks)

module runtime_monitor(
    input logic clk,
    input logic reset,
    output logic [31:0] m_axis_tdata,
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    // Runtime counter (counts seconds)
    logic [31:0] runtime_seconds;
    logic [26:0] clock_counter;
    localparam CLOCKS_PER_SECOND = 100_000_000; // 100 MHz
    
    // Sample rate divider (2 Hz sampling)
    localparam SAMPLE_DIV = 50_000_000;
    logic [25:0] sample_counter;
    logic sample_trigger;
    
    // State machine
    typedef enum logic [1:0] {IDLE, WAIT_READY} state_t;
    state_t state;
    logic [31:0] runtime_latched;
    
    // Count seconds since reset
    always_ff @(posedge clk) begin
        if (reset) begin
            runtime_seconds <= 0;
            clock_counter <= 0;
        end else begin
            if (clock_counter >= CLOCKS_PER_SECOND - 1) begin
                clock_counter <= 0;
                runtime_seconds <= runtime_seconds + 1;
            end else begin
                clock_counter <= clock_counter + 1;     // Increments counter every second
            end
        end
    end
    
    // Sample rate divider
    always_ff @(posedge clk) begin
        if (reset) begin
            sample_counter <= 0;
            sample_trigger <= 0;
        end else begin
            sample_trigger <= 0;
            if (sample_counter >= SAMPLE_DIV - 1) begin     // Resets counter and send trigger high at 49,999,999
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
            runtime_latched <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;  // Clear valid when idle
                    if (sample_trigger) begin
                        runtime_latched <= runtime_seconds;
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
    
    // Output format: runtime in seconds
    assign m_axis_tdata = runtime_latched;

endmodule
