// AXI4-Stream Arbiter - Round-robin arbiter for 5 input streams
// Prioritizes inputs and forwards data with source ID

module axi_stream_arbiter(
    input logic clk,
    input logic reset,
    
    // Slave interfaces (5 inputs)
    input logic [31:0] s0_axis_tdata,   // Voltage
    input logic s0_axis_tvalid,
    output logic s0_axis_tready,
    
    input logic [31:0] s1_axis_tdata,   // Temperature
    input logic s1_axis_tvalid,
    output logic s1_axis_tready,
    
    input logic [31:0] s2_axis_tdata,   // Button
    input logic s2_axis_tvalid,
    output logic s2_axis_tready,
    
    input logic [31:0] s3_axis_tdata,   // AXI
    input logic s3_axis_tvalid,
    output logic s3_axis_tready,
    
    input logic [31:0] s4_axis_tdata,   // Runtime
    input logic s4_axis_tvalid,
    output logic s4_axis_tready,
    
    // Master interface
    output logic [31:0] m_axis_tdata,
    output logic [2:0] m_axis_tid,      // Source identifier
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    // Internal state
    typedef enum logic [2:0] {
        IDLE,
        SERVE_0,
        SERVE_1,
        SERVE_2,
        SERVE_3,
        SERVE_4
    } state_t;
    
    state_t state, next_state;
    logic [2:0] last_served;
    
    // State register
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            last_served <= 0;
        end else begin
            state <= next_state;
            // Only update last_served when transaction completes
            if ((state != IDLE) && m_axis_tvalid && m_axis_tready) begin
                last_served <= m_axis_tid;
            end
        end
    end
    
    // Next state logic with round-robin priority
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                // Round-robin selection starting after last_served
                // When in SERVE_1, the next state in line will always be SERVE_2 and SERVE_1 gets pushed to the back of the line
                
                // Sample Pathing: reset -> IDLE -> case 0 -> next_state = SERVE_1 -> state = SERVE_1 -> case SERVE_1 sets outputs and sets m_axis_tvalid high
                //                 ->  m_axis_tvalid && m_axis_tready is true -> last_served is now 1 and next_state = IDLE -> state = IDLE -> case 1...
                case (last_served)
                    0: begin
                        if (s1_axis_tvalid) next_state = SERVE_1;
                        else if (s2_axis_tvalid) next_state = SERVE_2;
                        else if (s3_axis_tvalid) next_state = SERVE_3;
                        else if (s4_axis_tvalid) next_state = SERVE_4;
                        else if (s0_axis_tvalid) next_state = SERVE_0;
                    end
                    1: begin
                        if (s2_axis_tvalid) next_state = SERVE_2;
                        else if (s3_axis_tvalid) next_state = SERVE_3;
                        else if (s4_axis_tvalid) next_state = SERVE_4;
                        else if (s0_axis_tvalid) next_state = SERVE_0;
                        else if (s1_axis_tvalid) next_state = SERVE_1;
                    end
                    2: begin
                        if (s3_axis_tvalid) next_state = SERVE_3;
                        else if (s4_axis_tvalid) next_state = SERVE_4;
                        else if (s0_axis_tvalid) next_state = SERVE_0;
                        else if (s1_axis_tvalid) next_state = SERVE_1;
                        else if (s2_axis_tvalid) next_state = SERVE_2;
                    end
                    3: begin
                        if (s4_axis_tvalid) next_state = SERVE_4;
                        else if (s0_axis_tvalid) next_state = SERVE_0;
                        else if (s1_axis_tvalid) next_state = SERVE_1;
                        else if (s2_axis_tvalid) next_state = SERVE_2;
                        else if (s3_axis_tvalid) next_state = SERVE_3;
                    end
                    default: begin // 4 or higher
                        if (s0_axis_tvalid) next_state = SERVE_0;
                        else if (s1_axis_tvalid) next_state = SERVE_1;
                        else if (s2_axis_tvalid) next_state = SERVE_2;
                        else if (s3_axis_tvalid) next_state = SERVE_3;
                        else if (s4_axis_tvalid) next_state = SERVE_4;
                    end
                endcase
            end
            
            SERVE_0, SERVE_1, SERVE_2, SERVE_3, SERVE_4: begin
                // Wait for handshake to complete before going back to IDLE
                if (m_axis_tvalid && m_axis_tready) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output multiplexing
    always_comb begin
        // Default values
        m_axis_tdata = 32'h0;
        m_axis_tid = 3'h0;
        m_axis_tvalid = 1'b0;
        s0_axis_tready = 1'b0;
        s1_axis_tready = 1'b0;
        s2_axis_tready = 1'b0;
        s3_axis_tready = 1'b0;
        s4_axis_tready = 1'b0;
        
        case (state)
            SERVE_0: begin
                m_axis_tdata = s0_axis_tdata;       // Links arbiter output data to voltage
                m_axis_tid = 3'h0;
                m_axis_tvalid = s0_axis_tvalid;     // Sends valid signal from arbiter to UART
                s0_axis_tready = m_axis_tready;     // Sends t_ready signal from UART to voltage monitor
            end
            SERVE_1: begin
                m_axis_tdata = s1_axis_tdata;       // Links arbiter output data to temperature
                m_axis_tid = 3'h1;
                m_axis_tvalid = s1_axis_tvalid;     // Sends valid signal from arbiter to UART
                s1_axis_tready = m_axis_tready;     // Sends t_ready signal from UART to temperature monitor
            end
            SERVE_2: begin
                m_axis_tdata = s2_axis_tdata;       // Links arbiter output data to button presses
                m_axis_tid = 3'h2;
                m_axis_tvalid = s2_axis_tvalid;     // Sends valid signal from arbiter to UART
                s2_axis_tready = m_axis_tready;     // Sends t_ready signal from UART to button monitor
            end
            SERVE_3: begin
                m_axis_tdata = s3_axis_tdata;       // Links arbiter output data to AXI transactions
                m_axis_tid = 3'h3;
                m_axis_tvalid = s3_axis_tvalid;     // Sends valid signal from arbiter to UART
                s3_axis_tready = m_axis_tready;     // Sends t_ready signal from UART to AXI monitor
            end
            SERVE_4: begin
                m_axis_tdata = s4_axis_tdata;       // Links arbiter output data to runtime
                m_axis_tid = 3'h4;
                m_axis_tvalid = s4_axis_tvalid;     // Sends valid signal from arbiter to UART
                s4_axis_tready = m_axis_tready;     // Sends t_ready signal from UART to runtime monitor
            end
            default: begin
                // IDLE state - all signals already defaulted
            end
        endcase
    end

endmodule
