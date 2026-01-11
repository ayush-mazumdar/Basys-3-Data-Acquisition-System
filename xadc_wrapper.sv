// Reads both Temperature (Channel 0) and VAUXP15/VAUXN15 (Channel 15)
// Distributes data to both temperature and voltage monitors


module xadc_dual_channel(
    input logic clk,
    input logic reset,
    input logic vauxp15,
    input logic vauxn15,
    
    // Temperature output
    output logic [15:0] temp_data,
    output logic temp_ready,
    
    // Voltage output
    output logic [15:0] voltage_data,
    output logic voltage_ready
);

    // XADC signals
    logic [6:0] daddr_in;           // Channel being read by XADC
    logic den_in;                   // Data enable (start reading)
    logic [15:0] di_in;
    logic dwe_in;                   // Data write enable
    logic drdy_out;                 // Data is ready for reading
    logic [15:0] do_out;            // Data output
    logic [4:0] channel_out;        // Unused
    logic eoc_out;                  // End of conversion from analog to digital
    
    // Channel addresses
    localparam TEMP_ADDR = 7'h00;    // Temperature
    localparam VOLT_ADDR = 7'h1F;    // VAUXP15/VAUXN15
    
    // State machine for reading both channels
    typedef enum logic [2:0] {
        STARTUP,
        IDLE,
        WAIT_EOC,
        READ_TEMP,
        WAIT_TEMP,
        READ_VOLT,
        WAIT_VOLT
    } state_t;
    
    state_t state;
    
    // Startup delay counter
    logic [23:0] startup_counter;
    
    // Output registers
    logic [15:0] temp_data_reg;
    logic [15:0] voltage_data_reg;
    logic temp_ready_pulse;
    logic voltage_ready_pulse;
    
    // Single XADC wizard instance (xadc_wiz_0)
    xadc_wiz_0 XADC_INST (
        .di_in(di_in),
        .daddr_in(daddr_in),
        .den_in(den_in),
        .dwe_in(dwe_in),
        .drdy_out(drdy_out),
        .do_out(do_out),
        .dclk_in(clk),
        .reset_in(reset),
        .vp_in(1'b0),
        .vn_in(1'b0),
        .vauxp15(vauxp15),
        .vauxn15(vauxn15),
        .channel_out(channel_out),
        .eoc_out(eoc_out),
        .alarm_out(),
        .eos_out(),
        .busy_out()
    );
    
    assign di_in = 16'h0000;
    assign dwe_in = 1'b0;  // Read only
    
    // Generates a pulse when data is ready for reading
    logic drdy_r;
    logic drdy_pulse;
    
    always_ff @(posedge clk) begin
        if (reset)
            drdy_r <= 0;
        else
            drdy_r <= drdy_out;
    end
    
    assign drdy_pulse = ~drdy_r & drdy_out;
    
    // State machine to alternate between reading temperature and voltage
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= STARTUP;
            den_in <= 0;
            daddr_in <= 0;
            temp_data_reg <= 0;
            voltage_data_reg <= 0;
            temp_ready_pulse <= 0;
            voltage_ready_pulse <= 0;
            startup_counter <= 0;
        end else begin
            temp_ready_pulse <= 0;
            voltage_ready_pulse <= 0;
            
            case (state)
                STARTUP: begin
                    // Wait for XADC to initialize (10ms)
                    if (startup_counter >= 1_000_000) begin
                        startup_counter <= 0;
                        state <= IDLE;
                    end else begin
                        startup_counter <= startup_counter + 1;
                    end
                end
                
                IDLE: begin                         
                    den_in <= 0;
                    state <= WAIT_EOC;
                end
                
                WAIT_EOC: begin     // Requests temperature reading once conversion is finished
                    if (eoc_out) begin
                        daddr_in <= TEMP_ADDR;
                        den_in <= 1;
                        state <= READ_TEMP;
                    end
                end
                
                READ_TEMP: begin
                    den_in <= 0;    // Wait for temperature reading to be ready
                    state <= WAIT_TEMP;
                end
                
                WAIT_TEMP: begin    // When data is ready, read data onto temp_data_reg and request voltage reading
                    if (drdy_pulse) begin
                        temp_data_reg <= do_out;
                        temp_ready_pulse <= 1;
                        daddr_in <= VOLT_ADDR;
                        den_in <= 1;
                        state <= READ_VOLT;
                    end
                end
                
                READ_VOLT: begin    // Wait for voltage reading to be ready
                    den_in <= 0;
                    state <= WAIT_VOLT;
                end
                
                WAIT_VOLT: begin    // When data is ready, read data onto voltage_data_reg and wait for next ADC conversion.
                    if (drdy_pulse) begin
                        voltage_data_reg <= do_out;
                        voltage_ready_pulse <= 1;
                        state <= WAIT_EOC;
                    end
                end
                
                default: state <= STARTUP;
            endcase
        end
    end
    
    // Output assignments
    assign temp_data = temp_data_reg;
    assign voltage_data = voltage_data_reg;
    assign temp_ready = temp_ready_pulse;
    assign voltage_ready = voltage_ready_pulse;

endmodule