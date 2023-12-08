`timescale 1 ns / 1 ps



module axi_cg_cfg #(
    parameter integer S_AXI_LITE_DATA_WIDTH        = 32  ,
    parameter integer S_AXI_LITE_ADDR_WIDTH        = 11  ,
    parameter integer REQUEST_FROM_DEVICE_INTERVAL = 1000
) (
    input  logic                                 CLK               ,
    input  logic                                 RESETN            ,
    // DEVICE ACCESS REGISTER UNIT
    input  logic [    S_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_LITE_AWADDR ,
    input  logic [                          2:0] S_AXI_LITE_AWPROT ,
    input  logic                                 S_AXI_LITE_AWVALID,
    output logic                                 S_AXI_LITE_AWREADY,
    input  logic [    S_AXI_LITE_DATA_WIDTH-1:0] S_AXI_LITE_WDATA  ,
    input  logic [(S_AXI_LITE_DATA_WIDTH/8)-1:0] S_AXI_LITE_WSTRB  ,
    input  logic                                 S_AXI_LITE_WVALID ,
    output logic                                 S_AXI_LITE_WREADY ,
    output logic [                          1:0] S_AXI_LITE_BRESP  ,
    output logic                                 S_AXI_LITE_BVALID ,
    input  logic                                 S_AXI_LITE_BREADY ,
    input  logic [    S_AXI_LITE_ADDR_WIDTH-1:0] S_AXI_LITE_ARADDR ,
    input  logic [                          2:0] S_AXI_LITE_ARPROT ,
    input  logic                                 S_AXI_LITE_ARVALID,
    output logic                                 S_AXI_LITE_ARREADY,
    output logic [    S_AXI_LITE_DATA_WIDTH-1:0] S_AXI_LITE_RDATA  ,
    output logic [                          1:0] S_AXI_LITE_RRESP  ,
    output logic                                 S_AXI_LITE_RVALID ,
    input  logic                                 S_AXI_LITE_RREADY ,
    output logic                                 PLL1_LOCKED       ,
    output logic                                 PLL2_LOCKED       ,
    output logic                                 CONFIGURE_COMPLETE,
    //
    output logic                                 AD9528_SPI_CS_N   ,
    output logic                                 AD9528_SPI_SCK    ,
    output logic                                 AD9528_SPI_SIMO   ,
    input  logic                                 AD9528_SPI_SOMI   ,
    output logic                                 AD9528_REF_SEL    ,
    output logic                                 AD9528_RST_N      ,
    input  logic [                          1:0] AD9528_SP         ,
    input  logic                                 AD9528_SYSREFIN_P ,
    input  logic                                 AD9528_SYSREFIN_N
);

    logic [S_AXI_LITE_ADDR_WIDTH-1:0] axi_awaddr ;
    logic                             axi_awready;
    logic                             axi_wready ;
    logic [                      1:0] axi_bresp  ;
    logic                             axi_bvalid ;
    logic [S_AXI_LITE_ADDR_WIDTH-1:0] axi_araddr ;
    logic                             axi_arready;
    logic [S_AXI_LITE_DATA_WIDTH-1:0] axi_rdata  ;
    logic [                      1:0] axi_rresp  ;
    logic                             axi_rvalid ;

    localparam integer ADDR_LSB_DEV          = (S_AXI_LITE_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS_DEV = 3                                 ;

    (* dont_touch="true" *) logic                                 slv_reg_rden;
    (* dont_touch="true" *) logic                                 slv_reg_wren;
    (* dont_touch="true" *) logic [S_AXI_LITE_DATA_WIDTH-1:0] reg_data_out;
    (* dont_touch="true" *) logic                                 aw_en       ;


    always_comb begin : S_AXI_LITE_processing

        S_AXI_LITE_AWREADY = axi_awready;
        S_AXI_LITE_WREADY  = axi_wready;
        S_AXI_LITE_BRESP   = axi_bresp;
        S_AXI_LITE_BVALID  = axi_bvalid;
        S_AXI_LITE_ARREADY = axi_arready;
        S_AXI_LITE_RDATA   = axi_rdata;
        S_AXI_LITE_RRESP   = axi_rresp;
    end 



    always_comb begin : S_AXI_LITE_RVALID_proc

        S_AXI_LITE_RVALID = axi_rvalid;
    end 



    always_ff @( posedge CLK ) begin : axi_awready_proc
        if (~RESETN)
            axi_awready <= 1'b0;
        else    
            if (~axi_awready & S_AXI_LITE_AWVALID & S_AXI_LITE_WVALID & aw_en)
                axi_awready <= 1'b1;
            else 
                if (S_AXI_LITE_BREADY & axi_bvalid)
                    axi_awready <= 1'b0;
                else
                    axi_awready <= 1'b0;
    end       



    always_ff @( posedge CLK ) begin : aw_en_proc
        if (~RESETN)
            aw_en <= 1'b1;
        else
            if (~axi_awready & S_AXI_LITE_AWVALID & S_AXI_LITE_WVALID & aw_en)
                aw_en <= 1'b0;
            else 
                if (S_AXI_LITE_BREADY & axi_bvalid)
                    aw_en <= 1'b1;
    end       



    always_ff @( posedge CLK ) begin : axi_awaddr_proc
        if (~RESETN)
            axi_awaddr <= '{default:0};
        else
            if (~axi_awready & S_AXI_LITE_AWVALID & S_AXI_LITE_WVALID & aw_en)
                axi_awaddr <= S_AXI_LITE_AWADDR;
    end       



    always_ff @( posedge CLK ) begin : axi_wready_proc
        if (~RESETN)
            axi_wready <= 1'b0;
        else    
            if (~axi_wready & S_AXI_LITE_WVALID & S_AXI_LITE_AWVALID & aw_en )
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
    end       



    always_comb begin : slv_reg_wren_processing

        slv_reg_wren = axi_wready & S_AXI_LITE_WVALID & axi_awready & S_AXI_LITE_AWVALID;
    end



    always_ff @( posedge CLK ) begin : axi_bvalid_proc
        if (~RESETN)
            axi_bvalid  <= 1'b0;
        else
            if (axi_awready & S_AXI_LITE_AWVALID & ~axi_bvalid & axi_wready & S_AXI_LITE_WVALID)
                axi_bvalid <= 1'b1;
            else
                if (S_AXI_LITE_BREADY && axi_bvalid)
                    axi_bvalid <= 1'b0; 
    end   



    always_ff @( posedge CLK ) begin : axi_bresp_proc
        if (~RESETN)
            axi_bresp <= '{default:0};
        else
            if (axi_awready & S_AXI_LITE_AWVALID & ~axi_bvalid & axi_wready & S_AXI_LITE_WVALID)
                axi_bresp  <= 2'b0; // 'OKAY' response 
    end   

///////////////////////////////////////////// READ INTERFACE SIGNALS /////////////////////////////////////////////

    always_ff @( posedge CLK ) begin : axi_arready_proc
        if (~RESETN)
            axi_arready <= 1'b0;
        else    
            if (~axi_arready & S_AXI_LITE_ARVALID)
                axi_arready <= 1'b1;
            else
                axi_arready <= 1'b0;
    end       



    always_ff @( posedge CLK ) begin : axi_araddr_proc
        if (~RESETN)
            axi_araddr  <= 32'b0;
        else    
            if (~axi_arready & S_AXI_LITE_ARVALID)
                axi_araddr  <= S_AXI_LITE_ARADDR;  
    end       



    always_ff @( posedge CLK ) begin : axi_rvalid_proc
        if (~RESETN)
            axi_rvalid <= 1'b0;
        else
            if (axi_arready & S_AXI_LITE_ARVALID & ~axi_rvalid)
                axi_rvalid <= 1'b1;
            else 
                if (axi_rvalid & S_AXI_LITE_RREADY)
                    axi_rvalid <= 1'b0;
    end    



    always_ff @( posedge CLK ) begin : axi_rresp_proc
        if (~RESETN)
            axi_rresp  <= 1'b0;
        else
            if (axi_arready & S_AXI_LITE_ARVALID & ~axi_rvalid)
                axi_rresp  <= 2'b0; // 'OKAY' response             
    end    



    always_ff @(posedge CLK) begin : slv_reg_rden_proc 

        slv_reg_rden <= axi_arready & S_AXI_LITE_ARVALID & ~axi_rvalid;
    end 



    always_comb begin : axi_rdata_proc

        axi_rdata = reg_data_out;     // register read data
    end    


    axi_cg_cfg_functional axi_cg_cfg_functional_inst (
        .CLK                         (CLK               ),
        .RESET                       (~RESETN           ),
        // signal from AXI_DEV interface
        .WDATA                       (S_AXI_LITE_WDATA  ),
        .WSTRB                       (S_AXI_LITE_WSTRB  ),
        .WADDR                       (axi_awaddr[10:2]  ),
        .WVALID                      (slv_reg_wren      ),
        // read interface
        .RADDR                       (axi_araddr[10:2]  ),
        .RDATA                       (reg_data_out      ),
        // control
        .REQUEST_FROM_DEVICE_INTERVAL(32'd10000000      ),
        
        .PLL1_LOCKED                 (PLL1_LOCKED       ),
        .PLL2_LOCKED                 (PLL2_LOCKED       ),
        .CONFIGURE_COMPLETE          (CONFIGURE_COMPLETE),
        
        
        // component control
        .AD9528_SPI_CS_N             (AD9528_SPI_CS_N   ),
        .AD9528_SPI_SCK              (AD9528_SPI_SCK    ),
        .AD9528_SPI_SIMO             (AD9528_SPI_SIMO   ),
        .AD9528_SPI_SOMI             (AD9528_SPI_SOMI   ),
        .AD9528_REF_SEL              (AD9528_REF_SEL    ),
        .AD9528_RST_N                (AD9528_RST_N      ),
        .AD9528_SP                   (AD9528_SP         ),
        .AD9528_SYSREFIN_P           (AD9528_SYSREFIN_P ),
        .AD9528_SYSREFIN_N           (AD9528_SYSREFIN_N )
    );


endmodule
