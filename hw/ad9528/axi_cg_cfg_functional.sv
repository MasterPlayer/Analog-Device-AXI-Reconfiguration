`timescale 1ns / 1ps


module axi_cg_cfg_functional (
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

    output logic        PLL1_LOCKED                 ,
    output logic        PLL2_LOCKED                 ,

    output logic        CONFIGURE_COMPLETE          ,

    // component control
    output logic        AD9528_SPI_CS_N             ,
    output logic        AD9528_SPI_SCK              ,
    output logic        AD9528_SPI_SIMO             ,
    input  logic        AD9528_SPI_SOMI             ,
    output logic        AD9528_REF_SEL              ,
    output logic        AD9528_RST_N                ,
    input  logic [ 1:0] AD9528_SP                   ,
    input  logic        AD9528_SYSREFIN_P           ,
    input  logic        AD9528_SYSREFIN_N
);

    localparam integer ADDRESS_BEGIN = 11'h000;
    localparam integer ADDRESS_END   = 11'h509;

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

    // read memory signal group : 8 bit input 32 bit output;
    logic [10:0] read_memory_addra = '{default:0};
    logic [ 7:0] read_memory_dina  = '{default:0};
    logic        read_memory_wea                 ;
    logic [31:0] read_memory_doutb               ;
    logic [ 8:0] read_memory_addrb = '{default:0};

    logic [31:0] request_from_device_interval_counter;

    logic [31:0] spi_di  ;
    logic        spi_dvi ;
    logic        spi_busy;
    logic [31:0] spi_do  ;
    logic        spi_dvo ;


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

    logic [7:0] reg508 = '{default:0};
    logic [7:0] reg003 = '{default:0};
    logic [7:0] reg00c = '{default:0};
    logic [7:0] reg00d = '{default:0};

    localparam [7:0] REG003_VALUE = 8'h05;
    localparam [7:0] REG00C_VALUE = 8'h56;
    localparam [7:0] REG00D_VALUE = 8'h04;

    logic has_ad9528;

    always_ff @(posedge CLK) begin : AD9528_RST_N_processing 
        if (RESET) begin 
            AD9528_RST_N <= 1'b0;
        end else begin 
            AD9528_RST_N <= 1'b1;
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
        .ADDR_WIDTH_B           ( 9             ), // DECIMAL
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
                read_memory_wea <= spi_dvo;

            default : 
                read_memory_wea <= 1'b0;
        endcase // current_state
    end 



    always_ff @(posedge CLK) begin : read_memory_dina_processing 
        case (current_state)
            FROM_DEVICE_RX_READ_DATA_ST : 
                read_memory_dina <= spi_do;

            default 
                read_memory_dina <= read_memory_dina;
        endcase // current_state
    end 


    always_ff @(posedge CLK) begin : reg508_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == 'h508) begin 
                        reg508 <= read_memory_dina;
                    end else begin 
                        reg508 <= reg508;
                    end 
                end else begin 
                    reg508 <= reg508;
                end 

            default : 
                reg508 <= reg508;

        endcase // current_state
    end 


    always_ff @(posedge CLK) begin : reg003_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == 'h003) begin 
                        reg003 <= read_memory_dina;
                    end else begin 
                        reg003 <= reg003;
                    end 
                end else begin 
                    reg003 <= reg003;
                end 

            default : 
                reg003 <= reg003;
        endcase // current_state
    end 

    always_ff @(posedge CLK) begin : reg00c_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == 'h00c) begin 
                        reg00c <= read_memory_dina;
                    end else begin 
                        reg00c <= reg00c;
                    end 
                end else begin 
                    reg00c <= reg00c;
                end 

            default : 
                reg00c <= reg00c;
        endcase // current_state
    end 

    always_ff @(posedge CLK) begin : reg00d_processing 
        case (current_state) 
            FROM_DEVICE_RX_READ_DATA_ST : 
                if (read_memory_wea) begin 
                    if (read_memory_addra == 'h00d) begin 
                        reg00d <= read_memory_dina;
                    end else begin 
                        reg00d <= reg00d;
                    end 
                end else begin 
                    reg00d <= reg00d;
                end 

            default : 
                reg00d <= reg00d;
        endcase // current_state
    end 


    always_ff @(posedge CLK) begin : has_ad9528_processing 
        if (RESET) begin 
            has_ad9528 <= 1'b0;
        end else begin 
            if ((reg003 == REG003_VALUE) & (reg00c == REG00C_VALUE) & (reg00d == REG00D_VALUE)) begin 
                has_ad9528 <= 1'b1;
            end else begin 
                has_ad9528 <= 1'b0;
            end 
        end 
    end 



    always_ff @(posedge CLK) begin : pll1_locked_processing 
        PLL1_LOCKED <= reg508[0] & has_ad9528;
    end 



    always_ff @(posedge CLK) begin : pll2_locked_processing 
        PLL2_LOCKED <= reg508[1] & has_ad9528;
    end 



    always_ff @(posedge CLK) begin : spi_di_processing 
        case (current_state) 
            FROM_DEVICE_TX_ADDR_PTR_ST : 
                spi_di <= {5'b10000, read_memory_addra[10:0], 8'h00, 8'h00};

            TO_DEVICE_TX_ST : 
                spi_di <= {5'b00000, addr_reg_high[8:0], addr_reg_low[1:0], data_reg[7:0], 8'h00};

            default : 
                spi_di <= spi_di;

        endcase // current_state
    end 




    always_ff @(posedge CLK) begin : spi_dvi_processing 
        case (current_state) 
            FROM_DEVICE_TX_ADDR_PTR_ST : 
                if (!spi_busy) begin 
                    spi_dvi <= 1'b1;
                end else begin 
                    spi_dvi <= 1'b0;
                end 

            TO_DEVICE_TX_ST: 
                if (!spi_busy) begin 
                    spi_dvi <= 1'b1;
                end else begin 
                    spi_dvi <= 1'b0;
                end 

            default : 
                spi_dvi <= 1'b0;

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
                    if (!spi_busy) begin 
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
                    if (!spi_busy) begin 
                        current_state <= TO_DEVICE_INCREMENT_ADDR_ST;
                    end else begin 
                        current_state <= current_state;
                    end 

                default : 
                    current_state <= current_state;
            endcase // current_state
        end 
    end 



    always_ff @(posedge CLK) begin : CONFIGURE_COMPLETE_processing 
        case (current_state)

            IDLE_CHECK_TO_DEVICE_ST : 
                if (!fifo_empty) begin 
                    CONFIGURE_COMPLETE <= 1'b0;
                end else begin 
                    CONFIGURE_COMPLETE <= CONFIGURE_COMPLETE;
                end 

            TO_DEVICE_INCREMENT_ADDR_ST : 
                if (addr_reg_low == 3) begin 
                    if (fifo_empty) begin 
                        CONFIGURE_COMPLETE <= 1'b1;
                    end else begin 
                        CONFIGURE_COMPLETE <= CONFIGURE_COMPLETE;
                    end 
                end else begin 
                    CONFIGURE_COMPLETE <= CONFIGURE_COMPLETE;
                end 

            default : 
                CONFIGURE_COMPLETE <= CONFIGURE_COMPLETE;

        endcase
    end 



    spi_interface #(
        .SPI_MODE ("MSBFIRST"),
        .SOMI_MODE("RISING"  ),
        .CLK_SCALE(6         )
    ) spi_interface_inst (
        .CLK       (CLK            ),
        .RST       (RESET          ),
        
        .DATA_WIDTH(5'b10111       ),
        
        .DI        (spi_di         ),
        .DVI       (spi_dvi        ),
        .BUSY      (spi_busy       ),
        
        .DO        (spi_do         ),
        .DVO       (spi_dvo        ),
        
        .SPI_CS_N  (AD9528_SPI_CS_N),
        .SPI_SCK   (AD9528_SPI_SCK ),
        .SPI_SIMO  (AD9528_SPI_SIMO),
        .SPI_SOMI  (AD9528_SPI_SOMI)
    );



endmodule