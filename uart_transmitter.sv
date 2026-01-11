// UART Transmitter - 115200 baud

module uart_tx_module(
    input logic clk,           // 100 MHz
    input logic reset,
    input logic [7:0] tx_data,
    input logic tx_valid,
    output logic tx_ready,
    output logic uart_tx
);

    // Baud rate generation
    // 100 MHz / 115200 = 868.05 (use 868)
    localparam CLKS_PER_BIT = 868;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;
    
    state_t state;
    
    logic [9:0] clk_counter;
    logic [2:0] bit_index;
    logic [7:0] tx_data_reg;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            clk_counter <= 0;
            bit_index <= 0;
            tx_data_reg <= 0;
            uart_tx <= 1'b1;  // Idle high
        end else begin
            case (state)
                IDLE: begin
                    uart_tx <= 1'b1;
                    clk_counter <= 0;
                    bit_index <= 0;
                    
                    if (tx_valid) begin     // Formatter has valid data
                        tx_data_reg <= tx_data;
                        state <= START_BIT;
                    end
                end
                
                START_BIT: begin
                    uart_tx <= 1'b0;  // Start bit
                    
                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        clk_counter <= 0;
                        state <= DATA_BITS;
                    end
                end
                
                DATA_BITS: begin
                    uart_tx <= tx_data_reg[bit_index];
                    
                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        clk_counter <= 0;
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end
                    end
                end
                
                STOP_BIT: begin
                    uart_tx <= 1'b1;  // Stop bit
                    
                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        clk_counter <= 0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Ready signal - can accept new data when idle
    assign tx_ready = (state == IDLE);

endmodule