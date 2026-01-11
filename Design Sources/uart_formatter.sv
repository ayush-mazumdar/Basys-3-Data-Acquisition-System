// UART Formatter - Converts 32-bit data to ASCII UART packets

module uart_formatter(
    input logic clk,
    input logic reset,
    
    // AXI4-Stream input
    input logic [31:0] s_axis_tdata,
    input logic [2:0] s_axis_tid,
    input logic s_axis_tvalid,
    output logic s_axis_tready,
    
    // UART byte output
    output logic [7:0] uart_tdata,
    output logic uart_tvalid,
    input logic uart_tready
);

    // State machine
    typedef enum logic [3:0] {
        IDLE,
        COMPUTE_DIGITS1,
        COMPUTE_DIGITS2,
        SEND_TYPE,
        SEND_COLON,
        SEND_DIGIT_5,
        SEND_DIGIT_4,
        SEND_DIGIT_3,
        SEND_DIGIT_2,
        SEND_DIGIT_1,
        SEND_UNIT,
        SEND_CR,
        SEND_LF
    } state_t;
    
    state_t state, next_state;
    
    // Latched input data
    logic [31:0] data_latched;
    logic [2:0] id_latched;
    
    // ASCII conversion
    logic [7:0] current_char;
    logic [15:0] display_value;
    
    // Pre-computed digits using bit shifting (registered for timing)
    logic [3:0] digit_10000;
    logic [3:0] digit_1000;
    logic [3:0] digit_100;
    logic [3:0] digit_10;
    logic [3:0] digit_1;
    
    // Pre-computed type and unit characters (reduce combinational depth)
    logic [7:0] type_char;
    logic [7:0] unit_char;
    
    // Latch input data AND extract display value
    always_ff @(posedge clk) begin
        if (reset) begin
            data_latched <= 0;
            id_latched <= 0;
            display_value <= 0;
        end else if (state == IDLE && s_axis_tvalid) begin
            data_latched <= s_axis_tdata;
            id_latched <= s_axis_tid;
            // Extract the lower 16 bits as the display value
            display_value <= s_axis_tdata[15:0];
        end
    end
    
    // Pre-compute type and unit characters when data arrives
    always_ff @(posedge clk) begin
        if (reset) begin
            type_char <= 8'h3F;     // ?
            unit_char <= 8'h20;     // Space
        end else if (state == IDLE && s_axis_tvalid) begin
            case (s_axis_tid)
                3'h0: begin type_char <= 8'h56; unit_char <= 8'h6D; end // V, m
                3'h1: begin type_char <= 8'h54; unit_char <= 8'h43; end // T, C
                3'h2: begin type_char <= 8'h42; unit_char <= 8'h23; end // B, #
                3'h3: begin type_char <= 8'h41; unit_char <= 8'h23; end // A, #
                3'h4: begin type_char <= 8'h52; unit_char <= 8'h73; end // R, s
                default: begin type_char <= 8'h3F; unit_char <= 8'h20; end
            endcase
        end
    end
    
    // Pre-compute digits using cascaded comparisons across TWO clock cycles
    logic [15:0] temp_intermediate;  // Stores result after first 2 digits
    
    always_ff @(posedge clk) begin
        if (reset) begin
            digit_10000 <= 0;
            digit_1000 <= 0;
            digit_100 <= 0;
            digit_10 <= 0;
            digit_1 <= 0;
            temp_intermediate <= 0;
        end else if (state == COMPUTE_DIGITS1) begin
            // CYCLE 1: Extract ten-thousands and thousands only
            logic [15:0] temp1;
            
            // Extract ten-thousands
            if (display_value >= 16'd50000) begin
                digit_10000 <= 4'd5;
                temp1 = display_value - 16'd50000;
            end else if (display_value >= 16'd40000) begin
                digit_10000 <= 4'd4;
                temp1 = display_value - 16'd40000;
            end else if (display_value >= 16'd30000) begin
                digit_10000 <= 4'd3;
                temp1 = display_value - 16'd30000;
            end else if (display_value >= 16'd20000) begin
                digit_10000 <= 4'd2;
                temp1 = display_value - 16'd20000;
            end else if (display_value >= 16'd10000) begin
                digit_10000 <= 4'd1;
                temp1 = display_value - 16'd10000;
            end else begin
                digit_10000 <= 4'd0;
                temp1 = display_value;
            end
            
            // Extract thousands
            if (temp1 >= 16'd9000) begin digit_1000 <= 4'd9; temp_intermediate <= temp1 - 16'd9000; end
            else if (temp1 >= 16'd8000) begin digit_1000 <= 4'd8; temp_intermediate <= temp1 - 16'd8000; end
            else if (temp1 >= 16'd7000) begin digit_1000 <= 4'd7; temp_intermediate <= temp1 - 16'd7000; end
            else if (temp1 >= 16'd6000) begin digit_1000 <= 4'd6; temp_intermediate <= temp1 - 16'd6000; end
            else if (temp1 >= 16'd5000) begin digit_1000 <= 4'd5; temp_intermediate <= temp1 - 16'd5000; end
            else if (temp1 >= 16'd4000) begin digit_1000 <= 4'd4; temp_intermediate <= temp1 - 16'd4000; end
            else if (temp1 >= 16'd3000) begin digit_1000 <= 4'd3; temp_intermediate <= temp1 - 16'd3000; end
            else if (temp1 >= 16'd2000) begin digit_1000 <= 4'd2; temp_intermediate <= temp1 - 16'd2000; end
            else if (temp1 >= 16'd1000) begin digit_1000 <= 4'd1; temp_intermediate <= temp1 - 16'd1000; end
            else begin digit_1000 <= 4'd0; temp_intermediate <= temp1; end
            
        end else if (state == COMPUTE_DIGITS2) begin
            // CYCLE 2: Extract hundreds, tens, and ones
            logic [15:0] temp2;
            
            // Extract hundreds
            if (temp_intermediate >= 16'd900) begin digit_100 <= 4'd9; temp2 = temp_intermediate - 16'd900; end
            else if (temp_intermediate >= 16'd800) begin digit_100 <= 4'd8; temp2 = temp_intermediate - 16'd800; end
            else if (temp_intermediate >= 16'd700) begin digit_100 <= 4'd7; temp2 = temp_intermediate - 16'd700; end
            else if (temp_intermediate >= 16'd600) begin digit_100 <= 4'd6; temp2 = temp_intermediate - 16'd600; end
            else if (temp_intermediate >= 16'd500) begin digit_100 <= 4'd5; temp2 = temp_intermediate - 16'd500; end
            else if (temp_intermediate >= 16'd400) begin digit_100 <= 4'd4; temp2 = temp_intermediate - 16'd400; end
            else if (temp_intermediate >= 16'd300) begin digit_100 <= 4'd3; temp2 = temp_intermediate - 16'd300; end
            else if (temp_intermediate >= 16'd200) begin digit_100 <= 4'd2; temp2 = temp_intermediate - 16'd200; end
            else if (temp_intermediate >= 16'd100) begin digit_100 <= 4'd1; temp2 = temp_intermediate - 16'd100; end
            else begin digit_100 <= 4'd0; temp2 = temp_intermediate; end
            
            // Extract tens and ones (temp2 is now 0-99)
            if (temp2 >= 7'd90) begin digit_10 <= 4'd9; digit_1 <= temp2 - 7'd90; end
            else if (temp2 >= 7'd80) begin digit_10 <= 4'd8; digit_1 <= temp2 - 7'd80; end
            else if (temp2 >= 7'd70) begin digit_10 <= 4'd7; digit_1 <= temp2 - 7'd70; end
            else if (temp2 >= 7'd60) begin digit_10 <= 4'd6; digit_1 <= temp2 - 7'd60; end
            else if (temp2 >= 7'd50) begin digit_10 <= 4'd5; digit_1 <= temp2 - 7'd50; end
            else if (temp2 >= 7'd40) begin digit_10 <= 4'd4; digit_1 <= temp2 - 7'd40; end
            else if (temp2 >= 7'd30) begin digit_10 <= 4'd3; digit_1 <= temp2 - 7'd30; end
            else if (temp2 >= 7'd20) begin digit_10 <= 4'd2; digit_1 <= temp2 - 7'd20; end
            else if (temp2 >= 7'd10) begin digit_10 <= 4'd1; digit_1 <= temp2 - 7'd10; end
            else begin digit_10 <= 4'd0; digit_1 <= temp2[3:0]; end
        end
    end
    
    // State register
    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (s_axis_tvalid)
                    next_state = COMPUTE_DIGITS1;
            end
            
            COMPUTE_DIGITS1: begin
                next_state = COMPUTE_DIGITS2;  // First half of computation
            end
            
            COMPUTE_DIGITS2: begin
                next_state = SEND_TYPE;  // Second half of computation
            end
            
            SEND_TYPE: begin
                if (uart_tready)
                    next_state = SEND_COLON;
            end
            
            SEND_COLON: begin
                if (uart_tready)
                    next_state = SEND_DIGIT_5;
            end
            
            SEND_DIGIT_5: begin
                if (uart_tready)
                    next_state = SEND_DIGIT_4;
            end
            
            SEND_DIGIT_4: begin
                if (uart_tready)
                    next_state = SEND_DIGIT_3;
            end
            
            SEND_DIGIT_3: begin
                if (uart_tready)
                    next_state = SEND_DIGIT_2;
            end
            
            SEND_DIGIT_2: begin
                if (uart_tready)
                    next_state = SEND_DIGIT_1;
            end
            
            SEND_DIGIT_1: begin
                if (uart_tready)
                    next_state = SEND_UNIT;
            end
            
            SEND_UNIT: begin
                if (uart_tready)
                    next_state = SEND_CR;
            end
            
            SEND_CR: begin
                if (uart_tready)
                    next_state = SEND_LF;
            end
            
            SEND_LF: begin
                if (uart_tready)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Character generation (now just uses pre-computed values)
    always_comb begin
        current_char = 8'h20; // Space default
        
        case (state)
            SEND_TYPE: current_char = type_char;
            SEND_COLON: current_char = 8'h3A; // ':'
            SEND_DIGIT_5: current_char = 8'h30 + {4'h0, digit_10000};       // ASCII codes h30 to h39 correspond to 0-9
            SEND_DIGIT_4: current_char = 8'h30 + {4'h0, digit_1000};
            SEND_DIGIT_3: current_char = 8'h30 + {4'h0, digit_100};
            SEND_DIGIT_2: current_char = 8'h30 + {4'h0, digit_10};
            SEND_DIGIT_1: current_char = 8'h30 + {4'h0, digit_1};
            SEND_UNIT: current_char = unit_char;
            SEND_CR: current_char = 8'h0D; // '\r'
            SEND_LF: current_char = 8'h0A; // '\n'
            default: current_char = 8'h20;
        endcase
    end
    
    // Output assignments
    assign uart_tdata = current_char;
    assign uart_tvalid = (state != IDLE && state != COMPUTE_DIGITS1 && state != COMPUTE_DIGITS2);
    assign s_axis_tready = (state == IDLE);

endmodule
