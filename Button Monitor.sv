// Button Monitor - Tracks button presses
// Outputs data whenever a button is pressed
// Uses 3-stage synchronizer + 50ms debounce timer

module button_monitor(
    input logic clk,
    input logic reset,
    input logic [3:0] btn,     // btn[0]=up, [1]=left, [2]=right, [3]=down
    output logic [31:0] m_axis_tdata,
    output logic m_axis_tvalid,
    input logic m_axis_tready,
    output logic [15:0] led_debug
);

    // Three-stage synchronizer for metastability
    logic [3:0] btn_sync1, btn_sync2, btn_sync3;
    
    // Debounce timer - 50ms debounce period at 100MHz
    localparam DEBOUNCE_TIME = 5_000_000; // 50ms
    logic [22:0] debounce_counter [3:0];
    logic [3:0] btn_stable;
    logic [3:0] btn_stable_prev;
    logic [3:0] btn_edge;
    logic button_pressed;
    
    // Button press tracking
    logic [15:0] total_presses;
    
    // State machine
    typedef enum logic [2:0] {IDLE, SEND_INITIAL, LATCH_PRESS, SEND_DATA, WAIT_READY} state_t;
    state_t state;
    logic [31:0] data_to_send;
    logic initial_sent;
    
    // Three-stage synchronizer
    always_ff @(posedge clk) begin
        if (reset) begin
            btn_sync1 <= 4'b0;
            btn_sync2 <= 4'b0;
            btn_sync3 <= 4'b0;
        end else begin
            btn_sync1 <= btn;
            btn_sync2 <= btn_sync1;
            btn_sync3 <= btn_sync2;
        end
    end
    
    // Debounce logic for each button
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 4; i++) begin
                debounce_counter[i] <= 0;
                btn_stable[i] <= 0;
            end
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (btn_sync3[i] == btn_stable[i]) begin
                    // Button state matches stable state, reset counter
                    debounce_counter[i] <= 0;
                end else begin
                    // Button states different (debounces both press and release)
                    if (debounce_counter[i] >= DEBOUNCE_TIME) begin
                        // Debounce time elapsed, update stable state
                        btn_stable[i] <= btn_sync3[i];
                        debounce_counter[i] <= 0;
                    end else begin      // Increments counter if button states are different and debounce counter is less than 5,000,000
                        debounce_counter[i] <= debounce_counter[i] + 1;
                    end
                end
            end
        end
    end
    
    // Edge detection on debounced signal
    always_ff @(posedge clk) begin
        if (reset) begin
            btn_stable_prev <= 4'b0;
        end else begin
            btn_stable_prev <= btn_stable;
        end
    end
    
    assign btn_edge = btn_stable & ~btn_stable_prev;
    assign button_pressed = |btn_edge;      // Reduces a 4 bit value to a one bit value that goes high whenever any directional buttone is pressed
    
    // Button press counter
    always_ff @(posedge clk) begin
        if (reset) begin
            total_presses <= 0;
        end else if (state == LATCH_PRESS) begin
            total_presses <= total_presses + 1;
        end
    end
    
    // State machine with initial transmission
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            m_axis_tvalid <= 0;
            data_to_send <= 0;
            initial_sent <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;
                    
                    // Send initial "0" state once after reset
                    if (!initial_sent) begin
                        data_to_send <= {16'h0000, total_presses};
                        m_axis_tvalid <= 1;
                        state <= SEND_INITIAL;
                    end
                    else if (button_pressed) begin
                        state <= LATCH_PRESS;
                    end
                end
                
                SEND_INITIAL: begin     // State for recording 0 presses on reset
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 0;
                        initial_sent <= 1;
                        state <= IDLE;
                    end
                end
                
                LATCH_PRESS: begin
                    state <= SEND_DATA;
                end
                
                SEND_DATA: begin
                    data_to_send <= {16'h0000, total_presses};
                    m_axis_tvalid <= 1;
                    state <= WAIT_READY;
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
    
    assign m_axis_tdata = data_to_send;
    assign led_debug = total_presses;

endmodule