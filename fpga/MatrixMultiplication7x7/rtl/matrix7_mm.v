`timescale 1ns/1ps
// 7x7 inteiros com sinal de 16 bits: 343 multiplicadores em paralelo.
// Uma multiplicação completa tem quatro estágios registrados:
// 0: produtos (32 bits); 1: pares (33); 2: grupos de quatro (34); 3: soma (35).
// O protocolo repete operações NÃO sobrepostas para medir latência, não vazão.
module matrix7_mm #(
    parameter CLOCK_FREQUENCY = 100000000
)(
    input wire clk,
    input wire reset,
    input wire [8:0] address, // Palavras de 32 bits: janela de 2048 bytes.
    input wire write,
    input wire [31:0] writedata,
    output reg [31:0] readdata
);
    reg signed [15:0] a [0:48];
    reg signed [15:0] b [0:48];
    reg signed [34:0] c [0:48];
    reg busy, done;
    reg [1:0] phase;
    reg [31:0] runs, remaining, cycles;
    integer i;

    // Controle e entradas não mudam durante um lote em execução.
    always @(posedge clk) begin
        if (reset) begin
            busy <= 0; done <= 0; phase <= 0;
            runs <= 1; remaining <= 0; cycles <= 0;
            for (i = 0; i < 49; i = i + 1) begin a[i] <= 0; b[i] <= 0; end
        end else if (busy) begin
            cycles <= cycles + 1'b1;
            phase <= phase + 1'b1;
            if (phase == 3) begin
                if (remaining == 1) begin busy <= 0; done <= 1; end
                else remaining <= remaining - 1'b1;
            end
        end else if (write) begin
            if (address == 0) begin
                done <= 0;
                if (writedata[0]) begin
                    busy <= 1; phase <= 0; cycles <= 0; remaining <= runs;
                end
            end else if (address == 4) begin
                // Limita o lote e evita estouro do contador de ciclos.
                if (writedata >= 1 && writedata <= 1000000) runs <= writedata;
            end else if (address >= 64 && address < 113)
                a[address - 64] <= writedata[15:0];
            else if (address >= 128 && address < 177)
                b[address - 128] <= writedata[15:0];
        end
    end

    genvar row, col, k;
    generate
        for (row = 0; row < 7; row = row + 1) begin: rows
            for (col = 0; col < 7; col = col + 1) begin: cols
                reg signed [31:0] product [0:6];
                reg signed [32:0] pair_sum [0:3];
                reg signed [33:0] quad_sum [0:1];
                for (k = 0; k < 7; k = k + 1) begin: multipliers
                    // 6 produtos por saída em DSPs (três pares) e o sétimo
                    // em ALMs. Todos continuam simultâneos. A tentativa de
                    // empacotar os sete exclusivamente em DSPs excedeu os
                    // recursos no Fitter, apesar da estimativa de síntese.
                    if (k == 6) begin: in_logic
                        (* multstyle = "logic" *) wire signed [31:0] mult_value;
                        assign mult_value = a[7*row+k] * b[7*k+col];
                        always @(posedge clk)
                            if (busy && phase == 0) product[k] <= mult_value;
                    end else begin: in_dsp
                        (* multstyle = "dsp" *) wire signed [31:0] mult_value;
                        assign mult_value = a[7*row+k] * b[7*k+col];
                        always @(posedge clk)
                            if (busy && phase == 0) product[k] <= mult_value;
                    end
                end
                // Estágios intermediários não precisam de reset: só são usados
                // depois de receber seus operandos válidos no mesmo lote.
                always @(posedge clk) begin
                    if (busy && phase == 1) begin
                        pair_sum[0] <= $signed({product[0][31],product[0]}) + $signed({product[1][31],product[1]});
                        pair_sum[1] <= $signed({product[2][31],product[2]}) + $signed({product[3][31],product[3]});
                        pair_sum[2] <= $signed({product[4][31],product[4]}) + $signed({product[5][31],product[5]});
                        pair_sum[3] <= $signed({product[6][31],product[6]});
                    end
                    if (busy && phase == 2) begin
                        quad_sum[0] <= $signed({pair_sum[0][32],pair_sum[0]}) + $signed({pair_sum[1][32],pair_sum[1]});
                        quad_sum[1] <= $signed({pair_sum[2][32],pair_sum[2]}) + $signed({pair_sum[3][32],pair_sum[3]});
                    end
                    if (reset) c[7*row+col] <= 0;
                    else if (busy && phase == 3)
                        c[7*row+col] <= $signed({quad_sum[0][33],quad_sum[0]}) + $signed({quad_sum[1][33],quad_sum[1]});
                end
            end
        end
    endgenerate

    always @* begin
        readdata = 0;
        case (address)
            1: readdata = {30'b0, busy, done};
            2: readdata = 32'h4d4d0701; // ID distinto do exemplo 2x2.
            3: readdata = cycles;
            4: readdata = runs;
            6: readdata = CLOCK_FREQUENCY;
            7: readdata = 4;
            default: begin
                if (address >= 256 && address < 354) begin
                    if (address[0])
                        readdata = {{29{c[(address-256)/2][34]}}, c[(address-256)/2][34:32]};
                    else readdata = c[(address-256)/2][31:0];
                end
            end
        endcase
    end
endmodule
