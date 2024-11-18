

module control (
    input clk,
    input rst,
    // ROM
    input[15:0] ROM_data,
    output reg rom_rd,
    // RAM
    output reg ram_rd,
    output reg ram_wr,
    // REGFILE
    output reg rd_rs,
    output reg rd_rt,
    output addr_rs,
    output addr_rt,
    output reg wr_rd,
    // ALU
    output reg[2:0] ALU_cmd,
    // MUXes
    output reg RES_MUX,
    output reg OP2_MUX,
    output reg PC_MUX,
    output reg SHAMT_IMM_MUX, 
    output reg BEQ_MUX,
    output reg JUMP_MUX,
    output reg WB_MUX,
    output reg SILENCE_MUX
);

reg state;
parameter [3:0] BOOT                = 4'b0000,
                INSTRUCTION_FETCH   = 4'b0001,
                INSTRUCTION_DECODE  = 4'b0010,
                EXECUTE             = 4'b0100,
                MEMORY_ACCESS       = 4'b1000,
                WRITE_BACK          = 4'b1111;


wire[2:0] Fcode;
wire[3:0] opcode;
wire[2:0] rs,rt,rd;
wire[5:0] immediate;
wire[2:0] shamt;
wire[5:0] offset;
wire[11:0] address;

// internals
wire[15:0] instruction;
reg jump, jump_d, jump_dd;
reg memory_op, memory_op_d, memory_op_dd;
reg shamt_d;
reg wb_wr; // write-back write in regfile 
reg silence_op, silence_d, silence_dd, silence_ddd; // 1: silence_on, 0: silence_off


assign Fcode = instruction[2:0];
assign opcode = instruction[15:12];
assign rs = instruction[11:9];
assign rt = instruction[8:6];
assign rd = instruction[5:3];
assign immediate = instruction[5:0];
assign shamt = instruction[5:3];
assign offset = instruction[5:0];
assign address = instruction[11:0];


// instruction fetch process
always @(posedge clk or negedge rst) begin

    if (!rst) begin

        rom_rd <= '0';

    end else begin 

        rom_rd <= '1';

    end

end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        rd_rs <= 1'b0;
        rd_rt <= 1'b0;
    end else begin
        // always reading source registers
        rd_rs <= 1'b1;
        rd_rt <= 1'b1; 
    end
end

assign instruction = ROM_data;
assign addr_rs = instruction[11:9];
assign addr_rt = instruction[8:6];

// PIPELINE IS EXTERNAL.
// shamt 1cc pipeline. shamt can arrive to EXECUTE.
// always @(posedge clk or negedge rst) begin
//     if (!rst) begin
//         shamt_d <= 1'b0;
//     end else begin
//         shamt_d <= shamt;
//     end 
// end

// DECODE process
always @(posedge clk or negedge rst) begin

    if (!rst) begin

        OP2_MUX         <= 1'b0;
        ALU_cmd         <= 3'b000;
        jump            <= 1'b0;
        memory_op       <= 1'b0;
        SHAMT_IMM_MUX   <= 1'b0;

    end else begin 

        // default
        SHAMT_IMM_MUX   <= 1'b0;
        RES_MUX         <= 1'b1;
        OP2_MUX         <= 1'b0;
        PC_MUX          <= 1'b1;
        JUMP_MUX        <= 1'b0;
        BEQ_MUX         <= 1'b1;
        WB_MUX          <= 1'b0;
        ram_rd          <= 1'b0;
        ram_wr          <= 1'b0;
        wb_wr           <= 1'b0;
        silence_op      <= 1'b0;

        // silence_op HIGH @EXECUTE, silence_d HIGH @MA, silence_dd HIGH @WRITEBACK
        silence_d <= silence_op;
        silence_dd <= silence_d;
        silence_ddd <= silence_dd;

        if (opcode==0) begin
            // R-format
            if (Fcode==0) begin
                // add
                OP2_MUX <= 1'b0;
                //
                ALU_cmd <= 3'b000;
            end else if (Fcode==1) begin 
                // subtract
                OP2_MUX <= 1'b0;
                //
                ALU_cmd <= 3'b001;
            end else if (Fcode==2) begin
                // and
                OP2_MUX <= 1'b0;
                //
                ALU_cmd <= 3'b101;
            end else if (Fcode==3) begin
                // or
                OP2_MUX <= 1'b0;
                //
                ALU_cmd <= 3'b110;
            end else if (Fcode==4) begin
                // slt 
                OP2_MUX <= 1'b0;
                //
                ALU_cmd <= 3'b011;
            end else if (Fcode==5) begin
                // sll
                OP2_MUX <= 1'b1;
                SHAMT_IMM_MUX <= 1'b1;
                //
                ALU_cmd <= 3'b010;
            end else if (Fcode==6) begin
                // srl
                OP2_MUX <= 1'b1;
                SHAMT_IMM_MUX <= 1'b1;
                //
                ALU_cmd <= 3'b100;
            end else if (Fcode==7) begin
                // jr
                OP2_MUX <= 1'b0; // read $r0
                // add operation
                ALU_cmd <= 3'b000;
                //
                JUMP_MUX <= 1'b1;
            end
        end else if (opcode==4'b0001) begin
            // addi
            OP2_MUX <= 1'b1;
            wb_wr <= 1'b1;
            // +
            ALU_cmd <= 3'b000;
        end else if (opcode==4'b0011) begin
            // slti
            OP2_MUX <= 1'b1;
            wb_wr <= 1'b1;
            // >
            ALU_cmd <= 3'b011;
        end else if (opcode==4'b0100) begin
            // lw
            OP2_MUX <= 1'b1;
            ram_rd <= 1'b1;
            RES_MUX <= 1'b0;
            wb_wr <= 1'b1;
            // +
            ALU_cmd <= 3'b000;
         end else if (opcode==4'b0101) begin
            // sw
            OP2_MUX <= 1'b1;
            ram_wr <= 1'b1; 
            // +
            ALU_cmd <= 3'b000;
        end else if (opcode==4'b0110) begin
            // beq
            BEQ_MUX <= 1'b0;
            SILENCE_MUX <= 1'b1;
            silence_op <= 1'b1; 
            //== 
            ALU_cmd <= 3'b111;
        end else if (opcode==4'b0111) begin
            // j
            OP2_MUX <= 1'b1; 
            JUMP_MUX <= 1'b1;
            silence_op <= 1'b1;
            SILENCE_MUX <= 1'b1;
            // + , 0+imm
            ALU_cmd <= 3'b000;
        end else if (opcode==4'b1000) begin
            // jal
            OP2_MUX <= 1'b1;
            JUMP_MUX <= 1'b1; 
            WB_MUX <= 1'b1;
            wb_wr <= 1'b1;
            wb_waddr <= 4'hF; // $ra
            SILENCE_MUX <= 1'b1;
            silence_op <= 1'b1;
        end


        if silence_ddd==1'b1 begin
            SILENCE_MUX <= 1'b0;
        end

    end

end


always @(posedge clk or negedge rst) begin
    if (!rst) begin
        state <= BOOT;
        instruction <= 0;
        jump <= 0;
        memory_op <= 1'b0;
    end else begin

        // defaults/triggers
        rd_rs  <= 1'b0;
        rom_rd  <= 1'b0;
        rd_rt  <= 1'b0;
        ram_rd  <= 1'b0;
        ram_wr  <= 1'b0;
        jump    <= 1'b0;
        memory_op <= 1'b0;

        // delays
        jump_d <= jump;
        jump_dd <= jump_d;
        memory_op_d <= memory_op;
        memory_op_dd <= memory_op_d;

        

        case (state)
            BOOT:
                state <= INSTRUCTION_FETCH; 
            
            INSTRUCTION_FETCH:
                instruction <= ROM_data;
                state <= INSTRUCTION_DECODE;

            INSTRUCTION_DECODE:
                if (opcode==0) begin
                    // R-format
                    if (Fcode==0) begin
                        // add
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b1;
                        OP2_MUX <= 1'b0;
                        //
                        ALU_cmd <= 3'b000;
                    end else if (Fcode==1) begin
                        // subtract
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b1;
                        OP2_MUX <= 1'b0;
                        //
                        ALU_cmd <= 3'b001;
                    end else if (Fcode==2) begin
                        // and
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b1;
                        OP2_MUX <= 1'b0;
                        //
                        ALU_cmd <= 3'b101;
                    end else if (Fcode==3) begin
                        // or
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b1;
                        OP2_MUX <= 1'b0;
                        //
                        ALU_cmd <= 3'b110;
                    end else if (Fcode==4) begin
                        // slt
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b1;
                        OP2_MUX <= 1'b0;
                        //
                        ALU_cmd <= 3'b011;
                    end else if (Fcode==5) begin
                        // sll
                        rd_rs <= 1'b1;
                        OP2_MUX <= 1'b1;
                        //
                        ALU_cmd <= 3'b010;
                    end else if (Fcode==6) begin
                        // srl
                        rd_rs <= 1'b1;
                        OP2_MUX <= 1'b1;
                        //
                        ALU_cmd <= 3'b010;
                    end else if (Fcode==7) begin
                        // jr
                        rd_rs <= 1'b1;
                        rd_rt <= 1'b0; // require $0
                        OP2_MUX <= 1'b0;
                        // add operation
                        ALU_cmd <= 3'b000;
                        //
                        jump <= 1'b1;
                    end
                end else if (opcode==4'b0001) begin
                    // addi
                    rd_rs <= 1'b1;
                    OP2_MUX <= 1'b1;
                    //
                    ALU_cmd <= 1'b0;
                end else if (opcode==4'b0011) begin
                    // slti
                    rd_rs <= 1'b1;
                    OP2_MUX <= 1'b1;
                    // >
                    ALU_cmd <= 3'b011;
                end else if (opcode==4'b0100) begin
                    // lw
                    rd_rs <= 1'b1;
                    OP2_MUX <= 1'b1;
                    // +
                    ALU_cmd <= 3'b000;
                    //
                    memory_op <= 1'b1;
                end else if (opcode==4'b0101) begin
                    // sw
                    rd_rs 
                end else if (opcode==4'b0110) begin
                    // beq

                end else if (opcode==4'b0111) begin
                    // j

                end else if (opcode==4'b1000) begin
                    // jal

                end
                //
                state <= EXECUTE;

            
            EXECUTE:
                //
                state <= MEMORY_ACCESS;


            MEMORY_ACCESS:
                //
                state <= WRITE_BACK;

            WRITE_BACK:
                //
                state <= INSTRUCTION_FETCH;


            default: 
        endcase



    end





end

    
endmodule