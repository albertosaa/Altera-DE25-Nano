`timescale 1ns/1ps
// Referência matemática de 64 bits e observação independente dos ciclos busy.
module tb_matrix7_mm;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [8:0] address = 0;
    reg write = 0;
    reg [31:0] writedata = 0;
    wire [31:0] readdata;
    reg signed [15:0] a[0:48], b[0:48];
    reg signed [63:0] expected, obtained;
    reg [31:0] low, high, status, cycle_count;
    integer test_number, i, row, col, k, runs, polls, observed_clocks = 0;
    matrix7_mm dut(.*);
    always @(posedge clk) if (!reset && dut.busy) observed_clocks = observed_clocks + 1;

    task put(input [8:0] addr, input [31:0] value);
        @(negedge clk); address = addr; writedata = value; write = 1;
        @(negedge clk); write = 0;
    endtask
    task get(input [8:0] addr, output [31:0] value);
        address = addr; #1; value = readdata;
    endtask
    initial begin
        repeat (2) @(negedge clk); reset = 0;
        get(1, status);
        if (status !== 0) $fatal(1, "Reset de STATUS");
        get(2, low);
        if (low !== 32'h4d4d0701) $fatal(1, "ID do 7x7");
        get(6, low);
        if (low !== 100000000) $fatal(1, "Clock declarado");
        get(7, low);
        if (low !== 4) $fatal(1, "Latência declarada");
        for (test_number = 0; test_number < 104; test_number = test_number + 1) begin
            for (i = 0; i < 49; i = i + 1) begin
                a[i] = $random; b[i] = $random;
                case (test_number)
                    0: begin a[i] = 0; b[i] = 0; end
                    1: begin a[i] = -32768; b[i] = -32768; end
                    2: begin a[i] = -32768; b[i] = 32767; end
                    3: begin a[i] = (i / 7 == i % 7); b[i] = a[i]; end
                endcase
            end
            put(0, 0);
            get(1, status);
            if (status !== 0) $fatal(1, "DONE não limpou");
            for (i = 0; i < 49; i = i + 1) begin
                put(64+i, {{16{a[i][15]}}, a[i]});
                put(128+i, {{16{b[i][15]}}, b[i]});
            end
            runs = test_number % 5 + 1;
            if (test_number == 4) runs = 10;
            put(4, runs);
            observed_clocks = 0;
            put(0, 1);
            if (test_number == 4) begin
                // Escritas durante busy devem ser ignoradas, sem corromper
                // operandos, repetições ou reiniciar o contador.
                put(64, 1234); put(4, 1); put(0, 1);
            end
            polls = 0;
            get(1, status);
            while (!(status & 1) && polls < 100) begin
                @(negedge clk); get(1, status); polls = polls + 1;
            end
            if (status !== 1) $fatal(1, "DONE/busy ou timeout");
            get(3, cycle_count);
            if (cycle_count !== 4*runs || observed_clocks != 4*runs)
                $fatal(1, "Ciclos: reg=%0d observados=%0d esperados=%0d", cycle_count, observed_clocks, 4*runs);
            for (row = 0; row < 7; row = row + 1)
                for (col = 0; col < 7; col = col + 1) begin
                    expected = 0;
                    for (k = 0; k < 7; k = k + 1)
                        expected = expected + 64'($signed(a[7*row+k])) * 64'($signed(b[7*k+col]));
                    get(256+2*(7*row+col), low);
                    get(257+2*(7*row+col), high);
                    obtained = {high, low};
                    if (obtained !== expected)
                        $fatal(1, "Caso %0d C[%0d,%0d]: esperado %0d obtido %0d", test_number, row, col, expected, obtained);
                end
        end
        // Reset durante uma operação deve abortar o lote e limpar estado/saídas.
        put(4, 100); put(0, 1);
        @(negedge clk); reset = 1;
        repeat (2) @(negedge clk); reset = 0;
        get(1, status);
        if (status !== 0) $fatal(1, "Reset de busy/DONE");
        get(3, low);
        if (low !== 0) $fatal(1, "Reset de contador");
        get(256, low);
        if (low !== 0) $fatal(1, "Reset de resultado");
        $display("RTL: 104 pares 7x7, 4 ciclos/op, lotes, signed, busy e reset corretos.");
        $finish;
    end
    initial begin #1000000; $fatal(1, "Timeout global"); end
endmodule
