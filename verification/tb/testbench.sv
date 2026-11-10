interface apb_interface(input logic PCLK);

    logic PRESETn;

    // Requests from testbench to synthesizable master
    logic        req_valid;
    logic        req_ready;
    logic        req_write;
    logic [31:0] req_addr;
    logic [31:0] req_wdata;

    // Responses from master
    logic        rsp_valid;
    logic [31:0] rsp_rdata;
    logic        rsp_error;

    // APB bus
    logic [31:0] PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

endinterface


class apb_driver;

    virtual apb_interface vif;

    function new(virtual apb_interface vif);
        this.vif = vif;
    endfunction


    task automatic transfer(
        input  bit          write,
        input  logic [31:0] addr,
        input  logic [31:0] data,
        output logic [31:0] read_data,
        output logic        error
    );

        // Wait until the master can accept a request.
        @(negedge vif.PCLK);
        while (!vif.req_ready)
            @(negedge vif.PCLK);

        vif.req_write = write;
        vif.req_addr  = addr;
        vif.req_wdata = data;
        vif.req_valid = 1'b1;

        // Request is accepted at a rising edge.
        do @(posedge vif.PCLK);
        while (!vif.req_ready);

        @(negedge vif.PCLK);
        vif.req_valid = 1'b0;

        // Wait for the transaction response.
        do @(posedge vif.PCLK);
        while (!vif.rsp_valid);

        read_data = vif.rsp_rdata;
        error     = vif.rsp_error;

        @(negedge vif.PCLK);
    endtask

endclass

class apb_monitor;

    virtual apb_interface vif;

    function new(virtual apb_interface vif);
        this.vif = vif;
    endfunction

    task run();
        forever begin
            @(posedge vif.PCLK);

            if (vif.PRESETn &&
                vif.PSEL &&
                vif.PENABLE &&
                vif.PREADY) begin

                if (vif.PWRITE) begin
                    $display(
                        "[MONITOR] WRITE addr=%08h data=%08h error=%0b",
                        vif.PADDR, vif.PWDATA, vif.PSLVERR
                    );
                end else begin
                    $display(
                        "[MONITOR] READ  addr=%08h data=%08h error=%0b",
                        vif.PADDR, vif.PRDATA, vif.PSLVERR
                    );
                end
            end
        end
    endtask

endclass

class apb_transaction;

    // Transaction request
    rand bit          write;
    rand logic [31:0] addr;
    rand logic [31:0] wdata;

    // Transaction response
    logic [31:0] rdata;
    logic        error;

    // Optional transaction identifier
    int unsigned transaction_id;

    function new();
        write          = 1'b0;
        addr           = '0;
        wdata          = '0;
        rdata          = '0;
        error          = 1'b0;
        transaction_id = 0;
    endfunction

    function void display(string prefix = "APB_TRANSACTION");
        $display(
            "[%s] ID=%0d OP=%s ADDR=0x%08h WDATA=0x%08h RDATA=0x%08h ERROR=%0b",
            prefix,
            transaction_id,
            write ? "WRITE" : "READ",
            addr,
            wdata,
            rdata,
            error
        );
    endfunction

endclass


class apb_scoreboard;

    logic signed [7:0]  model_a;
    logic signed [7:0]  model_b;
    logic signed [15:0] expected_product;

    int passed;
    int failed;

    function new();
        model_a = '0;
        model_b = '0;
        passed  = 0;
        failed  = 0;
    endfunction

    task process_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        case (addr)
            32'h00: model_a = data[7:0];
            32'h04: model_b = data[7:0];

            32'h08: begin
                if (data[0]) begin
                    expected_product = model_a * model_b;
                    $display(
                        "[SCOREBOARD] Expected product = %0d (0x%04h)",
                        expected_product, expected_product
                    );
                end
            end

            default: ;
        endcase
    endtask

    task check_result(input logic [31:0] observed);
        logic signed [31:0] expected_extended;

        expected_extended = {
            {16{expected_product[15]}}, expected_product
        };

        if (observed === expected_extended) begin
            passed++;
            $display("[SCOREBOARD] PASS: result = %08h", observed);
        end else begin
            failed++;
            $error(
                "[SCOREBOARD] FAIL: expected %08h, observed %08h",
                expected_extended, observed
            );
        end
    endtask

    function void report();
        $display(
            "[SCOREBOARD] Passed=%0d Failed=%0d",
            passed, failed
        );
    endfunction

endclass


module apb_coverage (
    input logic        PCLK,
    input logic        PRESETn,
    input logic        PSEL,
    input logic        PENABLE,
    input logic        PREADY,
    input logic        PWRITE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,
    input logic [31:0] PRDATA
);

    integer read_count;
    integer write_count;

    integer operand_a_writes;
    integer operand_b_writes;
    integer start_writes;
    integer result_reads;
    integer status_reads;
    integer invalid_accesses;

    integer positive_a_writes;
    integer negative_a_writes;
    integer zero_a_writes;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            read_count          <= 0;
            write_count         <= 0;
            operand_a_writes    <= 0;
            operand_b_writes    <= 0;
            start_writes        <= 0;
            result_reads        <= 0;
            status_reads        <= 0;
            invalid_accesses    <= 0;
            positive_a_writes   <= 0;
            negative_a_writes   <= 0;
            zero_a_writes       <= 0;
        end else if (PSEL && PENABLE && PREADY) begin

            if (PWRITE) begin
                write_count <= write_count + 1;

                case (PADDR)
                    32'h00: begin
                        operand_a_writes <= operand_a_writes + 1;

                        if ($signed(PWDATA[7:0]) > 0)
                            positive_a_writes <= positive_a_writes + 1;
                        else if ($signed(PWDATA[7:0]) < 0)
                            negative_a_writes <= negative_a_writes + 1;
                        else
                            zero_a_writes <= zero_a_writes + 1;
                    end

                    32'h04:
                        operand_b_writes <= operand_b_writes + 1;

                    32'h08:
                        if (PWDATA[0])
                            start_writes <= start_writes + 1;

                    default: ;
                endcase
            end else begin
                read_count <= read_count + 1;

                case (PADDR)
                    32'h0C: result_reads <= result_reads + 1;
                    32'h10: status_reads <= status_reads + 1;
                    default: ;
                endcase
            end

            if (PADDR != 32'h00 &&
                PADDR != 32'h04 &&
                PADDR != 32'h08 &&
                PADDR != 32'h0C &&
                PADDR != 32'h10)
                invalid_accesses <= invalid_accesses + 1;
        end
    end

    // Call this report task from tb_top at the end of simulation.
    task report_coverage;
        begin
            $display("");
            $display("======= FUNCTIONAL COVERAGE =======");
            $display("APB reads           : %0d", read_count);
            $display("APB writes          : %0d", write_count);
            $display("Operand A writes    : %0d", operand_a_writes);
            $display("Operand B writes    : %0d", operand_b_writes);
            $display("START writes        : %0d", start_writes);
            $display("Result reads        : %0d", result_reads);
            $display("Status reads        : %0d", status_reads);
            $display("Invalid accesses    : %0d", invalid_accesses);
            $display("Positive A writes   : %0d", positive_a_writes);
            $display("Negative A writes   : %0d", negative_a_writes);
            $display("Zero A writes       : %0d", zero_a_writes);
            $display("===================================");
        end
    endtask

endmodule


module tb_top;

    logic PCLK;

    apb_interface apb_if(PCLK);

    logic [31:0] mon_PADDR;
    logic        mon_PSEL;
    logic        mon_PENABLE;
    logic        mon_PWRITE;
    logic [31:0] mon_PWDATA;
    logic [31:0] mon_PRDATA;
    logic        mon_PREADY;
    logic        mon_PSLVERR;
	
  	
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

    // DUT response signals are included in the interface.
    apb_radix4_top dut (
        .PCLK       (PCLK),
        .PRESETn    (apb_if.PRESETn),

        .req_valid  (apb_if.req_valid),
        .req_ready  (apb_if.req_ready),
        .req_write  (apb_if.req_write),
        .req_addr   (apb_if.req_addr),
        .req_wdata  (apb_if.req_wdata),

        .rsp_valid  (apb_if.rsp_valid),
        .rsp_rdata  (apb_if.rsp_rdata),
        .rsp_error  (apb_if.rsp_error),

        .mon_PADDR   (mon_PADDR),
        .mon_PSEL    (mon_PSEL),
        .mon_PENABLE (mon_PENABLE),
        .mon_PWRITE  (mon_PWRITE),
        .mon_PWDATA  (mon_PWDATA),
        .mon_PRDATA  (mon_PRDATA),
        .mon_PREADY  (mon_PREADY),
        .mon_PSLVERR (mon_PSLVERR)
    );

    assign apb_if.PADDR   = mon_PADDR;
    assign apb_if.PSEL    = mon_PSEL;
    assign apb_if.PENABLE = mon_PENABLE;
    assign apb_if.PWRITE  = mon_PWRITE;
    assign apb_if.PWDATA  = mon_PWDATA;
    assign apb_if.PRDATA  = mon_PRDATA;
    assign apb_if.PREADY  = mon_PREADY;
    assign apb_if.PSLVERR = mon_PSLVERR;
    
    // Clock: 100 MHz
    initial PCLK = 1'b0;
    always #5 PCLK = ~PCLK;

    // Verification objects
    apb_driver     driver;
    apb_monitor    monitor;
    apb_scoreboard scoreboard;

    logic [31:0] read_data;
    logic        transfer_error;
    logic        invalid_pslverr_seen;
  
  
task automatic test_multiplication(
    input logic signed [7:0] A,
    input logic signed [7:0] B
);
    logic [31:0] expected;
    logic [31:0] observed;
    logic [31:0] temp_data;
    logic        error;

    begin
        // Calculate the reference result using signed arithmetic.
        expected = $signed(A) * $signed(B);

        $display("\n========================================");
        $display("MULTIPLICATION TEST: %0d x %0d", A, B);
        $display("Expected product = %0d (0x%08h)",
                 $signed(expected), expected);

        // Step 1: Write operand A to address 0x00.
        driver.transfer(
            1'b1, 32'h00, {{24{A[7]}}, A},
            temp_data, error
        );

        if (error)
            $fatal(1, "APB error writing A");

        scoreboard.process_write(32'h00, {{24{A[7]}}, A});

        // Step 2: Write operand B to address 0x04.
        driver.transfer(
            1'b1, 32'h04, {{24{B[7]}}, B},
            temp_data, error
        );

        if (error)
            $fatal(1, "APB error writing B");

        scoreboard.process_write(32'h04, {{24{B[7]}}, B});

        // Step 3: Start multiplication using address 0x08.
        driver.transfer(
            1'b1, 32'h08, 32'h00000001,
            temp_data, error
        );

        if (error)
            $fatal(1, "APB error starting multiplication");

        scoreboard.process_write(32'h08, 32'h00000001);

        // Step 4: Check that the multiplier has completed.
        driver.transfer(
            1'b0, 32'h10, 32'h00000000,
            temp_data, error
        );

        if (error)
            $fatal(1, "APB error reading status");

        if (temp_data[0] !== 1'b1)
            $fatal(1, "DONE flag not set for %0d x %0d", A, B);

        // Step 5: Read the multiplication result.
        driver.transfer(
            1'b0, 32'h0C, 32'h00000000,
            observed, error
        );

        if (error)
            $fatal(1, "APB error reading result");

        // Step 6: Compare DUT output against the reference.
        if (observed === expected) begin
            scoreboard.passed++;
            $display("[PASS] %0d x %0d = %0d",
                     A, B, $signed(observed));
        end
        else begin
            scoreboard.failed++;
            $error("[FAIL] %0d x %0d: expected %08h, got %08h",
                   A, B, expected, observed);
        end

        $display("========================================\n");
    end
endtask


    // Remember whether the slave asserted PSLVERR during the invalid ACCESS phase.
    always_ff @(posedge PCLK or negedge apb_if.PRESETn) begin
        if (!apb_if.PRESETn)
            invalid_pslverr_seen <= 1'b0;
        else if (mon_PSEL && mon_PENABLE && mon_PREADY &&
                 mon_PADDR == 32'h14 && mon_PSLVERR)
            invalid_pslverr_seen <= 1'b1;
    end

    // APB protocol assertions
    apb_assertions assertions (
        .PCLK    (PCLK),
        .PRESETn (apb_if.PRESETn),
        .PSEL    (mon_PSEL),
        .PENABLE (mon_PENABLE),
        .PWRITE  (mon_PWRITE),
        .PADDR   (mon_PADDR),
        .PWDATA  (mon_PWDATA),
        .PREADY  (mon_PREADY)
    );
  

    // Dedicated checker for a valid wait-state test.
    // These signals are independent of the real DUT bus so the DUT remains unchanged.
    logic        test_PSEL;
    logic        test_PENABLE;
    logic        test_PWRITE;
    logic [31:0] test_PADDR;
    logic [31:0] test_PWDATA;
    logic        test_PREADY;

    apb_assertions wait_state_assertions (
        .PCLK    (PCLK),
        .PRESETn (apb_if.PRESETn),
        .PSEL    (test_PSEL),
        .PENABLE (test_PENABLE),
        .PWRITE  (test_PWRITE),
        .PADDR   (test_PADDR),
        .PWDATA  (test_PWDATA),
        .PREADY  (test_PREADY)
    );

    // Exercise a legal APB wait state: controls remain stable while PREADY=0.
    initial begin
        test_PSEL   = 1'b0;
        test_PENABLE = 1'b0;
        test_PWRITE = 1'b0;
        test_PADDR  = 32'h00000004;
        test_PWDATA = 32'h00000007;
        test_PREADY = 1'b0;

        wait (apb_if.PRESETn === 1'b1);

        // SETUP phase: selected, PENABLE low.
        @(negedge PCLK);
        test_PSEL    = 1'b1;
        test_PENABLE = 1'b0;

        // ACCESS phase begins after a full SETUP cycle.
        @(negedge PCLK);
        test_PENABLE = 1'b1;
        test_PREADY  = 1'b0;

        // Two wait cycles. Keep PSEL/PENABLE/address/direction/data unchanged.
        repeat (2) @(negedge PCLK);

        // Complete the transfer; keep ACCESS controls stable through the next edge.
        test_PREADY = 1'b1;
        @(negedge PCLK);
        test_PSEL    = 1'b0;
        test_PENABLE = 1'b0;
        test_PREADY  = 1'b0;

        $display("[WAIT-STATE TEST] PASS: valid wait state completed without assertion failure");

    end
  
  	

    // Functional coverage
    apb_coverage coverage (
        .PCLK    (PCLK),
        .PRESETn (apb_if.PRESETn),
        .PSEL    (mon_PSEL),
        .PENABLE (mon_PENABLE),
        .PREADY  (mon_PREADY),
        .PWRITE  (mon_PWRITE),
        .PADDR   (mon_PADDR),
        .PWDATA  (mon_PWDATA),
        .PRDATA  (mon_PRDATA)
    );
  
  	
    initial begin
        apb_if.PRESETn   = 1'b0;
        apb_if.req_valid = 1'b0;
        apb_if.req_write = 1'b0;
        apb_if.req_addr  = '0;
        apb_if.req_wdata = '0;

        driver     = new(apb_if);
        monitor    = new(apb_if);
        scoreboard = new();

        // Run passive monitor independently.
        fork
            monitor.run();
        join_none

        repeat (4) @(negedge PCLK);
        apb_if.PRESETn = 1'b1;

        
        // Directed multiplication tests

        // 1. Positive x Positive
        test_multiplication(8'sd5, 8'sd6);

        // 2. Negative x Positive
        test_multiplication(-8'sd13, 8'sd7);

        // 3. Positive x Negative
        test_multiplication(8'sd9, -8'sd4);

        // 4. Negative x Negative
        test_multiplication(-8'sd8, -8'sd4);

        // 5. Multiplication by zero
        test_multiplication(8'sd0, 8'sd25);
        test_multiplication(-8'sd17, 8'sd0);

        // 6. Multiplication by one and minus one
        test_multiplication(8'sd1, 8'sd127);
        test_multiplication(-8'sd1, 8'sd127);

        // 7. Equal operands
        test_multiplication(8'sd12, 8'sd12);
        test_multiplication(-8'sd12, -8'sd12);

        // 8. Boundary values for signed 8-bit operands
        test_multiplication(-8'sd128, 8'sd1);
        test_multiplication(-8'sd128, -8'sd1);
        test_multiplication(8'sd127, 8'sd127);
        test_multiplication(-8'sd128, -8'sd128);

        // 9. Mixed magnitudes
        test_multiplication(8'sd3, -8'sd100);
        test_multiplication(-8'sd64, 8'sd2);

        // Report results for the complete test sequence
        scoreboard.report();

        if (scoreboard.failed != 0)
            $fatal(1, "MULTIPLIER VERIFICATION FAILED");
        else
            $display("ALL MULTIPLICATION TESTS PASSED");

        coverage.report_coverage();
        
        // Access an unmapped address. The slave should assert PSLVERR,
        // which the master must return as rsp_error.
        driver.transfer(
            1'b0, 32'h14, 32'h00000000,
            read_data, transfer_error
        );
        if (invalid_pslverr_seen !== 1'b1)
            $fatal(1, "INVALID-ADDRESS TEST FAILED: PSLVERR was not asserted during ACCESS");
        if (transfer_error !== 1'b1)
            $fatal(1, "INVALID-ADDRESS TEST FAILED: expected rsp_error=1, got %0b",
                   transfer_error);
        $display("[INVALID-ADDRESS TEST] PASS: PSLVERR=1 during ACCESS and rsp_error=1");
        $finish;

    

        scoreboard.report();

        if (scoreboard.failed != 0)
            $fatal(1, "TEST FAILED");
        else
            $display("TEST PASSED");

        coverage.report_coverage();
        
        $finish;
    end


    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end

endmodule

