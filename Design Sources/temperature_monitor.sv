// Temperature Monitor - Reads temperature from XADC dual channel wrapper
// Samples at 1 Hz, converts to Celsius

module temperature_monitor(
    input logic clk,
    input logic reset,
    
    // Input from XADC wrapper
    input logic [15:0] temp_data_in,
    input logic temp_ready_in,
    
    output logic [31:0] m_axis_tdata,
    output logic m_axis_tvalid,
    input logic m_axis_tready
);

    logic [15:0] temp_celsius;
    
    // Sample rate divider (1 Hz)
    localparam SAMPLE_DIV = 100_000_000;
    logic [26:0] sample_counter;
    logic sample_trigger;
    
    // State machine
    typedef enum logic [1:0] {IDLE, WAIT_READY} state_t;
    state_t state;
    
    // Sample rate divider
    always_ff @(posedge clk) begin
        if (reset) begin
            sample_counter <= 0;
            sample_trigger <= 0;
        end else begin
            sample_trigger <= 0;
            if (sample_counter >= SAMPLE_DIV - 1) begin     // Resets counter and send trigger high at 99,999,999
                sample_counter <= 0;
                sample_trigger <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end
        end
    end
    
    // Temperature conversion
    // XADC Temp(°C) = (ADC_12bit * 504 / 4096) - 273
    // Formula from UG480 XADC user guide
    always_ff @(posedge clk) begin
        if (reset) begin
            temp_celsius <= 0;
        end else if (temp_ready_in) begin
            logic [15:0] adc_12bit;
            logic [31:0] temp_kelvin;
            
            // Extract 12-bit ADC from upper 12 bits
            adc_12bit = temp_data_in >> 4;
            
            // Calculate temperature in Kelvin, then convert to Celsius
            temp_kelvin = (adc_12bit * 504) >> 12;
            
            if (temp_kelvin >= 273)
                temp_celsius <= temp_kelvin[15:0] - 273;
            else
                temp_celsius <= 0;
        end
    end
    
    // State machine
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            m_axis_tvalid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 0;
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
    
    assign m_axis_tdata = {16'h0000, temp_celsius};     // Upper 16 bits reserved for future use

endmodule
