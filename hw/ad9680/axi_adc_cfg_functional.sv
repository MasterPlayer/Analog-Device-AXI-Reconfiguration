`timescale 1ns / 1ps


module axi_adc_cfg_functional (
    input  logic        CLK                         ,
    input  logic        RESET                       ,
    // signal from AXI_DEV interface
    input  logic [31:0] WDATA                       ,
    input  logic [ 3:0] WSTRB                       ,
    input  logic [ 8:0] WADDR                       ,
    input  logic        WVALID                      ,
    // read interface
    input  logic [ 8:0] RADDR                       ,
    output logic [31:0] RDATA                       ,
    // control
    input  logic [31:0] REQUEST_FROM_DEVICE_INTERVAL,
    output logic        ADC_GOOD                    ,
    output logic        ADC_BAD                     ,
    //
    input  logic        SDIO_CLK                    ,
    // component control
    output logic        ADC_CSB                     ,
    output logic        ADC_PDWN                    ,
    output logic        ADC_SCLK                    ,
    inout  logic        ADC_SDIO
);

    localparam integer ADDRESS_BEGIN = 11'h000;
    localparam integer ADDRESS_END   = 11'h5C5;

    localparam [10:0] CHIP_TYPE           = 11'h004;
    localparam [10:0] VENDOR_ID_L         = 11'h00C;
    localparam [10:0] VENDOR_ID_H         = 11'h00D;
    localparam [10:0] ADDRESS_PLL_CONTROL = 11'h56F;

    logic need_update_flaq = 'b0;

    typedef enum {
        IDLE_CHECK_FROM_DEVICE_ST       , // await new action
        IDLE_CHECK_TO_DEVICE_ST         , // await new action
        // if request data flaq
        FROM_DEVICE_TX_ADDR_PTR_ST      , // send address pointer 
        FROM_DEVICE_RX_READ_DATA_ST     , // await data from start to tlast signal 
        // if need update flaq asserted
        TO_DEVICE_READ_FIFO_ST          ,
        TO_DEVICE_CHK_ST                , 
        TO_DEVICE_TX_ST                 ,
        TO_DEVICE_INCREMENT_ADDR_ST     ,
        TO_DEVICE_WAIT_ST                
    } fsm;

    fsm current_state = IDLE_CHECK_FROM_DEVICE_ST;

    logic request_flaq = 'b0;

    logic [31:0] out_din_data = '{default:0};
    logic [ 3:0] out_din_keep = '{default:1};
    logic        out_wren     = 1'b0        ;
    logic        out_awfull                 ;

    // read memory signal group : 8 bit input 32 bit output;
    logic [10:0] read_memory_addra = '{default:0};
    logic [ 7:0] read_memory_dina  = '{default:0};
    logic        read_memory_wea                 ;
    logic [31:0] read_memory_doutb               ;
    logic [ 8:0] read_memory_addrb = '{default:0};

    logic [31:0] s_axis_tdata ;
    logic        s_axis_tvalid;
    logic        s_axis_tready;

    logic [31:0] m_axis_tdata ;
    logic        m_axis_tvalid;
    logic        m_axis_tready;

    logic [31:0] request_from_device_interval_counter;

    logic has_ad9680;

    logic [7:0] reg_0004;
    logic [7:0] reg_000c;
    logic [7:0] reg_000d;
    logic [7:0] reg_056f;

    logic [44:0] fifo_din         ;
    logic        fifo_wren        ;
    logic        fifo_full        ;
    logic [44:0] fifo_dout        ;
    logic        fifo_rden  = 1'b0;
    logic        fifo_empty       ;

    logic [ 8:0] addr_reg_high = '{default:0};
    logic [ 1:0] addr_reg_low  = '{default:0};
    logic [31:0] data_reg      = '{default:0};
    logic [ 3:0] wstrb_reg     = '{default:0};



    always_ff @(posedge CLK) begin : reg_0004_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == CHIP_TYPE) begin 
                        reg_0004 <= read_memory_dina;
                    end else begin 
                        reg_0004 <= reg_0004;
                    end 
                end else begin 
                    reg_0004 <= reg_0004;
                end 

            default : 
                reg_0004 <= reg_0004;
        endcase
    end 



    always_ff @(posedge CLK) begin : reg_000c_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == VENDOR_ID_L) begin 
                        reg_000c <= read_memory_dina;
                    end else begin 
                        reg_000c <= reg_000c;
                    end 
                end else begin 
                    reg_000c <= reg_000c;
                end 

            default : 
                reg_000c <= reg_000c;
        endcase
    end 



    always_ff @(posedge CLK) begin : reg_000d_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == VENDOR_ID_H) begin 
                        reg_000d <= read_memory_dina;
                    end else begin 
                        reg_000d <= reg_000d;
                    end 
                end else begin 
                    reg_000d <= reg_000d;
                end 

            default : 
                reg_000d <= reg_000d;
        endcase
    end 



    always_ff @(posedge CLK) begin : reg_056f_processing  
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == (ADDRESS_PLL_CONTROL)) begin 
                        reg_056f <= read_memory_dina;
                    end else begin 
                        reg_056f <= reg_056f;
                    end 
                end else begin 
                    reg_056f <= reg_056f;
                end 

            default : 
                reg_056f <= reg_056f;

        endcase // current_state
    end 



    always_ff @(posedge CLK) begin : has_ad9680_processing 
        if ((reg_0004 == 8'hC5) & (reg_000c == 8'h56) & (reg_000d == 8'h04)) begin 
            has_ad9680 <= 1'b1;
        end else begin 
            has_ad9680 <= 1'b0;
        end 
    end


    always_ff @(posedge CLK) begin : ADC_GOOD_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == ADDRESS_END) begin 
                        if (reg_056f[7] == 1'b1) begin 
                            ADC_GOOD <= has_ad9680;
                        end else begin 
                            ADC_GOOD <= 1'b0;
                        end 
                    end else begin 
                        ADC_GOOD <= ADC_GOOD;
                    end 
                end else begin 
                    ADC_GOOD <= ADC_GOOD;
                end 
            default : 
                ADC_GOOD <= ADC_GOOD;
        endcase // current_state
    end 


    always_ff @(posedge CLK) begin : ADC_BAD_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == ADDRESS_END) begin 
                        if (reg_056f[7] == 1'b1) begin 
                            ADC_BAD <= ~has_ad9680;
                        end else begin 
                            ADC_BAD <= 1'b1;
                        end 
                    end else begin 
                        ADC_BAD <= ADC_BAD;
                    end 
                end else begin 
                    ADC_BAD <= ADC_BAD;
                end 
            default : 
                ADC_BAD <= ADC_BAD;
        endcase // current_state
    end 


    always_ff@(posedge CLK) begin 
        if (RESET) begin 
            ADC_PDWN <= 1'b1;
        end else begin 
            ADC_PDWN <= 1'b0;
        end 
    end 

    always_ff @(posedge CLK) begin : request_from_device_interval_counter_processing 
        if (RESET) begin 
            request_from_device_interval_counter <= '{default:0};
        end else begin 
            case (current_state) 

                FROM_DEVICE_RX_READ_DATA_ST :
                    request_from_device_interval_counter <= '{default:0};

                FROM_DEVICE_TX_ADDR_PTR_ST : 
                    request_from_device_interval_counter <= '{default:0};

                default : 
                    if (request_from_device_interval_counter == (REQUEST_FROM_DEVICE_INTERVAL-1)) begin 
                        request_from_device_interval_counter <= request_from_device_interval_counter;
                    end else begin 
                        request_from_device_interval_counter <= request_from_device_interval_counter + 1;
                    end 

            endcase // current_state
        end 
    end 



    always_ff @(posedge CLK) begin : request_flaq_processing 
        case (current_state)

            IDLE_CHECK_FROM_DEVICE_ST : 
                request_flaq <= 1'b0;

            default : 
                if (request_from_device_interval_counter == (REQUEST_FROM_DEVICE_INTERVAL-1)) begin 
                    request_flaq <= 1'b1;
                end else begin 
                    request_flaq <= 1'b0;
                end 

        endcase // current_state
    end 



    always_ff @(posedge CLK) begin 
        if (RESET) begin 
            s_axis_tready <= 1'b0;
        end else begin 
            s_axis_tready <= 1'b1;
        end 
    end 



    always_comb begin : RDATA_processing 

        RDATA = read_memory_doutb;
    end 



    always_comb begin : fifo_din_processing 
        fifo_din[31:0]  = WDATA; // данные 32 бит
        fifo_din[35:32] = WSTRB; // валидность байт в слове
        fifo_din[44:36] = WADDR; // только старшая часть адреса, надо будет оставшуюся часть вычислять на основе WSTRB
    end 



    always_comb begin : fifo_wren_processing 
        fifo_wren = WVALID;
    end 



    fifo_cmd_sync_xpm #(
        .DATA_WIDTH(64     ),
        .MEMTYPE   ("block"),
        .DEPTH     (512    )
    ) fifo_cmd_sync_xpm_inst (
        .CLK  (CLK       ),
        .RESET(RESET     ),
        .DIN  (fifo_din  ),
        .WREN (fifo_wren ),
        .FULL (fifo_full ),
        .DOUT (fifo_dout ),
        .RDEN (fifo_rden ),
        .EMPTY(fifo_empty)
    );



    always_ff @(posedge CLK) begin : fifo_rden_processing 
        case (current_state) 
            TO_DEVICE_READ_FIFO_ST : 
                fifo_rden <= 1'b1;

            default : 
                fifo_rden <= 1'b0;

        endcase // current_state
    end 




    always_ff @(posedge CLK) begin : addr_reg_high_processing 
        case (current_state)
            TO_DEVICE_READ_FIFO_ST : 
                addr_reg_high <= fifo_dout[44:36];

            default : 
                addr_reg_high <= addr_reg_high;

        endcase 
    end 



    always_ff @(posedge CLK) begin : wstrb_reg_processing 
        case (current_state)
            TO_DEVICE_READ_FIFO_ST : 
                wstrb_reg <= fifo_dout[35:32];

            TO_DEVICE_INCREMENT_ADDR_ST: 
                wstrb_reg <= {1'b0, wstrb_reg[3:1]};

            default : 
                wstrb_reg <= wstrb_reg;

        endcase 
    end 


    always_ff @(posedge CLK) begin : data_reg_processing 
        case (current_state)
            TO_DEVICE_READ_FIFO_ST : 
                data_reg <= fifo_dout[31:0];


            TO_DEVICE_INCREMENT_ADDR_ST : 
                data_reg <= {8'h00, data_reg[31:8]}; 

            default : 
                data_reg <= data_reg;

        endcase 
    end 




    xpm_memory_sdpram #(
        .ADDR_WIDTH_A           (11             ), // DECIMAL
        .ADDR_WIDTH_B           (9              ), // DECIMAL
        .AUTO_SLEEP_TIME        (0              ), // DECIMAL
        .BYTE_WRITE_WIDTH_A     (8              ), // DECIMAL
        .CASCADE_HEIGHT         (0              ), // DECIMAL
        .CLOCKING_MODE          ("common_clock" ), // String
        .ECC_MODE               ("no_ecc"       ), // String
        .MEMORY_INIT_FILE       ("none"         ), // String
        .MEMORY_INIT_PARAM      ("0"            ), // String
        .MEMORY_OPTIMIZATION    ("true"         ), // String
        .MEMORY_PRIMITIVE       ("auto"         ), // String
        .MEMORY_SIZE            (16384          ), // DECIMAL
        .MESSAGE_CONTROL        (0              ), // DECIMAL
        .READ_DATA_WIDTH_B      (32             ), // DECIMAL
        .READ_LATENCY_B         (1              ), // DECIMAL
        .READ_RESET_VALUE_B     ("0"            ), // String
        .RST_MODE_A             ("SYNC"         ), // String
        .RST_MODE_B             ("SYNC"         ), // String
        .SIM_ASSERT_CHK         (0              ), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_EMBEDDED_CONSTRAINT(0              ), // DECIMAL
        .USE_MEM_INIT           (1              ), // DECIMAL
        .WAKEUP_TIME            ("disable_sleep"), // String
        .WRITE_DATA_WIDTH_A     (8              ), // DECIMAL
        .WRITE_MODE_B           ("no_change"    )  // String
    ) xpm_memory_sdpram_read_inst (
        .dbiterrb      (                 ), // 1-bit output: Status signal to indicate double bit error occurrence
        .sbiterrb      (                 ), // 1-bit output: Status signal to indicate single bit error occurrence
        .doutb         (read_memory_doutb), // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
        .addra         (read_memory_addra), // ADDR_WIDTH_A-bit input: Address for port A write operations.
        .addrb         (read_memory_addrb), // ADDR_WIDTH_B-bit input: Address for port B read operations.
        .clka          (CLK              ), // 1-bit input: Clock signal for port A. Also clocks port B when
        .clkb          (CLK              ), // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
        .dina          (read_memory_dina ), // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .ena           (1'b1             ), // 1-bit input: Memory enable signal for port A. Must be high on clock
        .enb           (1'b1             ), // 1-bit input: Memory enable signal for port B. Must be high on clock
        .injectdbiterra(1'b0             ), // 1-bit input: Controls double bit error injection on input data when
        .injectsbiterra(1'b0             ), // 1-bit input: Controls single bit error injection on input data when
        .regceb        (1'b1             ), // 1-bit input: Clock Enable for the last register stage on the output
        .rstb          (RESET            ), // 1-bit input: Reset signal for the final port B output register stage.
        .sleep         (1'b0             ), // 1-bit input: sleep signal to enable the dynamic power saving feature.
        .wea           (read_memory_wea  )  // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
    );



    always_comb begin : read_memory_addrb_processing

        read_memory_addrb = RADDR;
    end 


    // address : sets before receive data, implies on MEM
    always_ff @(posedge CLK) begin : read_memory_addra_processing 
        case (current_state)
            IDLE_CHECK_FROM_DEVICE_ST : 
                read_memory_addra <= ADDRESS_BEGIN;

            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == (ADDRESS_END)) begin 
                        read_memory_addra <= ADDRESS_BEGIN;
                    end else begin 
                        read_memory_addra <= read_memory_addra + 1;
                    end 
                end else begin 
                    read_memory_addra <= read_memory_addra;
                end 

            default : 
                read_memory_addra <= read_memory_addra;

        endcase
    end 


    // readed data from interface S_AXIS_ to porta for readmemory
    always_ff @(posedge CLK) begin : read_memory_wea_processing
        case (current_state)
            FROM_DEVICE_RX_READ_DATA_ST : 
                read_memory_wea <= s_axis_tvalid;

            default : 
                read_memory_wea <= 1'b0;
        endcase // current_state
    end 



    always_ff @(posedge CLK) begin : read_memory_dina_processing 
        case (current_state)
            FROM_DEVICE_RX_READ_DATA_ST : 
                read_memory_dina <= s_axis_tdata;

            default 
                read_memory_dina <= read_memory_dina;
        endcase // current_state
    end 



    fifo_out_sync_xpm #(
        .DATA_WIDTH(32           ),
        .MEMTYPE   ("distributed"),
        .DEPTH     (16           )
    ) fifo_out_sync_xpm_inst (
        .CLK          (CLK          ),
        .RESET        (RESET        ),
        
        .OUT_DIN_DATA (out_din_data ),
        .OUT_DIN_KEEP ('b1          ),
        .OUT_DIN_LAST (1'b0         ),
        .OUT_WREN     (out_wren     ),
        .OUT_FULL     (             ),
        .OUT_AWFULL   (out_awfull   ),
        
        .M_AXIS_TDATA (m_axis_tdata ),
        .M_AXIS_TKEEP (             ),
        .M_AXIS_TVALID(m_axis_tvalid),
        .M_AXIS_TLAST (             ),
        .M_AXIS_TREADY(m_axis_tready)
    );



    always_ff @(posedge CLK) begin : out_din_data_processing 
        case (current_state) 
            FROM_DEVICE_TX_ADDR_PTR_ST : 
                out_din_data <= {8'h00, 5'b10000, read_memory_addra[10:0], 8'h00};

            TO_DEVICE_TX_ST : 
                // spi_di <= {5'b00000, addr_reg_high[8:0], addr_reg_low[1:0], data_reg[7:0], 8'h00};
                out_din_data <= {8'h00, 5'b00000, addr_reg_high[8:0], addr_reg_low[1:0], data_reg[7:0]};

            default : 
                out_din_data <= out_din_data;

        endcase // current_state
    end 



    always_ff @(posedge CLK) begin : out_wren_processing 
        case (current_state) 
            FROM_DEVICE_TX_ADDR_PTR_ST : 
                if (!out_awfull) begin 
                    out_wren <= 1'b1;
                end else begin 
                    out_wren <= 1'b0;
                end 

            TO_DEVICE_TX_ST: 
                if (!out_awfull) begin 
                    out_wren <= 1'b1;
                end else begin 
                    out_wren <= 1'b0;
                end 

            default : 
                out_wren <= 1'b0;

        endcase // current_state
    end 



    always_ff @(posedge CLK) begin : addr_reg_low_processing 
        case (current_state) 
            TO_DEVICE_INCREMENT_ADDR_ST : 
                addr_reg_low <= addr_reg_low + 1;

            TO_DEVICE_READ_FIFO_ST : 
                addr_reg_low <= '{default:0};

            default : 
                addr_reg_low <= addr_reg_low;
        endcase
    end 


    always_ff @(posedge CLK) begin : current_state_processing 
        if (RESET) begin 
            current_state <= IDLE_CHECK_FROM_DEVICE_ST;
        end else begin 
            case (current_state) 

                IDLE_CHECK_FROM_DEVICE_ST : 
                    if (request_flaq) begin 
                        current_state <= FROM_DEVICE_TX_ADDR_PTR_ST;
                    end else begin 
                        current_state <= IDLE_CHECK_TO_DEVICE_ST;
                    end 

                IDLE_CHECK_TO_DEVICE_ST : 
                    if (!fifo_empty) begin 
                        current_state <= TO_DEVICE_READ_FIFO_ST;
                    end else begin 
                        current_state <= IDLE_CHECK_FROM_DEVICE_ST;
                    end 

                FROM_DEVICE_TX_ADDR_PTR_ST  :
                    if (!out_awfull) begin 
                        current_state <= FROM_DEVICE_RX_READ_DATA_ST;
                    end else begin 
                        current_state <= current_state;
                    end 

                FROM_DEVICE_RX_READ_DATA_ST : 
                    if (read_memory_wea) begin 
                        if (read_memory_addra == ADDRESS_END) begin 
                            current_state <= IDLE_CHECK_TO_DEVICE_ST;
                        end else begin 
                            current_state <= FROM_DEVICE_TX_ADDR_PTR_ST;
                        end 
                    end else begin 
                        current_state <= current_state;
                    end 

                // Логика передачи данных 
                TO_DEVICE_READ_FIFO_ST : 
                    current_state <= TO_DEVICE_CHK_ST; 

                TO_DEVICE_CHK_ST : 
                    if (wstrb_reg[0]) begin 
                        current_state <= TO_DEVICE_TX_ST;
                    end else begin 
                        current_state <= TO_DEVICE_INCREMENT_ADDR_ST;
                    end  

                TO_DEVICE_INCREMENT_ADDR_ST : 
                    if (addr_reg_low == 3) begin 
                        if (fifo_empty) begin 
                            current_state <= IDLE_CHECK_FROM_DEVICE_ST;
                        end else begin 
                            current_state <= TO_DEVICE_READ_FIFO_ST;
                        end 
                    end else begin 
                        current_state <= TO_DEVICE_CHK_ST;
                    end 
                 
                TO_DEVICE_TX_ST : 
                    if (!out_awfull) begin 
                        current_state <= TO_DEVICE_INCREMENT_ADDR_ST;
                    end else begin 
                        current_state <= current_state;
                    end 
                default             : 
                    current_state <= current_state;
            endcase // current_state
        end 
    end 

    logic sdio_i;
    logic sdio_o;
    logic sdio_t;

    IOBUF iobuf_inst (
        .O (sdio_i  ), // 1-bit output: Buffer output
        .I (sdio_o  ), // 1-bit input: Buffer input
        .IO(ADC_SDIO), // 1-bit inout: Buffer inout (connect directly to top-level port)
        .T (sdio_t  )  // 1-bit input: 3-state enable input
    );

    ODDRE1 #(
        .IS_C_INVERTED (1'b0        ), // Optional inversion for C
        .IS_D1_INVERTED(1'b0        ), // Unsupported, do not use
        .IS_D2_INVERTED(1'b0        ), // Unsupported, do not use
        .SIM_DEVICE    ("ULTRASCALE"), // Set the device version for simulation functionality (ULTRASCALE)
        .SRVAL         (1'b0        )  // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
    ) oddre1_inst (
        .Q (ADC_SCLK), // 1-bit output: Data output to IOB
        .C (SDIO_CLK), // 1-bit input: High-speed clock input
        .D1(1'b0    ), // 1-bit input: Parallel data input 1
        .D2(1'b1    ), // 1-bit input: Parallel data input 2
        .SR(1'b0    )  // 1-bit input: Active-High Async Reset
    );

    axis_spi_master_sdio axis_spi_master_sdio_inst (
        .AXI_CLK      (CLK          ),
        .AXI_RESET    (RESET        ),
        
        .SPI_CLK      (SDIO_CLK     ),
        
        .SDIO_I       (sdio_i       ),
        .SDIO_O       (sdio_o       ),
        .SDIO_T       (sdio_t       ),
        
        .SS           (ADC_CSB      ),
        
        .S_AXIS_TDATA (m_axis_tdata ),
        .S_AXIS_TVALID(m_axis_tvalid),
        .S_AXIS_TREADY(m_axis_tready),
        
        .M_AXIS_TDATA (s_axis_tdata ),
        .M_AXIS_TVALID(s_axis_tvalid),
        .M_AXIS_TREADY(s_axis_tready)
    );


endmodule