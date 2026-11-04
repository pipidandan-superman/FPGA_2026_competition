// ����ͷ�ؼ��Ĵ������� (25MHz Input Clock, ������RGBɫ��У����ʱ�����)
module ov5640_regs
#(
    parameter CAM_HSIZE = 640   ,
    parameter CAM_VSIZE = 480   ,
    parameter REG_NUM   = 8'D251 // ȷ���������������251
)
(
    input       [7:0] REG_INDEX,
    output reg [23:0] REG_DATA
);

always@(*)
begin
    case(REG_INDEX)
    // ==========================================
    // 1. ϵͳ��ʼ����ӿ�ʹ��
    // ==========================================
    0:       REG_DATA<=24'h310311; // system clock from pad
    1:       REG_DATA<=24'h300882; // software reset
    2:       REG_DATA<=24'h300842; // software power down (����д��)
    3:       REG_DATA<=24'h310303; // system clock from PLL
    4:       REG_DATA<=24'h3017ff; // FREX, Vsync, HREF, PCLK enable
    5:       REG_DATA<=24'h3018ff; // D[5:0] output enable
    6:       REG_DATA<=24'h30341a; // MIPI 10-bit
    7:       REG_DATA<=24'h300e58; // MIPI power down, DVP enable
    8:       REG_DATA<=24'h302e00; // DVP ��������

    // ==========================================
    // 2. ʱ������ (25MHz -> 50MHz PCLK)
    // ==========================================
//    9:       REG_DATA<=24'h303711; 
//    10:      REG_DATA<=24'h310801; 
//    11:      REG_DATA<=24'h303541; 
//    12:      REG_DATA<=24'h303620; 
    // 2. ʱ������ (��� 24MHz Input Clock (XCLK))
    // ==========================================
    9:       REG_DATA<=24'h303713; // PLL Root Divider (Bit[4]=1 -> enable PLL, Bit[3:0]=3 -> Pre-divider = /2) (24/2 = 12MHz)
    10:      REG_DATA<=24'h310801; // system clock divider 
    11:      REG_DATA<=24'h303511; // PLL1 multiplier (Bit[7:0] = 0x11 -> x17) (12 * 17 = 204MHz VCO)
                                   // ���߿��Գ��� 24'h303514 (x20, 240MHz VCO) �ȣ�ȡ������Ĵ�������0x11 ��Ϊ�����ȶ���
    12:      REG_DATA<=24'h303646; // PLL1 sys divider (Bit[7:4] = sys_div -> 4 (��Ƶ/2), Bit[3:0] = pclk_div -> 6 (��Ƶ/2))
                                   // ���� PCLK ��ԼΪ 204 / 2 / 2 = 51MHz

    // ==========================================
    // 3. ����ϵͳ�� AEC (�Զ��ع�) ����
    // ==========================================
    13:      REG_DATA<=24'h363036;
    14:      REG_DATA<=24'h36310e;
    15:      REG_DATA<=24'h3632e2;
    16:      REG_DATA<=24'h363312;
    17:      REG_DATA<=24'h3621e0;
    18:      REG_DATA<=24'h3704a0;
    19:      REG_DATA<=24'h37035a;
    20:      REG_DATA<=24'h371578;
    21:      REG_DATA<=24'h371701;
    22:      REG_DATA<=24'h370b60;
    23:      REG_DATA<=24'h37051a;
    24:      REG_DATA<=24'h390502;
    25:      REG_DATA<=24'h390610;
    26:      REG_DATA<=24'h39010a;
    27:      REG_DATA<=24'h373112;
    28:      REG_DATA<=24'h360008; // VCM
    29:      REG_DATA<=24'h360133; 
    30:      REG_DATA<=24'h302d60; 
    31:      REG_DATA<=24'h362052;
    32:      REG_DATA<=24'h371b20;
    33:      REG_DATA<=24'h471c50;
    34:      REG_DATA<=24'h3a1343; // AEC
//    35:      REG_DATA<=24'h3a1800; 
    35:      REG_DATA<=24'h3a1802; // 02 �� 03 ������Чѹ�����ڰ����µĲ���
    36:      REG_DATA<=24'h3a19f8; 
    37:      REG_DATA<=24'h363513;
    38:      REG_DATA<=24'h363603;
    39:      REG_DATA<=24'h363440;
    40:      REG_DATA<=24'h362201;
    41:      REG_DATA<=24'h3c0134; 
    42:      REG_DATA<=24'h3c0428;
    43:      REG_DATA<=24'h3c0598;
    44:      REG_DATA<=24'h3c0600;
    45:      REG_DATA<=24'h3c0708; 
    46:      REG_DATA<=24'h3c0800;
    47:      REG_DATA<=24'h3c091c; 
    48:      REG_DATA<=24'h3c0a9c;
    49:      REG_DATA<=24'h3c0b40;
    50:      REG_DATA<=24'h381000; 
    51:      REG_DATA<=24'h381110;
    52:      REG_DATA<=24'h381200; 
    53:      REG_DATA<=24'h370864;
    54:      REG_DATA<=24'h400102; // BLC start
    55:      REG_DATA<=24'h40051a; 
    56:      REG_DATA<=24'h300000; // system block reset
    57:      REG_DATA<=24'h3004ff; // clock enable

    // ==========================================
    // 4. ͼ���ʽ�� ISP ���Ŀ��� (����RGB��ɫ�ʾ���)
    // ==========================================
    58:      REG_DATA<=24'h430061; // RGB565 output
    59:      REG_DATA<=24'h501f01; // ISP RGB mode
    60:      REG_DATA<=24'h440e00;
    61:      REG_DATA<=24'h5000a7; // BPC on, WPC on, CIP on
    62:      REG_DATA<=24'h5001b3; // CMX on, AWB on (ɫ�ʻָ��ؼ�)
//    63:      REG_DATA<=24'h3a0f30; 
//    64:      REG_DATA<=24'h3a1028;
//    65:      REG_DATA<=24'h3a1b30;
// ========= �޸�Ϊ (��������Ŀ��ֵ) =========
    63:      REG_DATA<=24'h3a0f38; // �����������
    64:      REG_DATA<=24'h3a1030; // �����������
    65:      REG_DATA<=24'h3a1b38; // ���Ŀ����Ƶ�
    66:      REG_DATA<=24'h3a1e26;
    67:      REG_DATA<=24'h3a1160;
    68:      REG_DATA<=24'h3a1f14;

    // ==========================================
    // 5. ��ͷУ�� (LENC)
    // ==========================================
    69:      REG_DATA<=24'h580023;
    70:      REG_DATA<=24'h580114;
    71:      REG_DATA<=24'h58020f;
    72:      REG_DATA<=24'h58030f;
    73:      REG_DATA<=24'h580412;
    74:      REG_DATA<=24'h580526;
    75:      REG_DATA<=24'h58060c;
    76:      REG_DATA<=24'h580708;
    77:      REG_DATA<=24'h580805;
    78:      REG_DATA<=24'h580905;
    79:      REG_DATA<=24'h580a08;
    80:      REG_DATA<=24'h580b0d;
    81:      REG_DATA<=24'h580c08;
    82:      REG_DATA<=24'h580d03;
    83:      REG_DATA<=24'h580e00;
    84:      REG_DATA<=24'h580f00;
    85:      REG_DATA<=24'h581003;
    86:      REG_DATA<=24'h581109;
    87:      REG_DATA<=24'h581207;
    88:      REG_DATA<=24'h581303;
    89:      REG_DATA<=24'h581400;
    90:      REG_DATA<=24'h581501;
    91:      REG_DATA<=24'h581603;
    92:      REG_DATA<=24'h581708;
    93:      REG_DATA<=24'h58180d;
    94:      REG_DATA<=24'h581908;
    95:      REG_DATA<=24'h581a05;
    96:      REG_DATA<=24'h581b06;
    97:      REG_DATA<=24'h581c08;
    98:      REG_DATA<=24'h581d0e;
    99:      REG_DATA<=24'h581e29;
    100:     REG_DATA<=24'h581f17;
    101:     REG_DATA<=24'h582011;
    102:     REG_DATA<=24'h582111;
    103:     REG_DATA<=24'h582215;
    104:     REG_DATA<=24'h582328;
    105:     REG_DATA<=24'h582446;
    106:     REG_DATA<=24'h582526;
    107:     REG_DATA<=24'h582608;
    108:     REG_DATA<=24'h582726;
    109:     REG_DATA<=24'h582864;
    110:     REG_DATA<=24'h582926;
    111:     REG_DATA<=24'h582a24;
    112:     REG_DATA<=24'h582b22;
    113:     REG_DATA<=24'h582c24;
    114:     REG_DATA<=24'h582d24;
    115:     REG_DATA<=24'h582e06;
    116:     REG_DATA<=24'h582f22;
    117:     REG_DATA<=24'h583040;
    118:     REG_DATA<=24'h583142;
    119:     REG_DATA<=24'h583224;
    120:     REG_DATA<=24'h583326;
    121:     REG_DATA<=24'h583424;
    122:     REG_DATA<=24'h583522;
    123:     REG_DATA<=24'h583622;
    124:     REG_DATA<=24'h583726;
    125:     REG_DATA<=24'h583844;
    126:     REG_DATA<=24'h583924;
    127:     REG_DATA<=24'h583a26;
    128:     REG_DATA<=24'h583b28;
    129:     REG_DATA<=24'h583c42;
    130:     REG_DATA<=24'h583dce;

    // ==========================================
    // 6. AWB �Զ���ƽ���� Gamma ٤������
    // ==========================================
    131:     REG_DATA<=24'h5180ff;
    132:     REG_DATA<=24'h5181f2;
    133:     REG_DATA<=24'h518200;
    134:     REG_DATA<=24'h518314;
    135:     REG_DATA<=24'h518425;
    136:     REG_DATA<=24'h518524;
    137:     REG_DATA<=24'h518609;
    138:     REG_DATA<=24'h518709;
    139:     REG_DATA<=24'h518809;
    140:     REG_DATA<=24'h518975;
    141:     REG_DATA<=24'h518a54;
    142:     REG_DATA<=24'h518be0;
    143:     REG_DATA<=24'h518cb2;
    144:     REG_DATA<=24'h518d42;
    145:     REG_DATA<=24'h518e3d;
    146:     REG_DATA<=24'h518f56;
    147:     REG_DATA<=24'h519046;
    148:     REG_DATA<=24'h5191f8;
    149:     REG_DATA<=24'h519204;
    150:     REG_DATA<=24'h519370;
    151:     REG_DATA<=24'h5194f0;
    152:     REG_DATA<=24'h5195f0;
    153:     REG_DATA<=24'h519603;
    154:     REG_DATA<=24'h519701;
    155:     REG_DATA<=24'h519804;
    156:     REG_DATA<=24'h519912;
    157:     REG_DATA<=24'h519a04;
    158:     REG_DATA<=24'h519b00;
    159:     REG_DATA<=24'h519c06;
    160:     REG_DATA<=24'h519d82;
    161:     REG_DATA<=24'h519e38;

    162:     REG_DATA<=24'h548001;
    163:     REG_DATA<=24'h548108;
    164:     REG_DATA<=24'h548214;
    165:     REG_DATA<=24'h548328;
    166:     REG_DATA<=24'h548451;
    167:     REG_DATA<=24'h548565;
    168:     REG_DATA<=24'h548671;
    169:     REG_DATA<=24'h54877d;
    170:     REG_DATA<=24'h548887;
    171:     REG_DATA<=24'h548991;
    172:     REG_DATA<=24'h548a9a;
    173:     REG_DATA<=24'h548baa;
    174:     REG_DATA<=24'h548cb8;
    175:     REG_DATA<=24'h548dcd;
    176:     REG_DATA<=24'h548edd;
    177:     REG_DATA<=24'h548fea;
    178:     REG_DATA<=24'h54901d;

    // ==========================================
    // 7. CMX ɫ�ʾ�����ͼ���Ż�
    // ==========================================
    179:     REG_DATA<=24'h53811e;
    180:     REG_DATA<=24'h53825b;
    181:     REG_DATA<=24'h538308;
    182:     REG_DATA<=24'h53840a;
    183:     REG_DATA<=24'h53857e;
    184:     REG_DATA<=24'h538688;
    185:     REG_DATA<=24'h53877c;
    186:     REG_DATA<=24'h53886c;
    187:     REG_DATA<=24'h538910;
    188:     REG_DATA<=24'h538a01;
    189:     REG_DATA<=24'h538b98;

    190:     REG_DATA<=24'h558006;
    191:     REG_DATA<=24'h558340;
    192:     REG_DATA<=24'h558410;
    193:     REG_DATA<=24'h558910;
    194:     REG_DATA<=24'h558a00;
    195:     REG_DATA<=24'h558bf8;
    196:     REG_DATA<=24'h501d40; 
    197:     REG_DATA<=24'h530008; 
    198:     REG_DATA<=24'h530130;
    199:     REG_DATA<=24'h530210;
    200:     REG_DATA<=24'h530300;
    201:     REG_DATA<=24'h530408;
    202:     REG_DATA<=24'h530530;
    203:     REG_DATA<=24'h530608;
    204:     REG_DATA<=24'h530716;
    205:     REG_DATA<=24'h530908;
    206:     REG_DATA<=24'h530a30;
    207:     REG_DATA<=24'h530b04;
    208:     REG_DATA<=24'h530c06;
    209:     REG_DATA<=24'h502500;
    210:     REG_DATA<=24'h3c0708;

    // ==========================================
    // 8. ����ʱ��ָ� (��ԭ��ԭ��.v��25M����ʱ��)
    // ==========================================
    211:     REG_DATA<=24'h382040; // flip off
    212:     REG_DATA<=24'h382101; // mirror on
    213:     REG_DATA<=24'h381431; 
    214:     REG_DATA<=24'h381531; 
    215:     REG_DATA<=24'h380000; // ԭ�� HS
    216:     REG_DATA<=24'h380100; // ԭ�� HS
    217:     REG_DATA<=24'h380200; // ԭ�� VS
    218:     REG_DATA<=24'h3803fa; // ԭ�� VS
    219:     REG_DATA<=24'h38040a; // ԭ�� HW
    220:     REG_DATA<=24'h38053f; // ԭ�� HW
    221:     REG_DATA<=24'h380606; // ԭ�� VH
    222:     REG_DATA<=24'h3807a9; // ԭ�� VH
    
    // �������ֱ���
    223:     REG_DATA<={16'h3808,CAM_HSIZE[15:8]} ;
    224:     REG_DATA<={16'h3809,CAM_HSIZE[ 7:0]};
    225:     REG_DATA<={16'h380a,CAM_VSIZE[15:8]} ;
    226:     REG_DATA<={16'h380b,CAM_VSIZE[ 7:0]};
    
    // ԭ�� 25MHz �г��ܴ�С (ǧ���ܶ�)
    227:     REG_DATA<=24'h380c07; 
    228:     REG_DATA<=24'h380d64; 
    // ========= �޸�Ϊ (���ӵ�ʮ���� 1000 ������) =========
    229:     REG_DATA<=24'h380e03; 
    230:     REG_DATA<=24'h380fe8;

    231:     REG_DATA<=24'h381304; 
    232:     REG_DATA<=24'h361800;
    233:     REG_DATA<=24'h361229;
    234:     REG_DATA<=24'h370952;
    235:     REG_DATA<=24'h370c03;
    236:     REG_DATA<=24'h3a0217; 
    237:     REG_DATA<=24'h3a03e0; // ԭ���ع����
    238:     REG_DATA<=24'h3a1417; 
    239:     REG_DATA<=24'h3a1510;
    240:     REG_DATA<=24'h400402; 

    // ==========================================
    // 9. �ر� JPEG ����β���� (�ָ�����ռ��)
    // ==========================================
    241:     REG_DATA<=24'h30021c; // reset JFIFO, SFIFO, JPEG
    242:     REG_DATA<=24'h3006c3; // disable JPEG clock
    243:     REG_DATA<=24'h471300; // JPEG OFF (����Ϊ00�����򲻳�RAWͼ)
    244:     REG_DATA<=24'h440704;
    245:     REG_DATA<=24'h460b37;
    246:     REG_DATA<=24'h460c20;
    247:     REG_DATA<=24'h483716; // DVP CLK divider
    248:     REG_DATA<=24'h382402; // DVP CLK divider
    249:     REG_DATA<=24'h350300; // AEC/AGC on

    // ������ָ��ǰ�ƣ���֤״̬��һ�����ܵ���
    250:     REG_DATA<=24'h300802; 
    
    default: REG_DATA<=24'h300a00;
    endcase
end
endmodule