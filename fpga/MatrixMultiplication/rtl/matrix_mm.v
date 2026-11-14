// Multiplicação 2x2, inteiros com sinal de 16 bits.
// Interface Avalon-MM: endereços de PALAVRAS de 32 bits, leitura combinacional.
// O Platform Designer converte o endereço em bytes do ARM para estas palavras.
// Não há DMA, interrupções ou máquinas de estados: START calcula quatro somas.
module matrix_mm (
    input wire clk,
    input wire reset,
    input wire [4:0] address,
    input wire write,
    input wire [31:0] writedata,
    output reg [31:0] readdata
);
    reg signed [15:0] a [0:3];
    reg signed [15:0] b [0:3];
    reg signed [32:0] c [0:3];
    reg done;
    integer i;

    // O atributo sugere DSPs ao Quartus. O relatório de síntese confirma
    // o mapeamento real; o número de DSPs depende do empacotamento do dispositivo.
    (* multstyle = "dsp" *) wire signed [31:0] p00 = a[0] * b[0];
    (* multstyle = "dsp" *) wire signed [31:0] p01 = a[1] * b[2];
    (* multstyle = "dsp" *) wire signed [31:0] p10 = a[0] * b[1];
    (* multstyle = "dsp" *) wire signed [31:0] p11 = a[1] * b[3];
    (* multstyle = "dsp" *) wire signed [31:0] p20 = a[2] * b[0];
    (* multstyle = "dsp" *) wire signed [31:0] p21 = a[3] * b[2];
    (* multstyle = "dsp" *) wire signed [31:0] p30 = a[2] * b[1];
    (* multstyle = "dsp" *) wire signed [31:0] p31 = a[3] * b[3];

    always @(posedge clk) begin
        if (reset) begin
            done <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                a[i] <= 0;
                b[i] <= 0;
                c[i] <= 0;
            end
        end else if (write) begin
            case (address)
                0: begin
                    // Escrever zero limpa DONE. Escrever um calcula e marca DONE.
                    done <= writedata[0];
                    if (writedata[0]) begin
                        // Extensão explícita para 33 bits ANTES da soma.
                        c[0] <= $signed({p00[31], p00}) + $signed({p01[31], p01});
                        c[1] <= $signed({p10[31], p10}) + $signed({p11[31], p11});
                        c[2] <= $signed({p20[31], p20}) + $signed({p21[31], p21});
                        c[3] <= $signed({p30[31], p30}) + $signed({p31[31], p31});
                    end
                end
                4, 5, 6, 7: a[address - 4] <= writedata[15:0];
                8, 9, 10, 11: b[address - 8] <= writedata[15:0];
                default: begin end
            endcase
        end
    end

    // Resultados são estendidos de 33 para 64 bits e lidos em duas palavras.
    // O alto vale 0 para resultado positivo e 0xffffffff para negativo.
    always @* begin
        readdata = 0;
        case (address)
            1: readdata = {31'b0, done};
            4, 5, 6, 7: readdata = {{16{a[address - 4][15]}}, a[address - 4]};
            8, 9, 10, 11: readdata = {{16{b[address - 8][15]}}, b[address - 8]};
            12: readdata = c[0][31:0];
            13: readdata = {32{c[0][32]}};
            14: readdata = c[1][31:0];
            15: readdata = {32{c[1][32]}};
            16: readdata = c[2][31:0];
            17: readdata = {32{c[2][32]}};
            18: readdata = c[3][31:0];
            19: readdata = {32{c[3][32]}};
            20: readdata = 32'h4d4d0001; // Assinatura e versão do periférico.
            default: readdata = 0;
        endcase
    end
endmodule
