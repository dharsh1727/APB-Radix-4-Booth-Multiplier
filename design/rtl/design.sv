module booth_4 ( 
    input  logic signed [7:0] X, 
    output logic [11:0] op 
); 

    int i; 
    logic [9:0] X_ext;  

    always_comb begin 
        op = 12'b0;  // avoid latches

        // Sign extension + appended 0 (x[-1])
        X_ext = {X[7], X, 1'b0}; 

        for (i = 0; i < 4; i = i + 1) begin 
            case (X_ext[2*i +: 3]) 
                3'b000, 3'b111: op[3*i +: 3] = 3'b000; // 0 
                3'b001, 3'b010: op[3*i +: 3] = 3'b001; // +1 
                3'b011:         op[3*i +: 3] = 3'b010; // +2 
                3'b100:         op[3*i +: 3] = 3'b110; // -2 
                3'b101, 3'b110: op[3*i +: 3] = 3'b111; // -1 
                default:        op[3*i +: 3] = 3'b000; 
            endcase 
        end 
    end 

endmodule

module ppg ( 
    input  logic signed [7:0] Y, 
    input  logic [11:0] op, 
    output logic signed [15:0] PP0, 
    output logic signed [15:0] PP1, 
    output logic signed [15:0] PP2, 
    output logic signed [15:0] PP3 
); 

    logic signed [15:0] Y_ext; 
    logic signed [15:0] temp; 

    always_comb begin 
        // Sign extend Y 
        Y_ext = {{8{Y[7]}}, Y}; 

        // Default values 
        PP0 = 0; 
        PP1 = 0; 
        PP2 = 0; 
        PP3 = 0; 

        // Group 0 
        case (op[2:0]) 
            3'b000: temp = 0; 
            3'b001: temp = Y_ext; 
            3'b010, 3'b011: temp = Y_ext << 1;  // âœ… FIXED
            3'b111: temp = -Y_ext; 
            3'b110: temp = -(Y_ext << 1); 
            default: temp = 0; 
        endcase 
        PP0 = temp; 

        // Group 1 
        case (op[5:3]) 
            3'b000: temp = 0; 
            3'b001: temp = Y_ext; 
            3'b010, 3'b011: temp = Y_ext << 1; 
            3'b111: temp = -Y_ext; 
            3'b110: temp = -(Y_ext << 1); 
            default: temp = 0; 
        endcase 
        PP1 = temp << 2; 

        // Group 2 
        case (op[8:6]) 
            3'b000: temp = 0; 
            3'b001: temp = Y_ext; 
            3'b010, 3'b011: temp = Y_ext << 1; 
            3'b111: temp = -Y_ext; 
            3'b110: temp = -(Y_ext << 1); 
            default: temp = 0; 
        endcase 
        PP2 = temp << 4; 

        // Group 3 
        case (op[11:9]) 
            3'b000: temp = 0; 
            3'b001: temp = Y_ext; 
            3'b010, 3'b011: temp = Y_ext << 1; 
            3'b111: temp = -Y_ext; 
            3'b110: temp = -(Y_ext << 1); 
            default: temp = 0; 
        endcase 
        PP3 = temp << 6; 

    end 

endmodule

module csa ( 
    input  logic [15:0] A, B, C, 
    output logic [15:0] Sum, 
    output logic [15:0] Carry 
); 
    assign Sum   = A ^ B ^ C; 
    assign Carry = (A & B) | (B & C) | (A & C); 
endmodule 

module CLA_16(
        input  logic [15:0] A,
        input  logic [15:0] B,
        output logic [15:0] Sum,
        output logic Cout
    );

    logic C1, C2, C3;

    Carry_look_ahead_adder CLA0 (
        .A(A[3:0]),
        .B(B[3:0]),
        .Cin(1'b0),
        .Sum(Sum[3:0]),
        .Cout(C1)
    );

    Carry_look_ahead_adder CLA1 (
        .A(A[7:4]),
        .B(B[7:4]),
        .Cin(C1),
        .Sum(Sum[7:4]),
        .Cout(C2)
    );

    Carry_look_ahead_adder CLA2 (
        .A(A[11:8]),
        .B(B[11:8]),
        .Cin(C2),
        .Sum(Sum[11:8]),
        .Cout(C3)
    );

    Carry_look_ahead_adder CLA3 (
        .A(A[15:12]),
        .B(B[15:12]),
        .Cin(C3),
        .Sum(Sum[15:12]),
        .Cout(Cout)
    );

    endmodule

module Carry_look_ahead_adder(
    input [3:0] A,
    input [3:0] B,
    input Cin,
    output [3:0] Sum,
    output Cout
);

wire [3:0] G;
wire [3:0] P;
wire C1, C2, C3;

assign P = A ^ B;
assign G = A & B;

assign C1 = G[0] | (P[0] & Cin);

assign C2 = G[1] | (P[1] & G[0]) | (P[1] & P[0] & Cin);

assign C3 = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) 
                      | (P[2] & P[1] & P[0] & Cin);

assign Cout = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) 
                        | (P[3] & P[2] & P[1] & G[0]) 
                        | (P[3] & P[2] & P[1] & P[0] & Cin);

assign Sum[0] = P[0] ^ Cin;
assign Sum[1] = P[1] ^ C1;
assign Sum[2] = P[2] ^ C2;
assign Sum[3] = P[3] ^ C3;

endmodule

module Booth_CLA_Top ( 
    input  logic signed [7:0] X, 
    input  logic signed [7:0] Y, 
    output logic signed [15:0] Product,
    output logic Overflow
); 
 
    logic [11:0] op; 
 
    logic signed [15:0] PP0, PP1, PP2, PP3; 
 
    logic [15:0] S1, C1; 
    logic [15:0] S2, C2; 
 
    // Booth Encoder 
    booth_4 BE (.X(X), .op(op)); 
 
    // Partial Products 
    ppg PPG ( .Y(Y), .op(op), .PP0(PP0), .PP1(PP1), .PP2(PP2),  .PP3(PP3) ); 
 
    // CSA Stage 1 
    csa CSA1 (.A(PP0), .B(PP1), .C(PP2), .Sum(S1), .Carry(C1)); 
 
    // CSA Stage 2 
    csa CSA2 (.A(S1), .B({C1[14:0],1'b0}), .C(PP3), .Sum(S2), .Carry(C2)); 
 
    // Final Adder
    CLA_16 CLA (.A(S2), .B({C2[14:0],1'b0}), .Sum(Product), .Cout(Overflow)); 
 
endmodule



module apb_master_controller (
    input  logic        PCLK,
    input  logic        PRESETn,

    // Request interface
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,

    // Response interface
    output logic        rsp_valid,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error,

    // APB bus master signals
    output logic [31:0] PADDR,
    output logic        PSEL,
    output logic        PENABLE,
    output logic        PWRITE,
    output logic [31:0] PWDATA,

    input  logic [31:0] PRDATA,
    input  logic        PREADY,
    input  logic        PSLVERR
);

    typedef enum logic [1:0] {
        IDLE,
        SETUP,
        ACCESS,
        RESP
    } state_t;

    state_t state;

    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic        write_reg;

    always_comb begin
        PADDR   = addr_reg;
        PWDATA  = wdata_reg;
        PWRITE  = write_reg;
    
        PSEL    = (state == SETUP) || (state == ACCESS);
        PENABLE = (state == ACCESS);
    
        req_ready = (state == IDLE);
        rsp_valid = (state == RESP);
    end


    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state     <= IDLE;
            addr_reg  <= '0;
            wdata_reg <= '0;
            write_reg <= 1'b0;
            rsp_rdata <= '0;
            rsp_error <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    if (req_valid) begin
                        addr_reg  <= req_addr;
                        wdata_reg <= req_wdata;
                        write_reg <= req_write;
                        rsp_error <= 1'b0;
                        state     <= SETUP;
                    end
                end

                SETUP: begin
                    state <= ACCESS;
                end

                ACCESS: begin
                    if (PREADY) begin
                        rsp_rdata <= PRDATA;
                        rsp_error <= PSLVERR;
                        state     <= RESP;
                    end
                end

                RESP: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end


endmodule


module apb_radix4_slave (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic [31:0] PADDR,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR
);

    localparam logic [31:0] REG_A      = 32'h00;
    localparam logic [31:0] REG_B      = 32'h04;
    localparam logic [31:0] REG_CTRL   = 32'h08;
    localparam logic [31:0] REG_RESULT = 32'h0C;
    localparam logic [31:0] REG_STATUS = 32'h10;

    logic signed [7:0] operand_a;
    logic signed [7:0] operand_b;

    logic signed [15:0] multiplier_product;
    logic               multiplier_overflow;

    logic signed [15:0] result_reg;
    logic               done_reg;

    logic access;
    logic valid_addr;

    assign access = PSEL && PENABLE;

    always_comb begin
        valid_addr = 1'b1;

        case (PADDR)
            REG_A,
            REG_B,
            REG_CTRL,
            REG_RESULT,
            REG_STATUS: valid_addr = 1'b1;

            default: valid_addr = 1'b0;
        endcase
    end

    // Zero-wait-state APB slave.
    assign PREADY  = 1'b1;
    assign PSLVERR = access && !valid_addr;

    // Existing multiplier: no change to its datapath.
    Booth_CLA_Top u_multiplier (
        .X        (operand_a),
        .Y        (operand_b),
        .Product  (multiplier_product),
        .Overflow (multiplier_overflow)
    );

    // Register write logic.
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            operand_a <= '0;
            operand_b <= '0;
            result_reg <= '0;
            done_reg <= 1'b0;
        end else if (access && PREADY &&
                     PWRITE && valid_addr) begin

            case (PADDR)

                REG_A: begin
                    operand_a <= PWDATA[7:0];
                end

                REG_B: begin
                    operand_b <= PWDATA[7:0];
                end

                REG_CTRL: begin
                    if (PWDATA[0]) begin
                        result_reg <= multiplier_product;
                        done_reg   <= 1'b1;
                    end
                end

                default: begin
                    // Writes to read-only registers are ignored.
                end

            endcase
        end
    end

    // Register read multiplexer.
    always_comb begin
        PRDATA = '0;

        if (PSEL && !PWRITE) begin
            case (PADDR)

                REG_A:
                    PRDATA = {{24{operand_a[7]}}, operand_a};

                REG_B:
                    PRDATA = {{24{operand_b[7]}}, operand_b};

                REG_RESULT:
                    PRDATA = {{16{result_reg[15]}}, result_reg};

                REG_STATUS:
                    PRDATA = {31'b0, done_reg};

                REG_CTRL:
                    PRDATA = 32'b0;

                default:
                    PRDATA = 32'b0;

            endcase
        end
    end

endmodule


module apb_radix4_top (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,

    output logic        rsp_valid,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error,
    
    output logic [31:0] mon_PADDR,
    output logic        mon_PSEL,
    output logic        mon_PENABLE,
    output logic        mon_PWRITE,
    output logic [31:0] mon_PWDATA,
    output logic [31:0] mon_PRDATA,
    output logic        mon_PREADY,
    output logic        mon_PSLVERR

);

    logic [31:0] PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;

    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    
    assign mon_PADDR   = PADDR;
    assign mon_PSEL    = PSEL;
    assign mon_PENABLE = PENABLE;
    assign mon_PWRITE  = PWRITE;
    assign mon_PWDATA  = PWDATA;
    assign mon_PRDATA  = PRDATA;
    assign mon_PREADY  = PREADY;
    assign mon_PSLVERR = PSLVERR;

    apb_master_controller u_master (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),

        .rsp_valid  (rsp_valid),
        .rsp_rdata  (rsp_rdata),
        .rsp_error  (rsp_error),

        .PADDR      (PADDR),
        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PWDATA     (PWDATA),

        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR)
    );

    apb_radix4_slave u_slave (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        .PADDR      (PADDR),
        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PWDATA     (PWDATA),

        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR)
    );

endmodule

module apb_assertions (
    input logic        PCLK,
    input logic        PRESETn,
    input logic        PSEL,
    input logic        PENABLE,
    input logic        PWRITE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,
    input logic        PREADY
);

    logic past_valid;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            past_valid <= 1'b0;
        else
            past_valid <= 1'b1;
    end
  
    default clocking cb @(posedge PCLK); endclocking

   
    property setup_before_access;
        disable iff (!PRESETn)
        past_valid &&
        (PSEL && PENABLE && !$past(PENABLE))
        |-> $past(PSEL && !PENABLE);
    endproperty

    assert property (setup_before_access)
        else $error("APB assertion failed: ACCESS without SETUP");


    // Control and address must remain stable while waiting.
    property stable_during_wait;
        disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY)
        |=> (PSEL && PENABLE &&
             $stable(PADDR) &&
             $stable(PWRITE) &&
             $stable(PWDATA));
    endproperty

    assert property (stable_during_wait)
        else $error("APB controls changed during wait state");

    // PENABLE cannot be asserted while PSEL is low.
    property access_requires_select;
        disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty

    assert property (access_requires_select)
        else $error("PENABLE asserted without PSEL");

endmodule


