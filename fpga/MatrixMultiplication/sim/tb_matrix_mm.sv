`timescale 1ns/1ps
// Testa o mesmo protocolo de registradores usado pelo programa C.
module tb_matrix_mm;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [4:0] address = 0;
    reg write = 0;
    reg [31:0] writedata = 0;
    wire [31:0] readdata;
    reg signed [15:0] a [0:3], b [0:3];
    reg signed [63:0] expected, obtained;
    reg [31:0] low, high;
    integer test_number, i, row, col;
    matrix_mm dut(.*);

    task put(input [4:0] addr, input [31:0] value);
        @(negedge clk);
        address = addr; writedata = value; write = 1;
        @(negedge clk);
        write = 0;
    endtask

    task get(input [4:0] addr, output [31:0] value);
        address = addr;
        #1;
        value = readdata;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        get(1, low);
        if (low !== 0) $fatal(1, "DONE não foi limpo pelo reset");
        get(20, low);
        if (low !== 32'h4d4d0001) $fatal(1, "ID incorreto");
        for (test_number = 0; test_number < 104; test_number = test_number + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                case (test_number)
                    0: begin a[i] = i + 1; b[i] = i + 5; end
                    1: begin a[i] = -32768; b[i] = -32768; end
                    2: begin a[i] = -32768; b[i] = 32767; end
                    3: begin a[i] = 0; b[i] = 0; end
                    default: begin a[i] = $random; b[i] = $random; end
                endcase
            end
            put(0, 0);
            get(1, low);
            if (low !== 0) $fatal(1, "DONE anterior não foi limpo");
            for (i = 0; i < 4; i = i + 1) begin
                put(4 + i, {{16{a[i][15]}}, a[i]});
                put(8 + i, {{16{b[i][15]}}, b[i]});
            end
            put(0, 1);
            get(1, low);
            if (low !== 1) $fatal(1, "DONE não foi ativado");
            for (row = 0; row < 2; row = row + 1) begin
                for (col = 0; col < 2; col = col + 1) begin
                    // Operandos estendidos para referência independente de 64 bits.
                    expected = 64'($signed(a[2*row])) * 64'($signed(b[col]))
                             + 64'($signed(a[2*row+1])) * 64'($signed(b[2+col]));
                    get(12 + 2*(2*row+col), low);
                    get(13 + 2*(2*row+col), high);
                    obtained = {high, low};
                    if (obtained !== expected)
                        $fatal(1, "Caso %0d [%0d,%0d]: esperado %0d, obtido %0d",
                               test_number, row, col, expected, obtained);
                end
            end
        end
        // Reset também deve apagar resultados de uma operação anterior.
        @(negedge clk); reset = 1;
        repeat (2) @(negedge clk);
        reset = 0;
        get(1, low);
        if (low !== 0) $fatal(1, "DONE após reset");
        get(12, low);
        if (low !== 0) $fatal(1, "Resultado após reset");
        $display("SUCESSO: 104 pares de matrizes, sinais, limites, DONE e reset.");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Timeout da simulação");
    end
endmodule
