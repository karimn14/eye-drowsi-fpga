// AUTO-GENERATED golden vectors from the Python integer model (simulation only)
module golden_rom (input [3:0] idx, output reg [3:0] pred, output reg [3:0] label,
                   output reg [239:0] logits);   // logits[24*c +: 24] = signed logit of class c
    always @* begin
        case (idx)
            4'd0: begin pred = 4'd0; label = 4'd0; logits = 240'hfffb8bfffdbeffeeeb00060b0002c8fff9b6fff08dfff2adfffa2a001661; end
            4'd1: begin pred = 4'd1; label = 4'd1; logits = 240'hffee7b0009f1ffed6f000278ffedc1fff918fff89cfffefb001e6affefa9; end
            4'd2: begin pred = 4'd2; label = 4'd2; logits = 240'hfff1c4fffe41fff138ffee79fff1ceffedad000f4c0023d3000304ffea91; end
            4'd3: begin pred = 4'd3; label = 4'd3; logits = 240'h00068600007000018affe5fcffff84ffe67e0022e40008cffff3aeffeb6a; end
            4'd4: begin pred = 4'd4; label = 4'd4; logits = 240'hffee2300043b000247000357fffb69001123fff9dcffeced00077dffe8ed; end
            4'd5: begin pred = 4'd5; label = 4'd5; logits = 240'h0005c7000152fff6cdfffcf0001a79fff920fffdbeffeeecfff0cefffa45; end
            4'd6: begin pred = 4'd6; label = 4'd6; logits = 240'hffde5a000311fff414001f38ffff54000277fff77ffff662fff51cfffb12; end
            4'd7: begin pred = 4'd7; label = 4'd7; logits = 240'hfff8dcffff82001af7ffeb4cfff8d3fffc82000826fffe7afff07cfff731; end
            4'd8: begin pred = 4'd8; label = 4'd8; logits = 240'h00047f000b32fffa5bfff55cffecd4ffedeefffd0c000180fffb29fff782; end
            4'd9: begin pred = 4'd9; label = 4'd9; logits = 240'h000c62fff732fff8bdffed760003e1ffe9200008da00045cfff76bfffb26; end
            4'd10: begin pred = 4'd4; label = 4'd9; logits = 240'h0006e600026d00014efffca1000128000d92ffed68ffe4d4fffb52fffc87; end
            4'd11: begin pred = 4'd6; label = 4'd6; logits = 240'hffe1c2000444ffe2c2001a130006ae00013dfff6d7fff502ffffd6fffecc; end
            4'd12: begin pred = 4'd1; label = 4'd1; logits = 240'h000029000832fff593fff487fff7870005230001bcfff1cc001945ffe637; end
            4'd13: begin pred = 4'd6; label = 4'd6; logits = 240'hffdb160005e6fff130001c1e000141000946fff7b9fff540fff864fff9a1; end
            4'd14: begin pred = 4'd3; label = 4'd3; logits = 240'hfffb1d00038bfffb2dfff61fffffb3ffee4f00135c000652fffb96ffebef; end
            4'd15: begin pred = 4'd0; label = 4'd0; logits = 240'hfffac0ffff9dfff27ffffc95fffd96fff690fff9bbfff49bfff56c0017b6; end
            default: begin pred = 4'd0; label = 4'd0; logits = 240'd0; end
        endcase
    end
endmodule
