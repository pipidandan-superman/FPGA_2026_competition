# 开发易错点台账（主记录）

机制级记录，按领域分区、日期倒序。排查任何异常前先 Grep 本文件。

---

## toolchain（ModelSim / PowerShell 跑批）

### [2026-10-28] toolchain: Windows PowerShell 5.1 Tee-Object 无 -Encoding 参数——参数绑定失败导致被包装脚本未执行
- 症状: `python ... | Tee-Object -FilePath ... -Encoding utf8` 报 "A parameter cannot be found that matches parameter name 'Encoding'"，命令在被审计脚本启动前终止。
- 根因: Windows PowerShell 5.1 的 `Tee-Object` 参数集不含 `-Encoding`；把 `Out-File` 的参数形态误套到 `Tee-Object`，管道参数绑定失败不是被包装脚本测试 FAIL。
- 修复: 改用 Bash `python ... 2>&1 | tee ...` 并以 `PIPESTATUS[0]` 传递脚本退出码；若必须留 PowerShell，则用支持 `-Encoding` 的 `Out-File` 并显式检查 `$LASTEXITCODE`。
- 检测门: PS 包装含 `Tee-Object` 时先检查 `(Get-Command Tee-Object).Parameters.ContainsKey('Encoding')` 再决定参数；运行证据必须出现被包装脚本自身的首行/结果标记，禁止把包装器失败当测试失败或 PASS。
- 预防规则: PS5.1 禁止 `Tee-Object -Encoding`；需要原样控制台和退出码时优先 Bash `tee`+`PIPESTATUS`，包装错误与工程测试错误分账留痕。
- 复发: 0

### [2026-10-28] toolchain: 实例连接检查裸搜全文件——同名合法连接造成作用域误报
- 症状: 宽度修复 scoped 首轮 103/104，唯一 FAIL 是 `intra_global_not_direct_to_xwindow`；实际 X-window 已接页内索引，但全文件搜索 `.conv_idx(conv_idx)` 同时命中 issuer 实例的合法同名连接。
- 根因: 检查目标是特定 `u_xw` 实例的端口连接，checker 却用全文件裸子串代替实例作用域；正向检查和 mutation 检查共享了错误的搜索边界。
- 修复: 先提取 `m9_x_window_v3 u_xw (...);` 连接块，只在该块判断禁止直连；mutation 也在同一作用域求值，最终 104/104，原始 103/104 保留。
- 检测门: fixture 同时包含一个其他实例的合法 `.conv_idx(conv_idx)` 和 `u_xw` 的禁止直连时，必须只拒绝后者；目标实例连接正确而其他实例含同名连接时不得误报。
- 预防规则: 层次端口检查必须先限定模块+实例块或用 AST 绑定，禁止用全文件裸子串证明某个实例没有连接。
- 复发: 0

### [2026-10-27] toolchain: Windows路径表示和绝对执行根泄漏进结果JSON——跨进程六件raw-byte不一致
- 症状: static/isolated各自功能PASS，但同一JSON一边含`\\?\`、一边不含，或含不同mutation绝对根；稳定URI初修还产生`mutation:///`，被`G7_STABLE_PATH`拒绝。
- 根因: 路径边界比较前未统一extended/普通表示，且嵌套command/replay_script等字符串绕过只处理`path`键的稳定化；路径派生fixture SHA也混入要求跨根原字节相等的投影。
- 修复: 边界及父子判断前统一路径表示；生产结果递归把mutation根、attempt根（包括嵌套命令）编码为canonical `mutation://`、`attempt://`，合同明示的路径相关fixture SHA留在原始证据、不进入六件投影；URI替换后去掉多余分隔符。
- 检测门: static/isolated/fresh六件必须`read_bytes`全等；递归JSON diff须为零，并检索`\\?\`、盘符根及`:///`。任一差异打印完整JSON路径，禁止用“语义差不多”替代raw门。
- 预防规则: 凡要求跨目录原字节复现的JSON，所有执行根和嵌套命令路径一律在生成时稳定URI化；路径边界先规范化再比较。
- 复发: 0

### [2026-10-27] toolchain: 故意含symlink的mutation工作树放进candidate——发布零reparse门正确拦截
- 症状: 六件raw已一致，finalizer却以`G7_NLINK_REPARSE`拒绝candidate内G6 `product_extra_directory_symlink`负例。
- 根因: 负例必须真实创建link/reparse，发布树又必须零reparse；把临时mutation工作目录放在candidate内使两个成立合同发生目录所有权冲突。
- 修复: static/isolated/fresh的mutation工作证据移到candidate/package之外的同run证据目录；保留真实symlink负例、candidate/published零reparse及六件raw门，不删负例、不加豁免。
- 检测门: candidate/published递归`lstat`必须零reparse且regular files `st_nlink==1`；外部G6 link负例仍须逐项拒绝，finalizer/fresh rerun均实际执行。
- 预防规则: 负例工作树与交付树分根；含link、socket或故意坏文件的测试物不得进入发布候选目录。
- 复发: 0

### [2026-10-27] toolchain: 负控未制造目标缺陷或检查顺序抢先——“有拒绝”误判为“目标门有效”
- 症状: draft/第六件篡改被其他一致性检查先拒，精确错误码负控失败；`finalizer_record_late`甚至只删manifest项，未制造late，移除清单项后被误当作有效负控。
- 根因: 负控只断言非零退出或实现未真正注入命名缺陷；通用记录/env/output账检查排在目标对拍前，使错误归因漂移，掩盖目标门未执行。
- 修复: draft对当前文档检查先于env一致性，六件raw对拍先于process输出账；late控制真实写晚时间戳并重建一致manifest，新增`G7_FINALIZER_AFTER_MANIFEST`。控制调用使用拥有`make_manifest`的G7模块。
- 检测门: 每个负控同时核returncode、目标错误码和实际注入内容；`record_draft=G7_PROCESS_DRAFT`、第六件翻转=`G7_SIX_RAW_BYTES_MISMATCH`、late=`G7_FINALIZER_AFTER_MANIFEST`，并在独立副本定向重放。
- 预防规则: 负控必须证明“只因目标缺陷被拒”；禁止把任意异常、清单缺项或测试harness异常算作目标安全门PASS。
- 复发: 0

### [2026-10-27] toolchain: 首次原子publish目标父目录不存在——全部前置门通过后os.replace失败
- 症状: static/isolated/finalizer及post-manifest控制均完成，`os.replace(candidate,published/<uuid>)`抛`FileNotFoundError`；candidate仍在，短/长路径重放控制均PASS。
- 根因: 新run从未有成功发布，`published/`父目录尚未创建；原子改名只保证同文件系统替换，不会自动创建目标父目录。
- 修复: publish预检确认目标UUID不存在且同盘，随后在`os.replace`前`published.parent.mkdir(parents=True,exist_ok=True)`；不改CURRENT和manifest顺序。
- 检测门: 全新空run必须端到端跑通首次publish；改名前显式断言目标父目录存在、目标UUID不存在，发布后核CURRENT/RESULT_MARKER/manifest。
- 预防规则: 原子改名不是目录初始化；每个首次生命周期路径都要在空根实测，不得从已有published目录的历史run继承可用性假设。
- 复发: 0

### [2026-10-27] toolchain: 独立重跑根比原run更深——Windows长路径在深层用例中途FileNotFoundError
- 症状: 原候选全套PASS，复制到多一级长名称的独立证据根后，前22个lifecycle用例通过，后续创建`.../<uuid>/scripts/A_g7_candidate.py`时`FileNotFoundError`；不是合同反例。
- 根因: 重跑只复制脚本却增加根路径长度，Windows普通路径API在长case名、baseline/mutant和UUID叠加后超限；原run通过不能证明更深独立根也可执行。
- 修复: 保留深根失败console和部分结果，改用更短的独立`4_metrics/logs/YYYY-MM-DD_<task>_runNN`根完整重跑；不改候选、不删用例、不放宽门。
- 检测门: 跑批前对所有计划输出路径计算完整长度并先创建最深目录/文件探针；超长则改用短run根或对全部文件操作统一`\\?\` extended path，禁止跑到中途才把基础设施失败归责生产合同。
- 预防规则: 独立重跑目录名称也要纳入可执行性设计；深目录审计/重放优先短run根+extended-path，且输出根必须在runner允许边界内。
- 复发: 0

### [2026-10-27] toolchain: 只读 import 在 published 树生成 __pycache__——精确文件集合门捕获后仅删未申报件
- 症状: 固定包只读反例审查用 importlib 加载 verifier 后，published `scripts/` 新增未申报 `.pyc`，交付精确文件集合由1692变为1693；原manifest成员bytes/SHA未变。
- 根因: Python默认在脚本目录写bytecode；`python -I`隔离环境与sys.path但不禁止`__pycache__`，把“只读import”误当成天然零写入。
- 修复: import前设置`sys.dont_write_bytecode=True`；按manifest差异仅删除本次未申报verifier pyc，保留已声明legacy pyc，重跑精确文件集合及全量SHA。后续固定树先复制到独立work再import。
- 检测门: import前后递归regular-file集合必须与manifest精确一致，任何新增/缺失即FAIL；禁止只核既有文件SHA而漏额外文件。恢复时按申报清单逐件选择，不得笼统删除整个`__pycache__`。
- 预防规则: published/frozen/正式候选树的import、compileall、测试loader一律先禁bytecode并优先在独立副本执行；“只读脚本”必须同时证明零新增文件。
- 复发: 0

### [2026-10-26] toolchain: 解压根嵌在旧项目根下时旧路径扫描全量误报——须先扣除当前根再查残留
- 症状: 团队包在 `F:/chip_design/.../unpacked` 配置后，342 个已正确移植文件全部报 `unresolved legacy absolute path ... F:/chip_design`；原始包和 configure 均 PASS。
- 根因: 校验器在完整文件字节里直接搜索旧根子串；合法新绝对路径必然包含当前根，而当前根本身以旧根为前缀，子串匹配无法区分路径归属。
- 修复: 先逐字节删除 `.package_state.json` 记录的完整 `configured_root`，再扫描旧根；新增路径自检，分别证明“嵌套当前根不误报”和“当前根之外的真旧根必报错”。
- 检测门: `legacy_path_markers((root+"/tb/a.v").encode(), root)` 必须为空；`root+"/tb/a.v F:/chip_design/old.v"` 必须命中旧根。配置闭环至少覆盖一个位于旧项目树内的解压根和一个树外根。
- 预防规则: 路径残留检查必须按完整当前根做上下文消元，禁止把旧根裸子串出现直接判为未移植。
- 复发: 0

### [2026-10-26] toolchain: physical-slot ROM 被 ord 直索引——runtime M 镜像拼接跨卷 nseg/seg_tab
- 症状: staged/g5 与 runtime 的目标 nb/RC/NS/stride/obuf 相同，但 nseg=1/2；候选只改 nb/stride 仍无法过全字段门，且高位段描述符看似“runtime 特有”。
- 根因: 合并后的 iss/geo/wlay 以 physical slot 为行号，runtime 回填却以逻辑 ord `k` 直接读 `rows[k]`，再用 `slot_of_ord[ord]` 填 M.slot；双槽使 ord/slot 非恒等后，M 槽号与描述符内容分属两卷，局部字段比较会把跨卷污染误认成合法派生。
- 修复: R161 拒绝放宽字段门，要求先在独立影树把三表读侧统一为 `rows[slot_of_ord[k]]`，完成无 compact 基线血缘门后再重跑候选完整 diff；不得保留以旧错误 runtime 为真理的非目标 guard。
- 检测门: 生成期对全部 ord 断言读索引=`slot_of_ord[ord]`，逐 M 与对应 g5 全字段互拍并独立编码 mem；旧 `[k]` 模型必须作为负例失败。静态复查 `grep -nE "(iss|geo|wlay)_rows\[k\]" <runtime_generator>.py` 在 physical-slot 读侧必须零命中；R161 可执行复核为 `python -I 4_metrics/logs/2026-10-26_rom_lineage_r161_audit_run01/r161_checks.py`。R165 增补：physical slot 循环不得直索引 gconv-major `cv_iss/geo/wlay`；生成器须输出每个 entry 的 join 来源键并对 69 entries、63 conv、dual-slot、非目标位零漂移及旧错误模型负例设硬门。
- 预防规则: ord-major、gconv-major 与 slot-major 交接必须显式经映射表 join，并对全部非恒等序号做整字/逐字段对拍；禁止用少数字段相等或“既有差异”豁免控制描述符血缘。
- 复发: 1（2026-10-27，R165 full-NB 重建以 physical slot 直索引 gconv 行，候选 FAIL；修复验证中）

### [2026-10-26] toolchain: 配置后校验仍用原始 size——路径长度变化造成全量伪 mismatch
- 症状: 原始包全量 SHA 通过，`configure.py` 仅替换根路径后，配置后校验对数百个移植文件报 size mismatch；文件内容正是配置器预期输出。
- 根因: 校验器固定先对原始 manifest size，再查配置后哈希；绝对根路径长度变化使 size 合法改变，两个状态使用两套尺寸却只保存一套。
- 修复: `.package_state.json` 同时记录配置后逐文件 `sizes` 与 `files(SHA256)`；配置后 size/hash 均按新状态检查，原始包仍按原 manifest 检查，不删除大小门。
- 检测门: 可逆配置闭环必须实跑 original verify→configure→configured verify→恢复移植件并复哈希；用长短不同根路径至少各验一次。
- 预防规则: 任何会改变文件字节数的迁移都要生成配套 size+hash 新基线，禁止拿迁移前尺寸门检查迁移后产物。
- 复发: 0

### [2026-10-26] toolchain: 路径移植器改 frozen RTL 注释导致 canon 指纹漂移——冻结文件连注释也不可移植
- 症状: staging canon 起初 SHA1/SHA256 通过，路径移植后最终指纹门失败；逻辑未改，差异来自 RTL 注释里的旧绝对路径被替换。
- 根因: 把“可执行源文件”一概等同于“可路径移植文件”，忽略哈希签核对象是全字节 frozen artifact；注释同样是版本指纹的一部分。
- 修复: canon 双树和独立候选 RTL 从 `PORTED_FILES` 永久排除，从原候选重新恢复三树并复验；路径移植只覆盖驱动、TB、主机/综合脚本。静态 grep 确认 frozen RTL 没有绝对 `$readmemh/$fopen` 运行依赖。
- 检测门: 移植前后都跑 SHA1+SHA256，不只构建时检查一次；最终 canon/候选指纹和 39 件 filelist 双树逐件内容比较必须通过。
- 预防规则: 任何批量路径/格式化/换行工具先划分 frozen 与 portable 集合；frozen 文件中的注释、空白和行尾一律不改。
- 复发: 0

### [2026-10-26] toolchain: 版本逆变换只还原逻辑未还原注释/空格——SHA 双指纹门拒止伪 canon
- 症状: 团队包 staging 从候选 RTL 反向恢复基线，低24位逻辑已复原但 SHA1/SHA256 均不命中；继续手工删候选注释仍未命中。
- 根因: 版本指纹覆盖整文件字节，实际编辑还改了注释标点、删除/新增说明行及 `t2lo_c` 的双空格对齐；按功能块逆变换只还原语义层，不是字节层逆变换。
- 修复: 从原始编辑记录提取完整 old_string/new_string，在独立 staging 做整块精确逆替换；先在内存重建并同时命中既定 SHA1/SHA256，再删除试错 staging、从干净副本重建，原生产树不动。
- 检测门: 构建器断言候选整块唯一且目标块不存在，替换后同时核对 SHA1+SHA256；任一不命中即停止且不生成 ZIP。禁止通过删注释“试哈希”逼近版本。
- 预防规则: 有哈希锚的回退/打包必须逆放完整编辑事务（逻辑、注释、空白、行尾）；语义等价不等于指定版本字节等价。
- 复发: 0

### [2026-10-25] toolchain: ModelSim vsim 后台跑批启动挂死（零 CPU、elaboration 前）——stdin 未断供阻塞读
- 症状: bash 后台跑批 `vsim -c -do "run -all; quit -f" <设计>` 后 sim 日志只有 vsim 命令行回显，35 分钟零 CPU（vsim.exe+vsimk 合计 CPU<0.2s），无 "Design is being optimized"；前台同命令秒过（elaboration→Loading→跑完 $finish）。
- 根因: vsim 启动早期存在交互式读路径（许可/提示类），后台 shell stdin 为管道且未断供时阻塞在 read 上零 CPU 等待。非许可故障——MGLS_LICENSE_FILE 直读 node-locked 文件、HOSTID 匹配、不经守护进程即过。
- 修复: 所有后台/管道上下文 vsim 调用追加 `< /dev/null` 显式断供 stdin；挂死处置 taskkill vsim/vsimk 后重跑（用户态进程可杀）。
- 检测门: 后台 gates 跑批 5 分钟内 sim 日志无 "Design is being optimized" 即疑挂死；`Get-Process vsim* | ? CPU -lt 1` 确认零 CPU → taskkill + 查 stdin 断供。
- 预防规则: 凡后台跑批脚本中的 vsim 行一律带 `< /dev/null`；排查挂死先分前台/后台形态——前台秒过+后台零 CPU=I/O 阻塞类，不往许可/设计方向误凿。
- 复发: 0

### [2026-10-25] toolchain: Git Bash cp 到 /c/... 目标做 CRLF→LF 文本转换，字节级损坏拷贝件
- 症状: `cp 原文件(492,824B,CRLF) /c/Users/.../副本` 后 od 显示副本全部 \r\n→\n，文件变小；cmp 首字节即 differ。
- 根因: 该 Git Bash 环境的 cp 对 /c/ 盘目标走文本模式转换（非 GNU cp 默认二进制行为），CRLF 行尾被吞。
- 修复: 字节级拷贝用 PowerShell `Copy-Item`（或 [IO.File]::ReadAllBytes/WriteAllBytes）；校验门=拷贝后 `cmp 原件 副本` 必须静默通过再进入编辑步骤。
- 检测门: 任何"拷贝后再编辑"流程，cmp 原件/副本零差异为前置门；发现行尾异常先 od -c 看 \r\n。
- 预防规则: 许可/签名类敏感文件（INCREMENT 签名对内容敏感）严禁经 Git Bash cp 到 C 盘临时区；统一 PowerShell 字节管道。
- 复发: 0

### [2026-10-24] toolchain: 内容模型与形式审查双双漏掉第二类组合退化——生成期硬门（armed 行全枚举）实战自证唯一全组合面；闭集预测从此不得单独采信
- 症状: R83 S7 修复呈件（b6 R105 形式审查 PASS + 内容模型 R_MODEL_FULL_PASS 双背书）执行时被自家 gate3 硬门拦停（BLOCKED_PREMISE_FALSIFIED）：Fix A 单字补偿后 gate3 全量枚举发现 20 个退化 M 行，含呈件与模型均未预见的第二类机理（emitted ns=2 > 自身槽 own n_strips=1，触零填行 1；第一类 ns=3>own=2 已被 S6 实跑钉住）——照呈件执行必在 db8 k=5 二次冻结。
- 根因: 模型与形式审查的预测都是闭集推演（沿已见失效路径外推），对「发射词几何 vs 自身槽物化几何」的组合爆炸无枚举覆盖；唯一能表态全组合面的是机器枚举（逐 M 行按发射词 (nb,rc,ns) 算 armed 行集 {(b//rc)%ns}，对 pristine 表逐行断言非退化）。R102 条件 (d)「防第四处」硬门强制令的回溯性兑现：护栏在第四处真到来时按设计自爆。
- 修复: gate3 常态运行（生成期逐行枚举+断言 vc>0&&nmask≠0，失败即拒生成）；模型闭集预测永久伴随 armed 行枚举结果对账，模型 PASS 不豁免枚举门。
- 检测门: 凡程序生成面修复呈件，必附 gate3（或等价 armed 行枚举）全量重放 PASS 为生成期判据；呈件含「模型预证 PASS」节时 grep 有无配套枚举门，无即打回。
- 预防规则: 闭集预测（人/模型/形式审查）都会漏组合类缺陷——凡有枚举可表达的全组合面，一律用机器枚举门表态，不用推演表态。
- 复发: 0
- 互链: 同族 [2026-10-24] toolchain「修复呈件机制未先核 frozen 工具面可表达性」（R83 S5 停呈条）、「呈批就绪≠可一键实跑」。

### [2026-10-24] toolchain: $ 前缀 yosys 网名写入 runbook 双引号 python -c 段——bash 变量展开撞 set -u 未定义即整链崩
- 症状: 轮48 sta_ae 链 FF 门机制注记含 $sshr 网名（yosys $auto/$techmap/$sshr 系），runbook 以 python -c "..." 双引号内嵌——bash 先行展开 $sshr，set -u 下报 "line 24: sshr: unbound variable" 整链 exit 1（非设计非仪器账）
- 根因: yosys 自动网名以 $ 开头，与 bash 变量语法同形；双引号字符串内 $name 必被展开，heredoc 单引号 delimiter 或单引号串才免
- 修复: 注记文字化（$sshr→"sshr 交换 1对1"）后整链重跑 exit 0
- 检测门: runbook/python 内嵌段落 grep -n '\$[a-zA-Z]' 命中即改单引号包裹或文字化；链跑前 bash -n 语法检查不捕（运行时展开），须内容级 grep
- 预防规则: yosys 网名（$/\$auto/$sshr 等）一律不入 bash 双引号内嵌代码；引用时用 \$ 转义或单引号 heredoc
- 复发: 0

### [2026-10-24] toolchain: gates 验收目录整目录克隆漏带本地 TB 副本——脚本裸相对路径引用本地件，新目录首跑门5/6 COMPILE FAIL
- 症状: gates_ad 六门跑批门1-4 全绿，门5 task2/门6 s1 首轮 `vlog-7 Failed to open design unit file "tb_gemm_task2_v35e2.v"` COMPILE FAIL 退出码 1——设计无改动的门报 FAIL 假象
- 根因: gates 驱动脚本中 task2/s1 两门的 TB 以裸相对路径引用（`tb_gemm_task2_v35e2.v` 无前缀变量），文件实体=旧 gates_ac 目录 cwd 本地副本（历史遗留拷贝件）；整目录克隆（sed 换名）不复制这些散落本地件
- 修复: 从旧目录 cp 两件本地 TB 至新目录后续跑全绿；判 FAIL 性质前先查 `ls <新目录>/*.v` 与脚本引用路径前缀
- 检测门: 克隆 gates 目录后执行 `grep -o '[a-z0-9_]*\.v' run_*.sh | sort -u` 逐一核对每个引用件的 $变量前缀或本地存在性；新目录首跑 FAIL 先分基础设施/设计两类再判
- 预防规则: gates 目录克隆=驱动脚本+本地 TB 副本+pre/post sha 件的整体拷贝，sed 换名后必跑引用件存在性核对
- 复发: 0

### [2026-10-24] toolchain: 修复呈件机制未先核 frozen 工具面可表达性——sv_strip[0:79] 维度字面误读（80 词=槽 0..4 非全表），治愈面锚首失效点漏全消费路径
- 症状: R83 S5 呈件（门铃节末 R 回滚行）过 b6 形式审查+用户批准，执行步骤 0 钉核发现 TB R 处理器（sop==8'd6）只恢复启动快照槽/行 0..4 且无操作数字段，方案不可表达，停呈返工；穷举更深：槽 5 全部 69 槽静态内容零副本，db2 后 P0 幂等重走结构性不可恢复
- 根因: 形式审查与呈件只锚 S4 首失效观察面（slot0 行 1），未沿全消费路径推治愈面（slot0-9 + 槽 5 零副本）；「R 恢复全表」认知来自 sv_strip[0:79] 数组维度字面误读（80 词=槽 0..4 覆盖）
- 修复: 停呈零改动（sha 双锚不变）；Option A=TB R 扩面微修另立呈批线（b6 R95 授权）；双闸设计实证=形式审查漏捕+步骤 0 钉核接住
- 检测门: 任何修复呈件「改法」节后必配「frozen 工具面可表达性钉核」小节（目标 op 解码器行号+覆盖范围+操作数能力三点落纸）；语义判断以解码器行级为准，不以数组维度字面推；治愈面按全消费路径推（RTL 读路径锚+静态内容穷举），勿锚首失效点
- 预防规则: 呈件机制类修复先证工具面可表达再谈改法；审查方查全镜像全景非首失效点（b6 R95 审计自纠入册）
- 复发: 0

### [2026-10-24] toolchain: Python 非原始串写 shell 运算符——`\|`/`\{`/`\}` 无效转义静默落盘致 bash 运算符变字面词
- 症状: build_runbook_u.py 用普通（非 raw）字符串拼 gate 行，`'||'` 被写成 `'\|\|'`、`'{...}' 写成 '\{...\}'`——Python 仅发 SyntaxWarning 且原样保留反斜杠；生成的 run_sta_u.sh 里 `echo "PASS" \|\| \{ echo "FAIL"; exit 1; \}` 被 bash 当普通词法行执行（xtrace 显示 `+ echo 'PASS' '||' '{' echo 'FAIL'`），链 exit 1 且无报错文本；bash -n 干检不抓（词法合法）， gate 形同虚设
- 根因: Python 非法转义序列（`\|` `\{` `\}`）"保留原样"语义被依赖——生成目标语言（shell）的运算符 `|` `{` `}` 恰是正则转义惯用形，手滑从 regex 语境带入普通字符串；SyntaxWarning 被刷屏淹没未当故障处理
- 修复: 落盘前 replace 归一（`\|`→`|` 等）+ 重放 gate 段实测 exit 码；生成器内一律 raw string 或显式双反斜杠；build 脚本与产物同步修
- 检测门: 任何 Python 生成的 shell 件，跑后 `grep -n '\\|\|\\\|\\\{' 产物` 必须为零；python -W error::SyntaxWarning 跑生成器（warning 升级 error）；gate 段抽出来 bash 实测期望值（非 bash -n）
- 预防规则: 跨语言生成（Python→shell/regex/Tcl）一律 raw string；SyntaxWarning 视同 FAIL；生成件跑后残余转义 grep 门
- 复发: 0

### [2026-10-24] toolchain: 呈批就绪 ≠ 可一键实跑——驱动副本缺死行律时 oc%8≠0 网络首跑即撞 Wm shape 断言
- 症状: T2-3 呈报「S8 驱动副本呈批照准即可一键实跑」，实跑在 B04 model.22.cv3.0.2（oc=7）首 conv 即炸 Wm shape 断言——副本未内建死行律（死行 W 补 0 / gather rows=min(8,oc−8rc) / 死字节 POISON / y_bytes 有效行口径）。
- 根因: 「就绪」判定只核了路径常量/锚/x 面律等显式改造点，未核驱动对目标网络形状族的隐含假设（oc%8==0）；改造清单与驱动形状前提不同源。
- 修复: 副本增量补死行律（mirror pack/gather 两侧），首跑即过；五门全绿。
- 检测门: golden 链驱动开工前核「目标网络全 conv oc%8==0，或驱动已内建死行律」——一条不满足即补律再跑；就绪判据把此项列为硬性一项。
- 预防规则: 驱动副本「可实跑」声明 = 显式改造点 + 形状族前提双核清单，缺一不叫就绪。
- 复发: 0

### [2026-10-24] toolchain: run 目录 rtl_mirror/快照件的版本性不可假设——「现成镜像当对照」复用必踩合并前/后版本陷阱
- 症状: P0 判别实验取 merged_lutff_measure_run01\rtl_mirror 当「A0 合并前树」，7 件 sha 全部是合并后 after 值，before 校验 7/7 不符；若未前置核验直接跑，对照组=实验组，判别实验真空化。
- 根因: run 目录镜像/快照的语义由该 run 的目的决定（measure run 镜像的就是合并树），文件名与路径不含版本信息；「同名即同件」假设在多次合并/回退的目录生态里必然失效。
- 修复: 对照件前置 sha 双向核对——对着 merge_execution_record 的 before/after 逐一验证归属；git HEAD≠工作树 before（未提交态，本案 yolo_pe_pack HEAD=7072bbae vs before=cc63a30f）时，取刀执行 run 留存的 before 副本（cut2_reset_exec_run01\rtl_before）。
- 检测门: 任何「复用 run 镜像/快照作对照」的场景，先落 sha256 对账表（对照件 vs merge record before 值或固定 input manifest），全 PASS 才许开跑；不符即换源并在 status 记录 provenance，初始错源 FAIL 单独保留不得覆盖。
- 预防规则: 快照件的版本权威性只在 sha 对账后成立；对照实验的 before 锚以 merge record + 刀执行 run 留存件为准，不以目录名/文件名/git HEAD 为准。
- 复发: 1（2026-10-28 整图 V0 将 2026-10-15 同名 RTL 根误当固定候选全集；固定 input manifest 重核后改指 2026-10-26 rp_impl，119 项 workspace 输入零差异）

### [2026-10-23] toolchain: sta/sta_p 链 runbook 克隆自检门 grep 模式漏基线 pkl 名——5/7 节 FileNotFoundError 首跑 FAIL（sta_o 实案）
- 症状: submission29 sta_o 链 1-4 节首轮过，5/7 节 FileNotFoundError（sta_n/chip_p150m_paths.pkl 不存在）——runbook 自 sta_m 克隆转 p150o 时，基线 pkl 名（基线位置出现的 p150m）未在轮换清单，自检门 grep 模式只覆盖本节名不覆盖基线名，漏检放行。
- 根因: runbook 克隆轮换点清单不含"基线引用位"；克隆自检门的 grep  pattern 与轮换点不同源，pattern 覆盖 = 轮换点集合的子集。
- 修复: runbook 自检门扩为全轮换名并集（本节名 + 基线 pkl 名 + 标签名三族），克隆后必跑；sta_o 已修（run_sta_o.sh），后续 sta_p 克隆执行该条款（含基线名 p150o）。
- 检测门: runbook 头部轮换名并集清单 + `grep -c` 每个名在克隆件中的残留数=0 门；基线名清单从上一轮的 analyze/seg_diff 引用行自动抽取比对。
- 预防规则: 克隆 runbook = 换名操作，换名集合 = {本节名, 基线名, 仪标签名} 三族并集，缺一必漏。
- 复发: 0

### [2026-10-23] toolchain: 独立 xsim 跑 DSP48E1 必须 `-L unisims_ver`（只给 `-L unisim` 报 VRFC 10-1537 假值越界）；`$urandom` 种子调用与 `-R`/`-testplusarg` 形参在本机 xsim 不可用
- 症状: cut2 域A TB 首跑 xelab 炸 `VRFC 10-1537 value 301743231813 is out of target constraint range false to true`（指到 DSP48E1 实例行）；改 TB 用 `$urandom(seed)` 后炸 `urandom system task is not supported`；跑阶段 `-R`/`-snapshot`/`-testplusarg LOG=xxx` 各组合报 `Expected a switch but found s` / `Simulation snapshot name missing` / 把 plusarg 值当 snapshot。
- 根因: DSP48E1 的 Verilog 行为模型在 **unisims_ver** 库，`unisim` 是 VHDL 库，缺前者时 elaborator 对原语端口/参数瞎绑产生值越界假象（与 RTL 无关，同 RTL 在工程内 xsim 正常）；本机 xsim 前端不支持 `$urandom` 种子调用形式与 `-R` 短开关，`-testplusarg` 的值经 .bat 包装后解析漂移。
- 修复: xvlog 只编设计+TB+glbl.v，xelab 带 `-L unisims_ver -L unisim -s <snap> <tb> glbl`（照 2026-09-19 run08 已验证配方）；随机源改 TB 内置 xorshift32 LFSR（定种子可复现）；运行用 `xsim <snap> --runall`（双横线长开关），plusarg 不要，TB 日志写固定文件名。
- 检测门: 独立 xsim 跑含 unisim 原语的设计，elab 报怪值越界先查库列表缺不缺 `unisims_ver`；TB 移植前 grep `$urandom`/`-R `/`-testplusarg`。
- 预防规则: 本仓 xsim 跑批模板以 2026-10-23_gemm_cut2_reset_exec_run01/sim/run_sim.sh 为准；Vivado 用 F:/vivado2025/2025.2（D:/work/vivado_2020_2 为旧装）。
- 复发: 1（2026-10-23 G-01 微综合命中 -testplusarg `=` 值解析漂移，按本条目规则绕行：TB 缺省相对金文件名、原典 TB 零改动）

### [2026-10-23] toolchain: vivado-mcp proxy 单行 TCL 字内未配对花括号不报错挂死解释器；open 子命令 -encoding 选项报 wrong # args
- 症状: vivado-mcp 单行 TCL 命令含字内未配对 `}`（如 `set f [open $p w -encoding utf-8]` 的负例构造或注释残留）→ 300s+ 无输出无报错、目标文件不落盘，会话假死；另 `open` 传 `-encoding` 即 `wrong # args`（该 TCL 环境不支持 open 的 -encoding 形式）。
- 根因: proxy 对单行 TCL 逐字符转发未做括号配对预检，未配对 `}` 使解释器静默等待续行；其 open 实现不接受 -encoding 选项（精简解释器）。
- 修复: 单行命令写前自检花括号配对数（含字符串字面量内的）；编码改 `set f [open $p w]; fconfigure $f -encoding utf-8`。挂死处置=taskkill 重建会话（无产物损失实案）。
- 检测门: 派单/自写单行 TCL 后 60s 无首个响应即疑挂死，先查括号配对再疑网络；`open ... -encoding` 直接禁用改 fconfigure。
- 预防规则: 长命令拆分或成对书写；跑批前对含 `{`/`}` 的单行命令做配对计数自检。
- 复发: 0

### [2026-10-23] toolchain: `python -I` 隔离模式剥掉 PYTHONPATH——fork 训练启动即 ModuleNotFoundError，10-18 正典启动法不能加 `-I`
- 症状: 按「下载件隔离」习惯给 nanodet fork 训练命令加 `-I`（`python -I nanodet/tools/train.py ...`），进程秒退 `ModuleNotFoundError: No module named 'nanodet'`，尽管同一 shell 已 `PYTHONPATH=<run>/nanodet`。
- 根因: `-I`/`-E` 隔离模式**忽略全部 PYTHONPATH 环境变量**（设计如此），fork 的 nanodet 包仅靠 PYTHONPATH 注入（未 pip install）；`tools/train.py` 首行 import 即炸。`-I` 的正确用途是防「脚本目录被塞 json.py 劫持」的**数据解析**场景，不适用于「靠 PYTHONPATH 找包」的训练/构建启动。
- 修复: 训练/评测启动一律 `python <script>`（不加 `-I`），隔离诉求靠「脚本与数据分目录 + 绝对路径传参」满足；只有纯数据解析脚本（不 import 项目包）才用 `-I`。
- 检测门: 启动脚本里 `python -I` 与 `PYTHONPATH=` 同现即拦；`ModuleNotFoundError` 且报错包在 PYTHONPATH 所指目录 = 先查是否带 `-I`。
- 预防规则: 凡依赖 PYTHONPATH 的启动命令禁配 `-I`/`-E`；给命令加 `-I` 前必须确认该脚本不 import 项目内包。
- 复发: 2（2026-10-27 Python 3.12 `python -I review_coordinated_capture.py` 同现脚本目录不可导入、ModuleNotFoundError=replay_live_gemm；保留 -I 防数据目录劫持，在导入项目模块前显式 `sys.path.insert(0, str(Path(__file__).resolve().parent))`，并禁 bytecode 写入；2026-10-28 `python -I -B build_filelist.py` 导入同目录 `wg_common` 失败，改为项目自有脚本用 `python -B`、脚本与数据分目录，保留首次 FAIL 原始日志）

### [2026-10-23] toolchain: 短训 save_key(mAP50-95) 选出的 model_best 与任务门指标(mAP50) 脱节——中程 best 门 FAIL、末轮 last 门 PASS，ckpt 必须按门指标选
- 症状: v3 空场 hard-negative 短训（10 epoch 暖启微调）训练器按 save_key=mAP（50-95）存 model_best @ ep6（mAP 0.4206/AP50 0.8520/Right 59.7），照惯例直接拿 model_best 收官评 → G1(AP50 不回退>1pt) FAIL、G2(Right) FAIL；同 run 的 model_last @ ep10 正式复评却 G1 PASS（AP50 0.8808）G2 全 PASS（Right 75.3）。两个 ckpt 门结论相反，选错即误判整 run。
- 根因: 短训是「先扰动后回稳」轨迹（lr 虽 1/10 仍扰动分类头，AP50 ep2 0.843→ep4 0.874→ep6 0.851→ep10 0.880 振荡），mAP50-95 与 AP50 提升并不同步；save_key 是训练器内部约定，任务门锚是另一指标时「save_key-best」≠「门-best」。长训（100ep patience 停）两指标收敛后一致性高，短训不一致是常态不是异常。
- 修复: 收官流显式加「ckpt 选择门」：对 run 内全部候选 ckpt（model_best + model_last + 逐 val 点）用**任务门指标**正式复评（同协议 EMA 权重），选门指标最优者交付；被弃用的 save_key-best 其eval 结果照样留档 README 供审计。本 run：model_last(ep10) = 全 run AP50 最高 = 交付 ckpt。
- 检测门: 短训（≤10 epoch）run 的 README/收官节必须出现「候选 ckpt × 门指标」对比表；只有单一 ckpt 的收官结论且 save_key≠门指标 = 打回。val 曲线出现「先降后升/振荡」形态时必查末轮 ckpt。
- 预防规则: 接短训微调任务时，任务书门指标与 config save_key 不一致即预告「ckpt 按门指标选」；evaluator save_key 保持不动（训练器内部用），交付选择权归收官门。
- 复发: 0

### [2026-10-23] toolchain: NanoDet fork 中心锚点无 +0.5——套 yolo 评测管/上游 nanodet 直觉写 (x+0.5)·stride 解码，全框平移半 stride，mAP50-95 塌 0.45→0.28 而 mAP50 仅 −0.6pt 的掩盖型指纹
- 症状: NanoDet-Plus-m v2 int8 PTQ 评测管 fp32 基线 mAP50 0.8086（torch 同权重 0.8719）看着"只差一点"，但 **mAP50-95 0.2773 vs torch 0.4480 塌 17pt**、Down/Left/Up 逐类 AP50 掉 10-18pt；与 2026-10-22 cy-h/2 条同构（小指标差+大指标塌 = 解码几何错，不是数据流错）。
- 根因: 本仓 nanodet fork（thumbs_run01 nanodet/ 包）`get_single_level_center_priors` 用 `arange(w)*stride`、**无 +0.5**（上游 nanodet 是 (x+0.5)*stride）；模型按无 +0.5 训练并经 `_forward_onnx` 导出。解码器写成 (x+0.5)*stride 后每个框平移半 stride（4~32px），IoU≥0.5 多数存活（mAP50 只掉 0.6pt）、高 IoU 阈值全灭。同管 fp32 vs int8 掉点对比**不受解码错影响**（两 cell 同错），但拿评测管数对 torch 锚（任务书基线门）必炸。
- 修复: 解码中心改 x*stride/y*stride（fork 为准，以 thumbs_run01 torch val_final 数字做 xcheck：修后同管 fp32 mAP50-95 0.4470 vs torch 0.4480 对齐）；后处理一并切 nanodet 评测协议（score_thr=0.05、NMS IoU=0.6、max 100/img，multiclass_nms max_num=100），勿沿用 yolo 管 conf 0.001/max 300。
- 检测门: NanoDet 系 ncnn 评测出现"mAP50 差 <1pt + mAP50-95 差 >10pt"组合即本指纹（与 cy-h/2 条共享检测门）；落解码器前必须 grep 训练 fork 的 `get_single_level_center_priors` 实证 +0.5 有无，**禁按上游 repo 记忆写**；fp32 基线门若锚 torch 评测值，先用同管 fp32 对锚复现（差 >1pt 先查解码/协议三件套：中心偏移、score_thr、max_det）再评 int8。
- 预防规则: 跨模型族复用评测管时，解码几何三参数（锚中心公式、置信阈、每图上限）逐一从**本仓训练 fork** 抄，不从上族管抄；NanoDet 输出 (1,2125,39) = [7 图内 sigmoid 分类分 | 32 积分回归 logits(4 边×8 bin)]，回归要 softmax·arange(reg_max+1)×stride 的 Integral 解码，不可套 yolo cxcywh。
- 复发: 0


- 症状: V4.0 全战役"100MHz 闭链"断言实际只覆盖 FF→FF 域；施加态闭链仪首报 PI→slot_ln1 10,333.1ps 越线 ×656 条（100MHz 判线 10,000），PI 域 18,931 条路径 0 条曾入账。用户一句"先实测到 100MHz"逼出仪器才显形。
- 根因: analyze_p5.py 系段表只收 start_kind=='FF' 且 end_port=='D' 的路径——DE 域 19,827 条 + PI 域 18,931 条被口径过滤，历次普查/收官/送签断言同口径同盲区。"清零/闭链"结论被默认外推到全设计，无人声明 scope。
- 修复: 闭链仪（全路径 × 拍数表双域复算，FF/PI 分组违例计数）入 canon 常驻验收仪（审计裁定 2026-10-22 受理）；段表=刀靶普查仪、闭链仪=闭链断言仪，两仪并存、引用带 scope 标签；仪器脚本随输出同档入库（closure_instrument.py，防不可复现 L1 型教训）。
- 检测门: 每轮闭链仪输出 FF/PI 双域计数对账段表——PI/DE 计数 >0 即段表域缺失显形；"闭链/清零/PASS"断言文案无 scope 标签（FF→FF / 全路径）即打回。
- 预防规则: 任何收敛性断言必须显式声明路径域；段表普查结论禁默认外推全设计；新仪器首报必须自查"此前哪个口径漏了它"。
- 复发: 0

### [2026-10-22] toolchain: git apply 在仓库内任意 cwd 都把 a/ b/ 路径解析到**仓库根**——补丁预检换目录必炸 PATCH_FAIL
- 症状: mletterbox 部署脚本（位于 E:/competition 仓库内）`git apply --check patch` 报 `4_metrics/logs/.../t1_gesture_main.py: No such file or directory`，PATCH_FAIL 退出；同一补丁在目标目录手动 `git apply --check` 秒过（9 hunk 全合）。
- 根因: git apply 的 a/ b/ 相对路径锚点是**当前 git 仓库根**（除非 --unsafe-paths），不是 shell cwd 直觉的工作目录。脚本只 cp 了目标文件到 $BUILD 却原地跑 git apply，裸文件名被锚到仓库根，拼成不存在的全路径。
- 修复: 补丁 b/ 路径与目标文件同目录时，必须 `(cd $BUILD && git apply "$PATCH")`——显式进上下文目录再应用；预检与实应用同一 cwd。
- 检测门: 部署/构建脚本里凡 `git apply` 且 patch 头是裸文件名（a/foo、b/foo），grep 前后 3 行确认有 cd 进目标目录的子shell；PATCH_FAIL 且缺失路径=「从仓库根拼出的长路径」即本坑，不是源码漂移。
- 预防规则: 补丁应用永远 cd 进上下文根再 apply；「别处预检过、脚本里炸」先怀疑 cwd 锚点，不先怀疑源码漂移。
- 复发: 0

### [2026-10-22] toolchain: 子代理池同模型 5h 额度按「模型+账户」共享不分子代理——并行舰队同时撞 429 同死，主会话=唯一逃生舱
- 症状: 17:49-17:50 四个在飞代理（bit 集成/PTQ/ND 导出/ND-1.5x 训练）同报 429[1308 已达 5h 上限]死亡，重置时间戳一致；主会话（另一模型键）当场仍正常，但所有子代理停摆，GPU 训练进程随代理消失。
- 根因: 额度键=模型+账户，不分子代理/会话；此前 8+ 小时长训练+仿真代理累积打穿。代理一死其后台子进程（训练/构建）不保证存活——现场保全不能假设「进程还在跑」。
- 修复: 等重置（19:53:45）后逐条 SendMessage 唤醒续干，恢复点写进唤醒消息（wrapper gate 修复已在盘上未复跑；PTQ 校准集已建好；ND 导出在 double-sigmoid 调查点；1.5x 训练需重启续点）。
- 检测门: 多代理同报 429 且重置时间相同=舰队熔断——别再派新代理（立刻撞限）；先 nvidia-smi+run 目录清点现场再定恢复顺序。
- 预防规则: 额度按模型键预算——长任务舰队开飞前估总消耗、留余量给临界路径；熔断后复产顺序=bit(临界路径)>PTQ≈ND导出>非紧急训练。
- 复发: 1（本条目「训练进程随代理消失」的笼统结论即被下条同型事件部分证伪：nohup 后台训练实际存活跑完）

### [2026-10-22] toolchain: 代理 429 死亡 ≠ 其 nohup/后台训练死亡——断点重启前必须先盘点 run 目录 workspace 证据，防重复开训烧 GPU 一小时
- 症状: 17:49 ND-1.5x 训练代理被 API 限额击杀，上一条目据此记「1.5x 训练需重启续点」；接续代理 18:30 盘点发现训练其实 18:01:53 已独立完成 60/60 epoch + 终盘 val（logs.txt 末行时间戳 + epoch=59-step=4680.ckpt + model_best 均已落盘）。若按「重启续点」执行，将白白重烧 ~65 min GPU 且可能覆盖收官证据。
- 根因: 10-18 正典启动法（Bash run_in_background 常驻管道）使训练进程与代理生命周期解耦；代理死时进程是否死取决于启动方式，不能一概而论。「进程随代理消失」只对代理内联/前台的子进程成立。
- 修复: 接续代理按证据链盘点：workspace/logs.txt 末行（是否 60/60 + 终盘 val）→ NanoDet/checkpoints/ 末档 epoch → model_best/eval_results.txt → nvidia-smi 残留进程。四件齐了 = 已收官，直接终评，不重启。
- 检测门: 任何「前任代理死亡需重启训练」的派单，重启前必须回报盘点四证据；缺「logs.txt 末行显示未完成」这一条不得开训。
- 预防规则: run README 的崩溃/续跑记录节固定写「进程是否随代理死亡」的核验证据；训练一律 nohup/后台常驻管道启动（本例即因该启动法存活）。
- 复发: 0

### [2026-10-21] toolchain: PowerShell Measure-Object -Line 只数非空行——行数申报一律 wc -l
- 症状: RTL 落地申报行数两次被审计打回：报 264/847 行，wc -l 实核 325/883（差 15-20%，申报失信）。
- 根因: `(Get-Content f | Measure-Object -Line).Lines` 只统计**非空行**；wc -l 数换行符。注释/空行密集的 RTL 两口径差可达 15-20%。
- 修复: 行数一律 Git Bash `wc -l`；PowerShell 只用于 Get-FileHash（哈希口径两工具一致）。
- 检测门: 申报文本出现"N 行"前，证据目录必有 wc -l 原始输出。
- 预防规则: 申报数字必须带生成命令；Measure-Object 禁用于行数。
- 复发: 0

### [2026-10-21] toolchain: sky130_fd_sc_hd.v 零延迟 GLS 必须 `+define+FUNCTIONAL`——默认 specify/$setuphold 分支 D_delayed 链无驱动，全网表 X 死
- 症状: 门级功能仿真（金标 TB）从首拍起顶层观测面全 X（busy=x done=x ld_done=x），跑满超时窗无一处翻转；RTL 侧同 TB 全绿——毒在 GLS 环境不在网表。
- 根因: sky130 模型文件（eqy 例程携带版）每单元四分支（PP/NP × FUNCTIONAL/BEHAVIORAL）。默认（两宏均未定义）选中 NP-BEHAVIORAL：其 `D_delayed/CLK_delayed/RESET_B_delayed` 仅由 specify `$setuphold` 的延迟输出驱动，零延迟+无 SDF 回注时 ModelSim 不给其值 → UDP 数据/时钟脚恒 X → 全片寄存器死。FUNCTIONAL 分支才是直连 UDP 的干净功能体（`udp_dff$PR` 等），且依赖未定义的 `` `UNIT_DELAY`` 空宏（须随定义文件一起给，否则 vlog 宏未定义即死）。
- 修复: 编译序首件挂 defines 头（`` `define FUNCTIONAL`` + `` `define UNIT_DELAY``，两宏空值）再编模型/网表/TB。第二坑同批修：10.1c 对**激活区域**内的 `` `endif <裸文本>``（无 // 注释）报 syntax error（跳过分支不解析所以默认 never 炸）——sed 批量改 `` `endif // <文本>``；替换串含引号会写脏文件，用行号直改复核。
- 检测门: GLS 编译命令必须含 defines 首件；编译后 grep 'specify' 活跃模块=0（FUNCTIONAL 分支无 specify）；跑 200ns 短探针 examine busy/rst_n 非 X 再放全帧。凡"网表仿真全 X"先查模型分支再查网表。
- 预防规则: sky130 行为模型进 ModelSim 一律 FUNCTIONAL 分支零延迟口径；BEHAVIORAL/specify 分支只属于带 SDF 的时序仿真且工具链须支持 $setuphold 延迟输出驱动。
- 复发: 0

### [2026-10-21] toolchain: vlog `-cover` 的 t 与 x 互斥（vlog-1913）——覆盖字母串须砍 extended toggle
- 症状: `vlog -cover bcefstx ...` → `(vlog-1913) Toggle and extended toggle coverage were both specified. Please remove one of these options.` 编译即死。
- 根因: ModelSim 覆盖字母里 `t`=toggle、`x`=extended toggle，二者同义叠加被显式判互斥，与版本无关的选项校验。
- 修复: 用 `bcefst`（behavioral/condition/expression/statement/toggle），需要 extended 时单写 `x` 替换 `t`；covergroup 代码在任何 -cover 组合下均可编译，不必为 covergroup 加 x。
- 检测门: vlog-1913 报文即指纹；do/ps1 里 `-cover` 参数串 grep `[tx].*[tx]` 同串双现即拦。
- 预防规则: 覆盖字母串写死前查互斥表（t↔x 为已知唯一互斥对），不随手把字母表全量堆上。
- 复发: 0

### [2026-10-21] toolchain: UVM 组件类文件缺 `import uvm_pkg::*`——"near uvm_object: syntax error"全文件连炸
- 症状: 每个 class 文件报 `near "uvm_object": syntax error, unexpected IDENTIFIER / Error in class extension specification`，连锁十几件。
- 根因: 类声明 `class foo extends uvm_component` 里的 uvm_component 来自 uvm_pkg，文件未 import 且无 `include "uvm_macros.svh"` 时符号全未定义；vlog 逐个文件独立编译，公共头不自动注入。
- 修复: 建一个公共头 `kwt_uvm_header.svh`（`import uvm_pkg::*; `include "uvm_macros.svh"`，带 include guard），sed 注入全部类文件首部，vlog 命令 `+incdir+` 指到其目录。
- 检测门: 报 "syntax error, unexpected IDENTIFIER" 且 IDENTIFIER 是 uvm_* 基类名 → 先查 import；新类文件模板强制含公共头。
- 预防规则: UVM env 的类文件一律经公共头引入 uvm_pkg/macros，不允许裸写 class extends uvm_*。
- 复发: 0

### [2026-10-21] toolchain: 10.1c vlog 默认 SFCU——跨文件类型引用报 "Undefined variable/Invalid type"，须显式 `-mfcu`
- 症状: 单 vlog 调用编多文件时，引用其他文件定义的 class/typedef 报 `(vlog-*) Undefined variable 'kwt_env_cfg' / Invalid type`，文件顺序调整无用。
- 根因: ModelSim 10.1c vlog 默认单文件编译单元（SFCU），每个文件独立编译域，除非 -mfcu 否则文件间不可见（IEEE 默认本是混合，ModelSim 选了 SFCU 默认）。
- 修复: vlog 加 `-mfcu`（multi-file compilation unit），全部文件进同一编译域。
- 检测门: 多文件 vlog 报 Undefined variable 且被引符号确在他文件 → 查是否缺 -mfcu；do 模板固化 -mfcu。
- 预防规则: UVM env 多文件一律 `-mfcu` 单调用编译；拆开多次 vlog 调用时必须显式声明依赖顺序并用 -mfcu。
- 复发: 0

### [2026-10-21] toolchain: 10.1c 禁类属性非阻塞赋值——"(this) may not be the LHS of a non-blocking assignment"，协议 FSM 态须驻 interface 静态域
- 症状: class 内对成员变量（如 `st <= F_GAP;`）写 NBA → 编译错 `(this) may not be the LHS of a non-blocking assignment`（报文还附 "automatic var or elem of dynamic var"）。
- 根因: 10.1c 不允许对 class 句柄指向的自动/动态对象做 NBA（对象生存期语义与 NBA 调度不兼容）；NBA 只允许 module/interface/program 的静态变量。
- 修复: 把跨拍协议 FSM 态寄存器（及其 NBA 更新逻辑）整体迁到 interface 的静态域（如 `vif.rsp_f_st <= F_GAP;`），class 只留协议纪律计数（阻塞赋值无可见性问题）；纯观测进程改阻塞赋值 + "先比对后捕获"排序，等价复刻母版 NBA"看穿上一拍"的采样语义。
- 检测门: 类文件内出现 `this.` 成员在 `<=` 左侧即拦（grep `this\.\w+\s*<=` 或裸成员 `<=` 且声明在 class 内）；迁 interface 后 vif. 前缀漏写会报 Undefined variable，一并查。
- 预防规则: UVM 组件里凡需要 NBA 跨拍记忆的协议状态，一律放 interface/module 静态域经 virtual interface 操作；class 属性只存可阻塞赋值的数据。
- 复发: 0

### [2026-10-21] toolchain: UVM-1.1b 无 `phase_done.set_timeout`（1.2 API）——帧生命周期靠组件 objection 逐帧 raise/drop
- 症状: 按 1.2 习惯写 `uvm_top.phase_done.set_timeout(...)`（或 phase 对象上 set_timeout）→ 编译错 `set_timeout is not a method of ...`。
- 根因: set_timeout 是 UVM-1.2 新增 API，1.1b 只有 objection 的 drain_time 机制。
- 修复: 需要跨进程帧生命周期收尾时，由握有帧边界的组件（monitor）在每帧开始 raise_objection、收齐判据后 drop_objection；test 只起一个总 objection。注意 objection 与 drain_time 抢跑风险——尾样未收齐就 drop 会丢最后一拍数据（本案丢过 1 个 rdout 样），必须让"收齐置位"先于 drop 且在数据通路内可见。
- 检测门: 报 "set_timeout not a method" 即版本指纹；1.1b 平台设计评审查有无 1.2 API 依赖（set_timeout、uvm_sequence_base 新回调等）。
- 预防规则: 目标 1.1b 时生命周期控制只用 objection（raise/drop + 可选 drain_time），禁用 1.2 才有的 API；drop 前必须确认数据收齐信号已在同一进程内观测到。
- 复发: 0

### [2026-10-21] toolchain: vsim Tcl shell 拒 `-work`（vish-3296 Unknown option）——库定位用 `库名.设计名` 设计名语法
- 症状: do 文件里 `vsim -work u1work top` → `(vish-3296) Unknown option '-work'` 即死；同 do 里 vlog -work 却正常。
- 根因: vlog/vlib 接受 -work，但 vsim 的库解析走 vsim 自己的参数集——10.1c 的 vsim 不列 -work（库由 modelsim.ini [Library] 映射 + 设计名前缀指定），-work 是 vlog/vcom 专属。
- 修复: vsim 用 `u1work.kwt_uvm_top`（库.顶层设计名）形式加载；库映射靠本地 modelsim.ini 注入的 `u1work = <路径>` 行（拷主 ini 注入，主 ini 零触碰），配 `-L u1uvm` 链 UVM 库。
- 检测门: vsim 报 vish-3296 Unknown option 且选项是 vlog 系（-work/-incr 等）→ 查 vsim 参数集；do 模板里 vsim 行固化 `库名.顶层` 写法。
- 预防规则: ModelSim 工具族选项不通用：-work 只给 vlog/vcom，vsim 库定位一律 `库.设计名` + -L。
- 复发: 0

### [2026-10-21] toolchain: 文件哈希"序不对则值不等"——got 文件序与金标层序不同时须逐窗同窗同序取哈希
- 症状: RDOUT 逐位 mismatch=0 但 got_hash != gold_hash，scoreboard 误报 FAIL。
- 根因: got 文件按"读回窗序"（win0=L11 在前），金标按"层升序"（L10 在前）扫描，两哈希序列元素顺序不同——内容相同、序不同则 FNV 类流哈希必不等。
- 修复: 逐窗取哈希且两轨同窗同序（got 按窗序切、金标每窗独立扫一遍只累加该窗元素）；外部 sha256 旁证同样按窗提取后再拼接比对，并做 CRLF 归一（`sed 's/$/\r/'`，ModelSim $fwrite 出 CRLF、GNU sed 出 LF）。
- 检测门: 哈希不等但 mismatch=0 时先核对两哈希的输入序列定义（起点/序/行尾），不先怀疑 DUT；sed 行段提取注意 0-based/1-based 混用（本案 L11 1-based=69697..76032）。
- 预防规则: 文件指纹比对前必须把"哈希输入序列规范"写成注释钉在代码里（序、窗界、行尾），双轨（仿真内 FNV/外部 sha256）同窗同序对齐。
- 复发: 0

### [2026-10-21] toolchain: Git Bash 跑 ModelSim 时 `+incdir+` 吃 MSYS `/f/...` 路径不解析（Cannot find `include file）
- 症状: vlog 报 `Cannot find `include file "xxx.vh" in directories: /f/chip_design/...`——目录里文件明明存在；后继炸一串 `(vlog-2730) Undefined variable`。错误信息里路径原样回显 MSYS 盘符形式。
- 根因: ModelSim 是原生 Windows exe，不理解 MSYS 虚拟盘 `/f/...`；Git Bash 对"看起来像路径的参数"做自动路径转换，但 `+incdir+/f/...` 是**单参数前缀拼接形式**，MSYS 转换启发式不认 `+incdir+` 前缀，原样传给 vlog → vlog 按 Windows 语义找 `/f/...` 不存在。裸 `/f/...` 文件参数是否被转换视位置/形式而定，行为不一致。
- 修复: 所有传给 vlog/vsim 的路径一律写 Windows 盘符形式 `F:/chip_design/...`（正斜杠即可，原生 exe 接受）；脚本内 ROOT 变量直接定义为 `F:/...` 形式拼接。
- 检测门: vlog 错误信息里出现 `/f/`、`/d/` 等 MSYS 盘符路径即此指纹；跑批脚本静态 grep `\+incdir\+/` 非零即拦。
- 预防规则: bash 跑批调 ModelSim（及任何原生 Windows EDA exe）时，路径常量统一 Windows 盘符式定义，不依赖 MSYS 自动转换。
- 复发: 0

### [2026-10-22] toolchain: 检测解码器 `cy - w/2` 笔误——mAP50 伪装正常、mAP50-95 塌 27pt 引"数据流腐败"假案；PT-on-blobs 三角定位 + ACIQ 版 DFL/回归头 fp32 复发回填
- 症状: M-contract int8 PTQ 评测管 fp32 基线对 ultralytics 官方 val（同权重同图）mAP50 只差 ~5pt 但 **mAP50-95 差 26~27pt**（0.244 vs 0.505），前任代理立项调查"校准/数据流逐位一致性"；同管朴素 int8（DFL 量化）mAP50 −55~−65pt 雪崩（2026-10-20 条指纹如期复发）。
- 根因: 三层叠加。①真凶是**评测解码器笔误**：`x0,y0 = cx-w/2, cy-w/2`（应为 `cy-h/2`），每个预测框垂直错位，IoU≥0.5 多数存活（mAP50 只差 5pt）、高 IoU 阈值全灭（mAP50-95 塌 27pt）——笔误从 plfront/v4 解码器继承，跨年静默。②Git Bash 把 `/model.22/dfl/` 类过滤参数当路径**MSYS 转换**，make_partial_fp32_table 静默 dropped=0（全表原样通过，"fp32 保留"变空气）——PowerShell 重跑才真剔。③y11n 的 ACIQ 掉点结构与 KL 不同：ACIQ threshold≤absmax，coverage-relax（floor≤1.0）**构造性无作为**（r40 relaxed=0）；仅 DFL fp32 不够（−2.85pt 门 FAIL），须把 box 回归头 `/model.22/cv2.*` 一并 fp32（−1.72pt PASS）。v8n 侧 infix（输入 absmax 定标）+r40（floor 0.40）+DFL fp32 照旧 −0.2pt PASS。
- 修复: 解码器改 `cy-h/2` 后同管 fp32 与官方差缩到 ~1pt/~0.7pt（xcheck 闭环）；**PT 源权重直跑同批 blob 与 ncnn fp32 逐分相同**（diag_pt_on_blobs，0.8741/0.4985 两格一致）⇒ blob 构造与 onnx→ncnn 转换双双无罪，"数据流 bitwise 调查"以三角定位收案不必再做。交付：v8n=infixr40_dflfp32、y11n=aciq_infix_regfp32（DFL+cv2 回归头 fp32），val59 门（≤2pt 单边）双 PASS，MCONTRACT_INT8_PTQ_PASS（2026-10-22_mcontract_int8_ptq_run01）。
- 检测门: 管 vs 官方 xcheck 出现"mAP50 差小 + mAP50-95 差大（>10pt）"组合先 grep 解码器 `cy - w`（半行笔误，肉眼审不出来）；table 过滤类脚本跑完必看 dropped 计数非零（ dropped=0 即参数被 shell 吃掉嫌疑，Git Bash 一律 PowerShell 重跑）；ACIQ 族掉点别指望 relax（构造性无作用），层保留策略按"DFL+回归头"起步。
- 预防规则: cxcywh→xyxy 解码落盘前用一组长宽差大的合成框自校验（w=10,h=100 框 y 向中心必须回中）；跨 run 继承的解码器 golden 与官方 val 数字对不上时先疑解码器再疑数据流；shell 传 ONNX/层名类 `/` 前缀参数统一 PowerShell。
- 复发: 0（本条为 2026-10-20 条之 M-contract 复发回填：该条检测门与修复路径全部命中，方法 A「DFL/conv 回归层保留 fp32」二次实证）
### [2026-10-20] toolchain: ncnn PTQ（ncnn2table KL）对 YOLOv8/11 系 DFL 回归路径砸框——朴素 int8 mAP50-95 可掉 40pt+ 而类别行无损
- 症状: v4 双 yolo 朴素 KL int8 评测 mAP50 −2.4~−2.8pt 尚可、mAP50-95 **−39~−43pt 雪崩**（NUMERICAL_FAIL）；诊断显示类别行 mean|Δ|≈1e-4 几乎无损，但框通道 mean|Δ|≈4px、top-20 anchor fp32-vs-int8 IoU 仅 0.77。
- 根因: 朴素 KL 给 DFL 解码头（1x1 conv）激活 scale 高达 243，量化噪声被翻译成像素级框偏移；**元凶是回归路径 scale/threshold 选择，非 int8 对 DFL 固有不适用**（eq 量化 DFL 层依然达标可证）。
- 修复: 两路互证——A：ncnn2table 生成后用 sed/table 剔除把 DFL/conv 回归层保留 fp32（交付口径，双模型掉点 ≤1.1pt PASS）；B：method=eq（yolo11n −0.04/−1.93pt PASS，逐通道暴力搜 scale 慢，单模型约 50min）。修后 top-20 anchor IoU 回 0.92~0.94。
- 检测门: YOLOv8/11 系 PTQ 评测 mAP50 小掉 + mAP50-95 大掉（>10pt）组合即此指纹；先查 diag 框通道漂移（mean|Δ|>1px）与类别行（≈1e-4 无损）的反差。
- 预防规则: YOLOv8/11 系 ncnn int8 化默认带「DFL 层 fp32 保留或 method=eq」预案；评测必须同时报 mAP50 与 mAP50-95（只看 AP50 会漏判）。
- 复发: 0

### [2026-10-19] toolchain: mini-STA（stamin 家族）拓扑排序早放行——FF 入队递减下游 indeg，到达被低估（种子+中途入队两连修）
- 症状: gemm 切后网表逐路径核验发现物理不可能读数：单元输出到达 1,822ps 而其 B1 输入网到达 8,304ps（p0_r[41].D 驱动 o21ai）；p0_r/p1_r（32×9 乘积寄存器）最差路径只有 1-2 级，乘法器锥凭空消失。同流重放复现：消费单元处理序 21,251 早于其组合驱动者 66,255。修完队列种子后 arc 守恒扫描仍扫出 877/423/394 处违例——同一坑第二入口复发。
- 根因: 到达 walk 的记账两套口径不一致——indeg 只计"组合逻辑驱动的输入"（FF 驱动输入不计，因 FF Q 在 t=0 已就绪），但 FF 单元有两条入队路径都未封：①初始队列种子 `deque(i for i if indeg[i]==0)` 收进 indeg=0 的 FF（D 由 FF/常量驱动的 strobe 链触发器，如 pe_yvalid/slice$85070）；②walk 中途 `indeg==0 → append` 把处理过程中 indeg 降到 0 的 FF 再次入队。FF 被处理后对其 Q 网的全部 loads（含下游单元的非计数输入）做递减 → 下游单元在真组合输入到达前被放行，best 只算了已到输入，到达系统性偏低。stamin.py 全家族（permod/v34pe/v34ln/v34chip）同码同病。
- 修复: FF 单元永不入队——种子 `indeg[i]==0 and get_ff(type) is None`，中途入队同条件；Q 已 t=0 就绪、其 loads 本不该递减；未处理计数同步减 FF 数。修复后 p0_r 段真值现形（乘法器锥回归），arc 守恒扫描三网表零违例。
- 检测门: ①"某单元输出到达 < 其带 arc 输入的最大到达"物理不可能——每次 STA 后跑 arc 感知全表扫（`arr[out] < max(arr[in])` 恒假；FF 的 Q 不依赖 D，必须按 liberty arcs 过滤否则全表误报）。②路径级数与网表常识核对（乘积寄存器路径只有 1-2 级必假）。
- 预防规则: 自研拓扑 walk 的"入度计数口径"与"递减事件口径"必须是同一集合——凡不计入 indeg 的驱动源（FF/PI/常量）就永远不得产生递减事件；且种子里排除的单元类型在中途入队条件里必须同口径再排除一遍。
- 复发: 1（2026-10-19 当日修种子后中途入队入口复发，已强化检测门②）

### [2026-10-19] toolchain: oss-cad-suite yosys 0.70+145 `sta` 全废 + `write_verilog` twine 公名污染端口名（STA 战役双连坑）
- 症状: ① `yosys -p "read_liberty -lib <lib>; read_verilog <mapped_netlist>; sta"` 对任何 liberty/icell 单元报 `Module '<cell>' is used with parameters but is not parametric!` 即死；② 同 build `write_verilog` 输出的实例端口名被污染为 twine 公名——`.\$auto$simplemap.cc:198:logic_reduce$110400 (active_slot)`（真名 S0）、`.\$auto$ff.cc:597:unmap_ce$952087`（真名 SLEEP）等数千处，多端口同污时 C1/D1 顺序不可判定，且被污染的交付网表 `hierarchy -check` 直接报 "port does not exist" 读不回来。
- 根因: 该 twine 重构版把 `derive()` 实现移出 RTLIL::Module 基类（基类留无条件 log_error 桩），read_liberty 导入的 icell 走基类 → sta 对任何单元 derive 即死；write_verilog 把端口 IdString 的 twine 公名当端口名写出，abc BLIF 回灌时公/私名交叉污染（私名正确、公名错位）。
- 修复: STA 不依赖 yosys sta——用 `write_json`（私名正确）取连接关系 + 自研 mini-STA（NLDM 查表，4_logs/2026-10-19_sta_v33/stamin.py）；网表连通性以"同流重综合 + stat 逐行 diff + write_verilog 输出 SHA256 逐字节相同"三重证据锚定（本案 deb68e6e… 双文件一致）。注意 `sdc` 命令只是对象收集器（真正求值靠未捆绑的 OpenSTA，bin/ 无 sta.exe）。
- 检测门: 任何 yosys sta 用法先跑 1 单元最小例（nand2 手工网表）验证；交付网表 grep 指纹 `'\.\\\$auto\$'` 非零即写口污染；读回校验 `hierarchy -check -top <top>` 必须过。GLS 前置门：网表全部实例端口名逐一对模型端口集闭包校验（含"解析成功但名不在端口集"形态，如 `.pl1_7_s0q(...)`），残留非零即拒编译。
- 预防规则: 此 build（oss-cad-suite 20261016，git a31d95ea0）下禁止信任 yosys 原生 sta/sdc/write_verilog 端口名；连接关系一律 write_json 出口 + 确定性重综合对账。
- 复发: 1（2026-10-21 Q5 GLS 实案：V3.5 综合网表 336,839 实例 33,883 污染口，20,955 为 `.\$F:` 形态、其余为解析成功但名不在模型端口集形态；修复=模型端口集差集回填，全部 5,050 个多坏口实例落在功能对称脚对（a222oi C1/C2、nor4bb C_N/D_N 等），序歧义无功能影响；V3.4 签核网表同 bug 字节级在场但从未 GLS——签核面积不受影响，功能面网表从未被仿真过。改名 `rename -enumerate` 前/后 abc 均不治本；`abc -liberty -dff` 免 dfflibmap 变体在此 build 于 Windows 引号下炸（yosys-abc -c "read_lib 不被识别）；`write_blif` 出口同污染（腐点在 abc 回灌后的设计本体，非 write_verilog 独责）。）

### [2026-10-19] toolchain: PowerShell 变量把整段 vlog 选项当单 token（vlog-1902）
- 症状: `& vlog -work $LibName $VlogOpts +cover=sbctf $f`（`$VlogOpts="-timescale 1ns/1ps"`）→ `(vlog-1902) Option "-timescale 1ns/1ps" is either unknown, requires an argument, or was given with a bad argument`。
- 根因: PowerShell 传原生 exe 时变量扩展为**一个参数字符串**（含空格不切分），vlog 收到名为 `-timescale 1ns/1ps` 的整体选项无法解析。同型隐患：任何"选项+值"对放进单个变量。
- 修复: 选项与值拆成独立参数（`-timescale $TimeScale` 两个 token）；或 vlog 侧合并写法 `-timescale=1ns/1ps` 单 token（等号式对 ModelSim 工具合法）。
- 检测门: vlog/vsim/vcover 报 "unknown option" 但选项明明支持 → 先 echo 实际 argv（PowerShell 侧 `$args`/历史），疑 token 粘连。
- 预防规则: ps1 runner 里每个 CLI 选项单独 param，禁止把"选项 值"对打包进一个 string 变量传给 native exe。
- 复发: 0

### [2026-10-23] sim: TB 死抽头被永久 FAIL 豁免档 masking——自 S3 代两代死锚潜伏实例
- 症状: t6ln 两抽头自 S3 代结构性死亡无人察觉：①score 抽头挂调度态 4'd3（S_SMAX 态早已拆除）→ 该态永不执行，wire_n 永缺 12/层（156 实际只 144 可达）；②p 抽头读 ACT 窗（p 不落 ACT 窗，V3.2 起窗内实为 score 数据，实测 got=g_score 首字 0295）→ 9,801 元素全错。两门均靠"血统差豁免档"（门永久 FAIL 故无人深查）masked 数代。
- 根因: 比对调度抽头的"可达性"与"数据源正确性"两个维度都没有独立断言；整体 verdict 永久红时，wire_n==156 已埋在 PASS 合取式里与其他红同辉，死锚指纹（wires=144）混在全红日志里不显眼。门 FAIL 常态化=任何次级缺陷信号都被归因为"已知血统差"。
- 修复: ①score 抽头迁至 t6smax 已实证锚位 4'd4；②p 抽头移植 p_cap 写口捕获（sram_wen/addr/wdata 抽头+行和 tripwire [32512,33024] over 99×99）+pcap/rsum 断言入 verdict。修复后门回绿。
- 检测门: TB 摘要区必须有**独立指纹行** `WIRE_REACH_SELFCHECK_FAIL wire_n=N expect=156`（wire_n 合计≠12×13 时单独打出，不与 verdict 合取）；换锚/换 VD 源后必查 wires= 行计数=声明数。抽头新增/迁移时三问：调度态在枚举里吗（可达）？窗内数据是目标的吗（源）？消费拍与写拍差几拍（重捕）？
- 预防规则: 门永久 FAIL 豁免档在档期间，任何该门日志的新指纹（计数类/首错类）必须逐项归因后才许归"血统差"——豁免档豁免的是已知指纹，不是全部红。
- 复发: 0

---

## vivado-bd（Block Design / module_ref / IP 集成器）

### [2026-11-05] vivado-bd: 拷贝工程携带原工程 `ips.modRefOverrideMrefDirPath`——module_ref OOC 脚本的 read_memh/read_verilog 全部解析到原树，改 work 副本数据文件永远进不了网表（与 [2026-11-02] OOC 陈旧 DCP 条目为同族不同机制面：那篇是 run 新鲜度，本篇是路径解析）
- 症状: work 副本工程改 `label24.hex`（V8:→V8PL:）后重建 BIT 全绿，板端仍 "V8:"；再生的 OOC run tcl 里 `$read_memh` 路径指向 `2_fpga/final_project/.../label24.hex`（旧内容 7fbd764b），read_verilog 同样从原工程读，DCP 产物写回原树 .gen——**改的那份文件从未被任何综合读过**，日志零报错零警告。
- 根因: 整目录拷贝工程后，全局参数 `ips.modRefOverrideMrefDirPath` 仍指向**原工程**的 `.gen/sources_1/bd/mref`；module_ref IP 的 OOC 脚本生成时以该参数解析模块源与 $readmemh 数据文件位置（相对路径 `label24.hex` 按 OOC 脚本上下文解析，不是按 .v 所在目录）。与 run 新鲜度无关：即使 OOC 真重跑，读的也是原树的旧文件。
- 修复: open_project 后立即 `set_param ips.modRefOverrideMrefDirPath "<work>/.gen/sources_1/bd/mref"` 再 generate/regen OOC tcl；断言再生 tcl 内原工程路径出现次数=0、read_memh 指向 work 副本；跑完以 OOC runme.log `readmem data file … read successfully`（work 路径）+ hex 内容差分落点（本轮恰为 v8n 族条目 k=9..16）+ BIT SHA 变更/HWH 不变三项闭环。
- 检测门: 每个拷贝工程 open_project 后 `get_param ips.modRefOverrideMrefDirPath` 输出必须以本工程根为前缀，否则视为未净化禁止 launch；OOC tcl regen 后 `grep -c <原工程根>` 必须为 0；凡 module_ref 数据文件改动，OOC runme.log 的 readmem 行路径必须落在 work 树内。
- 预防规则: 拷贝工程第一动作=重指 modRefOverrideMrefDirPath 到自身 .gen；「改了文件」与「文件被综合读到」是两个命题，证据只能来自 runme.log 的实际读取路径，不能来自文件本身的修改时间。
- 复发: 0

### [2026-11-02] vivado-bd: BD module_ref 的 OOC 子综合 run 不追踪被引用 .v 修改——顶层 reset+rebuild 后模块 DCP 原样复用，BIT 静默链接旧模块网表（multitask OSD 乱码"无数轮修不好"的根因）
- 症状: task_coco_osd.v/task_pose_osd.v 字体奇数行位段修复（`font_q[5'd23-sel_bit]` 误写 `[4'd15-sel_bit]`）写入工程 imports 后两次重建 BIT 均告成功，板端字符仍乱码，而同 RTL 的像素级仿真全 PASS；impl runme.log 显示模块 cell 从 `.gen/.../display_test_task_*_osd_0_0.dcp` 读网表，该 DCP mtime（22:16:42）早于 .v 修改时刻（23:03:55）；23:31 重建时两个 `display_test_task_*_osd_0_0_synth_1` OOC run 只有 gen_run.xml 被 touch，`.vivado.end.rst`/DCP 纹丝不动。
- 根因: module reference 的 OOC 子 run 新鲜度由 BD generate 状态推导，**不把被引用 .v 的 mtime/内容哈希计入依赖**；`reset_run synth_1`/`launch_runs impl_1` 只校验各自名下依赖，已 100% 完成的模块 OOC run 被判 up-to-date 直接复用旧 DCP，link_design 静默吃进——改 RTL→重建 BIT 全链零报错零警告。顶层 synth_1 的 NEEDS_REFRESH 翻转也拉不动这些子 run。
- 修复: 显式 `reset_run display_test_task_coco_osd_0_0_synth_1; reset_run display_test_task_pose_osd_0_0_synth_1` 后重 launch；以 launch 日志出现 "Launched display_test_task_*_osd_0_0_synth_1"、`.vivado.end.rst` 与 DCP mtime 更新为本轮时刻、DCP SHA256 变化为三项确证。
- 检测门: 重建后断言每个被改模块：`Get-Item <runs>/<mod>_synth_1/.vivado.end.rst` 与 `.gen/.../<mod>.dcp` 的 mtime ≥ 本轮 launch 时刻且 DCP SHA ≠ 上轮；impl 日志里 "Reading design checkpoint …<mod>.dcp" 行存在≠新鲜，必须对 mtime。任一失败=BIT 未含修改，禁止上板。**强化（复发①后）：reset 清单不靠手写白名单——用 glob 把本轮改动面映射到的全部 module_ref OOC run 一并 reset，并以 `STRUCTURAL_OOC_PASS n=<期望条数>` 计数门核对（n 少了=清单漏项），凡改 module_ref 的 RTL/数据文件（含 $readmemh hex）三者（RTL/hex/其它数据）任一改动都触发。**
- 预防规则: 凡 BD 内 module_ref 的 RTL 修改，重建前必须显式 reset 对应 `<bd>_<mod>_0_0_synth_1` 子 run；BIT 是否含修改以模块 DCP mtime/SHA 变化为准，不以"构建成功/时序达标"为准。
- 复发: 1（2026-11-05 dip v2 实案：改 label24.hex（V8:→V8PL: 字模）后重跑 BIT 全绿，板端仍显 "V8:"；`display_test_t1_text_osd_0_0_synth_1` 不在手写 OOC reset 清单（v2 只 reset 6 个），15:56 完成的 v1 OOC DCP 原样链进 v2 BIT——计数门若在位（n=8 vs 实际 6）当场可拦；v3 补 reset 后 OOC n=8、$readmemh 重读 work hex、BIT SHA 变更而 HWH 逐字节不变，板上 V8PL: 确认）

### [2026-10-25] vivado-bd: BD 缝合丢失类——端口在/连接丢，优化器合法折叠把活逻辑变死逻辑（B期 G0 实案，R136-R138 全链）
- 症状: G0 指纹门拒止 rom_pctl_addr 13→12 位；法证链 7 探针钉死真凶=BD 层 cv_slot 连接丢失（.bd JSON connections 零对象、wrapper 绑 {7×1'b0}），issuer 见 cv_slot≡0→pbase[13:12]≡0→opt 合法折 bit13。硅片若流出=PLFRONT63 最后 5 conv（slot 64-68）控制字读别名区。
- 根因: 三重叠加——①「回退目标即验收标准」陷阱：10-23 协调批准的 r11 形态还原，验收 Gate C 明文把「cv_slot 残留=0」当通过标准，断连是回退的预期产物非失误；②改编缺口：run01 时代端口再手术只补了端口，改编脚本丢了 connect_bd_net 块+双门+wrapper 鲜度门（查端口存在≠查连接存在）；③传播链三跳（AC1→run01→run02 字节拷贝）。**隐形机理：仿真面零暴露——仿真跑 RTL shadow 直缝不经 BD，此类缺陷全部构建门不可见**。
- 修复: BD 补 connect_bd_net+validate+save_bd_design **落盘**（只修内存=每个未来容器副本重丢一次）+regen wrapper；禁 DONT_TOUCH 钉锥（会把断连常量 0 焊进硅片比断连更糟——DONT_TOUCH 只保网表形态不保功能）。
- 检测门: **常设 BD 缝合门**（synth 前）：.bd JSON connections 普查架构必备网（不得只查端口声明）+wrapper 绑零形态 grep+模块端口三门齐验（声明门+连接门+wrapper 鲜度门）+快照回退/容器复制后三门全重跑。
- 预防规则: 破坏性还原的 Gate 证明的是"回退成功"——被回退特征的再引入必须配对完整再手术链检查；任何容器复制/快照回退后，缝合门重打才算净。
- 复发: 0

### [2026-10-27] vivado-build: 工程迁移后 39 个已完成 run 集体 NEEDS_REFRESH=1——只清顶层会被 IP/OOC 依赖重算回 1
- 症状: 已上板验证工程未改设计，换目录打开后 synth/impl 均显示 100% Complete 却报比特流非最新，并伴 Refresh Changed Modules；只 set_property NEEDS_REFRESH false 给 synth_1/impl_1，当会话为 0，close/reopen 后又为 1。
- 根因: 工程整体迁移使 .xpr 保存路径和 run 依赖对象不一致，open_project 扫描把顶层及 IP/OOC 子 run 集体标旧（实案 39 个）；顶层新鲜度由子 run 依赖重算，不是能脱离子 run 持久清除的独立状态。mtime 不能证明内容变化，须先内容哈希对账。
- 修复: 先备份 bit/ltx/xsa/xpr/bd 并 SHA256 登记，确认 462 个设计输入与原工程逐件相同；修正 .xpr Path 后，仅对 PROGRESS==100% 且 NEEDS_REFRESH=1 的所有 run 逐个 set_property NEEDS_REFRESH false，不 reset、不重综合；close/reopen 后 open_bd_design+validate_bd_design 并复查全部 run。
- 检测门: Tcl 遍历 get_runs，在重开工程和打开 BD 后分别断言 NEEDS_REFRESH=1 的数量为 0，且 synth_1/impl_1 PROGRESS==100%；清除动作遇到非 100% run 必须 error 停止；最终 bit/ltx/xsa/bd SHA256 与备份一致。
- 预防规则: 工程搬家后先查全 run 依赖状态并做内容哈希对账；不得只清顶层两个 run，也不得在未归档已验证 bit 前用 reset/rebuild 掩盖迁移状态。
- 复发: 1（2026-10-27 最终识别构建后同族复发 37 个：顶层 launch 复用已完成 OOC DCP，只有显式 reset 的 pp_ram_ctrl 为 0，其余已完成子 run 及顶层重开均为 1；BD/wrapper/生成网表内容硬查正确，未重建，按子 run→顶层顺序清除后 close/reopen+BD validate 前后均为 0，bit/BD SHA 不变）

### [2026-10-25] vivado-build: 构建门名锚腐烂类——按旧树校准的网表普查门在新树空转，首次求值才现形（D16 实案，沿 D11/D15 先例族）
- 症状: r12 构建电池中 M10SMOKE_NETLIST/edge 指纹门以 r11 树名锚（*u_csr*cfg_edge_node*/cfg_edge_win/join_tab）普查，r12 树表已迁 m9_page_tables 银行寄存器（edge_bank/join_bank output wire）→锚匹配 0→门拒止或空转。attempt6 死于 G0 在先、run01 从未走到——**impl_pfr7 系该门在 plfront 树史上首次求值，腐烂为 pre-existing**。
- 根因: 构建门的名锚随树演化腐烂无版本伴生；r11/r12 双形态互斥（AC1 A/B：cfg_edge_node=73/edge_bank=0 vs r12 反之）——单形态校准的门换树即失效。
- 修复: D16=只修门检不修设计，r12 形锚（edge_bank≥64/join_bank≥100 实测 256/640，加严方向），注释块留痕+前后脚本双 sha（门脚本 mid-battery 变更证据链诚实性）。
- 检测门: 凡网表普查门必须带**非零断言**（腐烂时空转=悄悄 PASS 是最坏形态；本门带非零断言所以正确响了）；门锚变更须 RTL diff+旧树 A/B+消费树 sha 三证；首次在新树求值的门一律按"未验证"对待。
- 预防规则: 构建门锚与树版本伴生（r11 锚门/r12 锚门分文件或带树标）；树迁移（表搬家）时门锚同步迁移入任务书 checklist。**门脚本 mid-battery 补丁+即刻重跑=存盘竞态窗**——补丁后必须核 mtime<启动时刻或直接重新 source 验证被载字节=补丁后内容；横幅字符串（"XX applied"）是意图声明≠被 source 内容，不作证据（审计 R138 回执法条）。
- 复发: 0

### [2026-10-21] vivado-bd: 2025.2 JSON xci 不暴露派生参数名——读回用 CONFIG.WEA_Width 等派生名直接 12-4371 ERROR；派生量须读基本量自算或 grep xci
- 症状: blk_mem_gen 配置读回 `get_property CONFIG.WEA_Width` 报 12-4371/12-1341/17-39 三连 ERROR（参数不存在），而 xci 内 WEA_WIDTH=80 明明在盘。
- 根因: 2025.2 起 xci 改 JSON 格式，只暴露基本配置参数（Write_Width_A/Byte_Size/Use_Byte_Write_Enable），派生量（WEA_WIDTH=Width/Byte_Size、读口宽度链）由 IP 模型推导，不是可 get_property 的属性。
- 修复: 派生量=基本量自算（WEA_WIDTH=Write_Width_A/8）或直接 grep xci JSON；读回脚本撞 ERROR 后也要把撞墙行如实带进派件/报告（下不为例律）。
- 检测门: IP 配置门只钉基本参数集；任何"参数不存在"ERROR 出现即检查是否把派生名当基本名用。
- 预防规则: xci 参数分基本/派生两族，读回只碰基本族；派生值以 xci grep 为权威证据。
- 复发: 1（2026-10-28：同族变体=IP 对象身份/修订属性改名 component_reference/ip_revision→IPDEF/CORE_revision，机制面不同独立建条，见 [2026-10-28] vivado-build IPDEF/CORE_revision 条，双向互链）


### [2026-10-21] vivado-bd: get_property DIR on bd_pins 返回单字母 O/I 而非 out/in——方向门自误报
- 症状: r12 cv_slot 方向门 `set D [get_property DIR [get_bd_pins roms/cv_slot]]; if {$D ne "out"}` 恒 FAIL，puts 实测 D=O。
- 根因: BD pin 的 DIR 属性词表是单字母码（O/I，仿 Verilog 方向码），与 RTL 端口声明文本（out/in）不同源；门作者按 RTL 词表写比较值。
- 修复: 方向门判 O/I（`{roms O shim I}`）。
- 检测门: 对新对象属性写门之前，先 puts 实测一次属性取值词表再固化比较值；或门统一写成大小写不敏感双词表接受（O/out、I/in）。
- 预防规则: BD pin 方向只认 O/I；任何 get_property 门值的词表以实测为准，不按同源工具的经验类推。
- 复发: 0

### [2026-10-21] vivado-bd: BD 自动网名从驱动 pin 全名派生（roms_cv_slot 带 cell 的 s），生成物字符串门按类推猜名自误报
- 症状: r12 wrapper 门 `{*rom_cv_slot*}` FAIL；人工 grep 生成物 m9_sys.v 实证 `wire [6:0]roms_cv_slot` + 两处 `.cv_slot(roms_cv_slot)` 全部正确——门自误报，产物无辜。
- 根因: 门作者按 cv_wlay→rom_cv_wlay 的构词类推猜 rom_cv_slot；实际 BD 自动网名取驱动 cell 全名前缀（roms_ 带 s）。猜名型门未对生成物先实证。
- 修复: 模式改实证名 `{*roms_cv_slot*}`；注释固化「先实证后固化」。
- 检测门: 凡对生成产物（m9_sys.v / wrapper / 网表）的字符串匹配门：模式必须从产物实证 grep 得出再写进 tcl；门首跑 FAIL 时先 grep 产物核对「是门错还是物错」再动手改物。
- 预防规则: 生成物门 = 先实证后固化，禁止类推命名；门 FAIL 与物 FAIL 的先验二分是排查第一步。
- 复发: 0


### [2026-10-21] vivado-bd: 文件集综合陈旧 imports wrapper——BD 新增外部口 XDC "No ports matched" 仅警告，引脚随机落位、bit 照常出（stale wrapper 第 4 形态）
- 症状: only_nanoDET_ble 工程给 BD 加 btn_n/led_out 外部口 + module_ref t1_model_btn_0，generate_target 后 synth/impl/bitgen 全"PASS"（WNS +7.747 零违例），但 impl log 有 `WARNING [Vivado 12-584] No ports matched 'btn_n'` + `CRITICAL WARNING 12-4739 set_false_path 无对象`；板上拨 SW0(AB6) 无任何反应，模块 CSR 却可读（"活着但按键悬空"假象：复位后 2-FF 同步器从初值翻到悬空随机电平计了 1 次）。
- 根因: 工程 sources 文件集的顶层 wrapper 指向 `sources_1/imports/hdl/display_test_wrapper.v`（10-02 历史手工拷贝），而非 `generate_target` 刷新的 `.gen/.../hdl/display_test_wrapper.v`。BD 加外部口只更新 .gen 侧；imports 旧 wrapper 无新端口 → 综合顶层无 btn_n/led_out → XDC get_ports 落空 → **引脚不报错、随机分配**，bit 完整出片。
- 修复: `diff imports/hdl wrapper .gen wrapper` 确认除新端口外零差异（无手改）后，用 .gen 新 wrapper 覆盖 imports 拷贝；reset_run synth_1 + impl_1 重出；复检 `grep -c 'No ports matched' synth runme.log == 0`。
- 检测门: BD 新增外部口后，布线前必须 `diff <imports wrapper> <.gen wrapper>`（或 `grep -c 新端口 <imports wrapper>`）；impl runme.log 里 `No ports matched`/`CRITICAL WARNING 12-4739`/`CRITICAL WARNING 12-1411`（bel occupied = 引脚被既有 XDC 占用，IO placer 硬报错 Place 30-58）出现即停——**这三类警告在带外部口的构建里=致命，不许放行**；新引脚约束前必须**全量** grep 工程所有 XDC（本工程四份：pin_zynq7020_cam / ble_uart / action_v1_pins / action_v1_clock_impl + new/），不能只查两份。板上"寄存器可读"不是按键接上的证据，必须边拨边采 PRESSES 增量。
- 预防规则: 该工程（及一切 imports/hdl 存 wrapper 拷贝的工程）每次 BD 改外部口，同动作内同步覆盖 imports wrapper；把 "No ports matched 出现在 impl log = 构建无效" 写进部署前检查清单。
- 复发: 0

### [2026-10-14] vivado-bd: module_ref 端口改宽后 bd 不跟随（stale wrapper 三连坑）
- 症状: RTL `m9_plan_roms.v` cv_wlay 136→168 已改、validate_bd_design PASS、OOC 例化里 BMG douta 是 168 脚，但布线网表 cv_wlay 只有 136 位，上位 32 位（ch_stride）悬空；综合/实现照常跑完不报错。
- 根因: bd module_ref 的引脚宽度在**建 cell 时快照**三处：(1) .bd JSON 端口表（改了也会被覆盖）；(2) 权威源 = `<bd>/ip/m9_sys_<cell>_0*/` 下每实例缓存 `.xci` 的 ports 定义（bd 读取时以它为准）；(3) `.gen` 输出 wrapper 又是另一份快照。改 RTL 三者都不自动刷新；`validate_bd_design` 不检查 module_ref 端口漂移；bd pin 的 `LEFT` 属性只读；delete+recreate cell 也照样 135（重建从缓存 xci 重导入）。
- 修复: 工程+bd 全关 → sed 全部 module-ref 缓存 .xci（每个 cell 可能有 _0/_1/_2 多份，全改）→ 重开验证 LEFT=167 → **purge `.gen` 对应 ip 目录 + `reset_target all` bd 后再 `generate_target`**（generate_target 单独跑不刷新它认为 up-to-date 的产物）→ 门验 m9_sys.v 顶层的 `wire [167:0]<net>`。
- 检测门: 构建脚本里加内容型门（不是时间戳）：读 `.gen/.../synth/m9_sys.v` 必须含 `[167:0]<信号>` 且不含 `[135:0]<信号>`；网表门用细胞指纹（`get_cells -hier -filter {REF_NAME==<ip>}` 的 dout 脚 BUS_WIDTH + 其网 BUS_WIDTH），**不要用 wire/reg 名当指纹**（综合会合并/吸收）。
- 预防规则: module_ref 端口宽度一变，立刻意识到「三处快照」都要处理：.xci 缓存 + .gen purge/reset_target + 内容门。
- 复发: 4（①2026-10-21 t1_label_osd 实锤第二形态：**改模块内部（端口不变）OOC run 同样不刷新**——synth_1 40s"完成"用的是旧 OOC 检查点，vds/dcp 时间戳出卖；须显式 `reset_run <cell>_synth_1` 再 launch 才重跑；②同日第三形态：**只改 module_ref 关联数据文件（label24.hex $readmemh）OOC 同样不刷新**——主 synth _checksum 变了但 ROM 内容照旧进 bit，硅上"修复完全没生效"；③2026-10-26 CNN 实案：仅 reset_run synth_1 后出 bit/XSA 并下板，Conv OOC DCP 仍早于 RTL 2 小时、downsample DCP 仍为 5 月旧档，板上 Pool 退化为单通道常量；统一检测门=任何 module_ref 源（RTL/MIF/hex）mtime 新于 .runs/<cell>_synth_1/*.dcp 即必须显式 reset_run <cell>_synth_1 或改 Global Synthesis 直接编译源码，重跑后核对实际综合模块与 bit sha 必变；④2026-10-27 Vivado 2020.2 vio_to_gray 新增 vid_ce：`.srcs/sources_1/bd/mref/<module>/component.xml` 与 synth `.gen` 下同路径缓存仍存旧接口，update_module_reference 和 delete+recreate cell 都拿不到新端口；备份并移走旧 mref 缓存、由当前 RTL 在临时 BD 重建后，再生 wrapper 必须出现新端口及实际源连接才可 launch）

### [2026-10-14] vivado-bd: open_bd_design 复用内存态，磁盘编辑不生效
- 症状: 关闭 bd 再 open_bd_design，日志打印 "Reading block design file"，但引脚仍是旧值；随后 save_bd_design 把内存旧态写回盘，**覆盖磁盘上的手工修复**。
- 根因: close_bd_design 后设计对象仍在工程内存里，open_bd_design 直接返回缓存对象不重读盘。
- 修复: 磁盘编辑 .bd/.xci 前必须 `close_project`（不是只 close_bd_design）；编辑完重开工程。
- 检测门: 改完磁盘后重开，先 `get_property LEFT` 验证与磁盘一致再 save。
- 预防规则: 对 .bd 的任何磁盘级手术 = close_project 先行；内存里 save 过一次就再也不可信。
- 复发: 0

### [2026-10-14] vivado-bd: 全属性自省循环卡死 Vivado TCL
- 症状: `foreach pr [list_property [get_bd_cells X]] { get_property ... }` 跑 6 分钟不返回。
- 根因: bd cell 继承的 UIM 属性表极大，逐属性 get_property（尤其带 catch）在 bd 上下文是病态慢。
- 修复: 杀掉会话重启（无未保存损失）。只查白名单属性。
- 检测门: 任何 introspection 循环先在小对象上试跑限时；bd 上下文禁止全属性遍历。
- 预防规则: bd 对象查属性用 `list_property <obj> <glob>` 定向取，禁全表遍历。
- 复发: 0

---

## vivado-build（综合/实现/bit 构建）

### [2026-10-29] vivado-build: 内部 BD shim 被当作芯片顶层——主综合完成后 place 展开 1689 I/O 超过器件 330
- 症状: 主综合 100% 完成，实现却在 `place_design` 报 `Place 30-415 IO Placement failed due to overutilization`，设计 1689 I/O、器件仅 330 用户 I/O；XPR 实测 `TopModule=m9_v25_bd_shim` 且生成的 `m9_sys_wrapper.v` 被自动禁用。
- 根因: 板级顶层选择错误。内部 BD shim 的宽向量接口直接暴露为芯片端口，并非这些接口都应连接到物理 I/O；原板证工程的芯片顶层是 `m9_sys_wrapper`。
- 修复: 启用生成的 board wrapper 并在当前 fileset 设置 `top=m9_sys_wrapper`，不删减接口、不更换器件；随后同一 XPR 完成实现和 BIT/XSA。
- 检测门: 发射主综合前执行 `get_property top [current_fileset]` 必须等于板级 wrapper，`get_files */m9_sys_wrapper.v` 唯一且 `IS_ENABLED=1`；生成的主综合脚本必须含 `synth_design -top m9_sys_wrapper`。
- 预防规则: BD 内部 shim 与芯片 wrapper 是两种顶层角色；出现 I/O 数量异常先核 XPR TopModule/wrapper enabled，禁止用裁接口掩盖顶层错误。
- 复发: 0

### [2026-10-29] vivado-build: 新 attempt 复用刚失败的 Vivado 会话——同输入在旧进程中出现端口重复采集假缺陷
- 症状: 相同设计在前一全新进程已通过 RTL 端口采集，新 attempt 复用刚失败会话后却提前报 `SHIM_RTL_SCALAR_DUPLICATE:<port>`，尚未进入主综合。
- 根因: 新 attempt 被送进保留失败设计/elaboration 状态的旧 Vivado 进程，破坏了 attempt 的进程级隔离；输入相同并不代表执行上下文干净。
- 修复: 停止失败会话，后续每个真实 attempt 使用全新 Vivado session/PID，不复用失败进程；相同设计随后重新越过该采集点并完成完整构建。
- 检测门: 发射记录必须包含本 attempt 独有的新 session、PID、working/argv 根；任何非零终态后旧 session 必须停止，新 attempt 的 session id 不得与失败 attempt 相同。
- 预防规则: 失败 Vivado 会话只用于取证，不用于新 attempt；重跑必须新进程，禁止把旧进程状态污染误判为 RTL 回归。
- 复发: 0


### [2026-10-28] vivado-build: `_stub.v`/`_sim_netlist.v`/`.dcp` 是 synth_ip 产物而非 generate_target 产物；产品落点由 XCI `gen_directory` 决定（serial run04 launch01 实案）
- 症状: `generate_target all $ip` 后按 `.gen/sources_1/ip/<name>/` 合同路径取 BMG 产品，报 `required BMG product missing: ..._stub.v`；generate_target 与 synth_ip 均 RC=0 也不能保证 `.gen` 下有 stub。
- 根因: 产品生成机制两分——veo/sim/synth 等由 generate_target 产出，`_stub.v`/`_sim_netlist.v/.vhdl`/`.dcp` 只能由 synth_ip 产出；落点由 XCI 内嵌 `gen_directory` 决定（`"."`=XCI own-dir 原生，4-up=`.gen`），25 个 standalone XCI 实测 8 件 own-dir+17 件 4-up，不能假设统一 `.gen`。
- 修复: 不改钉定 XCI——保留原生生成并补 `synth_ip $ip`（BRAM 同补），再把 8 类产品以声明式逐文件字节对账 copy stage 到 `.gen` 合同路径；真实发射 8 条 `BMG_STAGE_BYTE_EQUAL` 全过（证据=2026-10-28_wg_exec_r04_probe03/、wg_exec_r05 launch01 console）。
- 检测门: 静态门 TCL_BMG_SYNTH_IP_STUB/TCL_BRAM_SYNTH_IP_STUB/TCL_BMG_STAGE_COPY_DECLARED/TCL_BMG_STAGE_BYTE_EQUAL/TCL_BMG_STAGE_SOURCE_FAIL_CLOSED+三个对应 mutation；真实日志门=BMG_STAGE_BYTE_EQUAL 恰 8 条；XCI gen_directory 分组先实测再写产品路径公式。
- 预防规则: 凡合同需要 IP 的 stub/netlist/dcp，必须显式 synth_ip；产品路径公式以每个 XCI 的 gen_directory 实测分组为准，禁止按单一 `.gen` 假设写死。
- 复发: 0

### [2026-10-28] vivado-build: 2025.2 IP 对象身份/修订属性改名——get_ips 对象 component_reference/ip_revision 报 12-1341，正名=IPDEF/CORE_revision（serial run03 launch02 实案）
- 症状: create_project/read_ip 全过后 Tcl VLNV 门 `get_property component_reference $ip`（$ip=get_ips 单 IP 对象）报 ERROR 12-1341「Failed to get property ... on IP ...」+17-39 即死；探针实测 component_reference/ip_revision/revision 三名全部 MISSING。
- 根因: 2025.2 起 get_ips IP 对象顶层属性面重命名：身份 VLNV=IPDEF、修订=CORE_revision（SW_VERSION=工具版本）；旧名 component_reference/ip_revision 不再暴露。与 [2026-10-21] vivado-bd 2025.2 JSON xci 派生参数名条同族（JSON 时代属性面变更）但机制面不同——本条=IP 对象身份/修订属性改名，非 CONFIG.* 派生参数不可见，按变体律独立建条双向互链。
- 修复: 6 处外科 component_reference→IPDEF、ip_revision→CORE_revision（输出 JSON 键名不变）；探针法=复用失败 attempt 已建工程 open_project + list_property 全量清单 + catch 逐项 get_property，实测 IPDEF=xilinx.com:ip:blk_mem_gen:8.4、CORE_revision=12、SW_VERSION=2025.2（证据=2026-10-28_wg_exec_r03_probe02/）。
- 检测门: 静态门 TCL_IP_PROPERTY_CANON_2025（Tcl 禁出现 component_reference/ip_revision，6 钉位=IPDEF/CORE_revision）+负例 old_property_name 注入拒收；新对象属性写门先 list_property+实测取值（沿 10-21 DIR 词表条同律）。
- 预防规则: Vivado 版本属性面不可凭记忆/旧版类推——get_ips 对象身份=IPDEF、修订=CORE_revision；首次在新版本求值的属性查询一律先探针再固门。
- 复发: 0（互链：2026-10-21 CONFIG.* 派生名条复发 +1 2026-10-28）

### [2026-10-28] vivado-build: Vivado batch `-tclargs` 后置选项全部漏给 Tcl argv——脚本单参合同被三个值击穿（serial runner 首跑实案）
- 症状: runner 命令 `vivado -mode batch -source S -tclargs ROOT -log L -journal J`，Tcl `argv`={ROOT,L,J} 三个值，脚本入口 `llength $argv != 1` fail-closed；Vivado 本体 exit 1，wrapper 侧只见 `G6_TERMINAL_WHITELIST`，未产任何产品。
- 根因: Vivado CLI 中 `-tclargs` 是"后续全部参数交给脚本"的终结符；其后再放任何选项（-log/-journal）都不会被 Vivado 自己消费，而是整段进入脚本 argv。
- 修复: 命令固定为 `-mode batch -source S -log L -journal J -tclargs ROOT`（root 恒为最后元素）；runner 启动前做 argv 合同校验（恰一个 `-tclargs`、其后即 root、script_argc==1、全选项序校验），并用 5 个 argv mutation（旧序/尾插/缺 root/重复 `-tclargs`/log-journal 互换）证明 fail-closed。
- 检测门: 启动器单元校验 `len(argv)==1 and cmd[-2]=='-tclargs'`；mutation 门必含"选项位于 `-tclargs` 之后"形态。
- 预防规则: Vivado batch 命令合同 `-tclargs` 永远最后；新增任何选项一律插在 `-tclargs` 之前。
- 复发: 0

### [2026-10-28] vivado-build: 下游命令计划把 G1P-first 当头部门——G6 反向依赖 G1P 成环，静态自检全绿也退回（downstream preflight 实案）
- 症状: 候选 command_plan/checker 阶段序=G1P,G2,NEGATIVE_CLOSURE,G6,V4,V12_BUILD,V13_RUN05,…，自报 21/21 mutation 与 287 文件 SHA 全绿；对照 SPEC §10/§11/§16 实为循环依赖（G1-P 的前置本身需要 G6 真产品）。
- 根因: 计划按"验证强度"排序而非按"产物供给方向"建 DAG——G6 真 products 是 V4/G1P/V12 的共同上游；checker 与 plan 共用同一错误序，mutation 自检在用错误序验证错误序，结构性不可能发现。
- 修复: 唯一接受序=G6→V4→G1P/G2+完整负例→V12→V13→preload→board21→restore→独立复核+promotion 单独决策；checker 加 stage_dependencies DAG 校验（`G6_HEAD_GATE_DEPENDENCY_FORBIDDEN`/`CIRCULAR_STAGE_DEPENDENCY`），旧 G1P-first 序降级为必杀 mutation 输入。
- 检测门: 任何命令计划/checker 交付前，阶段序对 SPEC 章节逐项对拍 + DAG 校验实测注入（含下游环 V12→V13 负例）；计划与 checker 不得互为校验源。
- 预防规则: 门序合同按产物供给方向（DAG）定义，不按验证强度排序；checker 序与计划序必须同源于 SPEC，禁止互相复制。
- 复发: 0

### [2026-10-25] vivado-build: 门集互斥类——电池脚本钉点修订未做门集可满足性走查，新钉与既有门校准形结构性互斥（修复 B 实案，首次求值现形家族第四成员）
- 症状: r12 电池脚本 GLUE_SRC 门钉 6f7069ff（α v1.2 手写数组形），而同电池 repack_pfifo 门要求 *u_repack* 下 RAMB≥1（v1.3 BMG 黑盒形）——α 形下该门结构性不可过=**电池自 α 钉点移入之日起不可满足**；隐形因该门从未被求值（10-23 synth 死/run01 预算 HALT/attempt6 G0 先，repack 门首次求值=pfr8 才现形）。
- 根因: 钉点修订（alpha/beta 移动/新门加入）时未做门集可满足性走查——比"门按形校准漂移"更锐利：不是校准腐了，是**修订那一刻就没检新钉与所有既有门的校准形依赖**。伴生例：脚本头部文档块写"GLUE_SRC pins 9f7f04fd"而门体 enforcement 钉 6f7069ff——doc-vs-gate 分叉本身即陷阱。
- 修复: 修复 B=把胶水钉移回 v1.3（门本来就校准的正确形）=合法解锁非松门；D17 补丁同步修订头部文档块（doc-gate 一致）。
- 检测门: **电池脚本任何钉点修订时强制门集可满足性走查**——新钉形态与所有既有门的期望形态（名锚/资源形/sha/宽度）逐项对检，走查记录落脚本注释块；头部文档块与门体 enforcement 一致性 grep 为发布前置门。
- 预防规则: 门=合同的集合，单个门的"正确"不够，集合必须可同时满足；钉点移动=合同变更，变更必带走查。
- 复发: 0

### [2026-10-25] vivado-build: FIXED_ROUTE 钉网投递时点错=已布态要求——place 前钩报 18-11819 Unplaced driver，烟测语境≠挂点语境（锁布局消融 T3 实案）
- 症状: 消融 T3 首轮把 13 网 FIXED_ROUTE 约束在 place 前钩投递，route_design 报 `Constraints 18-11819 Unplaced driver` 即死；同一脚本在 E0b 内存态烟测语法 PASS（误导性绿）。
- 根因: FIXED_ROUTE 预设具体布线资源，要求驱动 cell 已完成布局——投递时点必须是 route 前（已布态）；烟测在 place 前的内存态做，约束虽被解析但无已布驱动可挂，两种语境结果不可互推。
- 修复: 钩位移至 STEPS.ROUTE_DESIGN.TCL.PRE（16:16:19 重发后 13 网全钉成功，进入路由迭代）；烟测必须与挂点同语境（至少到同阶段内存态）才算数。
- 检测门: 18-11819 Unplaced driver = 约束投递时点早于布局完成；任何 pre-route 类约束的烟测绿不豁免挂点复验。
- 预防规则: FIXED_ROUTE/DONT_TOUCH 布线类约束一律挂 route 前位；建立「烟测语境≠挂点语境」警觉——语法过≠阶段对。
- 复发: 0

### [2026-10-25] vivado-build: CONTAIN_ROUTING 硬包含圈域先验不足=约束性不可布——圈外负载网被截断，171 unroutable+248 unrouted pins（锁布局消融 T2 证伪）
- 症状: 消融 T2 对 repack/hbuf 域下 CONTAIN_ROUTING 硬包含后 route_design 终止：171 unroutable pins + 248 unrouted pins 全集中 repack/re 域，拥塞非因（Global 迭代 ≤4x4 不劣于 E0b）。
- 根因: 圈域边界截断了跨界负载网的合法布线通道——圈内 cell 的网有圈外负载（或 vice versa）时，包含约束使网无法同时满足连通与包含，属约束性不可布而非资源不足。
- 修复: 回退零残留（约束摘除，基线复原）；该路线永久列入本项目禁项（与 FIXED_ROUTE 钉网并列，双双证伪）。
- 检测门: 选域下硬包含前，先验负载跨界率（圈内 cell 的网遍历，负载出域率>0 即不可硬包含）；route 报 unroutable pins 集中单一 pblock 域时先疑约束性不可布。
- 预防规则: 锁布局优先软锁（IS_SOFT=1）与资源锁（DSP/BRAM 按类型不圈 SLICE）；硬包含仅在负载完全自闭域上考虑，且必须先做跨界率先验。
- 复发: 0

### [2026-10-25] vivado-build: unplace_design 在 Vivado 2025.2 已移除——正典=place_design -unplace（锁布局消融 T2 回退实案）
- 症状: 回退脚本调用 `unplace_design` 报无效命令，T2 回退第一次执行失败。
- 根因: 2025.2 起 unplace_design 子命令移除，撤布局功能并入 `place_design -unplace`。
- 修复: 全部脚本改用 `place_design -unplace`；跨版本可移植写法先 `info commands unplace_design` 探测再分支。
- 检测门: 脚本在新版本 Vivado 首跑时先 elab 一遍全部命令（catch 探针）；报「is not a valid command」先查版本变更日志再改语义等价式。
- 预防规则: 本项目构建链统一 2025.2 正典命令集；老脚本迁移时 grep unplace_design/add_cells_to_pblock 等历史命令逐个验。
- 复发: 0

### [2026-10-25] vivado-build: MCP 代理投递 Tcl 三坑——多行括号折行/|| 吞错/return list 误报 exit 2（消融 run01 全实案）
- 症状: 经 vivado-mcp execute 投 Tcl 时出现三类隐蔽故障：①多行 proc/foreach 体在传输中括号折行断裂（语法错但不报在明处）；②`cmd1 || cmd2` 形态被静默改写/吞错；③脚本末尾 `return $list` 被包装层报成 exit code 2 假失败。
- 根因: MCP 传输层对 Tcl 脚本的包装（单行化/退出码映射）与原生 vivado -source 语义不等价；list 返回值经 exit 码通道表达时必然撞 2。
- 修复: ①多行体改单行分号连写或先落盘 .tcl 再 source；②禁用 ||/&& shell 形态，用 catch/if 显式分支；③需要回传值的场景写结果到文件再读，不用 return 值通道。
- 检测门: MCP 投脚本后 Vivado 侧行为与预期不符时，先把同一脚本 write 到磁盘 source 对照排传输层；exit 2 且日志无对应 ERROR 时先疑包装层误报。
- 预防规则: 复杂 Tcl（>3 行或含 proc/分支/回传值）一律落盘 source，不走 MCP 直投；短命令才用直投。
- 复发: 0

### [2026-10-24] vivado-build: batch 模式 Tcl 变量读取错误披 Common 17-53「No open project」外衣——无 can't-read 细节，且 write_hw_platform 的 run 路径在 batch 下必炸 17-69（AC1 两炸实案）
- 症状: AC1 首跑 3 秒炸 `ERROR: [Common 17-53] No open project`，字面上像工程没打开，实际工程开得好好的；次跑 impl 链全程跑完（bit 已落盘）后 write_hw_platform 炸 `Common 17-69 Unable to get BIT file from implementation run`，Vivado 当场退出。
- 根因: ①batch 模式下 Tcl 未定义变量（`$BID_CANDIDATE` 少写花括号被当整个串读）抛 can't-read，经 batch 包装层呈现为误导性的 17-53 用户异常，原始读错误细节丢失；②write_hw_platform 的 run 路径假设交互会话上下文——batch 父会话不认可子进程刚完成的 impl run（母本血统在交互模式从未真正执行到这一行，缺陷被隐藏）。
- 修复: ①变量名拼接一律 `${BID}_CANDIDATE` 花括号定界；②write_hw_platform 两段式——run 路径先试并 catch，17-69 即 defer 到 `open_run` 后用 open-design 路径再导（与 physopt-rebuild XSA 同型），再败才 FAIL（已入 build_integration_ac.tcl，run02 实证 deferred 路径成功）。
- 检测门: batch tcl 开跑前先 `fconfigure stdout -buffering line` wrapper 定位真炸点；遇 17-53 先 grep 自身脚本变量引用（`grep -n '\$[A-Za-z_]*_'` 查可疑拼接）而不是真去查工程；write_hw_platform 调用一律包 catch+deferred 路径。
- 预防规则: batch 下「报错码≠真因」——17-53/17-69 都是包装层外衣，先怀疑 Tcl 侧变量/上下文再看工程；平台导出必须两段式兜底。
- 复发: 0

### [2026-10-24] vivado-build: impl run「100% finished」≠ bitgen 已跑——配置步齐全的 run 没配 bitgen 时 write_hw_platform 直接 abort（AC1 实案）
- 症状: AC1 构建 synth 后 write_hw_platform 炸 `Common 17-69 Unable to get BIT file from implementation run. Aborting write_hw_platform`，Vivado 当场退出；而 impl run 日志报「100% finished」——那 100% 是「已配置步骤全跑完」，run 里根本没配 bitgen 步。
- 根因: impl run 的 progress=100% 语义 = 已配置步骤完成度，不代表 bitstream 生成过；tcl 从母本删段（挂门）时连带改变了 impl 配置链，bitgen 步没进 run，BIT 消费点（write_hw_platform）无货可取。
- 修复: impl run 配置显式含 bitgen（place→route→phys_opt→**bitstream** 全在 run 内）；write_hw_platform/write_bitstream 调用前 `[file exists $bit]` 硬门。
- 检测门: 平台写出前 BIT 文件存在性硬门 + impl run 配置步清单打印核对（必须见 bitstream 步）。
- 预防规则: 看到「100% finished」先问「100% of what」——进度永远是已配置步口径；任何 BIT 消费点前置存在性硬门。
- 复发: 0

### [2026-10-23] vivado-build: vivado.bat -mode batch 退出码恒 0——内部 ERROR 只能靠完成标记 grep
- 症状: ppu_f7_top OOC 岛级 synth 首跑「exit 0」但被静默判过；复核 utilization.rpt 是旧文件才发现 synth 内部早炸（Synth 8-439 module not found 链）
- 根因: vivado.bat 包装层不把 TCL 内 ERROR 传播为进程退出码；脚本里 `; echo exit=$?` 拿到的是 bat 壳的码
- 修复: 每个 batch run 后 grep 脚本自 puts 的完成标记（KNIFE_SYNTH_DONE / ISLAND_SYNTH_DONE）+ grep ERROR 双门，缺一即判失败重跑
- 检测门: 任何新 synth tcl 首跑后 `grep -c <DONE标记> <log>` 必须 ≥1；提取数据前先看报告 mtime 是不是本轮
- 预防规则: 「退出码 0 ≠ 成功」在 vivado.bat 上是常态；批处理判据唯完成标记论
- 复发: 0

### [2026-10-23] vivado-build: ppu 岛 OOC synth 两处暗桩——blk_mem_gen 五 IP 黑盒 + 时钟端口名 s_axi_aclk
- 症状: rtl_ppu 全文件 glob 进 OOC synth 连环 Synth 8-439：yolo_{desc,buf,lut,quant,ring}_bram 全部 not found（xsim 走 ip_*_sim.v 包装，synth 无 IP 库）；补齐桩后又炸 create_clock No valid object(s)（端口叫 s_axi_aclk 不是 clk_i）
- 根因: 五表 RAM 真身是 blk_mem_gen IP（板级容器里经 IP 集成器），OOC 文件流没有 IP 输出产物；岛顶层时钟沿 AXI 命名 s_axi_aclk
- 修复: 写行为桩 ppu_bram_stub（真双口/字节写/读延迟 1，AW 参数化 + 5 个薄包装）放 scripts/synth_stubs/ 只给 synth tcl glob，不进仿真 files.f；create_clock 用 [get_ports s_axi_aclk]
- 检测门: 岛级 OOC 首跑前 comm 清单差集（实例模块名 vs 定义文件名）必须为 ∅；tcl 里 get_ports 前先 grep 顶层 module 头核对时钟名
- 预防规则: 「仿真有 sim 模型 ≠ 综合可闭合」——凡 IP 真身的表 RAM，OOC 证据必须自带桩；时钟端口名以 RTL module 头为准不猜
- 复发: 0

### [2026-10-23] vivado-build: BD 快照回退只还原 .srcs 不清 .gen 产物——陈旧 module-ref wrapper 让 OOC 综合原样复发（Synth 8-11365）
- 症状: r12 smoke bit：BD+六 xci 已从 .bak_pre_r12_width 快照回退（sha 逐件对账相等、.srcs 全树 grep cv_slot=0），重跑构建仍是同一 Synth 8-11365 cv_slot 报错；罪魁是 .gen/sources_1/bd/m9_sys/ip/m9_sys_{roms,shim}_0_2/ 下 synth+sim wrapper .v 与 .xml（上一轮写入的 r12 形状，`.cv_slot()` 挂尾）未被回退覆盖，OOC run 直接消费陈旧 wrapper。
- 根因: 快照回退只覆盖 .srcs 源件；.gen 产物目录是 Vivado 自管的"按 BD 校验和记新鲜度"缓存——外部改写 .bd 后其新鲜度记录仍认为产物 up-to-date，reset_target/generate_target 与 OOC run-reset 都不必然重写它们（本例 wrapper .v mtime 停在上一轮 12:29:30 即铁证）。
- 修复: 回退/换形后同时删除 BD module-ref 的 .gen 产物目录（.gen/.../bd/m9_sys/ip/ 下 m9_sys_roms_0*、m9_sys_shim_0* 全部 _N 变体），再 reset_runs 对应 OOC run，然后才重跑构建（r12 smoke ruling 3：tcl pre-open purge 段扩到 .gen bd 产物 + 删后由 generate_target 从干净 .bd 重出）。
- 检测门: wrapper 再生后（BD_WRAPPER_REGEN 后）立即 grep 再生 wrapper .v：无 cv_slot 且端口表正确（.cv_wlay(cv_wlay) 在、异代际专有端口不在），硬门过了才准 launch synth（M10SMOKE_MODULE_REF_WRAPPER_CLEAN_PASS）。
- 预防规则: 跨代际共享容器的"回退/换形"动作，作用域必须= .srcs 源件 + .gen 产物两棵树；只动 .srcs 等于回退了一半。
- 复发: 0

### [2026-10-23] vivado-build: update_module_reference 在本工程恒 rc=1 且空错误消息——print-only 防线门掩掉再生成失败，硬门必须基线校准
- 症状: build tcl 的 roms module-ref 防线步 update_module_reference 两轮都 rc=1 out=（错误消息为空），tcl 只 puts 不设门照常往下走；10-18 r11 BIT_PASS 正典构建日志同位置同样是 rc=1 out=（正典也"失败"过且照样 PASS）。
- 根因: 该命令在本工程/2025.2 下是"常形失败"（define-free module-ref 场景），catch 到 1 属基线形态而非再生成失败的证据；真正成败取决于 purge+generate_target 的产物重出，print-only 门对两者都无感。
- 修复: 硬门基线校准：rc 偏离正典基线（≠1）才 M10SMOKE_BIT_FAIL module_ref_redetect_anomalous_rc 停报；再生成成败的权威判据改为"再生 wrapper grep 硬门"（见上一条）。
- 检测门: 把"观察型 puts"升级为硬门前，先在 PASS 基线构建日志核对该命令历史 rc——形态非 0 却常态存在的命令，按基线 rc 设异常门，不按 rc!=0 死门。
- 预防规则: defense-in-depth 门要么真门（FAIL 即停）要么别装；装错形态的死门会把 PASS 流程也闸死，装 print-only 则等于没装。
- 复发: 2（①2026-10-27 Vivado 2020.2 vio_to_gray 新增 vid_ce 同现 rc=1/out 空；②同日下午定位对象类型变体：传 `get_bd_cells` 必现 rc=1/out 空，改传文档规定的 `get_ips design_1_pp_ram_ctrl_0_0` 后 rc=0、component.xml/XCI 均实际更新且端口不变。后续先核对象类型，不得把 rc=1 当工具常态；最终仍只认 component.xml、XCI、端口/地址和 wrapper 内容门）

### [2026-10-23] vivado-build: Copy-Item 保留源 mtime——回退/对账的复制成败证明只能用 sha256，mtime 会指认错轮次
- 症状: BD 快照回退 cp 后，live 文件 mtime 呈新旧混杂（roms xci=快照日 10/21、shim xci=当轮 12:28），按 mtime 判断"哪件被复制过/被重写"与实际内容完全对不上。
- 根因: PowerShell Copy-Item（及带 -p/保留戳的复制）把源 LastWriteTime 原样带来；Vivado 的 generate_target/产物重出同样有保留时间戳行为——mtime 证明的是"内容是哪一刻的"，不是"这一刻发生过写"。
- 修复: 快照回退流程固化三步：① 复制前先落【当前态】sha256 清单（logs/pre_revert_sha256.txt）② close_project 确认后复制 ③ 复制后逐件 sha256 与 .bak 对账相等才准续跑；mtime 仅旁证不作判据。
- 检测门: 对账门=逐文件 Get-FileHash 与快照源比对相等（全 True）；文件树年龄审计用内容哈希树，禁用 mtime 列表。
- 预防规则: 任何"回退/对账/取证"环节，复制成败与内容一致性的唯一证明是 sha256 对账；mtime 在 Windows+Vivado 双重保留戳环境下是误导源。
- 复发: 0

### [2026-10-22] vivado-build: `launch_runs impl_1 -to_step route_design` 合法停 83.33%（5/6 步）——impl 完成闸查 PROGRESS==100% 对分段 run 必假 FAIL
- 症状: r12 A1 stage 构建：route 完整收官（routed.dcp 已生成、runme.log 0 err/0 crit），闸 `get_property PROGRESS==100%` 却报 `impl_not_complete`，83.33% 触 FAIL，整条 source 中止——后面全部预算/时序/DSP 闸被连坐。
- 根因: `-to_step route_design` 的 run 步表仍含第 6 步 write_bitstream（R30 禁地），route 是第 5 步→5/6=83.33%；PROGRESS 语义是"全 run 步骤占比"不是"本段目标步完成"。闸令牌把"full-run 100%"当成了"分段目标达成"。
- 修复: 不改设计、不重跑 impl——同会话写 tail tcl（staged 行 996-1293 verbatim）接力：前置条件改证"routed.dcp 存在 + run STATUS 残留步为 *Post-Route*（=仅剩 route 后步骤）"，open_checkpoint routed dcp 跑完全部 post-impl 闸，决算 M10R12_A1_STAGE_PASS（WNS=+0.894/DSP=87/DRC clean）。
- 检测门: 凡 staged/tail 构建（-to_step），impl 闸必须接受"目标步完成"证据族（routed.dcp 存在 + STATUS 显示剩余步均为目标步之后），禁止裸查 PROGRESS==100%；**进度期望由 -to_step 实参推导（本例 5/6=route 后 write_bitstream 被 R30 禁），禁写死 6/6**（b6 R36 条件；本闸第四次"合法停被误判"类，token 语义必须跟参数走）；起飞前在 tcl 头注明本 run 步表分母。
- 预防规则: 分段 run 的完成判据 = 目标步 checkpoint 文件存在 + STATUS 残余步全在目标步之后；PROGRESS 百分比只用于全程 run。
- 复发: 0（r36 追认 tail 接力；同类"合法停误判"全工程已第四次，再犯即查 token-参数是否脱钩）

### [2026-10-22] vivado-build: 预算/决算呈报必须四行齐引（Slice/LUT/FF/BRAM）——口头只引 LUT 漏 Slice 92% 实案（b6 R36 补正）
- 症状: A1 stage 决算呈报只引 Slice LUT=63.3%/FF/BRAM，漏引 **Slice=12258/13300=92.17%**（rpt L76）——真实最紧资源被口头略过，b6 亲验 rpt 才补上；资源态势误判一档（"BRAM 83% 最紧"应为"Slice 92% 最紧、BRAM 83% 次紧"）。
- 根因: 呈报人脑内"预算三重"只映射到 LUT/FF/BRAM 三行，Slice 行在 utilization.rpt 是独立行（L76），提取脚本/肉眼都容易跳。
- 修复: 资源态势入 03 日志与呈报模板固定四行：Slice/LUT/FF/BRAM(+DSP)；最紧资源判定以 Slice 行打头。
- 检测门: 凡呈报 utilization 数字，自检一句"Slice 行引了吗？几 %？"
- 预防规则: 预算/决算呈报=四行齐（Slice/LUT/FF/BRAM），缺一不可；最紧资源以 Slice 为首判。
- 复发: 0

### [2026-10-22] vivado-build: netlist 闸的 NAME 匹配令牌会随 R63/synthesis 命名漂移集体失效——闸 FAIL 先验"设计丢了还是令牌旧了"，三查再立案
- 症状: r12 A1 stage routed checkpoint 连撞三闸：edge_slot（r11 有 edge_node_ff=73，r12=0）、cvslot（cells=0）、repack_pfifo（bram 4→0）。初看像三连回归。
- 根因: 三案三因，两种性质——①②是令牌漂移：R63 把 cfg_edge_node/win 迁入 u_csr/u_page_tables（edge_bank_reg 256 cells，net cfg_edge_node[63:0]/cfg_edge_win[127:0] 健在）；cvslot 实例 RTL 名 u_cvslot（REF=m9_bm_cvslot，prim RAMB18E1），NAME 过滤器 *m9_bm_cvslot* 自然 0 命中。③是真 delta：glue AXI 读口 tie-off 为 M11a 正典（原版逐字节同），死锥（pfifo 256×64 + rpwin BMG）在 r12 被裁、r11 被留=opt 种子分歧。
- 修复: b6 R36 裁：①② token 修正批（edge=REF 级 u_page_tables*edge_bank* + net 宽 64/128 双证，cvslot=REF_NAME==m9_bm_cvslot），已落 parent tcl（sha 1375CE7A…）并对 routed checkpoint 重验 **WOULD_PASS=1**；③repack 裁 (a) benign 死锥：双模闸（存储存在降 WARN+留痕，活性=u_repack 例化+glue 控制锥+skid），**G5 全帧 walk=终审**（repack 区数据错即升级回查）。修法共同前置=三查：裸名查（去 u_csr 等层次限定）、net/driver 反查（net 在不在、谁在驱动、负载活不活）、RTL 亲读（例化名 vs 模块名、tie-off 何时引入）。
- 检测门: netlist 闸 FAIL 时依次跑：get_cells 去层次限定重查 → get_nets 同名 net 存在性+BUS_WIDTH → driver/loads 反查 → RTL grep 例化名；四步全空才允许怀疑设计丢失，否则按令牌漂移呈审。
- 预防规则: netlist 闸令牌写死时注明"命名依据哪个 run 的 netlist"；跨 RTL 代际（R63 级）复用闸必须重验令牌；小 ROM/小数组优先怀疑"实例名≠模块名"与"溶解进 LUT"。
- 复发: 0

### [2026-10-22] vivado-build: import_ip 在摄入时重写 xci——creation-run 字节钉永不可达，项目内 xci 钉必须钉 post-import 字节
- 症状: r12 A1 首次 synth：xci 字节门 `axiwr_xci_sha_drift` FAIL——项目内 m9_bm_axiwr_fifo.xci（a1e79671…）≠ 创建 run 钉（877bbb3c…）；diff 仅 3 处：gen_directory/OUTPUTDIR 被改指项目 .gen 目录 + checksum 被重算。
- 根因: import_ip 摄入 xci 时按目标工程重写 gen_directory/OUTPUTDIR 并重算 checksum——创建 run 的原生 xci 字节在"已被 import 过的工程"里数学上不可能复现；钉创建 run 字节=门永远自杀。同理 shadow 派生文件的 sha 在进工程/被工具碰过后也可能漂移，逐文件钉要分清"哪一侧的字节"。
- 修复: 项目内 xci 门改钉 post-import 实测字节（a1e79671…），注释写明机制与创建 run 钉（877bbb3c=import 源 provenance 钉）并存；任何 CONFIG 改动会改内容→checksum→漂移仍可检，手改洞不 reopened。
- 检测门: 新建 IP 的构建门起飞前，先把"xci 钉的是哪一侧字节"写明（creation-run / post-import）；门 FAIL 时先 diff 两侧 xci，全是 gen_directory/OUTPUTDIR/checksum 三类行=摄入重写，重钉即可，不怀疑配置被改。
- 预防规则: import_ip 字节门一律钉 post-import 实测值；creation-run 钉只用于 import 源校验。
- 复发: 0

### [2026-10-22] vivado-build: 利用率预算门只盯 LUT/RAMB36 漏 SLICE——R5 门覆盖缺口，预算门必须升维三重
- 症状: r12 一路绿灯过预算门（LUT 39678/53200、RAMB36 110/140）却在 route 阶段 level-5 拥塞暴死（35-162 52209 unrouted）；placed 报告揭示 **Slice 13300/13300=100%** 才是真绑定约束，而门从来没看它。
- 根因: 预算门设计以 LUT/BRAM 当利用率代理，漏了 SLICE（切片）这个 7 系打包密度真约束——控制集碎片化使 LUT<80% 时 slice 可以已 100%（FF/LUT 不能同片填充），代理指标失真。
- 修复: 预算门升维三重：E3 锁 + LUT/RAMB36 + **SLICE**；硬闸 **slice<95% 才进 route**（不是 100%）——arm1 死因就是 100% 时 SpreadLogic 疏散无米下锅。
- 检测门: 构建 tcl 预算门段 grep 无 SLICE 行即拦；每轮 synth/place 后 report_utilization 三行（SLICE/LUT/RAMB36）齐录留痕。
- 预防规则: 利用率门永远以"最紧资源"为闸，单看代理指标（LUT）等于没看。
- 复发: 0

### [2026-10-22] vivado-build: Slice≈100% 时 SpreadLogic 疏散族 place 初始化必败（Place 30-4/30-99）——directive 选择先看 slice 余量
- 症状: r12 route 失败后臂1 从 physopt.dcp `place_design -directive AltSpreadLogic_high` 重排：ERROR [Place 30-4] Design utilization is very high → [Place 30-99] Placer initialization failed，46 秒即败。（首飞还踩过指令名陷阱：Congestion_SpreadLogic_high 是 implementation strategy 名，place_design 拒识 18-641；SpreadLogic 族的 place directive 正身是 AltSpreadLogic_*。）
- 根因: Slice 13300/13300=100%（LUT 仅 74.6%）——疏散指令需要空余 slice 承接被疏散逻辑，零余量时 placer 初始化即死。绑定约束是 SLICE 打包密度不是裸 LUT。
- 修复: 降压先行（资源模式优化/控制集收敛，见 1_docs 方法论文档 2A 节），slice<95% 后才允许 spread 类 directive 上桌。
- 检测门: 上任何 spread 族 place directive 前必查 report_utilization 的 SLICE 行，≥98% 直接判该族不可用；strategy 名 ≠ directive 名，用前在 UG904 strategy 描述表核对。
- 预防规则: directive 选择先看资源余量再谈策略名；高利用率设计的 spread 类指令是降压之后的菜，不是救急的药。
- 复发: 0

### [2026-10-22] vivado-build: route 35-162 拥塞失败——第一反应是 placement 密度/结构诊断，同 DCP 换 route directive 重试=相关失败
- 症状: route_design Phase 10 收尾: CRITICAL [Route 35-162] N signals failed to route（r12 实案 52209）+ ERROR [Route 35-2] node overlaps（122340），写出 routed_error.dcp 后 Vivado 退出。此前 GI1/GI2/R&R 全"成功"完成——失败只在最终合法性校验现形。
- 根因: 有效拥塞 level≥5（runme.log 有 "Effective congestion level: 5" 行，r12 实案 Aspect 0.5 / Sparse 5.375）——这是 placement 密度问题，router 在既定布局上怎么 rip-up/reroute 都解不开；Overlapping Nets top-10 行直指震中 RTL 结构（r12 实案 u_feeder/x_hold_reg[127]_0[*]，地理 INT_R_X19Y15/X15Y28）。基线 r11 同利用率能上板 → 拥塞增量来自新逻辑的结构，不是全局资源。
- 修复: 改变设计状态再 route——b6 裁定双臂从 physopt.dcp 出发（臂1 place_design -directive Congestion_SpreadLogic_high 重排布；臂2 phys_opt_design -directive AggressiveFanoutOpt 高扇出复制），route 恒定 Explore；不动 synth 保钉链。并行诊断 E3 pblock 围栏是否限制震中模块摆放自由度。
- 检测门: route FAIL → ① 立即存档三档 DCP（placed/physopt/routed_error）② runme.log grep "Effective congestion level" + "Overlapping Nets" top-10，震中模块名+INT tile 坐标落诊断文件 ③ 查失败 attempt 已用 route directive——同 placement 只换 route directive 属相关失败，禁止当独立处置臂。
- 预防规则: route 失败的第一反应永远是"placement 密度/结构怎么改"，不是"换个 route 指令再赌一次"；高利用率（LUT>75% 或 Slice 近满）设计的 route 阶段只做验证不做抢救。
- 复发: 0

### [2026-10-21] vivado-build: `get_cells -of_objects <pblock> <pattern>` 不按名过滤——pblock 成员门永假炸；成员判定须回读集转 NAME 名单做 in 判定
- 症状: E3 锁加固门在 synth 网表上实跑误炸：`e3_pblock_partial n_rb=2 roots_ok=0/2`——无过滤回读明明含 u_xrd/u_wrd 两根，带精确名 pattern 的同命令却返回 0。
- 根因: `-of_objects <pblock>` 先取 pblock 细胞集，pattern 参数在该组合下不按 NAME 过滤（Vivado 2025.2 实测：精确名/花括号名/`*u_xrd` 通配全部返回 0）——集合过滤语义与全局 `get_cells <pattern>` 不同，属 API 组合陷阱而非写法错误。
- 修复: 无过滤取回读集 → 逐细胞 `get_property NAME` 建名单 → 期望名 `$name in $names` 精确成员判定（r12_e3_lock.tcl 实证 E3_PBLOCK_OK n_rb=2 roots_ok=2/2）。
- 检测门: 任何 pblock 成员检查脚本发布前，必须干跑正例（已知在集成员命中）+ 反例（不在集名不命中）各一次；两条都过才准进构建 hook。
- 预防规则: pblock 成员/回读口径一律「无过滤回读 → NAME 名单 → in 判定」；禁止把 pattern 当作 `-of_objects pblock` 的过滤器用；回读门强度按回读口径设计（根级 2 个 vs 叶级 3478 个要写清捕获的是哪一档部分失败）。
- 复发: 0

### [2026-10-21] vivado-build: `{*}$collection` 批量展开把 Vivado 集合字符串化——>500 元素即触发 Common 17-736 ERROR 中断 place hook；已证正典的逐元素 append 改写必须原样保留
- 症状: r12 impl_1 的 PLACE_DESIGN.TCL.PRE（E3 锁 hook）在 opt 后、place 前死亡：`ERROR [Common 17-736] tcl.collectionResultDisplayLimit was exceeded while converting a collection of '1730' elements to a list of text strings` → hook 非零返回 → place 步失败 → impl_1 FAILED（约 25 分钟 impl 尝试蒸发）。
- 根因: 改写 pre_e3.tcl 时把已证的 `foreach c [get_cells ...] { lappend cells $c }` 改成 `lappend cells {*}$root {*}$hier`——`{*}` 展开要求先把集合转成 Tcl 列表（字符串化 1730 个全路径名），撞 tcl.collectionResultDisplayLimit（默认 500）直接 ERROR。逐元素 foreach 是集合原生迭代，不经字符串化，任意规模安全。同类隐患：`llength $collection` 安全，但一切把集合当字符串用的写法（puts 整个集合、string 操作、`{*}` 展开）都受该上限管制。
- 修复: 恢复逐元素 append 正典；hook 先在 post-synth 网表上手动 source 验证 E3_PBLOCK_OK（3478 cells）再进 impl。
- 检测门: 一切 place/route 步 hook 脚本发布前，必须在 post-synth checkpoint 上真跑一次并留 E3_PBLOCK_OK 类标记证据；静态 grep hook 脚本内 `\{\*\}\$` 命中即审。
- 预防规则: 已证 idiom（逐元素 foreach）禁止「顺手优化」成批量展开；集合只走原生迭代/llength，不做字符串化操作。
- 复发: 0

### [2026-10-21] vivado-build: 门 FAIL 后不先归档 runme.log 就 reset_run/relaunch——失败现场被覆盖灭失，事故归因变考古
- 症状: r12 回合 5 shim OOC 8-11365 的 runme.log 在后续 reset_run+relaunch 后被新综合日志覆盖，审计时只能从旁证（会话 log 尾部）还原，原始 runme 不可考。
- 根因: 构建 tcl 的重试循环（reset_run → relaunch）就地覆盖 yolo_v25_board.runs/*/runme.log，门 FAIL 的现场没有先快照进 run 证据目录的纪律。
- 修复: run 证据目录新增 evidence/ 子目录，门 FAIL 后、任何 reset_run 前必须 `cp runme.log evidence/<门名>_runme.log`；本轮 impl_1（17-736）与 shim 两份现场已补归档。
- 检测门: 构建 tcl 的门 FAIL 分支里加入自动归档命令（cp runme.log 到 $R12R/evidence/），让归档成为门的一部分而不是靠人记。
- 预防规则: FAIL 现场先固化再重试——任何 reset_run/relaunch 之前，对应 run 的 runme.log/.jou 必须已进 run 证据目录。
- 复发: 0


### [2026-10-21] vivado-build: set_property -dict 配置值花括号包变量 → 字面 `$var/path` 串进 IP 校验器
- 症状: create_ip m9_bm_cvslot 后 `set_property -dict [list ... CONFIG.Coe_File {$R63D/cvslot.coe} ...]` → IP_Flow 19-3317 校验器报 `Unable to open file: $R63D/cvslot.coe`（带字面美元符号的路径）；IP「Restoring to previous valid configuration」把配置回滚，构建 FAIL。
- 根因: Tcl 花括号全抑制变量替换；set_property -dict 的 [list ...] 里写 `CONFIG.X {$var/字面}` 时 IP 拿到的是字面串 `$var/字面`，到 COE_FILE 校验这类需要真路径的下游才炸。
- 修复: 配置值裸写 `CONFIG.Coe_File $R63D/cvslot.coe`（无空格安全）或双引号；花括号只留给真正的字面枚举值（Single_Port_ROM 等）。
- 检测门: tcl 发布前静态 grep `CONFIG\.[A-Za-z_]+ \{\$` 命中即拒发；IP 校验报错文本里出现 `$` 字面串即同型指纹。
- 预防规则: set_property -dict 内一切含变量的值禁止花括号；「枚举字面用 {}、路径/变量用裸写或引号」写进 tcl 模板。
- 复发: 0


### [2026-10-21] vivado-build: reset_run synth_1 后 launch_runs synth_1 会连带清空下游 impl_1 全部产物——未归档的 bit 当场蒸发
- 症状: 09:42 write_bitstream 新鲜出炉的 display_test_wrapper.bit（sha 已记录、文件已验证存在）在 09:58 reset_run OOC+synth_1 并 relaunch 后，impl_1 目录被清得只剩 .vdi/.jou 备份，bit 无副本可救。
- 根因: Vivado 工程模式把 impl_1 标记为依赖 synth_1；上游 run 被 reset 重新 launch 时，下游过期 run 的输出目录被一并清理（stale run cleanup）。
- 修复: 无（bit 已随重综合重建）。流程修正：**任何 reset_run/重 launch 之前，先把 impl_1 的 bit/hwh/reports 归档到 run 证据目录**（ Archive 纪律本来也要求 run 产物进 4_metrics）。
- 检测门: 执行 reset_run 前 checklist 第一条 = bit 已拷出 runs 目录并 sha256 登记。
- 预防规则: 比特流即资产——write_bitstream 完成的第一动作永远是"复制+哈希+登记"，早于任何后续 Tcl。
- 复发: 0

### [2026-10-21] vivado-build: ROM 深度 >4096 词必吃 8×RAMB36（4K×36 一列装不下），双读口让 2025.2 整表复制而非推断 TDP
- 症状: t1_label_osd 单 ROM 4320×32b（135Kb）初版综合出 **2×8192×32 Block RAM = 16×RAMB36**（576Kb，4 倍浪费）：诊断读回口（第二读口）存在时，无论单 always 块两读还是 UG901 式分进程两读，2025.2 都把表**复制**成两份各 8192 深；且 4320 词本身超 4096 → 单口也得 8K×4 模式 = 8×RAMB36。
- 根因: 两层机制叠加。①BRAM 列账：RAMB36 最宽配置 4K×9/1K×36，**深度 >4096 的词表只能走 8K×4 模式** → 4320×32 = 8 块（不是按总 bit 算 4 块）；②Vivado 对无写口双读口数组在本例（跨 CDC 的读地址、经大 mux 的读地址）不做 TDP 推断，退化为两份独立 SDP。
- 修复: BRAM-min 三件套——砍永不读的分区（空白条目由 CODE=0 门控，不占 ROM 空间）+ 子条目压缩（数字 2 行字形打包进 1 个 32b 词，16 词/数字）把总深压到 ≤4096 + **砍诊断第二读口**（代价是失去硅上 ROM 读回自检，由 xsim 像素级对拍覆盖）→ 4096×32 = **4×RAMB36 整一列零浪费**。
- 检测门: 综合后 `Select-String vds "Block RAM"`——**同名 rom 出现 ≥2 行即被复制**；期望块数 = ceil(depth/4096)×4（32b 宽时），总行数×深度与预期不符即停；给 ROM 加第二读口前先想清楚自检值不值 4×RAMB36。
- 预防规则: 固定内容表定容第一式：总词数 ≤4096 才进单列（砍废分区+打包子条目是常备手段）；诊断读口默认砍，确要保留则接受 8 块账并写进设计文档。
- 复发: 0

### [2026-10-17] vivado-build: 相邻分立软 Pblock = 负收益来源，成对软锁必须合并单块
- 症状: 消融 E6 轮——E2(DSP 列锁,单轮 Δ+0.210) + E3'(读面双岛锁,单轮 Δ+0.358) 两个**各自及格**的软 Pblock 同挂一轮，组合 Δ 坍缩到 +0.010（=噪声）；worst path 两端都在其中一个框内却被布出 16.1ns 绕行（route 占 81%）。
- 根因: 软 Pblock 虽非硬约束，但成对存在时 placer 把两个人造块边界当聚类锚点，块间缝隙区域被回避 → 跨边界网线被迫绕行。单锁时边界外全是自由空间无碍；双锁时边界互相夹挤。违 UG1388 最小化原则。
- 修复: 合并为**单个 Pblock**（两细胞集同一 pblock、bbox 取并集范围）→ E6b 同细胞组合 Δ 从 +0.010 恢复到 +0.205。实证对照。
- 检测门: 多 Pblock 消融/约束轮，若组合结果远差于各单锁（次可加），第一疑边界夹挤 → report_timing 看 worst path 是否贴块边界绕行。
- 预防规则: 需要锁多个相邻逻辑组时，默认合并单块或令边界相切无缝；只有物理上充分隔离（对角/跨die）的组才分立软块。入布局消融计划 §5 机制行。
- 复发: 0

### [2026-10-14] vivado-build: 构建脚本 `exit 1` 杀死整个 Vivado 会话
- 症状: 门失败脚本 `exit 1`，MCP 会话直接消失（session not found）。
- 根因: source 进 Vivado TCL 的脚本里 `exit` 是进程级退出。
- 修复: 失败后必须 vivado_start 重建会话再跑。
- 检测门: 写门脚本时知道代价；MCP 报 session not found 先想「上次是不是 exit 了」。
- 预防规则: 门脚本 fail 路径优先 `error`/`return -code error`；要用 exit 就接受重启代价并预置重启步骤。
- 复发: 0

### [2026-10-14] vivado-build: 陈旧网表 = 时序逐位一致指纹（废片定律）
- 症状: 换 RTL 后重跑，report_timing 到三位小数与上轮雷同 → 网表根本没换。
- 根因: 工程文件集仍引用旧路径/旧文件，构建脚本静默用了旧网表。
- 修复: 先 grep .xpr 核对 fileset 引用路径 == 编辑路径；swap 名单外文件加 sha256 溯源门。
- 检测门: 时序指纹雷同报警 + fileset 路径 grep + swap 文件 certutil SHA256 与源对账。
- 预防规则: 「时序三位雷同=没换网表」是铁证级指纹，见即停。
- 复发: 0（机制见 memory stale-netlist-identical-timing-fingerprint）

---

## vivado-sim（xsim）

### [2026-11-02] vivado-sim: 裸 `$fatal(1);` 不中止 xsim 2025.2——TB 失败照跑到底还打印 ALL_PASS 退出 0；必须用带 message 形态+失败计数硬门
- 症状: 负向对照 TB（故意保留位段 bug 的 RTL）打出数百条 COCO_FONT_PIXEL_FAIL 后**继续运行**，仍打印 COCO_OSD_ALL_PASS 且退出码 0——若拿它当门，坏 RTL 会领到 PASS 证。
- 根因: xsim 2025.2 对无 message 参数的 `$fatal(1);` 只置 finish 语义不触发 abort（打印皆无），带 message 的 `$fatal(1,"...")` 才真正终止仿真；门语义不能押在系统任务形态上。
- 修复: 所有断言改 `$fatal(1,"TAG_...got=%h exp=%h",...)` 带消息形态；另加 `font_fails` 计数器，在任何 PASS 标记前硬门 `if(fails!=0) $fatal(1,"...FAILS=%0d",fails)`——PASS 行天然在门后，失败时不可能到达。
- 检测门: TB 审查规则——出现裸 `$fatal(1);`/`$fatal;` 即拒；每个 PASS 标记前必须存在对应计数器非零硬门；负向对照（注入已知 bug 的 RTL）必须真实 FAIL（非零退出+无 PASS 行）才算 TB 有效。
- 预防规则: 仿真门的有效性以负向对照实杀为准；`$fatal` 一律带 message，PASS 标记只准写在计数硬门之后。
- 复发: 0

### [2026-11-02] vivado-sim: 复用旧 xsim.dir 工作库——xelab/xsim 不重跑 xvlog 就静默链上旧编译单元，产生"重验证 PASS"假证据（[2026-10-22] xsim.dir 落点坑的机制变体）
- 症状: RTL 已改（mtime 22:12 晚于上次编译 02:27），随后只跑 xelab+xsim"复验"，秒回 PASS 且 $finish 行号与旧 TB 一致——实际仿真的是旧编译单元；RTL 级 bug（字体奇数行）就这样带着"仿真 PASS"证据上了板。
- 根因: xsim.dir 工作库按单元名缓存，xelab 不检查源文件新鲜度，`file delete -force xsim.dir` 缺位时新 RTL 从未进入编译链；与 [2026-10-22] 条（xsim.dir 落在调用者 cwd 导致找不到）同库不同机制：那条是**位置错位**，本条是**陈旧复用**。
- 修复: 每次验证三件套完整重跑：`file delete -force xsim.dir` → xvlog → xelab → xsim；以 run 日志中 `$finish` 行号/新 TB 专属标记（如新增 $display 行）出现为准，证明跑的是新编译产物。
- 检测门: 封装脚本必须先删 xsim.dir 再 xvlog（grep 日志顺序：delete→xvlog→xelab→xsim）；TB 带版本指纹行（如 `TB_V2_$display`），run 日志无指纹行=无效轮次。
- 预防规则: "改 RTL 后的复验"必须从 xvlog 重起；任何跳过 xvlog 的 xelab+xsim 结果一律作废；对照证据以新指纹行为准（变体互链：xsim.dir 落点坑 [2026-10-22]）。
- 复发: 0

### [2026-10-27] vivado-sim: 批处理 120 s 总超时停在 xelab 快照完成后——先分阶段执行快照，禁止误判为 RTL wait 挂死
- 症状: 六帧编译/仿真批处理首帧 `subprocess.TimeoutExpired(120)`，driver.log 已到 `Built simulation snapshot`，但没有 xsim_console.log；同轮五个定向用例和两帧前端均正常。
- 根因: 包装器把 xvlog+xelab+xsim 合并在一个固定 120 s 子进程超时内，本次 xelab 在快照生成后未及时退出，尚未进入仿真；它与 TB 的 `wait`/帧完成条件无证据关系，不能按识别帧挂死处理。
- 修复: 直接对已生成快照单独运行 xsim，正常得到 `LIVE_FRONTEND_SIM_DONE` 且计数齐全；仅将包装进程上限增至 300 s 后六帧全部通过，RTL 与 golden 均未改。
- 检测门: 超时先读阶段日志最后标记并清点 xelab/xsim/xsimk 进程；已有快照则单独执行 xsim 验证本体，并分别检查 `LIVE_FRONTEND_SIM_DONE`、`LIVE_FRONTEND_SIM_TIMEOUT` 和功能计数，禁止只看包装器退出码或直接整批重跑。
- 预防规则: 编译、展开、仿真共用超时时，日志必须能定位阶段；超时诊断先隔离已有快照，延长的是进程启动/退出预算，不得放宽功能超时判据。
- 复发: 0

### [2026-10-25] vivado-sim: in-script 终局判据按"他形程序"硬编=起飞即错杀；TaskStop 后须进程树清点非单点（C腿复跑首飞实案）
- 症状: C腿复跑首飞 5 分钟内主动杀起重来——仿真本身零异常，是包装脚本把终局判据（NSEG>=9+第 9 锚）硬编成了 golden63 九门铃形，而消费件是 plfront 三门铃形卷，判据对本案为空集必触发；TaskStop 后现场残留 bash/cmd/xsim/xsimk 三层孤儿需逐层清点补杀。
- 根因: 判据值从上一形（S8/golden63）抄录未按消费件形制参数化；TaskStop 只断前台句柄不保证进程树（子进程脱管续跑，占文件锁/端口干扰重飞）。
- 修复: ①终局判据一律按消费件形制参数化（门铃数/锚集从卷面元数据读，不硬编字面）；②杀飞后进程树清点=遍历 bash→cmd→xsim→xsimk 逐层 `tasklist|findstr` 确认零存活再重飞；被改名的残骸现场 *_aborted/*_rogue 保全备查。
- 检测门: 复用既有跑批脚本于新消费件前，先 diff 判据段与消费件形制（门铃数/desc 期望/S 标记源）；杀飞重飞前清点四类进程映像零存活为前置门。
- 预防规则: 验收判据与消费件形制绑成一对参数（判据表随卷走）；任何"换个程序重跑"先问三个形制参数再起飞。
- 复发: 0

### [2026-10-25] vivado-sim: plfront 形 desc 期望行 FAIL 类=门铃窗内 live 期望，与 R125 终局比对行不同面——卷血统待归因（C腿复跑 R133 立案）
- 症状: C腿复跑 desc_done 行 3 条全触 FAIL（seg=1 0/14、seg=2 4/20、seg=3 4/42）；而 S8/golden63 卷 desc 零触（声明与岛队列相符）。seg=1 窗 0/14=声明 14 个 desc 未发射。
- 根因: 已归因=LINEAGE_BENIGN（run=2026-10-25_plfront_desc_lineage_run01，CONFIRMED 级证据链）：声明=卷内词流逐字节相等（S 标记第 3 字段=layout.json 各段 ppp_windows 词数累计 14/6/22，新旧两卷逐页解码实测一致）；不符发生在硬件账语义层——0x11C 计 island walker 描述符完成（W_ENG&&eng_done 逐描述符+1），而"词数==walker 完成数"等式仅在 r11 电池 9 门铃排程下成立（S8 锚 5/10/14/20/25/30/36/42 全对上）；plfront 三门铃 t2_4 排程下 issuer 主路直发词、walker 完成仅 0/4/4，结构性不相等。决定性旁证：heads 行两卷同 signature（desc_done=1 expect=43 字面不可达），golden63 对照同样触发；S49 时代 plfront desc 封顶 2 同族。
- 修复: 卷面零缺陷无需重生成；pi1422/pi1714 修复结论不受影响（全卷 diff 实测仅 2 词且均在 S/desc 区外）。TB 消费侧对 plfront 三门铃形显式预分类 desc 判据行（一行级，继承 R125-C1 谓词法）；不构成 bit 验收/卷面晋级阻塞。
- 检测门: plfront 形跑批遇 desc 行 FAIL 先分面——终局比对期望行（R125 类=结构性非判据）vs 门铃窗内 live 期望（本条=可能真缺陷）；终局判据须按消费卷形制参数化（门铃数/锚集/desc 期望从卷面元数据读，不硬编字面，互见上条 in-script 判据条）。
- 预防规则: plfront 三门铃形验收脚本建形制参数表（ee 词数/desc 期望/S 标记源随卷携带）；换卷先跑 desc 期望面对拍再进终局门。
- 复发: 0

### [2026-10-25] vivado-sim: CIM cmdline 过滤器自匹配——枚举进程自身 cmdline 含匹配串，kill 自测假「still_alive」/计数永不归零
- 症状: plfront C 腿 run（2026-10-25_plfront_cleg_sim_run01）看守上线前 kill 自测：按 tag 枚举到目标 powershell 休眠进程并 Stop-Process 后，复查计数恒=1 → KILL_SELFTEST_FAIL（rc=90 停跑）；手动核查目标 PID 实际已被杀死，「活着」的是查询进程自己。
- 根因: `Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*TAG*' }` 的匹配串 TAG 原样出现在**枚举进程自己的 CommandLine**里（-Command 脚本文本即 cmdline 一部分）→ 枚举器自匹配。按 xsimk/xsim 映像名过滤时不触发（枚举器=powershell.exe 非 xsim 映像），但凡「按 cmdline 标记枚举/计数/击杀 powershell、cmd 等通用映像」必触发。与 rc=127 条（命令不可达）/wmic 条（枚举源缺失）/bash-$! 条（PID 命名空间脱钩）同族（守卫杀失牙）但机制实质不同：目标已死而判活=自匹配污染。
- 修复: 过滤器一律加自排除 `and $_.ProcessId -ne $PID`（实案 scripts/guard_common.sh selftest_kill，修后 KILL_SELFTEST_PASS）；遗留自测休眠进程按同 tag 补杀清零。
- 检测门: 看守/自测脚本的 CIM cmdline 过滤上线前，grep 查询串本身是否会被目标映像的进程携带；自测断言「目标真死+计数归零」双条件，计数查询与击杀查询同形同过滤。
- 预防规则: CIM cmdline 匹配一律带 `-ne $PID` 自排除；自测用进程内唯一 tag 串。
- 复发: 0
- 互链: 同区 [2026-10-24] rc=127 条 / wmic 条 / bash-$! 条（toolchain）/ 兄弟谋杀条——同族守卫杀四变体齐（不可达/枚举源缺失/命名空间脱钩/自匹配污染），双向互链，原条复发计数不变。

### [2026-10-25] vivado-sim: 守卫杀按 cmdline tag 杀 xsim.exe 后 xsimk 内核孤儿逃逸——子进程 cmdline 不继承 -f 路径，tag 过滤双盲（杀与复查同盲）
- 症状: plfront C 腿 run（2026-10-25_plfront_cleg_sim_run01）seg A 看守 cap 守卫杀掉 xsim.exe 后，xsimk.exe 内核（PID 5984，cmdline=`xsim.dir/g5_plfront_r11_sim/xsimk.exe -simmode gui -testplusarg G5_SETUP_MAXW=1507 -wdb ... -socket ...`）**父亡存活成孤儿**继续空转；事后枚举才发现。兄弟 run（s8_fix）xsimk 同期在飞，裸按映像名清会谋杀（兄弟谋杀条复发形态）。
- 根因: xsim 启动器把 `-f <opt路径>`（唯一含 run 标识的实参）留在父进程 cmdline，**xsimk 子进程 cmdline 只有快照名/plusarg/wdb/socket 无 run tag** ⇒ 同一条「cmdline like run_tag」过滤在击杀与杀后复查双双漏网（正是 wmic 条预警的「枚举为空⇒无事可做⇒成功」迷彩的 tag 版）。与自匹配条同批同案但机制实质不同（那条=匹配串污染枚举器自己，本条=目标进程天生不带匹配串）。
- 修复: 守卫杀收尸加第二程「孤儿清扫」：凡 xsimk.exe 其父进程已亡（ParentProcessId 查无）即孤儿候选；归属判定三证（启动时间窗=本 run 起跑分/plusarg 或快照名唯一指纹/cmdline 无他 run 标识），三证齐才按 PID 杀。本案实证：G5_SETUP_MAXW=1507 唯一指纹+父亡+启动秒=本 run 起跑秒，一击必杀，兄弟零触碰。
- 检测门: 守卫杀 ALL_DEAD 报出后，另起独立查询列全机 xsimk.exe 及其 ParentProcessId，存在父亡者即逃逸实锤；长跑看守日志心跳周期内 cyc 停增但进程列表仍有 xsimk=同款指纹。
- 预防规则: 「cmdline tag 守卫杀」只管得住带 tag 的进程本体；凡是会产生无 tag 子进程的工具（xsim.exe→xsimk.exe），收尸必须=tag 杀+父亡孤儿清扫双程，ALL_DEAD 定义=两程均零存活。
- 复发: 0
- 互链: 同区 [2026-10-25] 自匹配条（同案双变体，双向互链）；[2026-10-24] wmic 条（枚举源失效同族）/兄弟谋杀条（裸杀复发形态）；rc=127 条/bash-$! 条（守卫杀失牙族齐）。

### [2026-10-24] vivado-sim: 观测 cap 停令后看守 kill 步命令不可达（rc=127）——cap 失牙引擎越窗穿越死亡区，须手动守卫杀收尸
- 症状: S6 追迹 run（2026-10-24_scdone_s6_trace_run01）30M cap 停令正常打印（「G5PROG cyc 30000000 >= 30000000 cap -> guarded stop」）后，in-run 看守脚本 kill 步返回 rc=127（命令不可达），xsim 引擎无人收尸继续跑至 38.1M（越过 32-35M 死亡区并存活——第四次存活观测）；最终由调查代理 20:51 手动守卫杀（PowerShell 核 cmdline/父链后按 PID 杀本 run xsim.exe+xsimk.exe，兄弟 plfront 进程零触碰）。
- 根因: 看守脚本内嵌 kill 命令在该 shell 环境不可达（rc=127=command not found），kill 静默失败且脚本无 rc 上报告警；cap 检查→打印停令→kill 执行链中无「kill 有效性自证」环节——观测 cap 的牙齿只挂在打印上。与 [2026-10-24] 兄弟谋杀条（全局 taskkill 变体）/ [2026-10-18] 外部探测条同族（xsim 生命周期失守）但注入路径机制实质不同（自家看守 kill 不可达型），按变体例独立立条（b6 R102 入册令）。
- 修复: 看守 kill 一律走绝对路径外部命令或 PowerShell 显式杀（先核 cmdline 含本 run 标识）；kill 后 rc≠0 或目标仍存活即告警升级；cap 停令后加「引擎真停」二次确认（下一个心跳周期 cyc 必须停增，停增失败转手动守卫杀流程）。
- 检测门: 看守脚本上线前自测 kill 步（故意对已知 PID 验证 rc=0+进程消失）；run 收尸 checklist 加「cap 停令后一个心跳周期引擎 cyc 停增」勾项；长跑日志出现「停令已打印但 heartbeat 继续增长」= 本条目复发。
- 预防规则: 观测 cap 的牙齿不在打印停令而在 kill 有效性自证——任何 cap/timeout 停令必须自带 kill 可达性自检 + 失败告警 + 真停确认三段。
- 复发: 0

### [2026-10-24] vivado-sim: wmic 在本机已被移除（Win11 26200）——历史看守脚本的 wmic 守卫杀静默失牙（空 PID 列表→假「kill complete」rc=0 迷彩，比 rc=127 无声更危险）
- 症状: S7' 执行 run（2026-10-24_scdone_s7prime_fix_run01）freeze 停令后看守日志打印「guarded kill complete: no <run-img> xsim process alive」，但 xsim 引擎实际仍在跑（cyc 继续增至 41.15M 才被手动收尸）；交互核查 `wmic /?` = 「command not found」，`wmic process where ...` 输出恒为空。
- 根因: Windows 11 build 26200 默认不装 WMIC（Feature on Demand 未启用）——S5a/S6 时代看守脚本里的 `wmic ... get processid,commandline` 从此静默产出空表（stderr 被 2>/dev/null 吞掉），kill 目标 PID 列表恒空 → 函数走「无匹配=成功」分支返回 0。与上一条 rc=127（命令不可达、有声失败）同族（自家看守 kill 失牙）但机制实质不同：rc=127 是「杀不了且报不出」，本条是「根本没试且报成功」——观测 cap 的牙齿连打印告警环节都没有。
- 修复: 守卫杀统一改 PowerShell `Get-CimInstance Win32_Process`（cmdline 匹配本 run 标识）→ `Stop-Process -Force` → 杀后同法复查零存活才报 ALL_DEAD（实案 scripts/guarded_kill.ps1，xsim.exe+xsimk.exe 父子双杀在案）；派单/复用看守脚本一律禁用 wmic。
- 检测门: 看守脚本上线前 `command -v wmic` 必检（不存在=历史 wmic 调用全部失效，逐条审计）；日志出现「guarded kill complete」后下一个心跳周期 cyc 必须停增，停增失败=本条目复发；kill 成功的定义改为「杀后复查零存活」而非 kill 命令 rc。
- 预防规则: 进程枚举/kill 一律走 PowerShell CIM 或 tasklist/taskkill 对，wmic 视同不存在——任何「枚举为空⇒无事可做⇒成功」的守卫逻辑都必须对枚举源本身做存在性自检。
- 复发: 0
- 互链: 同区上一条 rc=127 条（双向互链，原条复发计数不变——机制面实质不同：命令不可达有声 vs 枚举源缺失静默）；同批发现下一条 bash-$! 条（双向互链）。

### [2026-10-24] toolchain: git bash 后台作业 `$!` 不是 Windows PID——kill 自测假阴性（taskkill rc=128「找不到进程」），交给 Windows 工具的 PID 必须出自 Windows 枚举源
- 症状: S7' 看守启动自测对 `python -c "..." &` 的 `$!` 执行 `taskkill //F //PID $!` 得 rc=128（「没有找到进程 272089」），判 KILL_SELFTEST_FAIL；而同一时刻 tasklist/PowerShell 枚举到的该 python.exe Windows PID（74588/25232）被 taskkill/Stop-Process 一击必杀。
- 根因: MSYS2 bash 给原生 Windows 后台作业登记的 `$!` 是 bash 内部作业命名空间的 PID，与 Windows PID 命名空间脱钩（实测 $!=272089 vs tasklist 实际 74588）；taskkill/tasklist/PowerShell 只认 Windows PID。自测设计错误把「PID 命名空间不匹配」误报成「kill 不可达」，与 rc=127 真失牙症状表面相似（都报 kill 失败）但根因完全不同。
- 修复: kill 自测探针的 PID 一律经 `tasklist //FI "PID eq N"` 或 PowerShell CIM 反查确认在 Windows 进程表可见后再杀；或自测全程用 PowerShell（探针启动+枚举+杀+复查一体）。
- 检测门: kill 自测断言 rc=0 之前先断言「PID 在 Windows 表可见」（tasklist findstr 映像名）；不可见即判「自测设计错误」而非「kill 不可达」，禁止据假阴性升级 kill 通道。
- 预防规则: bash 脚本中凡要交给 Windows 工具（taskkill/tasklist/PowerShell/perfmon）的 PID，必须从 Windows 枚举源获得——`$!`、`jobs -p`、`ps`（msys 视图）一律禁用。
- 复发: 0
- 互链: 同批发现上一条 wmic-absent 条（双向互链）；rc=127 条复发计数不变（该条机制=命令不可达，本条=命名空间脱钩假阴性）。

### [2026-10-24] vivado-sim: 兄弟 run 看守脚本退火全局 taskkill 谋杀在飞 xsim——死点=对方 verdict 落盘秒，自家日志零错误零终态戛然而止
- 症状: 本 run 分段 B xsim 起跑约 70s、cyc 仅 458,752，主日志戛然停在 G5HB 心跳行——无 ERROR、无 $finish、无崩溃日志；包装脚本收 rc=1；死亡秒与本机另一 run（scdone_s4_trace）run_s4.verdict.txt 落盘秒逐秒相同。
- 根因: 兄弟 run 的看守脚本退火路径无条件 `taskkill //F //IM xsimk.exe`+`xsim.exe`（按映像名全局杀，不看归属）——对方 run 正常收官触发的退火清理把本机当时在飞的他家 xsim 一并杀掉。与 [2026-10-18] toolchain 条目（vsim 被外部 HTTP 探测击杀）同族（多代理同机并发仿真互杀）但注入路径机制实质不同（peer watcher 全局 taskkill vs 外部 socket 探测），按变体例独立立条。
- 修复: 看守退火改守卫杀——退出前仅当 xsim 进程**仍在存活**（自家 stuck 情形）才 taskkill；进程已不在（自家被谋杀/自然终局）则跳过不杀。被谋杀 run 按分段律原样重跑（进程死亡≠FAIL≠PASS），被杀现场证据改名 attempt1 保全。实案：2026-10-24_cleg_sim_run01 seg B attempt1（凶 run：2026-10-24_scdone_s4_trace_run01）。
- 检测门: 长跑 xsim 日志「零错误零终态戛然而止」+ 死亡秒与任一兄弟 run 的 verdict/marker 落盘秒对齐 = 外部谋杀定性（对时扫描：`Get-ChildItem 4_metrics/logs -Directory | % { 最新文件 mtime }` 找同秒写者）；自家/派单看守脚本 grep `taskkill //F //IM` 命中且无「进程仍在」守卫即高危。
- 预防规则: 一切仿真看守退火路径禁裸全局映像名 taskkill——必须「进程仍在 + 日志无终态标记」双条件守卫；多 run 并发期起跑前 `Get-Process xsimk,xsim` 清零确认。
- 复发: 0
- 互链: 同族原条 [2026-10-18] toolchain「vsim 内核 localhost socket 被外部 HTTP 探测击杀」（该条复发计数已 +1）。

### [2026-10-23] vivado-sim: 跨模块 err 码撞车把真凶藏到盲区——「err=01 既可能是 issuer S_L1C 也可能是 walker ppu_done_err」；状态迁移逐拍钉针（st 变化才打）一轮钉死，静态推理三轮全错
- 症状: r12 G5 整图 walk 在 conv9（94 块后）err=01 卡三轮：per-block axf 事务流缺末块前导 0x40 读、152 拍静默后 S_L1C 消费陈旧 rdata=0x02（前一 BRG 读值）——所有静态路径推演都断言「S_L1C 必发读」，与观测矛盾，曾怀疑 xelab 错编译。
- 根因: **误诊**。G5STRC（issuer st 逐拍迁移探针，仅 st 变化时打一行带 axf_start/busy/done/we/addr/rdata + ld busy/seen_busy + sc_done） reveal 真链：S_W3→S_W4→S_ADV→S_PPPG(39)→S_PPPF(40)→S_PPPW(41) 驻留 148 拍→S_HALT。err=01 是 walker loader 首错锁存经 `ppu_done_err` 落到 S_PPPW 的 `err<=ppu_done_err`——与 S_L1C 的 err<=8'd1 **同码不同源**。S_L1C 从未到访末块；「缺 0x40 读」只因 conv9 首块根本没走 GEMM 装载链（图岛 PPP 闸接管）。静态推理的失败模式：对「每条路径必发读」的断言型推演过度自信，未枚举「FSM 根本没走这条路」。
- 修复: 无需修 TB；在 G5WLKERR 探针（abort 沿打 walker err_code/op/desc + loader fnd/estep/ebit/ecode + scnt）钉出 estep=5。真凶与修法见 rtl 分区 [2026-10-23] 条目。
- 检测门: 错误码是 8bit 局部枚举时，**禁止跨模块归因**——先打 st 迁移钉针确认「错误在哪个 FSM 被登记」，再谈机制；「全路径推演与观测矛盾」是「路径前提错了（根本没走这条路）」的信号，不是「编译器错了」的信号。
- 预防规则: 多 FSM 系统的 err 码在 TB 探针里一律带源标签（如 iss_err vs ppu_err 分开打）；新增判决态（如 S_PPPW）时同步在 TB 的 st 名表注册，避免 41→26 这类裸数字迁移线被读漏。
- 复发: 0

### [2026-10-22] vivado-sim: TB 用 task inout 实参写 AXI 读服务器 BFM——copy-in/copy-out 使服务器整体空转（ready 永不上总线、input 是入口快照恒 0），DUT 挂出的 AR 永无响应
- 症状: r12 G5 整图 walk 首段 20M 拍零进展签名：w feeder ST_PRE 发出 12 个行请求（inflight=12 信用打满）、u_wrd（m9_axi_rd_v3）LSQ=12/enq=8/AR 稳挂 ST_SEND（arv=1），但 TB 侧 m1_arready 恒 0、AR 握手计数=0、R 通道全零——全链路只有 TB 侧一动不动，形态酷似 DUT 死锁。
- 根因: Verilog/SV task 的 inout 实参是 **copy-in/copy-out**：任务存活期对 arready/rvalid/rdata/rlast 的赋值全写在局部副本，任务返回才回写；input 实参（arvalid/araddr/arlen）是**调用入口快照**。`forever rd_ch_srv(...)` 里 `while(!arvalid)` 引用的是入口快照（0）→ 恒真死循环 → 任务永不返回 → 总线信号永远停在 initial 赋的 0。DUT 全程正常。m0/m1 是本 TB 新增通道（旧里程碑走 m3 岛壳 DMA），所以从未暴露。
- 修复: 服务器改写为 always 块两态 FSM（AR_WAIT/R_BURST，ready/valid 全 NBA 到真实信号，len/addr 在 AR 拍锁存）；同链路即刻打通。
- 检测门: 「DUT 侧信号活跃、TB 侧对应 BFM 信号恒等于初始化值」的零计数签名（arv=1 对 arr=0、rv=0）；在 BFM 内埋相位标记，srvph=1 永驻=卡在首个等待循环→实参快照嫌疑；层级探针读 BFM 内部变量与总线信号对拍一次二分。
- 预防规则: TB 的 BFM/常驻服务器一律 always 块或 module 实现；task 只做无跨调用状态的原子事务（如单发 axi_lite_wr）；task 形参表出现 inout 总线信号即评审拦截。
- 复发: 0

### [2026-10-22] vivado-sim: 挂死解剖的逐拍 $display 状态探针 35 分钟撑爆磁盘（3-7GB/轮）——ENOSPC 会中途打断 Edit 落盘、编译日志建不出文件
- 症状: partial 排障轮每轮日志 3-7GB，E: 300G 占满后 Edit 报 ENOSPC 写失败、xvlog 重定向日志文件直接创建失败。
- 根因: 挂死等待循环里每拍打 4 行长探针行，20M 拍 × ~250B × 4 ≈ GB 级/轮；磁盘被多轮叠加静默占满。
- 修复: 探针降频（cyc[16:0]==0 一格 + 前 256 拍细档保留启动瞬态），解剖信息集中 STALL_AUTOPSY 单次快照；大日志处理顺序=先 rm 最大文件释放空间，再 grep 重裁小份（满盘时连裁剪写入都会失败，必须先删后裁）。
- 检测门: 跑批前 df 确认余量 > 预期日志量×3；supervisor 加日志尺寸上限（超阈值先 trim 留证再判杀）。
- 预防规则: 任何进等待循环的逐拍打印必须带降频门；预期会挂死的排障轮，探针全部走 autopsy 一次性快照，不随 tick 打。
- 复发: 0

### [2026-10-22] vivado-sim: TB 读 BFM 改 always 块后仍握手失真——capture 只看 valid 且同拍 `<=0` 覆盖 `<=1`，注册 ready 在任何采样沿都不为 1（注册 ready 必须「旧值握手」判别）
- 症状: partial18 签名：BFM 侧 capture 计数 91 万次、R beat 计数同阶（自洽空转循环），而 DUT 侧 AR 握手计数恒 1、ar 队列恒 7 不消化——两侧各说各话，形态酷似 xelab 错编译（烟测又因驱动端等 ready 的时序恰好避坑而 PASS）。
- 根因: AR_WAIT 态写成 `arready <= 1'b1; if (arvalid) begin …; arready <= 1'b0; end`——valid 常 1 时**每个 AR_WAIT 拍都进 capture 分支**，`<=0` 覆盖 `<=1`，ready 在任何时钟沿的采样值都是 0，DUT 永不见握手；BFM capture 又不验旧 ready，无握手也自转。
- 修复: 注册 ready 的握手法=`if (arvalid && arready)` 判别**旧 ready**（上拍已立起的 1）：真握手拍才锁存并撤 ready；valid 缺席拍 ready 保持 1。修后 DUT 握手计数与 capture 同阶、队列正常消化。
- 检测门: 「BFM 自转计数 ≫ 总线握手计数」两侧计数对拍即破；BFM 必埋双计数（内部 capture/hit vs 总线握手计数），一轮 run 自证不冤枉仿真器。
- 预防规则: BFM 状态机评审 checklist——capture 条件必须含旧 ready 项；同拍对同信号两次 NBA 赋值（先 1 后 0）视为红牌。
- 复发: 0（同案第二形态，task inout 首形态见上条）

### [2026-10-23] rtl: m9_axi_rd_v3 复位后首个行请求 enq 地址恒 X——lsq_push 与 enq_ldem 同拍，首拍读到 NBA 未落地的 lsq_mem[0]
- 症状: 首帧首个 W 行请求：ar_mem[0] 入队 X 地址、AR 带 X 地址上总线；该笔完成后 tag_buf[X 槽]<=X，lsq 头永无 tag 匹配 → lsq 不弹、feeder 信用打满死锁。正常 BFM 下被「头地址重复 enq」自愈（后续同址真实 AR 补齐正确行），只有 BFM 握手失真时才升级成死锁（partial17/18 实案）。
- 根因: enq_ldem 组合使用 lsq_head_addr=lsq_mem[lsq_rptr]，首个请求拍 lsq_mem[0] 还是未初始化 X（本拍 push 的 NBA 未落地），X 地址入 ar_mem[0]、rt_tag=X。
- 修复: 本 run 不改 DUT（自愈成立 + 证据目录冻结纪律）：X 槽 tag=X 永不匹配真实头；未来若修，enq 侧加「本拍 push 写入即头」的旁路（同拍取 laddr_line_i）。
- 检测门: 首帧首请求 AR 地址采样钉针（BFM capture 打印地址，X 即现形）；lsq 头 tag 匹配率探针。
- 预防规则: 凡「push 与头消费同拍」的队列，首元素消费必须旁路本拍输入或推迟一拍使能；新 BFM 首帧必开地址打印。
- 复发: 0

### [2026-10-22] vivado-sim: xelab 2025.2 时序块 concat 内对宽 reg 的 part-select 错读——寄存器值对、拼接结果错；宽积切片必须先落 wire
- 症状: letterbox 核 stage C：`pC_G <= tC_G*R44`（54b 积，探针打印 1130297960985600 完全正确），下一拍 `pix_rgb <= {pC_R[53:44],pC_G[53:44],pC_B[53:44]}` 拍出 0x010000——逐周期追踪证实探针读 dut.pC_G=1.13e15（[53:44] 应=64）而同一拍 concat 里 pC_G[53:44] 读出 0、pC_R[53:44] 读出 1（pC_R=8.8e12 根本不可能是 1）。6/6 帧门全 FAIL、pad 行（不过 scale）全对、三通道只有 B 对。
- 根因: xelab 2025.2 的 RTL 仿真优化缺陷：时钟块内拼接表达式引用前序宽乘法积寄存器的 part-select 时，位选索引被错误映射（疑似按表达式内部中间量位宽对齐）。同一表达式改成 **continuous-assign wire 切片**（`wire [9:0] v = pC[53:44]`）后完全正确；隔离对照（单通道、wire 积、无复位 always）不复现——三通道+异步复位 always+块内 concat 切片四要素齐才触发。
- 修复: 宽乘法积寄存后需切片时，切片一律走 `wire [9:0] x = wide_reg[HI:LO];` 连续赋值，再在时钟块里引用 wire；**禁止**在时钟块拼接里直接写 `wide_reg[HI:LO]`。附带第二坑：`v10 <= (t*R44) >> 44` 直接压窄寄存（10b）被按赋值上下文宽度截断求值恒 0——必须先落全宽积寄存再切片。
- 检测门: 门 FAIL 呈"部分通道对/部分错"或"探针值对、派生值错"=立即怀疑仿真器而非逻辑；把派生表达式提成 wire 对照一拍即知。RTL 评审 checklist：凡 `宽reg[HI:LO]` 出现在 always 块内 concat/RHS 的，一律改 wire 切片。
- 预防规则: 宽算术→寄存→位选三段式，位选永走连续赋值 wire；写 RTL 时就把切片 wire 化，不留块内直写。
- 复发: 0

### [2026-10-22] vivado-sim: xsim 快照必须在其 xsim.dir 所在目录起跑——绝对路径快照名被拼成 `xsim.dir/<绝对路径>/xsimk.exe`；且 xvlog/xelab 把 xsim.dir 落在调用者 cwd（非脚本目录）
- 症状: 逐帧批量门脚本（每帧独立 work 目录、独立快照）从数据目录或 run 根起跑 `xsim --nolog /abs/path/work_f0/snap_f0 -runall`，报 `ERROR: snapshot name "xsim.dir/E:/.../work_f0/snap_f0/xsimk.exe" does not exist`（绝对路径被当快照名原样拼进 xsim.dir/ 下）；改为从数据目录用相对快照名同样失败，因为 xvlog/xelab 实际把 xsim.dir 写在了**脚本调用者 cwd**（run 根），work 目录里根本没有编译产物。
- 根因: xsim.exe 的快照解析只认 `<cwd>/xsim.dir/<snapname>`（无绝对快照路径概念）；而 xvlog/xelab 无 outdir 时不写进脚本所在目录，写进进程 cwd。两件事叠加：批跑脚本若不显式 cd，编译产物与 xsim 期望位置错位。
- 修复: 批跑循环内先 `cd "$WORK"` 再依次 xvlog/xelab/xsim（run_gate.sh 式整块 cd）；TB 需要的相对路径数据文件（$readmemh）复制/软链进同一 work 目录。
- 检测门: 任何 xsim 批跑封装，日志里 grep `Running: xelab.exe` 与 `Running: xsim` 两行的 cwd 必须一致；起跑前 `[ -f "$WORK/xsim.dir" ]` 存在性检查。
- 预防规则: xsim 三段式一律「单 work 目录、整块 cd、相对名起跑」；不给 xsim 传绝对快照路径。
- 复发: 0

### [2026-10-22] vivado-sim: xsim `$sscanf` 的 `%s` 写动态 string 是带牙地雷——重复利用即 heap 崩（~2s kernel FATAL）或零时长无限循环饿死调度器
- 症状: r12 G5 stage-2 TB 面表解析，循环里 `$sscanf(ln,"...%s...",pnm,...)`（pnm 为 string）——第 1 迭代正常，第 2 迭代必 kernel FATAL "exceptional condition"（Time 0 Iteration 0，HDL Line 随机指到无关模块如 ppu_f7_top）；改 packed 承接后若仍有别处 string 目标，则变体为"Simulation engine not responding"（零时长循环饿死时钟，看门狗 cyc=0）。
- 根因: xsim 2025.2 的 `$sscanf` 对动态 string 目标的堆管理有缺陷：重复写入不同长度触发 use-after-free / 内部悬挂；症状形态取决于踩到的堆状态（崩 or 死循环），且 FATAL 的 HDL Line 归因不可信（随机指到并发进程）。
- 修复: 一切 `%s` 目标改 packed 向量（`reg [511:0]` 等）承接，再 putc 逐字节转 string（putc 构建路径实证安全）；字符串比较/分类也禁 `substr`/`==`（见下条）。
- 预防规则: xsim TB 里 `$sscanf`/`$fscanf` 的 `%s` 一律只写 packed；需要 string 只经 putc 从 packed 构建；面表/指令表等机读文件优先 `$readmemh` 进 packed 内存字（layout2tb 出 .mem：{nb,off,name_hex} 256b/word），TB 零 fgets/sscanf 解析。
- 复发: 0

### [2026-10-22] vivado-sim: xsim 动态 string 的 `substr`/`==` 比较机不可靠——内容正确的串比较全假
- 症状: putc 从 packed 构建的 string 经装载路径实证内容正确（$readmemh 文件路径全部打开成功），但 `s.len()>=2 && s.substr(0,1)=="y_"` 与 `s=="heads_f0"` 全部返回假，致 exp 分类 130 片全错（金面误装活体区）。
- 根因: xsim 2025.2 动态 string 内部表示与比较算子实现不一致（同族堆缺陷的只读侧）。
- 修复: 全部前缀/等值分类改 packed 字节直判（`pt_mem[pi][191:184]=="y" && [183:176]=="_"`、`[191:128]=="heads_f0"`），名字保留一份 packed 副本专供分类。
- 预防规则: xsim TB 内禁对动态 string 用 substr/len/== 做任何语义判定；判字符看 packed。
- 复发: 0

### [2026-10-22] vivado-sim: xsim `$sscanf %s` 入 packed reg 单字符右对齐——`[15:0]` 装 "W" 得 0x0057 非 0x5700
- 症状: mnemonic 判 `t0_v[15:8]=="W"` 全不匹配，unknown-op FAIL 逐行爆出（op=0023/0057/0050）。
- 根因: xsim 的 %s→packed 对不足整宽的单 token 右对齐填（双字符 "PT" 在 16b 内左右同形恰好正常，掩蔽了该差异）。
- 修复: 单字符 token 判低位字节 `t0_v[7:0]`；≥2 字符全宽比较不变。判前先 `$display` 实值校准对齐方向，不臆测。
- 预防规则: 任何 %s→packed 的判读先用一跑打印实值确认对齐方向再写比较；跨 xsim 版本须复验。
- 复发: 0

### [2026-10-22] vivado-sim: xsim `#` 延时字面量超 32b 静默溢出——看门狗 `#20_000_000_000` 实延迟仅 ~70-150ns，boot 期即误炸
- 症状: 全局墙钟看门狗 wait(rst_n) 后 `#20_000_000_000`（意图 20ms=1M 拍）实际 ~2 个时钟即 $finish，报 `GLOBAL_WALL_TIMEOUT cyc=0 prog=0`；stage-1 的 `#2_000_000`（32b 内）从未暴露。
- 根因: 裸整数延时字面量按 32b 解释，20e9 溢出截断。
- 修复: `localparam time G5_WALL_PS = 64'd2_000_000_000_000;`（64b time 型）+#G5_WALL_PS；同时按真预算校值（20ns 拍 × 帧预算 100M 拍=2s，原值即使不溢出也不够三段全程）。
- 预防规则: 仿真延时 >2^31 ps 一律 time-typed 64b localparam；写看门狗值时顺手算"够几个帧预算"。
- 复发: 0

### [2026-10-22] vivado-sim: xsim 2025.2 拒裸 `+plusarg`，`-testplusarg G5_PARTIAL=1` 被 wrapper 拆断——`-f` 选项文件是唯一稳路
- 症状: 命令行尾 `+G5_PARTIAL` 或 `-testplusarg "G5_PARTIAL=1"` 均打印 usage 拒收；`-testplusarg G5_PARTIAL`（无值）可过但 `$value$plusargs("G5_PARTIAL=%d")` 匹配不到。
- 根因: xsim.exe 参数解析把裸 +token 与内嵌 = 值拆断（"Expected a switch but found 1"）。
- 修复: 写 `scripts/xsim_partial.opt`（每行一参数：snapshot/-testplusarg/G5_PARTIAL=1/-t/runall.tcl），`xsim.bat -f scripts/xsim_partial.opt` 实证可过且 = 值完整到达。
- 预防规则: xsim 批跑带 plusarg 一律 -f 选项文件；run_gate.bat 类封装留 -f 入口。
- 复发: 0

### [2026-10-22] vivado-sim: time-0 逐行 `$fgets+$sscanf` 磨百万行级文件触发内核保护 FATAL（~2s 墙钟）
- 症状: 8.5M 行面装载循环 time-0 无进时 grind，~2s 墙钟 kernel FATAL（同一 ~2s 签名，与 $sscanf-string 坑叠加时互相掩蔽）。
- 根因: xsim 对零时长超长系统调用循环有内核保护。
- 修复: `$readmemh(path, ddr, off, off+nb-1)` 带起止地址直落目标偏移，原生解析瞬时完成。
- 预防规则: TB 装载一律 readmemh（带地址窗口）；禁止 time-0 行循环解析大数据文件。
- 复发: 0

### [2026-10-22] vivado-sim: xsim 静默冻结核——先分「零时长自旋 vs 时间照走的活锁」再理论化；Exception-at-PC 日志 + 孤儿 xsimk 是指纹
- 症状: TB $display 停摆后三种形态互掩：(a) xsim.dir/<snap>/xsimcrash.log 单行 "Exception at PC 0x..." 重复数千条、主日志冻住；(b) 无任何崩溃日志、主日志同样冻住；(c) 加 `-tl` 跑时崩溃消失（但龟速）。杀 xsim.exe 后 `xsimk.exe`（编译出的仿真内核）成孤儿继续自旋烧 CPU、持锁 xsimcrash.log（日志文件删不掉=mtime 还在涨=有孤儿）。
- 根因: 两类底层完全不同：零时长无限循环（cyc 不涨，-tl 迹时间戳钉死同一 ns）vs 活锁（每拍 ~100-200ms 龟速、-tl 迹 20ns/步推进、20M 拍级超时按自旋速率折算数日=事实永不炸）。Exception-at-PC 是内核对某类进程异常的重试侧写，HDL Line 归因不可信（同 $sscanf-string 坑教训）；`(a)(c)` 两形态可在同一 bug 上依时序竞态分别出现。收案更正（同日 G5 bready 案）：17c-17e 曾按「从属时钟进程被摘调度」结案——错；真因是 TB 例化 bready 隐式网（引脚恒 z），从属「寄存器冻结」恰是其语义正确行为，寄存器活跃探针（对从属 clk 引脚加计数器）照走、层级读引脚值=z 才翻案。
- 修复: 诊断梯四步：①supervisor 双日志（主日志+xsimcrash.log）停滞即杀，杀后连 `xsimk.exe` 一起杀（wmic 按 commandline 含快照名过滤）；②截断型 plusarg（如 G5_SETUP_MAXW=N）前缀二分首挂指令（注意生成器跳过注释行，词号≠文本行号——先核对再设点）；③`-tl` 跑 30-40s 看时间戳：钉死=零时长自旋，步进=活锁；④BFM 握手等待超时从 20M 拍压到 ≤1k 拍，挂死秒级显形；⑤挂死取证必须含被挂从属的引脚级层级读（u_dut.…u_slave.s_axi_bready 直读）+ 对其 clk 引脚挂计数器对照全局 cyc——TB 侧信号值≠DUT 引脚值，z/0/1 一读便知布线洞还是调度洞。
- 检测门: 仿真 supervisor 脚本必备三件套：xsimk 孤儿清理 + 双日志停滞判杀 + 截断二分入口；BFM `while(!ready)` 类等待必须有千拍级超时牙。
- 预防规则: 任何「日志冻住」先跑 -tl 判形态再理论化；超时阈值按「自旋速率下也能秒级炸」选取，不按正常速率选取。
- 复发: 0

### [2026-10-22] vivado-sim: TB 例化端口名单边漂移生隐式网线——DUT 收不到激励、BFM 等 Z 永挂（活锁形态），xvlog 零警零误
- 症状: r12 G5 TB 声明 `reg s2_awvalid; wire s2_awready;` 而例化写 `.s2_axi_awvalid(s2_axi_awvalid), .s2_axi_awready(s2_axi_awready)`（8 处，含 rresp）——前 14 个 CSR 写全绿，首个 s2_axi 写（岛面表装载第 1 笔）后永挂：DUT 输入隐式网线恒 0 不应答；TB 等待的 wire 恒 Z，`!(Z&&Z)`=X 进 while 死等；时间照走=活锁（见上条），非 trace 跑 ~5.6 拍/s。
- 根因: Verilog 隐式网线规则——端口连接中未声明标识符自动生 1b wire；xvlog 2025.2 对 TB 内 implicit net 警告静默（编译 0 ERROR 0 警、implicit 字样 0 命中）；`s2_*`/`s2_axi_*` 混用命名肉眼难察。旧代码同挂点被误判为 $sscanf-string 坑，修串后原样复现才逼出真根因。
- 修复: 映射逐名对声明修正（sed 8 处）；修后同一笔写 5 拍 ack（cyc 66→71）；复扫 `grep -icE implicit` 全编译日志 0 命中。复发案补充：同批 8 处修复漏了第 9 处 `.s2_axi_bready(s2_axi_bready)`——第 1 笔写靠复位后 ready=1 窗口完成、bvalid 上升沿 TB 侧可见，第 2 笔因 awready 永不回升而挂；表象酷似「从属 B 通道时序异常/内核冻结」，误导 6 轮调试（BFM 重写×3、port-B force 绕避、内核退化理论），终审靠引脚级层级读 z 翻案。
- 检测门: 新 TB/顶层例化落地后 `grep -icE implicit <xvlog.log>` 必须 0；同簇信号映射名从声明块整簇复制；新 TB 首跑用截断 plusarg 过前 ~20 指令、确认每笔握手 ≤10 拍 ack；例化修复后必须机械全连接审计——脚本提取全部 `.port(id)` 标识符对声明集比对（多声明行 `reg a, b;` 要拆开），局部 sed 肉眼修复必漏（本复发即证）。
- 预防规则: 新 SV TB 文件头加 `` `default_nettype none ``、文件尾 `` `default_nettype wire `` 恢复（防影响后续编译单元）；端口簇一种前缀到底，禁 s2_/s2_axi_ 混用。
- 复发: 1（同日第 9 处 bready；见上复发案补充）

### [2026-10-22] vivado-sim: $readmemh 窄字行左补零——生成器位数不对齐使 op 段读 0、指令被静默跳过（探针假通过）
- 症状: G5 机器指令卷 tb_setup.mem 词为 64 个 hex 字符（op2+addr4+零50+data8）；手写探针生成器少拼 2 个零成 62 字符，$readmemh 按窄值左侧补零 → smem[255:248] 读 0x00 → 回放循环走「unknown op 0」非致命打印分支，两笔 P 写被静默跳过。6 组探针「全过」实为全没测，险些据此误判「文件尾内容影响行为=xsim 内核非确定性」。
- 根因: $readmemh 行值窄于数组元素位宽时左补零（值语义正确、字段布局错位）；非致命 $display 分支让「跳过」与「通过」在结果行上不可分辨；探针判据只看收尾 TRUNC 行，不看执行了什么。
- 修复: 生成器按位宽算字符数（op(2)+addr(4)+200b(50)+data(8)=64）；探针判据加「每词 op 直方图」或在装载后断言抽词高位段；unknown-op 分支改计数并收尾 FAIL（非零即败）。
- 检测门: 任何机器码/表 memh 生成后，先 $display 抽查首/中/尾词的 [255:248] 或关键字段与生成源一致再跑；探针实验的判据必须含「指令实际执行数」，防止空转假通过。
- 预防规则: 生成 memh 的代码里字符数用 `WID//4` 推导不手写常数；「unknown op」类解析异常一律计入失败，不允许静默继续。
- 复发: 0

### [2026-10-22] vivado-sim: 编译进 files.f ≠ 例化进 TB——集成 gate 呈报必须附被改模块例化路径行 + BMG 横幅条数对账
- 症状: r12 A1 集成 G7 case0/case9 "PASS 且 wallcyc 与改前逐字一致"被审计实锤为空转：files_g7.f 编入了 A1 V2.0 + axiwr BMG sim wrapper，但 TB 例化树里根本没有 m9_axi_wr（xsim 日志 BMG 横幅 11 条=旧实例全集 pptab/edgetab/jointab/wblk/w_g0/g1/x_g0/g1/lut_bmg/ycap/hbuf，无 axiwr）——仿真的是无 A1 网表，"逐字一致"正是"什么都没变"的直接解释。
- 根因: xvlog 对"编而不用"的模块零报错；files.f 挂文件只保证编译进 work 库，不保证例化树消费；呈报方把"与基线逐字一致"当强证据，但 +2 气泡律下全帧逐字一致本就反常——反常即线索，先疑覆盖而非信 RTL 无事。
- 修复: 呈报模板加两行硬字段：①被改模块在 TB 层级中的例化路径（grep TB 源文件确认命中）；②xsim 日志 BMG/实例横幅条数与预期条数对账（A1 后预期 12）。G7 不重跑，A1 集成证据由 G5 整图 TB 承担（G5 层级必须例化 m9_axi_wr A1 BMG 版且 y 写流/W 通道有逐字节比对面——y 写通路从未被 G2-G7 任何一梯覆盖）。
- 检测门: gate 日志落账前：grep TB 源 `m9_axi_wr|axiwr` 有命中；xsim 日志 BMG 横幅条数==预期；"与基线逐字一致"结果先查 TB 覆盖再宣告。
- 预防规则: 编译集（files.f）≠ 例化树（DUT hierarchy）；一切集成门呈报附例化路径一行，成本一行，防静默空洞。
- 复发: 0

### [2026-10-22] vivado-sim: xvlog 默认 V 模式编译 -f 列表——shadow 树 SV 合法空语句报 VRFC 10-2096 ERROR；unisim 原语须显式 -L unisims_ver
- 症状: 照记忆手敲 `xvlog -f files_g7.f`（无 flag）连炸：①ERROR [VRFC 10-2096] "empty statement in sequential block"（m9_cmd_issuer.v:1061 合法空语句 `;`），模块被 ignore；②xelab 静态细化报 DSP48E1 not found + 参数化 blk_mem_gen 模块 ignored → 快照建不起来。
- 根因: xvlog 对 -f 列表里 .v 文件默认按 Verilog 标准编译（空语句在 V 模式非法、SV 模式合法）；DSP48E1 等 unisim 原语不在默认搜索库，须显式 -L unisims_ver（-L unisim 为伴）。
- 修复: `xvlog -sv -f files_g7.f`；`xelab work.tb work.glbl -s sim -debug typical -L blk_mem_gen_v8_4_12 -L unisims_ver -L unisim -timescale 1ns/1ps`。
- 检测门: 复用既有 xsim 证据树 files.f 前，先 grep 该树既往 PASS 日志的 `Running: xelab.exe` 行，flag 集与本次命令行逐字对账；编译日志出现 "Analyzing Verilog file"（而非 SystemVerilog）即停。
- 预防规则: xsim flag 集以该证据树既往 PASS 日志的 Running: 行正典为准，不得凭记忆缩减；.f 列表不含语法模式信息时 -sv 是安全默认。
- 复发: 0

### [2026-10-22] vivado-sim: 无反压脉冲写 FIFO 的差分探针，激励占空比不构成合法域证据——必须以黄金 gauge 节流 + FAIL 域锁存挂起比较 + quiesce 预算按排空速率×峰值深度核算
- 症状: m9_axi_wr 探针三连伪 FAIL：①T1 高占空随机流把**黄金参考自身**推进 fill≥512 FAIL 域（实测 ref_fill 冲到 671/1023），差分比较 FAIL 被误报为 DUT 缺陷；②1 拍 flush 脉冲 quiesce 后 "busy stuck"（滞后 DUT 错过脉冲窗口，V1.0 的 ST_AW 窗口同理）；③quiesce guard 5000 拍对 ~480 深、1 字节行排空速率 0.083B/cyc 的队列只差 800 拍 → 双侧齐报 stuck（当时还以为硅 bug，实为预算不足）。
- 根因: 探针合同三漏洞：把"占空比< drain 速率"当支持域担保（跳线走法 1 字节行让 drain 掉到 0.083B/cyc，均值论证失效）；FAIL 域 NOTE 承诺"挂起比较"但 scoreboard 没实现；quiesce 预算拍脑袋 5000，没按 峰值深度×每字节排空拍 核算。
- 修复: 激励写门控 `ref_fill<480`（T6 hold 期 <505），黄金 gauge 即合同节流阀；fail_domain 锁存 + fd_now 门控全部 equality chk（入队/弹出照跑保 quiesce 对账）；quiesce 持 flush 至排空（生产合同），guard=40000=480×12+余量。
- 检测门: 探针申报 PASS 前 grep 日志确认：无 "FAIL-DOMAIN entered" 出现在支持域测试里；每个 quiesce 正常退出（无 QUIESCE-STUCK）；超时类 FAIL 先算 `guard ≥ 峰值fill×最差每字节排空拍` 再怀疑 DUT。
- 预防规则: 无反压面的深度 FIFO，激励节流永远挂在**黄金内部 gauge**（不是外部统计）；NOTE 承诺的语义必须在 scoreboard 代码里找到对应门。
- 复发: 0

### [2026-10-21] vivado-sim: TB 在 negedge 用 while 轮询 ready 电平 = 晚整整一拍错过握手窗口，AXI 假死锁（xsimk 100% CPU、仿真时间照常推进、零输出挂 8 小时）
- 症状: t1_label_osd 门仿真 G1 像素帧 0 mismatch 通过后 axi_read 永不出数——xsimk 单核 100% 烧 8 小时，日志除首行外零输出，watchdog 到时正常触发（时间推进正常）。加逐拍 $display 后确认卡在 `while (!s_axi_arready)`，arvalid=1 arready=0 永恒。
- 根因: TB 任务在 negedge 用 NBA 拉 valid，从机的 ready/accept 全在 posedge 寄存；master 下一个 negedge 才来轮询 ready 时，**握手早已在两者之间的 posedge 完成、ready 已被从机拉低**——等 ready==1 的窗口只有半个周期，轮询永远落在窗口后。零输出+时间推进+CPU 满额 = 有进程永久阻塞在等一个不会再来的电平，时钟类 always 照常跑。同型 bug 藏了整轮回归：run1 因 checker bug mism≠0 跳过了 axi_read 才偶然打印，run2/3/4 全部静默死。
- 修复: TB 握手改为"驱动 valid → 过一个 negedge（accept 必已在中间 posedge 完成）→ 撤 valid → 等响应通道电平"；响应通道（bvalid/rvalid）是从机保持到 bready/rready 的电平，可以安全轮询。加 while 迭代上限 + DEADLOCK $finish 探针。
- 检测门: AXI TB 任务里出现 `while (!xxxready) @(negedge clk);` 即为可疑；跑门仿真前先确认该从机 ready 是否"握手即撤"型。仿真挂死诊断正典：watchdog（纯 #delay）能触发=无零时间死循环，逐个阻塞点加 $display 二分。
- 预防规则: 电平轮询只用于从机"保持到被取走"的信号；对"握手即撤"信号，master 侧用同拍采样或"驱动→等一拍→撤"模式，禁止事后追 ready。
- 复发: 0

### [2026-10-21] vivado-sim: TB 期望模型与 DUT 打包公式用 `+` 拼接位域 = label≥16 时进位串位，DUT 对/TB 错各打五十大板
- 症状: G3 单独 FAIL、mismatch 聚在 label 21 第 24 行散点：DUT 显示 label 5+数字 9，TB 期望 label 21+数字 9。`32'd5 + (32'd9<<5)` 本意 label 21|digit 9，实际 = 293，[4:0]=5（21 的 bit4 借加法进位跑到 bit5 撞上 digit 域）。
- 根因: 位域拼接是 `|`（按位或）不是 `+`（算术加）——相邻位域无进位关系时两者同值，一旦低位域最高位为 1（label≥16），`+` 的进位污染高位域。TB 注释写 21 手滑写 5，更加一层转写错。
- 修复: 全部改 `label | (digit<<5)`；RTL/文档/TB/PS 打包同一公式。
- 检测门: RTL 打包/解包审查grep `[+(]<<`；TB 里凡是 `a + (b<<N)` 形式断言 a < (1<<N)。
- 预防规则: 位域组装永远用按位或；用加法先证明无进位可能并写注释。
- 复发: 0

### [2026-10-20] vivado-sim: TB 同步激励极性与硅上真实驱动源不一致——门全过、上板全哑（GBOX 输出反极性 sync）
- 症状: 文字 OSD v1/v2 xsim 六门全过（30720 checks PASS），上板 AXI 寄存器读写全对但画面一个字都没有；同链框 OSD（GBOX）正常。
- 根因: 模块消费 pix_frame_display 的**寄存器输出**做行场计数复位，而 GBOX `hdmi_hsync <= ~vio_hsync`（反极性：idle 高、行首一拍低脉冲）；RTL 写 `else if (vio_hsync) h_cnt<=0` 在硅上=每拍复位→h_cnt 永冻 0→v_cnt 不增→文字永不画。TB 却把 hsync/vsync 建模成 active-HIGH 脉冲（仿 vid_out 原始时序），与模块硅上真实输入（GBOX 反相输出）极性相反——激励建模错了对象。GBOX 自己消费 vid_out 原始 active-HIGH 时序所以它的同名写法是对的：**同一信号名在不同模块输入端的真实极性可以不同，必须追驱动链。
- 修复: RTL 计数器改 `else if (!vio_hsync)`（低脉冲复位）；TB 激励改 idle 高/行首低脉冲（GBOX 极性），门重跑全过；且新激励对旧 RTL 必炸（h_cnt 冻结→G2 FAIL），回归有效。
- 检测门: 写 TB 激励前先从 BD 追该模块同步输入的驱动链到源头，逐级确认有无取反（`<= ~`）；门过但上板哑火时第一项复查=TB 激励极性 vs 驱动链真实极性；对比法：v1 硅上寄存器全对+ROM 综合日志 readmemh 成功+GBOX 正常 ⇒ 缺陷必在像素域时序语义。
- 预防规则: 像素域时序 TB 一律按"直接驱动 DUT pin 的真实波形"建模，不按上游某级波形建模；消费寄存器/反相输出的计数逻辑复位条件用显式低脉冲并头注驱动源极性。
- 复发: 0

### [2026-10-20] vivado-sim: TB packed-string 字节序——右对齐字面量首字符在最高字节，s[8*(k+1)-:8] 拆字必反序
- 症状: 文字 OSD 门 G4/G5 fail：DUT 侧渲染正确（AXI 按序写 'H','i'），TB golden 却期望镜像串 "iH"，双字门像素大面积 mismatch；单字门 G2 "A" PASS（反序不可见）。
- 根因: Verilog 字符串字面量赋给 `reg [8*N:1]` 为右对齐且**首字符占最高字节**："Hi" → s[16:9]='H'、s[8:1]='i'。TB 按 `s[8*(k+1)-:8]` 取"第 k 字"实际取到倒数第 k 字，nchar≥2 时模型串整体反序。
- 修复: `m_str[k] = s[8*(nch-k)-:8]`（k<nchar）；改后 G4 "Hi"/"A A"、G5 全 PASS。
- 检测门: TB 用 packed string 喂 golden model 时，门里必须含**非对称多字串**（"Hi"/"A A"），并在 set 后 `$display` 回显逐字 hex 对照预期；"AA" 这类对称串不能当多字证据。
- 预防规则: TB 拆 packed string 一律显式按右对齐字节序取字；凡"单字 PASS、多字 FAIL"的图形错位指纹，先查字节序再查 RTL。
- 复发: 0

### [2026-09-23] vivado-sim: xsim 三段式正典 + MCP launch_simulation 必炸
- 症状: MCP 会话里 `launch_simulation` 报 Spawn failed（与 PATH 无关）。
- 修复/正典: MCP 内直接 `xvlog`/`xelab`（须 `库名.顶层` 前缀）/`xsim` 三段式。
- 预防规则: 仿真主证 = xsim + 真 IP；MCP 里永远不点 launch_simulation。
- 复发: 0

### [2026-09-23] vivado-sim: TB 等待/ack 任务落定居拍 + BFM 禁止逐拍 new[n+1]
- 症状: 仿真挂死或竞态。
- 修复: 等待/ack 任务在时钟进程内落定居拍；BFM 一次分配数组后驱动。
- 预防规则: 写 TB 前先复读本两条。
- 复发: 0

### [2026-10-18] vivado-sim: BMG "无写使能却内容变化" 三角取证正典（M10.3 X1 假腐坏案）
- 症状: desc BMG 字 448 双口同读 0x114（磁盘 hex 为 0x112），引脚 wea 全运行采样恒 0，无运行期写、无 collision 打印，表象=完美"存储腐坏"。
- 根因: 非模型缺陷。BMG v8.4 行为模型 write_a 仅在 `wea_i=WEA`（引脚）时写 `memory[]`（阻塞赋值+字节 RMW），双 always 块同拍无竞争；C_COMMON_CLK=0 双块同窗仅影响同址读写可见性。"内容变"实为**加载期写数据本身就是错值**（上游 TB 数据源错），读回校验与加载同源（同一 rom 数组）使错包也能"回读全对"，假象自我一致。
- 修复: 三角取证一轮定案——①引脚级 wea/addra/dina 全运行采样阱（含加载期 addr 窗口打印）；②`dut.u_xxx.inst.native_mem_module.blk_mem_gen_v8_4_12_inst.memory[addr]` 层级直读（层级名从 BMG collision 警告的 %m 输出直接取）；③加载后/启动后/+4k 拍/停滞前三~四检查点 ARRPROBE 直读。三者交叉即区分"写数据错 / 运行期被改 / 读路径错 / TB 选错文件"四类。
- 检测门: 任一"表内容异常"先跑三角取证再动 RTL；层级路径可从 `blk_mem_gen_v8_4_12 collision detected` 行的 Instance 字段截取。
- 预防规则: 岛级表类调试标配三角取证设施一轮跑完出真相；"内容变了但没人写"的第一嫌疑是数据源选错而非硬件腐坏。
- 复发: 0

### [2026-10-26] board: WO 寄存器读回空转观测——LD_DATA 读出恒 0 与 BRAM 内容零相关，一次观测预算被烧未获任何信息（R150 更正①新类，g7 实案）
- 症状: g7_obs.py 写 LD_SEL/LD_ADDR 后读 LD_DATA 期望取表字，读出恒 0
- 根因: LD_DATA 是 WO（write-only）CSR，读出恒 0 属规范行为，与表 BRAM 内容无任何数据通路；观测脚本未做读口语义审查
- 修复: 观测作废（无修补对象）；表内容落账分辨只可走窄读 0xE9/0xEA 臂取 tbl 字 bits[31:8] 对卷面词（D1 铁采②）或 PL 侧 ILA——**禁用任何 WO 读回当内容证据，再犯即本类新案**
- 检测门: 观测/呈文设计先过"读口语义审查"——CSR 图分 RO/RW/WO 三态，WO 一律禁读；凡以 WO 读回支撑的内容性结论一律拒收
- 预防规则: 观测预算门（一次）触发即停呈换新观测方案，不得在同预算内塞 WO 空转观测凑数
- 关联: R150 §2 更正①；G7 观测预算已烧，表落账状态=未知（非"已证装载"亦非"已证空"）
- 复发: 0

### [2026-10-26] process: 台账已知类消费门失牙——DE 窄写不可靠自 R141 已入册，prep/run 驱动设计仍排半字写（R151 审计追加条）
- 症状: A8 板窗 prep/run 驱动对 0xDE 排半字写（lanes[3:2]），尽管"DE 窄写值落错位"自 R141（2026-10-25）已是台账在册已知类
- 根因: 台账预防规则只有"写条目"侧，无"消费"侧——后续驱动/脚本设计评审不强制核对台账已知类，已知缺陷在新制品中复发
- 修复: R151 裁定驱动改全字写+写后读回断言（RO 读臂 L946 在，读回应=写入值）
- 检测门: 驱动/脚本设计评审必过"已知窄写类核对"清单（台账检索窄写/halfword/byte 类逐条问"本设计有没有踩"）；板端驱动凡写窄口寄存器必配写后读回断言
- 预防规则: 新驱动/脚本/TB 设计稿定稿前强制台账已知类核对并留核对记录；核对记录随呈件
- 关联: R141 条目 DE 格（本案伏笔源）；缺陷B 修面裁定 §3
- 复发: 0

### [2026-10-26] rtl(候选类): 0xEA 表读臂家族第六成员候选——首次真 exercise 返回 erratic 数据（0xFF 掩码签名+零漂移），判别器待 run02 定性
- 症状: D0 重放 0xEA 读臂首真 exercise：PPP word≥1 读回 0（10 行 FAIL），grp5 PPP word0 读出 0x00000031=expected&0xFF 签名；EDGE/JOIN tbl_verify 的 PASS 全为 expected=0 虚过（审计按表统计 nonzero_expected=0），即 D0 全部表内容实测仅 PPP 10 词+PAGE 2 词
- 根因（两假设待判别）: ①读臂罪——0xEA 读数据通路位片/掩码错（历史上硅上字对齐律不可达、既往 sim 全走层级/tbl_rd 旁路，本次首次真 exercise 即 erratic）；②内容缺罪——FSM 提交路径第三缺陷（PPP 未落账，重大另案）
- 修复: 无（判别前禁动手）；run02① 判别器=直驱 tbl_rd 口或层级 BRAM 直读取 PPP 真值（绕开 0xEA 臂）：内容在=读臂罪（本类转正=第六家族员坐实）；内容缺=FSM 提交路径第三缺陷另案
- 检测门: 凡表内容核验，0xEA 读臂读数不得单独作判定锚，必须 tbl_rd/层级直读交叉；tbl_verify 表须报 nonzero_expected 计数防虚过
- 预防规则: 长期不可达命令臂首次启用=按"新臂首评"fail-closed 对待，先离线判别器定性再上硅
- 关联: R151 §5 审计新发现入册；**D1 铁采②（板上窄读 0xE9/0xEA）挂起至判别器出结果**——若坐实读臂罪，板上内容核验改走 PPP 窗面/TBL 消费侧间接法，方案随 run02 重呈
- **run02 判别器裁决（2026-10-26，否证转正为清白）**：读臂无罪——arm 与门铃可见 bank 双路一致（word0 双 PASS、word1-4 双 FAIL=0），bank≠sent→内容缺在 BRAM 提交路径=根因C（见下条）；本候选关闭，第六家族不成立
- 复发: 0

### [2026-10-26] sim-products: 跨代制品借用危害——无字节使能代 RTL 配字节使能代 BMG 产物，1bit rm_we 零扩展接 wea[31:0]/[79:0] 每拍只提交 byte0（R152 更正：仅 replay 侧污染，硅上正身免罪）
- 症状: replay 侧表装载 cnt=8 err=0 全绿（丢失在 FSM 记账之下），BRAM 行内容只 byte0 落地——word0=0xb1 单字节"落地"假象、word1-7 全 0、word0 截断 0x…31；硅面表现不涉（见正身免罪注）
- 根因: run02 replay 的 filelist 三核制品借自 2026-10-08_yolo_m9_intra_run01 旧代产物（wrapper wea[31:0]/[79:0] L78 亲读），与当代 RTL（1bit rm_we）位宽不配→隐式零扩展只使能 byte0；xelab 仅 WARNING 无 ERROR=门失牙
- **正身免罪注（R152 审计现场取证）**: A8 硅上 bit 制品=merge_fsm_lock_run01 自身 .gen m9_bm_pptab.v L75 `input wire [0:0] wea`，1bit 对 1bit 对接正确；10-25 r63 bit 同；硅面 C3=0/21 由缺陷A（EE 字全 0x08 单页早退）单独完全解释。**"改 RTL 迁就陈旧制品"与"历史表恒零类翻案"双驳回**（历史 green 不被弹劾；翻案举证责任=先证某 green run filelist 真用了 32bit 制品）
- 修复: 无 RTL 改动（正身冻结）；replay 侧=制品源换本树自身 .gen（run03 照准）；run 目录副本的 3 行 wea 复制仅作机理反向确认，禁外溢为修复建议
- 检测门: 任何 replay/sim filelist 的 IP 产物必须本树本代 .gen（跨树跨代借用=本类现场）；位宽不匹配 WARNING 升级必查（显式扩展审查）；表内容核验 nonzero_expected 计数门防虚过
- 预防规则: sim 制品血缘钉入 run README（树名+代际+.gen 路径+sha）；装载"cnt 绿"只证记账面不证内容面
- 关联: D0/RUN02/RUN03 全链；0xEA 读臂候选条（判别器"内容缺"分支的本因=制品污染非正身缺陷）
- 复发: 0（run03 换正身后预期绝迹；复发即本类新案）

### [2026-10-26] sim-process: 看守判据盲区——"clk 照走"型跨模块握手活锁使 REAL_HANG（G5HB 输出停滞）判据失效（run01 db2/run02 db1 双实案）
- 症状: 仿真内核不死、时钟照走、输出静默停滞——run02 db1 conv5 cyc144484 冻结于 S_PPPW（st=41 等 ppu_done）79 组探针逐字 frozen；签名=walker 空闲（wfst=0）+节点读批欠 1（ck=143/xk=144）+serve 打满（hit=cap）+孤读 X 无响应；run01 db2（ck=575/xk=576）逐位同型=非单门铃偶发
- 根因: 看守 v3 以"输出停滞+探活无响应"判挂死，对时钟照走但内部状态机冻结的握手活锁失效；根机理方向=walker 读响应末笔丢失的跨模块握手活锁（精确站点在 PPU walker/dma 侧，未越树定性）
- 修复: 看守 v4=加 st/done 进度指纹（关键状态机 st+done 计数 N 拍无变化即判活锁 scoped kill）；活锁本体的站点解剖须扩树授权后另案
- 检测门: 看守判据必须覆盖"输出停滞"与"状态机冻结"双模式；长仿真关键 st/done 指纹采样落 CSV
- 预防规则: 跨模块握手设计评审必答"末笔响应丢失"场景（req/ack 计数对账）；仿真看守升级不得迟于第二次同型活锁
- 关联: run01 db2 活锁/run02 db1 conv5 活锁；下呈批轮待办②
- 复发: 1（跨 run 同型两次，v4 未落前仍开放）

### [2026-10-26] rtl: 单拍判决吞没型活锁+配置面 tie-off 静默失锁双缺陷叠加（run03 干净制品基线活锁复发实案，预授权解剖相闭合，D1/D2 修复呈批面）
- 症状: db1 conv5（全图首个 paged PPP 派发）cyc 144484 冻结 S_PPPW（st41 等 rp_done），clk 照走型活锁；run02 污染基线同周期同转移曾判"症状面"，run03 干净基线（三核本树 .gen 1bit wea，编译告警归零）复发=真实 RTL 缺陷
- 根因 D1（配置面静默失锁）: M11 repack 配置面恒 0——m9_intra_axi_top_v3 L404 `rp_arm=1'b0` tie-off（SPEC §8 OPEN-1/2 惰性载体未闭合）→ paged SPPF 锚点 rp_start 判 err 0x02 RP_ERR_NOT_ARMED 粘着，**rp_err 未连接=完全静默**，rp_done 永 0
- 根因 D2（判决无锁存）: issuer S_PPPW 的 `paged_w && !rp_done_g` 空转分支吞掉 walker 单拍判决脉冲（cyc 368657 ppu_done=1/ab=0 到达，当拍 rpdone_g=0，无锁存）→ 岛内全归 idle 而 issuer 永驻 S_PPPW
- 反向确认（C1，TB 副本 force rp_done_i=1，issuer RTL 一字未改）: 同一 368657 判决拍，368658 st41→39 即刻消费、368660 重门推进 PPP 链、desc1 岛内核行——rp_done=唯一缺失令牌，机理链闭合；add_engine+dma 隔离对/walker+shell 最小环双双 PASS=PPU 消费层无罪
- 修复: 未实施（正身冻结呈批面）；方向=repack 配置真源闭合（D1）+S_PPPW 判决锁存化（D2），建议同修后走新 bit 线+run04 重放
- 检测门: 跨模块单拍脉冲判决必须锁存或有握手机制（状态机空转分支设计评审必答"判决丢失"场景）；tie-off 常量审查其错误输出是否连接（未连接=静默失锁类）；SPEC OPEN 惰性载体项必须带闭合期限与载重评估（本案 OPEN-1/2 躺过三轮硅窗）
- 预防规则: "clk 照走+输出静默"型挂死第一动作=关键状态机 st/done 指纹采样（看守 v4 已实证有效）；单拍判决线全树盘点（grep 脉冲式 done/verdict 接无锁存状态机分支）
- 关联: 看守盲区条（v4 实证 LIVELOCK_FP@7.47M+SCOPED_KILL_CLEAN）；制品借用条（run03 血缘三行钉 README=新预防规则首落地）；装载面 4/4 全绿 tbl_verify arm/bank 双 PASS（nonzero_expected 5/6/6/6，fail_nz=0）=干净基线表真值落账首证
- 复发: 0（修复呈批前仍开放）

### [2026-10-26] docs: RTL 头注引用漂移——头注引"SPEC §8 OPEN-1/2"但现行 SPEC v3 全文无此编号，溯源失锚（R153 审计查证）
- 症状: m9_intra_axi_top_v3 L404 头注"r11 裁惰性载体 SPEC §8 OPEN-1/2"，审计查现行 SPEC v3 全文无 OPEN-1/2 编号、§8 无此目——引用悬空，惰性载体的原始裁定语不可达
- 根因: OPEN 项销项/改版时头注未跟随重锚；惰性载体无闭合期限（与"单拍判决吞没"条 D1 同宗：挂账无期的必然漂移）
- 修复: D1 设计件重锚现行 OPEN 挂账项或按实测出处律入 SPEC 新章；头注引用格式强制带 SPEC 版本+条目名+日期
- 检测门: RTL 头注引用 SPEC 条目时，呈批面 grep 现行 SPEC 确认编号存在（悬空引用=本类现场）
- 预防规则: SPEC 改版/销项时全树 grep 被引编号逐条重锚；禁裸编号引用（无版本无日期=漂移温床）
- 关联: 单拍判决吞没条 D1（本漂移的实害载体）；SPEC 单独立章律
- 复发: 0

### [2026-10-26] process: err 码分配普查抽样化——人工列占用集漏实占段，须机验全表（grep err<= 全部赋值点）才准分配（D1D2 实施门实案）
- 症状: 审计全表普查 issuer err 占用={1,6,7,8,9,0x20-0x26}，据此裁分配 0x02-0x05；实施面机验 grep err<= 全部 20 处赋值点发现 0x02-0x05 实占 4/4（L1379/L1395/L1407 err=2、L1422 err=3、L1435 err=4、L1457 err=5，全为活跃错误面非死码）——实占全集={0x01..0x09, 0x20..0x26}
- 根因: 普查方法=人工列目（抽样/枚举 E_* 宏），漏非宏字面赋值点；正确法=机验全表 grep `err\s*<=` 逐点登记
- 修复: fail-closed 停呈生效（RTL 零改动，碰撞证据 err_code_table_check.txt 留证）；再裁定须同时答两面=issuer 新码段（候选 0x0A-0x1F，0x10-0x13 需另核 E_CHAIN 组合面）+repack rp_err_code 原生 0x01-0x05 呈现策略（直通不可分=与 issuer {1..5} 全面重叠，须重映射或换段）→ **R155 已裁两面**：新段 0x0E-0x12（映射 UNSEALED→0x0E/NOT_ARMED→0x0F/GEOM_LANE→0x10/GEOM_ZERO→0x11/BUSY→0x12）+呈现=连接点重映射（L738 空挂点 `rp_err_mapped = rp_err_w ? (rp_err_code_w + 8'h0D) : 8'h00`，repack 正身一字不动）；顶层面 E_CHAIN OR 组合实占 0x0A-0x0D（0x10-0x13 悬空担忧解除）
- 检测门: 任何 err 码/错误码分配裁定，附机验全表（grep 赋值点清单）非人工列目；跨模块错误码直通前必查两码表重叠
- 预防规则: 码段分配=稀缺资源，分配门=机验全表零碰撞证明；审计侧普查同样适用本门（本案审计普查漏列被实施门拦截=双门设计的正确性实证）
- 关联: D1D2 同修设计件 §2/§7（碰撞 fail-closed 条款激活实案）
- 复发: 0

### [2026-10-26] process: 设计件偏离旗标律——实施侧偏离已批设计件形状时须在偏离点即旗标，禁终报一次性自曝（R156 纪律条）
- 症状: D1/D2 实施中几何配置面维持 tie-off 未接线（对设计件 §1 形状的保守收窄），代理终报才自曝——审计定性合法（豁免：fail-closed 未破+方向保守+自曝）但立纪律：今后偏离须在偏离点即旗标
- 根因: 实施代理无"偏离即旗标"内建门，靠终报自曝=审计/主会话失去过程中介入窗口
- 修复: 纪律条入册：实施代理任务书强制"任何偏离已批形状的决定=当场记录偏离旗标（偏离点/理由/依据律/影响面）到 run 目录 deviation_flag.md 并继续，终报汇总引用"
- 检测门: 实施 run 的 deviation_flag.md 存在性检查（无偏离=空文件声明"零偏离"）；审计呈件面核对偏离旗标与终报自曝一致性
- 预防规则: 设计件批次呈批时把本律写进实施任务书；偏离旗标=新呈批面入口（旗标不自动=批准，重大偏离仍须停呈）
- 关联: err 码普查条（同期 fail-closed 双实证轮）；D1/D2 同修全链
- 复发: 0

### [2026-10-26] sim-process: 观测归档缺口——每相清日志覆盖前相，观测证据只可追最新相（R157 纪律条）
- 症状: run04 观测相日志每相启动清空/覆盖前相，审计复盘只能看到最后一相，前相观测证据缺口
- 根因: 相位脚本日志以 > 覆盖写而非 >> 追加写（或同路径重复打开），相位间无独立命名
- 修复: 各相日志**追加保存不覆盖**（或 per-phase 独立文件名），wdb 大件同样保留（obs-B 482MB 保留令同条）
- 检测门: run 收官 manifest 覆盖全部相位日志（缺相=归档缺口现场）；审计呈件面抽查前相可读性
- 预防规则: 多相仿真/板窗脚本一律追加写+相位时间戳；收官前相位清单核对
- 关联: R157 obs-B 独立观测线条件①③；看守盲区条（观测力纪律同族）
- 复发: 0

### [2026-09-23] vivado-sim: xsim 函数读 memory 挂连续赋值永不重估
- 症状: 卡 X。
- 修复: memory 读只能放时钟进程过程式读。
- 预防规则: `assign` 右侧禁函数读 memory。
- 复发: 0

---

### [2026-10-22] vivado-sim: 经 AXI-Lite 写面构造 dirty 门铃在 0/1/2 拍偏移下不可能——握手间距律（r12 G7BELL 探针实证：门铃 wr_go 比最后一笔表写晚 ≥12 拍，回填只需 3 拍）
- 症状: r12 trap 包 CASE=3/4/5（门铃-dirty 竞争 0/1/2 拍）三臂 wallcyc 完全相同（1023511），疑全部退化为净门铃；G7BELL 探针打印实证门铃 wr_go 拍 win_rdy=1、距末笔表写 12-13 拍。
- 根因: AXI-Lite 两次写事务的最小 wr_go 间隔由握手决定（aw/w 接收→bvalid→下一笔 aw/w，≥4 拍），且 TB/PS 在 bvalid 返回后才发下一笔；窗回填 dirty→filling→win_rdy 全程仅 3 拍 → 任何合法门铃必然落在 win_rdy=1 之后。pending 锁存的真实调用方只有中帧页 bump 窗跌落（~3 拍）与复位后未填窗。
- 修复: dirty-bell 竞争改到真实场景构造——页 bump anchor+1 拍重摇门铃（win_rdy=0 实证），验证 pending 锁存 + 重发拍被 busy issuer 吸收、帧仍逐位 PASS（CASE=8）；间距臂保留为净门铃回归。
- 检测门: 凡「写后 N 拍内触发 X」类竞争测试，先用握手间距账证明 N 拍内可达（门/握手级探针打印为证），构造不了就改构造真实场景，不得把退化臂当竞争覆盖申报（F1 申报纪律同源）。
- 预防规则: AXI 握手间距 ≥ 内部 FSM 恢复时间的竞争构造一律先算间距账再设计 case；竞争覆盖的声明以探针打印的真实状态（本例 win_rdy@bell=0）为准，不以意图拍数为准。
- 复发: 0


### [2026-10-22] vivado-build: 同会话重 source 构建 tcl 时标量变量跨 source 存活——`info exists` 守卫不重初始化，改钉不生效（r12 DSP 门 want=91 僵尸值实证）
- 症状: r12 build tcl 的 DSP 钉 91→90 已落盘（三处实核），但同会话第三次 source 仍报 `dsp=90 want=91`——文件改了、行为没变。
- 根因: tcl 顶部 `if {![info exists V2B_DSP_REF]}` 初始化守卫只在变量不存在时生效；同 Vivado 会话上一次 source 已把 V2B_DSP_REF=91 写进会话级标量，后续 source 守卫跳过 → 僵尸值压过新文件默认。array-set 合并律的标量版（r12 第 2 集 array set 会话残留同族）。
- 修复: 会话内 `set ::env(V2B_DSP_REF) 90; unset V2B_DSP_REF` 后再 source（tcl 自带 env 覆盖通道）；或重 source 前统一清点 tcl 的自建标量并 unset。
- 检测门: 同会话重 source 构建 tcl 后，第一条门输出仍报旧钉值 = 标量存活嫌疑；门日志的 want= 值与盘上 tcl 默认值 diff 一行即可判定。改钉类修复的验收标准 = 门日志里的新值实证，不是文件 diff 实证。
- 预防规则: 凡「同会话多次 source 同一构建 tcl」，改钉后必须 unset 对应会话标量或走 env 覆盖；验收一律以门的运行时输出值为准。
- 复发: 0


### [2026-10-22] vivado-build: tcl 路径变量拼接缺引号——单词上下文合法、expr 上下文首执行才炸（r12 build tcl L932 `$_eread ne $R12R/r12_e3_lock.tcl` 实证）
- 症状: r12 第五次 source 在 E3 钩读回门炸 `invalid bareword "r12_e3_lock" in expression "$_eread ne $R12R/r12_e3_lock.tcl"`；同表达式形态的路径拼接（L927/928/930）在括号命令上下文（单词语义：`$R12R`+字面后缀拼接）却完全合法。
- 根因: `$VAR/literal` 在命令参数上下文=变量替换后拼接（合法），在 expr 上下文（if 条件）=除法+裸词（必炸）——同一写法跨上下文合法性不同；且该代码块此前从未被执行（run01 第 3 集走的是带引号的 resume 副本，build 版八连 source 止于更早的门），latent 到首执行才现形（静态检查/词法平衡均看不见）。
- 修复: expr 上下文一律 `"$VAR/literal"` 引号包裹（与 resume 正典对齐）+ _brace_tcllex 四 tcl 干跑 depth=0 后重 source，原爆炸块干净通过（E3_LOCK_SET 运行时行实证）。
- 检测门: 改钉/改表达式后的验收一律看运行时门输出（见 62ed8eae 条验收标准），不以文件 diff 或静态检查为证；全仓 grep tcl 里 `ne $[A-Z]`/`== $[A-Z]` 后随 `/` 的 expr 用法，凡缺引号即修。
- 预防规则: tcl 里凡变量+路径/字面拼接进入 if/expr 条件必须加引号；「首执行才炸」类 latent 的唯一防御 = 干跑律（构建 source 前独立干跑）+ 门日志逐行读。
- 复发: 0


## rtl

### [2026-11-03] rtl: ROM 数据文件索引基址与 RTL 寻址不一致（0x20 偏移）+ TB 期望值同源自洽——全链仿真 PASS 仍上屏乱码
- 症状: COCO/pose OSD 文字上屏异常：名字区不可见、补位区呈 '@' 串（数量随名字长度变，"keyboard"=7 个），两位分数数字显示成错位大写字母（"40"→"TP"、"28"→"RX"）；像素级仿真（COCO 8840、POSE 6415 检查，奇数行强制覆盖）与负向对照全部 PASS，综合日志 `readmemh ... read successfully`，零警告零违例。
- 根因: `osd_font32.hex` 生成时从 ASCII 0x20（空格）起连续排槽（file[k]=glyph(k+0x20)），RTL 却用原始 ASCII char_code 直索引 `font_rom[{char_code,…}]` → 基址错 0x20：小写名字 0x61-0x7A 落入未定义槽（黑底空白，看似"名字乱码"），coco80.hex 补位空格 0x20 命中 glyph(0x40)='@' 槽（'@' 串真身），数字 0x30-0x39 命中 'P'-'Y' 槽（分数变字母）。TB 的 exp_font 与 DUT 加载同一文件、同一地址公式 → 错位自洽，任何像素比对都 PASS；check_char 只验 char_code 的 ASCII 值（正确）不验字形身份。
- 修复: 字表重排为 ASCII 直索引（new[k]=old[k-0x20]、前 0x20 槽清零；五活动副本 SHA 齐一 `536ce292…`；11-01 历史运行目录副本保留旧表以保全证据链）；两个 TB 新增 GLYPH_IDENTITY 门——'T'/'0'/'k'/'P' 四字模硬编码，独立于加载文件（COCO/POSE 仿真 PASS 含 GLYPH_IDENTITY_PASS）。
- 检测门: 字体/查找表类 TB 必须含硬编码字形身份断言（≥3 个已知字模按 ASCII 直索引核对，独立于被加载文件）；**期望的推导链必须独立于 DUT**——数据面禁止与 DUT 同源加载同一文件作唯一基准，几何面（h/v→cell/row/col、sel_char/sel_glyph_y/sel_bit 一类）禁止回读 DUT 选择寄存器自证，必须由原始 h_cnt/v_cnt 计数器 + 规格公式另行推导（复发 2026-11-03：pose 标签 `>>3` 半字形布局下，TB 回读 `char_code/sel_glyph_y/sel_bit` 作期望索引、探针坐标又按坏布局标定 → 6415 像素检查全 PASS 而屏上半字形乱码；且检测坐标点本身按被测布局校准会随布局一起错）；只改 hex 内容时同样必须显式 `reset_run <bd>_<mod>_0_0_synth_1` 并核对模块 DCP SHA 变化（hex 变更与 .v 变更一样不触发 module_ref OOC run 失效，见 vivado-bd 2026-11-02 条）；负向对照必须用旧缺陷 RTL+新 TB 真实 FAIL 首像素才可宣布门有牙；OSD 显示正确性的人眼/实拍收口不可用仿真 PASS 替代。
- 预防规则: ROM 初始化文件与 RTL 的索引基址约定必须成对文档化；TB 期望值（数据面与几何面）一律独立于 DUT 推导。
- 复发: 1（2026-11-03 pose 标签 16px 字符格几何 `>>3`→`>>4`，TB 几何期望回读 DUT 自证，检测门强化为上面黑体三律）

### [2026-10-27] rtl: RGB565 双 PCLK 像素流漏用 vid_ce——显示正常而识别 ROI 按字节计数并退化为空白特征
- 症状: OV5640 显示/VDMA 路径正常，识别板上 Pool 却可与全空输入逐字相同；定向 TB 对 112×112 中央黑块实测 `valid=25088 black=0`，预期 `12544/12544`。
- 根因: RGB565 每像素占两个 PCLK，源端以 vid_ce 标记有效像素；显示路径使用了该使能，识别灰度/ROI 前端却仅用 vid_active 推进横纵计数并产生 roi_valid，把字节时钟误作像素时钟，导致 ROI 坐标、有效像素数和后续帧边界全部错位。
- 修复: 灰度前端新增 vid_ce，统一 `pixel_valid=vid_active&&vid_ce`；横纵计数和 roi_valid 只由 pixel_valid 推进/限定，行内非 ce 字节拍保持 h_cnt，只有 vid_active=0 时清零。修复后同 TB 为 `valid=12544 black=12544` 并输出 `CAMERA_ROI_PIXEL_ENABLE_TEST_PASS`。
- 检测门: 运行 `run_camera_roi_pixel_enable.ps1 -PixelEnable`，同时硬查 PASS 标记和 `valid=12544 black=12544`；BD/wrapper 另查 `cam_captrue_data/vid_ce -> 识别前端/vid_ce` 实际连接，禁止只看 RTL 端口声明或显示画面正常。
- 预防规则: 多时钟周期像素接口的计数、坐标、ROI、写使能必须统一受像素资格信号约束；同一源显示正确不能证明旁路识别前端采样正确。
- 复发: 0

### [2026-10-26] rtl: 协议异常未进当拍 strobe 组合门——issuer hang 误发射/误0F，glue DONE+abort warm/start 泄漏
- 症状: RP 缺失 RLAST 后，issuer WARM 在 watchdog 前进入 HALT/0x0F、START 在 `pf_hang=1` 当拍仍 `rp_start=1`；glue 在 PF_DONE/已 warm 后接收 abort，实测 `warm=1 fault=1 start=1`。只覆盖 clean/explicit-fault 的矩阵曾全绿，未触达这些路径。
- 根因: 异常只参与时序资格/错误寄存器，未完整进入 `arm/start/warm` 当拍组合封门和状态机消费；NBA 拍末才置 fault 或清 shadow，另一时序分支仍可读取旧 warm/armed 并发射，显式资格错与协议挂死也因此混码。
- 修复: issuer 的 arm/start 输出加入 `!pf_hang`，四个 RP 状态单设 hang 保持至精确 watchdog 0x07；glue 的 live warm/start 以当前及粘着 abort/fault/hang 组合封门，DONE warm 更新纳入当前 abort，异常清 armed shadow。
- 检测门: 分别在 WARM/START 注入 hang，并在 DONE/已 warm 的 legacy/paged 两形注入 abort；逐拍断言无新 arm/start/ppu_start/warm，hang 最终0x07、abort fault保持，另验reset。脚本同时 grep PASS 与 FAIL/VIOLATION，禁以 XSim 返回码代替功能判据。证据=`4_metrics/logs/2026-10-26_bline_r163_audit_run01/c6_fix02_recheck/`、`axi_fix_recheck/`。
- 预防规则: 每类协议异常必须显式区分“立即显式错误”与“保持待 watchdog”，同时进入状态机消费和所有相关 strobe 的当拍组合门；只清历史资格影子或只置下一拍 fault 不能阻止旧值当拍发射。
- 复发: 1（2026-10-26 glue PF_DONE/已warm+abort同型变体；修复后独立探针 PASS）

### [2026-10-24] rtl: 寄存器容器窄化族刀五要素模板——单读点普查/裸宽三配对/L1 精确界/L2 lane 移位穷举/latent 条款（AL/BL/CL/DL 四件套 70b+ 陈年容器全收口实案）
- 症状: layernorm pm 族 pcp{AL,BL,CL,DH,DL,AH,BH,CH}_r 系 71b/72b 陈年全宽容器，真实值域远窄（AL 26b max 54,787,678/BL 25b 9.96M/CL 26b 28,049,194/DL 25b 11,796,390），白白寄存 46b+/个。四件套（AL 26b/BL 25b/CL 26b/DL 25b）按本模板连续收口：FF Δ −45/−46/−45/−46=合计 −182，area 四连降，六门帧指纹一字不变，恒等仪逐刀落刀后一字重出 ALL PASS。
- 根因: 容器宽按"积的物理全宽"（71b=8 行装配域宽度）一次写死，而每行寄存器只持单行积——行值域=17b/18b 操作数×8b/9b 常数片，容器该按行精确界定宽；带符号案（DL）还叠加 `$signed` 语义截断面，无符号幅值模板不可直套。
- 修复: 族刀五要素模板（审计 submission50-pre 裁4 立案）——**①单读点普查**：容器全树读点=恰 1（裸名+别名双扫，含 TB 树零引用核验+netmerge 别名面——实名段"消失"先疑 yosys 同位恒等合并）；**②裸宽常数三处配对**：声明界/复位字面/读点延拓复制数+位选索引（如 70:0→24:0、71'sd0→25'sd0、{1{…[70]}}→{47{…[24]}}）逐处成对改，漏一=编译零报功能毁；**③L1 精确界**：源组合式逐字语义模型（带符号案显式 `$signed` 截断+**双正化面断言**——{1'b0,} bit17=0 拼接恒真/常数片 bit7=0 常数恒真），17b 源全域穷举强制最小宽（DL max 11,796,390>2^23−1 且 <2^24⇒25b 带符号最小，余量 29.7%，bit24 置位总数=0 符号位清洁实证）；**④L2 含 lane 移位消费链穷举**：符号延拓结合律 2^W 全域含 <<lane 消费链（EXT-ASSOC），证容器宽=源宽 bit-exact 装配不变；**⑤latent 条款**：常数片改号（bit7 翻 1 变负值）或改宽须重跑恒等仪——证明仅对现常数成立。
- 检测门: pre 包五节固定骨架（普查/三配对清单/L1 穷举脚本+L2 脚本/latent 披露）；落刀后恒等脚本**一字重出**（落刀形态=验证形态）；FF Δ 首门计数对账（位宽差=型别差一字不差）；netlist 逐字同比首门。
- 预防规则: 凡"寄存器宽>源组合式精确界"的容器，一律按五要素过一遍再动刀；带符号案禁套无符号幅值模板（46-pre 裁4+48-pre 裁4 注记）。
- 复发: 0

### [2026-10-23] rtl: MCP 绑拍安全判据——源稳定窗 ≥ 绑拍数；终点行稳不构成绑拍依据（审计裁31，submission25 注记 a 表述撤回修正）
- 症状: submission25 裁1 注记 a 曾表述"rcpn_r 行稳=可绑 MCP=2 属性"，轮次31 提案绑 mprod_r→rcpn_r 时被审计独立推证驳回：终点 rcpn_r 行稳（NP 捕获窗每 2 拍一写）属实，但源 mprod_r 系 S1-S5 自由推进**每拍写**——cnt5 捕获拍前最近发射=cnt4 拍边，实际源稳定窗=1 拍；绑 2=对 STA 虚报 1 拍（工具按 13,333ps 验收，实硬件仅 6,666.7ps），D 第 2 拍才稳则 cnt5 沿已锁旧值，cnt6 读上拍数据=硅级数据腐化。该路径不存在"等到 cnt6 才捕获"的 RTL 机制。
- 根因: 绑拍 act 的可行性判据被错挂在终点行稳上；正确判据=**源寄存器稳定窗**（捕获拍前源最后一次实际更新到捕获拍的间距）≥ 绑拍数。对照正例 A6 六端点（sum_q/shi_r/sn_r）绑 2 安全：源稳定窗 ≥40 拍（累加窗与 NP 捕获窗不相交）≫2。判据一致性闭合。
- 修复: 裁31 驳回绑拍 act（禁止以拍数表 act 消化越线段；处置=裸档挂账或另案结构刀全要件呈报）。裁30 pre 同判据第二实证：pmlo_c→pcpAL_r 源 pmul_r 单写口 en3w[4]+mc3 每拍+1 ⇒ 源窗恰 1 拍，MCP 候选径呈报枚举表内即被自驳。
- 检测门: 凡拍数表/SDC 级绑拍提案，强制前置推证**源寄存器稳定窗**（源写口使能拍距直查：写口使能表达式 + 计数器递增周期），窗 ≥ 绑拍数方可进入 act 通道；act 通道要件=拍数表修订件+闭链仪重跑实证+seg_diff 影响节+帧指纹豁免六门。
- 预防规则: 绑拍先看源窗，不看终点；"行稳"主语必须落到被绑路径的起点寄存器上。
- 复发: 0

### [2026-10-23] rtl: pcpAL_c signed[25:0] 截断面 latent 档——17×9 常数乘积 ≥2²⁵ 时 bit25=1，signed 声明致 71b 行寄存器符号延拓，行贡献偏差 −2²⁶（mod 2⁷² 非恒等；探针轮闭环前挂 latent 档）
- 症状（latent，未在测试域触发）: layernorm pc 低半低片 `pcpAL_c = $signed({1'b0,pmlo_c}) * $signed({1'b0,klo_c[8:0]})`（17×9 常数乘，klo_c[8:0]=418）声明为 **signed [25:0]**，积 max=54,787,678<2²⁶ 位级无损，但积 ≥2²⁵（**pmlo_c ≥ 80,274**，穷举精确界 ceil(2²⁵/418)；含 pmul_r=−1→pmlo_c=131,071 情形）时 bit25=1 → pcpAL_r（signed [70:0]）装载时符号延拓 → AL 行贡献 = 积−2²⁶，8 行 mod 2⁷² 装配和偏差 −2²⁶，低 64b 结果错。**族内唯 AL 可触发**（BL max 9.96M/CL max 28.05M/DL max 11.8M 均<2²⁵；AH/BH/CH/DH 系 pmhi signed×signed 无此面）。触发剩余类密度 38.8%（50,798/131,072；gcd(39330,2¹⁷)=2 偶剩余类全覆盖）——六门绿+pe 同式 50 万随机全过只能说明测试分布避开触发类，**不能反推契约界成立**（审计独立补查推翻该推断）。
- 根因: 无符号幅值×无符号常数的积按有符号 26b 声明+有符号 71b 行寄存器装载，位 25 兼作"值位/符号位"双重身份；同族 L1348-1350 已对**操作数**层双正化设防，结果层截断面未对称设防。
- 修复: **待定向探针轮闭环后定**（审计裁②c 处置令）：探针目标=d2 契约域可达 pmlo_c 值全列举（六门测试域+契约域两口径）或从 d2 定义域严格证界；探针证可达→修件刀排队（候选：pcpAL_c 27b 容器+装配符号纪律重推导，或并入 V5.0 一并处置，呈裁时定）；探针证界→界入 canon 档。
- 检测门: 凡"积声明位宽 = 积真实位宽"贴线的乘法行（max 积 ≥ 容器符号位值 2^(W−1)），逐行核触发界；呈报族普查时附带 max 积 vs 2^(W−1) 对照行。
- 预防规则: 无符号×无符号积进有符号宽寄存器行，容器必 ≥ 积 max 位宽+1（符号位冗余），或装载前显式正化延拓。
- 复发: 0（latent 档，探针轮未闭环）

### [2026-10-23] rtl: 刀选型未枚举备选径即定型——as_r 桥退役选消费拍组合直读，[25] 备选可行性账簿从未推导；删桥须预演"被截锥在新形态从哪个源出发深几许"
- 症状: as_r 解(b) 落刀（消 resv_r 桥，消费者 en1w[24] 组合直读刀5 组）后新段 rbyp7_r→sum1_r 9,718.0 lv29 直接成为 100MHz min-period 锚（距 10,000 线仅 282ps）；而 resv_r 桥在时 resv_r→sum1_r 仅 5,515.7 lv18 带内——退役桥把 32b 累加 add 锥（Δlv23，同源双终点分解实证）从注册源搬到组合源即超限，被迫插队一轮加固刀（sum1_r 窄化 22b）回补。
- 根因: 选型期只论证了选定径（组合直读帧价 0），**从未枚举备选径**——消费拍后移 en1w[25] 的窗界闭界（[24,87] vs 尾拍 88）当轮未推导、res_buf/res_obs_addr 索引 −24→−25 级联改写面未盘点、P3 读余量未核，备选不在桌上是因可行性账簿不存在，非经评估被否。同时缺常备观测面：同源多终点分解（同起点 rbyp7_r：res_buf 终点 lv6 纯值锥 vs sum1_r 终点 lv29 值锥+加锥）只能在刀后 pkl 里重建，选型时看不见加锥主体。
- 修复: submission28 锚加固刀（sum1_r 32b→22b，值域恰界证明 [−2²¹,2²¹−64]⊆22b 有符号域）把锚压回 ≤9,000 线内；撞车复盘三条入 submission28pre/accept 档。
- 检测门: 预锁呈报包必含"候选径枚举表"——每条附可行性账簿（窗界闭界/索引级联/跨域余量/寄存器账），无枚举表不定型；凡删桥/消寄存器类改动，必答"桥截断的锥在新形态下从哪个源出发、深几许"（同源双终点差分预演：找同起点带/不带该锥的既有终点对）。
- 预防规则: 结构刀选型前强制两问——①备选径全枚举了吗（各带可行性账簿）？②被消寄存器截断的锥在新形态下的出发源/深度有观测面吗？任一无答即停手补分析再呈。
- 复发: 0

### [2026-10-23] rtl: 移位寄存器阵列加深只改声明+复位漏改移位循环——新增末级永驻复位值，编译零报错功能全毁（as_r 刀 echo [0:7]→[0:8] 实案）
- 症状: layernorm echo 侧带链 `reg [5:0] rs_e [0:7]`→`[0:8]` 加深后六门 FAIL：ln sat 计数 0（应 43）、res 计数暴涨 107×、L1 首字节数据错——但帧指纹/总拍数一字不变（结构拍账健康，纯数据路径毁）。vlog/yosys 全绿零警告。
- 根因: 加深阵列有三处联动——①声明界 `[0:7]`→`[0:8]` ②**复位**循环 `for(ei=0;ei<=7;…)` ③**移位**循环 `for(ei=1;ei<=7;…)`。落刀编辑清单只列了①②（呈报 §3 也只写"复位循环 ei<=7→8"），③漏改 → `rs_e[8]` 等四阵列末级只有复位赋值、仿真中永驻 0 → rs2_r（=rs_e[8]）移位量恒 0、rv2_r 旁路值恒 0 → B1 刀1 整锥错值。编译器不报错（数组界内、循环合法），STA 对"常数化寄存器"也不告警——六门才捕到。
- 修复: 移位循环 `ei<=7`→`ei<=8`；六门复跑（帧指纹不变+数据 PASS 双证）。
- 检测门: 凡改 `reg … [0:N]` 移位/echo 阵列，落刀后强制三址等界断言：声明/复位/移位三处循环界必须同值；六门 FAIL 而帧指纹一字不变=数据路径疑罪首查"新增寄存器是否只有复位赋值"（grep 该名只命中声明+复位两行即铁证）。
- 预防规则: 呈报/落刀清单写"阵列加深"时必须显式列三址（声明界/复位界/移位界）逐项打勾，禁写"复位循环"单址概括；echo 链加深类手术把"末级新元素在窗口首元素首拍的消费值"列进六门预期核验项。
- 复发: 0

### [2026-10-23] rtl: 宽拼接赋窄 ROM 条目静默截断——64b 拼 8b 取低字节，全表 224/256 项 X（G-smax C 案种子 ROM 实案）
- 症状: seed_rom[0:255] initial 块文本 32 行×8 值"全覆盖"，vlog/yosys 双编译绿；仿真读 224 项=X、已填 32 项全错（ROM[0]=249 应为 255）。单卡跑 RTL 逐位 FAIL，行和域 [4068,14161] vs 契约 [32512,33024]。
- 根因: 生成器按"8 项一组"产出 `seed_rom[r0] = {8'dv0,...,8'dv7}`——目标声明是 `reg [7:0] seed_rom [0:255]`（每项 8b），64b 拼接赋 8b 目标=Verilog 静默截断到**低 8 位**（组末项），且只写了 32 个索引。编译器零警告（赋值宽度合法，截断是语言允许行为）。
- 修复: 逐条目 `seed_rom[k] = 8'dv;`×256 行；微隔离台（空壳例化+ hierarchical 读 ROM[0]/[23]/[255] 三锚）跑前必验。
- 检测门: 任何生成器向定宽存储单元写拼接的代码，落盘后跑"微 ROM 台"：例化 DUT 空转 1 拍，$display 首/中/末三锚条目与表源对值；不等大仿真失败再回头。另：RTL 内 `arr[i] = {…}` 行数×每组项数 == 声明深度 的自对账断言进生成器。
- 预防规则: 存储阵列赋值生成只走"单元素一行"形态；成组拼接形态必须先证目标宽度==拼接宽度再允许。ROM/表类落地后默认疑似截断，三锚微台为常设门。
- 复发: 0

### [2026-10-23] rtl: 算法穷举背书≠实现逐操作数对账——NR 步 x←(x·g)>>30 的 A 操作数误装 u，结构性错值过编译仿真但毁逐位（G-smax C 案实案）
- 症状: 乘件/ROM 全绿后 softmax 单元门仍 FAIL：行和 [3983,14333] vs 契约 32768±，q 值定义但系统性偏小 2-8 倍（行相关）。逐遍探针（NP1..6 各遍 cnt==5 拍转储 mprod/mul_a/mul_b）对拍 Python 参考：p0/g0 全对，x1 起全错。
- 根因: 手术动作块写 P2(M2a) 装载时 A 操作数装了 uq_r（p 链的 u），而 NR 参考该步恒等是 x←(x·g)>>30 必须用 x 链（x0）。穷举验证背书的是算法不是实现；编译/双闸/行结构全绿（错值也是定义值，无 X）。
- 修复: mul_a_r <= x_r；手术器与 RTL 同批改（落刀形态=验证形态）。修后单元门 117,612 元素逐位 PASS。
- 检测门: 算法替换类手术（迭代器→NR/CSA 等）验收探针必须**逐遍打印内部积**（每遍 cnt==5 的 mprod+装载操作数）与参考模型逐遍对拍，不只对最终 q/r——首错遍即定位。探针台= forks tb_softmax_v3.v + 层级引用，半小时内出账。
- 预防规则: 任何"参考算法已穷举/已证明"的实现，落刀后第一问=实现里每个乘/加的操作数与参考第 n 步的符号名一一对应了吗（按遍列表对，不按意图对）；六门过了也只背书到"结构可跑"，逐操作数对账是算法手术的自设门。
- 复发: 0

### [2026-10-23] rtl: ram_style="block" 静默回退 LUTRAM——属性不可信，验收必须数 Block RAM Tile（Synth 8-6849，CUT1 wrfifo 实案）
- 症状: m9_axi_wr 的 512×40 手写 FIFO 改 BRAM 化后综合，ram_style="block" 被判 infeasible（Synth 8-6849），Vivado 静默改推 LUTRAM（Block RAM Tile=0）——综合不报错、属性还在，照属性验收会把「节省全泡汤」误判成刀成功（CUT1 硬门③抓到：LUT/FF delta 全不对）。
- 根因: 读口数据通路上的写数据旁路 mux（同拍碰撞前递的组合逻辑）使 block RAM 推断不可行；ram_style 只是推断提示，infeasible 即回退不 fail-loud。
- 修复: 碰撞前递改到 RAM 输出寄存器之后的寄存器旁路（coll_r/wreg_r），读口变纯无条件同步读 → RAMB36E1×1 推断成立；同 TB bit-exact 复测 659 万项 0 mismatch（CUT1 V2.2，sha 1aba5925→22b81ce5，b6 R49 合规确认）。
- 检测门: 任何「大数组→BRAM」改造验收必须查综合后 utilization 的 Block RAM Tile/RAMB36E1 计数 >0，禁信 ram_style 属性或「synth 无 ERROR」；读口带写旁路 mux 的 FIFO 先判 block 推断可行性再动手。
- 预防规则: ram_style/推断类属性一律视为提示非承诺；BRAM 化验收锚=物理原语计数（同大数组铁律口径）。
- 复发: 0

### [2026-10-23] rtl: CSR 字段按头注释位宽下契约——实现已改宽注释没跟上（cfg_nconv 注释 4b vs 实现 5b，prefix 切分机制不可表达实案）
- 症状: 混合架构 Phase 0 拟用 cfg_nconv（CSR 0x10[28:24]）做 prefix 切分，早期分析按字段 5b 估算上限 32；审计以交付 .param 实测 conv 计数 v8n backbone+neck=36 / y11n=42——上限 31 两边都越限，天然 seam 在 RTL 层根本不可表达，设计走到审计才撞破（阻断级）。
- 根因: RTL 演进把字段改宽时未同步头注释；头注释是陈旧副本非权威，实现 `output reg [4:0]`（m9_abi_v2_csr.v:186 等三处一致）才是契约；且实现位宽 5b 与网级实测量（36/42）谁都没单独越限、乘到一起才撞——两层各自看都"没问题"。
- 修复: seam 改烘焙 ROM 参数（混合版 plan ROM 只烘 bb+neck 前缀，R63 容器 y11n 42≤63 够装）；cfg_nconv 移出 seam 契约；PPP sanity 合法性界改指烘焙 plan 深度。CSR 注释失修（nconv[3:0]@24 vs 5b@[28:24]）挂账待修。
- 检测门: 契约/方案引用 CSR 位段前 grep `output reg \[`/`reg \[` 核实现位宽；网级 conv/层数预算用 flops_profile.py 实测交付 .param，禁估。
- 预防规则: RTL 字段契约以实现代码为准、头注释只当线索；方案评审把「字段可表达性=位宽×实测量」列为机制级检查项。
- 复发: 0

### [2026-10-23] rtl: 尾链顺延只改 tok_end 终值常数漏改 mc 计数帽——mc 饱和于旧帽、tok_end 永不可达、run3 不清零全链死锁（aghB 刀1 六门实案）
- 症状: aghB 刀1 落刀（p3_tok_end 101→102，尾链 en3w[27..38]→[28..39] 全顺延）后 gates_i 六门 2/6：门1 ln 单元 TIMEOUT 零 y 观测（TB_LNV3 res=0/192）、门2 L0 p=9,801 全错+pv=47 LSB 差、门3/4 t6/t6smax `TIMEOUT: V3.2 chain not done (st=7 lay=0)`、门5/6（不涉该链）PASS。STA 全 blind（结构性死锁，路径全在，纯功能病——六门先于 STA 纪律又一实证）。
- 根因: 递增帽 `if (mc3 < 7'd101) mc3 <= mc3 + 7'd1;` 未随 `p3_tok_end = (mc3 == 7'd102)` 同步——mc3 饱和于 101，102 永不可达，tok_end 永不置位，run3/f3 不前进。刀C 先例（100→101）即"tok_end/计数帽"双改同拍，本轮只改其一；vlog/yosys 双编译器自检对逻辑常数值不匹配完全失明。
- 修复: 计数帽 101→102 一点补丁（完成已批准设计，非新偏离）；修后六门全套重跑。新 sha 双树同步，旧形态作废不入账。
- 检测门: 凡改 `*_tok_end = (mc == N)` 终值：grep 全文件 `mc (==|<|<=) 7'd(N-1|N)` 配对清点，帽与终值两常数必须同值域出现（本轮 N-1=101 帽+N=102 终值即病灶指纹）；尾链顺延类刀的落刀自检清单加"计数域绝对常数普查"步（与 bet_c/y_addr 偏移类常数同列）。
- 预防规则: 尾链顺延=改动原子组{tok_end 终值+计数帽+一切 mc 绝对偏移读地址}，清单化逐项落改禁凭记忆；恒等模型不覆盖计数界（模型级 PASS≠计数域对），计数界变更只能六门裁判。
- 复发: 0

### [2026-10-23] rtl: RTL 补丁"被引用声明在后"——yosys 宽容通过、modelsim vlog-2730 全门编译阻断（yosys 单编译器验证漏检实案）
- 症状: submission10 carry-select 补丁块插在被引用的 tbBlo_e/tbBhi_e sext 声明之前；落地自检 yosys parse rc=0 判过，六门链门1-4 vlog 齐炸 vlog-2730 Undefined variable + vlog-8009 already declared（t6ln/t6/t6smax 逐字同），门5/6 不涉该模块故 PASS——2 PASS/4 FAIL 阻断型。
- 根因: yosys read_verilog 对模块内 wire 声明次序宽容（AST 先建后连），modelsim vlog 严格序（声明必须先于引用）；单编译器验证假设"yosys 过=RTL 干净"不成立。
- 修复: sext 两行声明上移至补丁块之前（纯次序、语义零变化）；修后 vlog 零错误 + yosys 零 ERROR 双验，新 sha 同步 rtl_c 快照。
- 检测门: RTL 落刀自检从"yosys parse"升级为"双编译器门"：vlog -work <自有库> 单文件编译（显式 -work，禁碰 D:\work\modelsim 安装件）+ yosys hierarchy -check 双过才算干净；补丁插入点必须核查被引用声明的行序。
- 预防规则: 插入组合逻辑块前先在目标区 grep 全部依赖声明的行号，依赖声明随行带上移；验证链把 vlog 单文件编译列为落刀自检固定步。
- 复发: 0

### [2026-10-23] rtl: walker buf 表 producer 编码违 loader 步5 law——walker 域外产出（GEMM conv 物化面/input/conv 侧 up2x）必须 0xFF，填 conv 全局序 ORD 必撞「producer<desc_id 或 0xFF」首岛 desc 全灭（G5 walk conv9 实案）
- 症状: r12 G5 整图 walk 首个图岛 conv（conv9=model.2.m.0 add, desc0）在 PPP 闸命中、walker 装载 148 拍后 abort：ppu_done_err=01（E_CODE_DESC_INVALID，上层 err_events[10] 引擎口）→ issuer S_PPPW err<=ppu_done_err → S_HALT。loader 首错锁存 estep=5/ebit=BUFFER。
- 根因: loader 步5 law（V1.4 正典，ppu_loader.v 头注「5 输入侧 producer<desc_id (0xFF豁免)」）：desc 的每个适用输入槽的 buf producer 必须 < did 或 =0xFF——producer 语义=**walker 域内前趋 desc 号**。布局生成器 stage2_gen.py 把 GEMM conv 物化面的 producer 填成 conv 全局序 ORD（0..62）：desc0(did=0) 的 in0/in1=buf0/buf1（producer=ORD 4/2）≥0 → 步5 必炸；且 did(0..21) 与 ORD(0..62) 同域重叠，任何「ORD<did 即安全」的指望都不成立。域外产出 valid 位由主机装载窗一次写 1（bit24），walker 本就不追踪其生产 → 正确编码恒为 0xFF（ppu_desc_bundle.py 外部输入=0xFF 同型）。
- 修复: stage2_gen.py buf_idx() conv 分支 producer=ORD[pn]→0xFF（input/op 输出分支本就 0xFF）；layout2tb.py heads 段 ord_of→0xFF 同病同修；WARN 注释改写为实裁定。重生成 layout.json/tb_setup.mem（57 项 producer 全 0xFF 静态验证过）。
- 终局（2026-10-24 回填）: 复验轮 partial26 过 conv9 后于 cyc=100,666,376 看门狗 err=07（walker 域深层病，另案 R83 链承办）；**本修复已被主线的 golden63→stage2_gen→layout2tb→gen_r11_setup 五连管线吸收**——S5a r11 程序 64 项 buf producer 全 0x000000ff 实证（`2026-10-24_scdone_s5a_fix_run01/work/r11/evidence/tb_setup_r11.txt`），db1-7 desc 闭合建立在本修复之上。本线收项。
- 检测门: 凡往 walker buf 表写 producer 的工具，写后静态断言「conv 物化面/input ⇒ 0xFF；desc 产出 ⇒ < 消费方 did」；walker abort err=01 时直接读 loader 首错锁存（fnd_r/estep_r/ebit_r/ecode_r，ppu_loader.v）一步到位——estep=5 即 producer 序违例，estep=3/4 即 buf 表 valid/几何。
- 预防规则: 跨域编号（conv 全局序 vs desc 号 vs PPP node 号）进同一张表前必须在生成器头注里写清每个字段的消费者与比较语义；loader 步5 这类「隐式拓扑排序校验」的 law 改动 = RTL+生成器双侧同步改。
- 复发: 0

### [2026-10-23] rtl: 注册使能窗 en3w[k]<=run&&(mc<=C_LAST+k) 与 mc 计数器天然差一拍——凡拷它做新寄存器捕获使能必漏 mc=0 边界拍（v9 同族病，刀A 预锁实案 y=2,360）
- 症状: V4.1-P150 刀A（装配窗预锁，5 源 b3/mean_p/g_p/sh_e/sh_oe/e_odd 捕获）落刀后 ln 单元门 TB_FAIL y=2,360/152064；错点严格 addr≡0 mod 64=**每行首元素**，12 层×2 臂×98 行全中；融合/纯 LN 双模式同位；SAT 行与基线逐值同（累加主体未污染）；错值=小偏差非垃圾。
- 根因: en3w[0]<=run3&&(mc3<=C_LAST) 是 NBA——高电平窗=[1,C_LAST+1]，**漏 mc3=0 拍**。预锁捕获使能拷了 en3w[0]，首元素拍无捕获→d2 消费上一行陈化标量。同文件 v9 修正注释自带该病描述（resq_r 已改组合门 mc3<=C_LAST），落刀未沿用。机制面：注册使能窗与组合门窗恒差起点拍，凡"每元素捕获"新寄存器拷注册使能即继承漏窗；凡"每行标量"预锁漏窗=整段陈旧数据。
- 修复: 捕获使能 en3w[0]→组合门 `mc3<=C_LAST`（与被捕获数据同链路、同沿对齐），d2 次拍消费不变，时序收益（b3→mux→预锁 DFF 整拍早于消费）保持。rtl_fix 单元门 TB_PASS y=0 位精确。
- 检测门: gate FAIL 先看错点是否 addr≡0 mod 行宽（行首元素病指纹）；落预锁/捕获刀时 grep 目标文件"漏 mc=0|边界拍"历史注释；审计预锁刀固定四问④=捕获使能窗是否含计数器起点拍。
- 预防规则: 每元素/每拍捕获的新寄存器，使能首选同链路组合门或与既有捕获寄存器（resq_r 类）完全同款；拷 en3w[k] 注册使能必须书面论证窗覆盖 [0,C_LAST]。
- 复发: 0

### [2026-10-22] rtl: 「axi4→axi3 auto_pc 写侧无 burst 拆分器」根因论断**已证伪**——≤16 拍封顶后板上仍挂，挂点=行 0 完成后第 16 个 burst（M 预处理板上实案，根因待钉）
- 症状: 新预处理 bit 上板：链点火 5 秒 `t1_preproc busy timeout` 崩、HDMI 黑。干净隔离实验（重载 bit 复位 FSM + 哨兵 DST + go）：**v3（burst≤16）写出恰好 1 行（960B 灰行完整、15 个 burst 全拿到 B）后卡死在第 16 个 burst**；busy 恒 1。门仿真 6/6 全过、WNS+8.982 全绿。
- 证伪证据（三件套）: ①v3 的 15 个 ≤16 拍 burst 全部完成 ⇒ 转换器写侧处理 ≤16 拍无问题；②**老板证设计（同 slot 同转换器）写引擎发 320 拍 burst 常年正常** ⇒「写侧无拆分器/AWLEN≤15」论断与事实矛盾（老设计若被截断 awlen 绝无可能工作）；③挂点精确在行 0 完成后的下一个 burst（含幻影重写的同型事务），与 burst 长度无关。
- 当前事实层: ~~挂死发生在 writer FSM 的 burst #16~~（10-22 深夜钉死，见下条更新）
- 教训（保留）: ①「shell 引脚兼容≠互联协议契约兼容」仍成立——但这次更隐蔽：协议层全对，是**真实 DDR 路径的某状态性条件**（仿真 BFM 无此行为）；②**排查纪律：隔离实验必须重载 bit 复位 FSM 再触发**——本日两次"手动复现"测的都是预挂死 DUT（go 被 !busy_r 门掉），产出"零行写出"伪证，差点把方向带进沟里；③门仿真 PASS + 时序 PASS 不推出板上 PASS，BFM 应答延迟窗口必须覆盖真实范围。
- 检测门: 板上"busy 恒 1"排查第一步 = 读 STATUS 确认挂前状态（busy 已 1 时 go 无效）；任何手动触发实验前先 Overlay 重载 bit。
- 预防规则: 板上挂死的隔离实验 = 重载 bit → 哨兵 → go → 轮询，四步缺一结论作废；仿真 BFM 对 AXI 应答延迟做参数化扫描（1/8/32 拍）。
### [2026-10-22] rtl: axi4→axi3 转换器对 W 通道 pacing 敏感——AW accept 后隔拍拉 wvalid/寄存器 wlast 即死锁首个写出 burst（M 预处理板上实案，**根因已钉死**）
- 症状: 新预处理 bit 上板写出**第 1 个 burst 即死锁**（dbg-CSR 实证：AW 被接受 1 次、B 应答 0 次、卡 ST_W、`wvalid=1` 但 W 永不被收、`bvalid` 在 AW 后恒高）。全 PS 重启重现 ×3、8 个目标地址（含 OCM）同型卡死、与时序无关（WNS+8.084/0 违例）、门仿真 6/6 全过（BFM 无此行为）。
- 根因: 互联 slot 的 `axi_protocol_converter`（TRANSLATION_MODE=2）对 W 通道启动时序敏感：新写引擎在 AW accept 后**隔 1 拍**才置 `wvalid`、且 `wlast` 用寄存器，触发转换器死锁；老设计（同 slot 常年正常）是 **AW accept 同拍置 `wvalid`、下一拍出首拍数据、`wlast` 组合逻辑**。仿真 BFM 对两种风格都正确应答，只有真实转换器分辨——**门仿真 PASS + 时序 PASS ≠ 板上 PASS 的教科书案例**。
- 修复: 写引擎握手改成与老设计逐拍一致（`wvalid` 在 ST_AW accept 分支同拍置位、`m_axi_wlast = wvalid && (beat_cnt==burst_len-1)` 组合）。门 6/6 零差 PASS；板上干净触发 **320/320 行全帧写出、gray=80 pad 行精确、0.05s/帧**。
- 检测门: ①凡复用旧外壳换内核，**写出引擎的 AW→W→B 握手时序必须与板上已证实现逐拍对齐**，不能只验协议合法（两种风格都合法）；②BFM 门增加"W 首拍延迟"参数化（0/1/2 拍）扫两种握手风格；③板上写出类挂死第一探针 = dbg 计数器（AW/B 接受计数 + 状态粘滞位），一眼定位 AW/W/B 哪段断。
- 预防规则: 换内核时把「已证实现的 AXI 握手时序风格」列为硬契约（与引脚兼容同级）；任何写通道 FSM 重构后，风格偏离已证实现必须过板上单 burst 冒烟再上全链。
- 复发: 0（同日前驱误判见上条：burst≤16 证伪轮次）

### [2026-10-22] rtl: 流式从机"先流后令"死锁 + 电平命令重复接单——命令必须先于数据流到手，且在接受沿清除（M 预处理 bit 门实案）
- 症状: 门仿真在首个内容行挂死：写出器 ST_FILL 等像素流，但调度器在最后一像素才拉高电平 cmd_valid——流已淌完令才到，互等死锁。修后 boundary 上写出器回 IDLE 时 cmd_valid 仍高，把上一行命令重接一次（又进 ST_FILL 等永不到来的 px）。
- 根因: 两级时序各错一位——(1) 命令发布点晚于数据生产点；(2) 电平握手清除挂在"完成"事件（wr_done 与从机回 IDLE 同拍重叠，清除生效时从机已能重采样）。电平 valid 的"恰好一次"只能靠接受沿清除保证。
- 修复: 行命令改到 ROW_START（像素流开始前）发出；valid 清除改全局接受条件 `if (valid && ready) valid<=0`（不挂状态机），done 只用于状态推进。
- 检测门: 门 FAIL 在"首个需要数据的内容单元"挂死 = 先查命令/数据先后序；同一命令被接单两次 = 查清除是否锚在接受沿而非完成沿（波形特征：done 拍与 IDLE 拍重叠、valid 仍高）。
- 预防规则: 流式从机协议 checklist 三条：命令先到（≥1 拍余量）、接受即清、完成只推进。缺一即 boundary 竞争。
- 复发: 0

### [2026-10-22] rtl: 模块头注释的时序契约不可信 + AXI W 通道 wdata 打拍落后读指针——异步读 RAM 必须组合驱动总线数据（M 预处理 bit 门实案）
- 症状: 门 FAIL 形态"blob 每词重复成对、奇位词消失"（W 波形 e0,e0,e2,e2,e3...）。溯源两级：(a) linebuf 头注释写读延迟 1 拍，实测 BMG 模型 2 拍（次像素采到陈旧 tap，首像素正确）；(b) 写出器 wdata 从异步读 row_ram 打拍寄存，握手沿推进读指针后 wdata 落后一拍——从机连收时重复上一词，气泡后跳一词。
- 根因: (a) 老 top 自带 issue 流水线把 BMG 裸延迟掩盖成"有效 1 拍"，注释记录的是 masked 值，新调度器无该流水线即爆；(b) 打拍使 wdata 对应"上一拍地址"，而握手语义要求 wdata 对应当拍地址——异步读 RAM 组合读出天然满足，打拍反而制造错位。
- 修复: LB_LAT 以门仿真逐拍实测钉 2（不引用注释值）；wdata 改 `assign`（pad 选择 + ram_dout），只寄存 wvalid/wlast。
- 检测门: 仿真"首样本对、次样本起陈旧" = 裸延迟比注释多一拍；W 通道"同值连发两拍后跳变" = wdata 打拍错位，查 wdata 是否组合自当拍读地址。
- 预防规则: 复用带注释的模块，时序契约一律最小 TB 逐拍实测复核；异步读 RAM 驱动的总线数据一律组合输出，禁止打拍。
- 复发: 0

### [2026-10-22] rtl: 流水拆段透传旁路对齐——拆 N 拍后消费拍=N+跨度，全部操作数（含透传/旁路窗）必须经同一出口级同拍对齐（V4.0 棒D 刀4 三次迭代实案）
- 症状: gelu S5a 拆两拍后 S_r 跨元素混窗，输出散点 7fff/0000 腐化形态；首轮只给主算子延拍、透传窗 s2hh 少延一拍即爆。平移类（全部元素同偏）vs 散点类（跨元素混）失败形态可区分"对齐类 vs 数据类"错源。
- 根因: 拆段改变了消费拍（N→N+跨度），但透传/旁路操作数没有自己的"生产→消费"算式，容易被遗忘——它们隐式假设消费拍不变。拆段只迁主算子、漏迁旁路即漂移。
- 修复: 拆段时列**全部**操作数清单（主算子+透传+旁路窗），逐一过同一出口级对齐；抽头 bisect 镜像计数法定位对齐点（同一疑点对两种拍法各跑一次，错误数镜像=对齐类实锤，V4.0 实案 6236/6294）。
- 检测门: 任何 stage 拆段/插拍的 diff，强制列该级全部输入操作数表逐项核拍；门 FAIL 先分形态——平移=数值/截断类，散点跨元素=对齐类，先按类走排查路径再逐行查。
- 预防规则: 拆段 checklist 第一条="透传旁路谁陪跑"——没有算式的操作数必须显式登记其锁拍，禁靠"结构同所以正确"。
- 复发: 0

### [2026-10-22] rtl: 块更名/结构重排随行寄存器 d 锁拍漂移——d 锁拍必须锚绝对 beat 事件，禁锚宿主块相对位（V4.0 棒B3 批3 实案，198 错 token 首元素起）
- 症状: ln 批3 窗结构重排（引入窗结果 echo 链）后 tb 部分积与 β 预取漂离锁拍：β 预取 d=26 锁 k=26、tb 部分积须消费 bet_r+1=k27，随行漂移致 tbasm 取陈值，y 错 198 个且自 token 首元素起。
- 根因: 随行寄存器的"锁拍"语义是相对宿主块位置（如"装配前两级"）定义的；块更名/重排移动宿主块位置时，随行寄存器未同步锚定即整体漂移。锁拍没写成绝对 k 拍注记，漂移不可见。
- 修复: 全部随行寄存器 d 锁拍改写成绝对 k 拍注记（锚事件：装配拍/窗出生拍）；块更名时对该块全部随行寄存器做清单重审。
- 检测门: RTL 凡带 `d=N`/`k=N` 锁拍注记的寄存器，结构改动 diff 时 grep 全部锁拍注记清单逐项复核锚点是否仍成立；y 错数≈窗数×每窗元素数且自 token 首元素起 → 先查随行漂移再查数值。
- 预防规则: d 锁拍一律绝对化（锚装配拍/出生拍，禁写"相对某块"）；块更名 = 随行寄存器锁拍清单强制重审项。
- 复发: 0

### [2026-10-22] rtl: CSA 进位行双移位——进位保存不变式必须写明"寄存时是否已加权"（C 权 2 时机二义，X=S+4C）
- 症状: 棒B 批2 首轮门 FAIL：sat 43→31 + res 大错；48b 累加改 3:2 进位保存后行为值恒为 X=S+4C（C 被双倍加权）。
- 根因: C 行寄存时已 `<<1` 预加权（寄存器存的是权 2 行），解算窗又 `{C[46:0],1'b0}` 再移一次 → C 计两次权。不变式 X=S+C 只在双方同权且注记声明时机时成立；注记没写权重时机，写解算端的人按"原始 C"读。
- 修复: 解算窗直读 C（零移位）；RTL 注记显式写"寄存时已加权"。canon：进位保存不变式声明必须含权重时机字样。
- 检测门: 凡进位保存结构，审阅 grep `<<1` 与窗解算 `{.*,1'b0}` 在同链成对出现即告警；切片恒等式 Python 抽象验必须把"寄存时已加权"建模进参考式——抽象只验 S+C 不逮双倍权（本实案 FAIL#1 与 FAIL#2 同轮并炸，互为佐证）。
- 预防规则: 进位保存三件套（S 行/C 行/解算窗）同一链内权重口径必须单一且注记显式；跨拍携带的 C 已含权，解算端永远零移位。
- 复发: 0

### [2026-10-22] rtl: 幅值切片符号性经**声明层**注入——`reg signed` 载体让全下游"看起来都对"，抽象验证须建模 $signed/LHS 截断语义
- 症状: 棒B 批2 首轮门 FAIL#2：y=14,982 错，全为 got=exp−{1,2,5,6,7}；pc 树被乘数拆半 X=Xh·2^17+Xl 的低半行恒定欠 K×2^17（探针实测差值数据无关，E=K×2^17）。
- 根因: `reg signed [16:0] pmlo_c = pmul_r[16:0]`——pmul[16:0] 是幅值（X mod 2^17），signed 声明使其最高位被当符号：pmul[16]=1 时读出 Xl−2^17。与 [2026-10-19] 条同族但注入路径不同：彼案在使用点 $signed()，本案在**声明层**——更隐蔽，所有下游消费点表达式全对，错在出生即翻号。
- 修复: 幅值载体改无符号声明，各消费点 `$signed({1'b0, pmlo_c})` 显式正化。
- 检测门: RTL 审阅 grep——凡名字含 lo/low/mag/幅值 语义的 reg/wire 声明禁带 signed；切片恒等式 Python 抽象全验**必须建模 $signed 语义与 LHS 位宽截断**——本实案 50 万向量抽象全验未逮（对照棒P1 verify_slice_identity.py 的逐位镜像 RTL 建模才是正确先例）。
- 预防规则: 符号语义只在真正带符号的值上用 signed；幅值一律无符号声明 + 消费点显式正化，与切片头注"顶/低片清单"纪律合流。
- 复发: 0（[2026-10-19] 条目复发+1 并回填本案变体，见下）

### [2026-10-22] rtl: PPP 表 emit-at-arrival 语义与"末 conv 才产 buf"的 heads 段时序不可闭合——M11a 潜伏缺陷（b6 R35 立案，RTL 冻结不动）
- 症状: r12 G5 stage-2 设计首验即撞：heads 六输入 buf88/94/100/91/97/103 的产者全在 P4，最后一个 = model.22.cv3.2.2（局部 conv15）= buf103 产者；PPP 门只在 conv 到达拍发射（m9_cmd_issuer.v L1549 S_ADV→S_PPPG），帧尾无 drain 扫表（L1538 末块直落 S_DONE）→ heads 若挂 PPP 表，conv15 到达拍发射时 buf103 尚不存在（该 conv 未跑），SPPW 又反压 conv15：等则看门狗 err=7 死锁，不等则 seg5 读陈旧数据。
- 根因: PPP 发射语义 emit-at-arrival 隐含假设"被挂段全部输入 buf 在发射拍已存在"，对"挂最后产者 conv"的 heads 段先天不成立；M11a 各梯 PPP 段均为 BFM 良性 add、从未真岛验，潜伏至 r12 整图全帧 walk 才显形（b6 认定：与 R15 同族 genuine design gap）。
- 修复: b6 R35 裁定（2026-10-22）：G5 的 PPP 表不挂 heads 段；帧尾 heads 走 0x114 des_mode PS 发射（m10p6 L231 板上先例=硅证路径），判据=目的面逐位对 + 岛 CSR 态；A1 覆盖无损（发射机制不改变写流字节，heads 302,400B 照样过 axiwr）。RTL 冻结不动；欠账一笔 = G7 式电池补 heads trap case（挂 B-R2 backlog，若重构 PPP 发射面再议）。备案：issuer sanity 白名单 {0x11,0x12,0x13} 无 0x15，挂表只能 0x12 词指 0x15 DESC（旗标 F2）。
- 检测门: 凡 PPP 表挂新段，先答一句——"该段最晚输入 buf 的产者 conv 是否早于钩 conv？"若最晚产者 = 钩 conv 本身（emit-at-arrival 拍 buf 未生）→ 时序不可闭合，立案，不得挂表。静态 grep 锚：ppp_ptr 消费态全集必须含帧尾 drain 态，否则末段只能 PS 发射。
- 预防规则: emit-at-arrival 发射门只许挂"全部输入 buf 早于钩 conv 存在"的段；"末 conv 产者"段必须走帧尾 PS 发射（0x114）或显式 drain 扫表语义，二者必居其一。
- 复发: 0

### [2026-10-22] rtl: BRAM 换 FF 组合读 FIFO 时单级预取换头晚一拍——必须双深（head 寄存 + next 组合直通 + addr=rp+consume+1），valid 位必须回答"消费后还剩"
- 症状: m9_axi_wr 等价探针连炸三轮：①背靠背 consume 时 FSM 用旧 head（刚消费的字节）判 contig → 错 skip 错行分组（ref={0d38}/03 vs dut={38}/01+{0d}/02）；②fill==1 排空后 head_v 卡 1（采样 fnempty 陈旧）阻塞 refill 路径，下次写到达消费全 0 垃圾字；③碰撞表"fill==1 碰撞→丢弃"分析错误（fnempty 在 wp 越过 rp 后仍为 1，字实际被保留）。
- 根因: BRAM 读延迟 1 + 寄存器锁存 1 = 新 head 在 rp 推进后**一整拍**才到，单级"consume 拍发 rp+1、次拍锁存"结构对背靠背消费先天不足；valid 位问错问题（"FIFO 现在空吗"而非"本拍消费后还剩吗"）。
- 修复: 双深流水线：head_r（寄存器像 fifo[rp]，决策链采样）+ next（**dout 组合直通**像 fifo[rp+1]），读地址每拍发 rp+consume+1（输入全为寄存器，发起合法），consume 换头纯 mux 零等待；head_v<=(wp!=rp+1)||yreq；reachable 同址碰撞（consume&&fill==2、!consume&&fill==1）用寄存写数据写穿顶替 undefined dout，consume&&fill==1&&yreq 的 head 走第二写穿（本拍在途写）。探针 1.22M 拍全绿（run01 probe_final）。
- 检测门: 凡"FF 数组→BRAM"替换，交付前黄金参考差分探针必须含**背靠背连续 consume**（duty 1.0 连续写）与 **fill==1 排空后立即重写**两个定向场景；静态自查一句话——"换头路径上有几个寄存器？BRAM 延迟+1 后新 head 第几拍到？"
- 预防规则: BRAM 化组合读存储时，预取深度 = 连续消费间隔 + 1；next 级必须组合直通 dout，禁止再插锁存；valid 语义永远回答"消费/事件之后还剩不剩"。
- 复发: 0

### [2026-10-22] rtl: xci 的 READ_LATENCY 参数≠时序真值——blk_mem_gen「Register Port Output of Memory Primitives=true」硅上有效延迟 2，且行为模型对孤立单拍 ENB 读永不吐数（dead-on-board + sim 失明双重陷阱，r12 页表三 IP 实证）
- 症状: r12 G2 P6 失败（页 bump 后 anchor 拍窗面仍是旧页）；微测试：addr1 孤立单拍 ENB 发起后其数据**永不出现**，第二次发起后一拍 doutb 才出第一次的数据（模型第二级被原始 ENB 门控）；xci 写 Register_*=true + READ_LATENCY_B=1。
- 根因: ①xci 的 READ_LATENCY 是派生显示值，true 时硅上总延迟=2（地址拍+1 出 memory_out +DOB_REG 再+1），v2.3 按「延迟 1」写的一拍偏斜在硅上必采旧数；②AMD 行为模型（blk_mem_gen_v8_4.v）第二级输出寄存由原始 ENB 门控——孤立单拍读数据等到下一次 ENB=1 才推出，与真实 BRAM（DOB_REG 不受外部 EN 门控、T+2 无条件出数）不符，功能梯对单拍读契约结构性失明。审计双方同误读 xci 参数。
- 修复: 三 IP 重配 Register_PortA/B_Output_of_Memory_Primitives=false（r11 硅证正典：m9_bm_wblk B=false/m9_bm_hbuf 双 false，一拍约定板上实证）→ 有效延迟 1，行为模型恢复忠实（微测试复跑孤立读 L+1 出数）。
- 检测门: 凡新配 blk_mem_gen，输出寄存选项一律对齐既有硅证 IP 先例（false）；重配后必跑 bmg_latency_probe 微测试（孤立单拍读 L+1 出数门）归档才认 sim 权威；审计 xci 时对任何「参数值 vs 行为模型」不一致做微仿真裁决，不采信参数面值。
- 材料钉（2026-10-22 终态=构建 tcl 自身重配输出，功能参数已核：三口 Register_PortA/B_Output=false + READ_LATENCY=1 + sim 模型 C_HAS_MEM_OUTPUT_REGS_*=0）: m9_bm_pptab.xci=954152cbf90d13ec76b834049063d8be0c4a5d090563543576bc54048fc321fa / m9_bm_edgetab.xci=485ee18719e9860351bd4e462fcb88b9581dc4b7e715fee6ae58150b1c250e1c / m9_bm_jointab.xci=d8bb9fbea17776d615f4ef0716d2bf38f939c46f3e2b01cbb6329790bfd549a0；正典钉位 = build_m10r12.tcl PGTBL_CFG 段+材料记录行 + r12_preflight.py PGTBL_XCI 电池（三处 sha 一致，preflight 每跑全核）。
- 预防规则: BRAM IP 时序账一律以「行为模型微仿真 + 硅证先例」双锚定，xci 参数只当线索；单拍读发起+1 拍捕获契约的消费端，配输出寄存=false。
- 补充律（2026-10-22 构建自炸实证）: xci 字节随写入路径不同——同参数集经 Vivado 会话交互式 REGEN 与经 tcl set_property 流重写，产出字节不同（三本全中）；钉必须以「构建 tcl 自身重配的幂等输出」为准，任何会话侧手工 REGEN 后必须让 tcl 重配一遍再取钉，否则构建 tcl 的钉门必自炸（pgtbl_xci_sha_drift）。
- 复发: 0

### [2026-10-21] rtl: 新网声明落进 `ifdef 区域、消费端在区域外=elab 时声明蒸發，网退化为隐式 1-bit 标量——黄金-green 级静默截断（r12 B 轮 pg_base/pg_nedge actual 1 vs formal 6/3 实证）
- 症状: xelab VRFC 10-3091：actual bit length 1 differs from formal 6/3 for port pg_base/pg_nedge，指向声明齐全的终版字节（sha 已核），改声明宽度重编译警告纹丝不动。
- 根因: 6 条新网声明（iss_pg_base_w[5:0] 等）写在 `` `ifdef M11_REPACK … `endif `` 区内，而消费它们的模块实例在区外无条件 elaborated；elab 链未定义该宏 → 声明整段蒸發 → 首次使用处按 Verilog 隐式网规则退化为 1-bit 标量，零 error 零 redeclare 冲突。功能梯 TB 定义了宏所以功能面永远绿——只有 elab/综合点可见。
- 修复: 声明整体移到 `endif 之后（模块级、无条件），注释记律；消费端零改动。变异构实验证明 elaborator 未读声明（[4:0] 副本警告仍 actual 1）。
- 检测门: elab 日志 10-3091 宽度警告零容忍归类——凡新增端口/网连接警告必须解释到「声明在蒸發区」级；xelab 有 10-3091 一律先查两端声明是否同在一个宏区内再谈 benign。补充门：B 轮新增网全部列名 grep，确认声明行号不在任何 `ifdef/`endif 对之间。
- 预防规则: 声明跟着消费端走不跟着功能块走——凡被无条件实例消费的网，声明必须在最外层模块级；宽度 WARNING 默认按病灶处理，benign 归类权归审计。
- 复发: 0

### [2026-10-21] rtl: Edit 动块注释区后 `*/` 终止符可静默丢失——远处 syntax error 先查注释闭合，申报前必过 xvlog 解析门
- 症状: 文件头加修订历史后 181 行丢 `*/`，xvlog 在 356 行（注释内英文词 'windowed'）报 syntax error——报错点与病灶相距 175 行。
- 根因: 块注释未闭合时后续代码全被吞进注释流，解析器吞到无法匹配的 token 才报错，位置与真实病灶无关。
- 修复: 报错行落在注释文本内 = 先查上方注释终止符；改 RTL 后先 xvlog/xelab（秒级）再申报。
- 检测门: 申报前证据目录必有 xvlog.log 0 ERROR。
- 预防规则: "落地/通过"措辞前工具门输出已在盘（三件套之一）。
- 复发: 0

### [2026-10-21] rtl: 模块级"异步复位 for 循环清零 + 组合读"的 reg 数组永不推断 RAM——功能全绿、集成炸片（xc7z020 LUT 超 1.8% 实证）
- 症状: r12 impl place 前 DRC UTLZ-1 ERROR：LUT as Logic 需 54156 > 53200。层级报告定位：单模块 m9_page_tables（1160×32b 表存储）吃掉 18626 LUT + 37185 FF；全设计其余部分合计仅 34741 LUT（r11 终态 36483 同量级，余量充足）。模块级 xsim 门全绿，首个综合点才爆。
- 根因: RTL 风格三宗罪叠加，任一都阻断 Vivado RAM 推断、合起来必炸：(1) `always @(posedge clk or negedge rst_n)` 里 for 循环异步清零整个数组——推断 RAM 禁止复位；(2) 组合读（always @* 里读 memory 词，"hbuf 先例" sim 律）限定分布式/寄存器实现；(3) 字节 lane 部分写进一步排除 BRAM 推断。37k 位存储全部落成 FF + 18.6k LUT 读Mux。且 M11a 交付门只有功能/位宽/xsim 梯，**无任何面积估算或芯片预算对账**——模块在纸面无罪，集成即炸弹。
- 修复: 改 RTL——去数组异步复位（上电零语义用 `initial` 承载，FPGA 可综合为初始化值、不阻断推断），按目标 RAM 类型（BRAM=同步读/打一拍，LUTRAM=保留组合读）重构读口；改后重跑模块 xsim 梯 + 全链 G5 + 重综合。
- 检测门: 任何含 `reg [W] arr [0:N]`（N×W ≥ 8192 位）的模块发布前：(a) 单独 OOC 综合或 elaborate + report_utilization，登记 LUT/FF 预算对照表（芯片余量 ≤85% 才准集成）；(b) grep 该模块 `or negedge rst_n` 与 always@* 内存读并存 → 红灯；(c) 集成构建 preflight 电池加"上代终态 LUT + 本代模块 OOC LUT ≤ 预算"硬门。
- 预防规则: 表存储类模块（≥8Kb）默认按 RAM 写（无异步复位 + 同步读优先，组合读仅在确认 LUTRAM 时）；功能门之外必须有面积门；新硬件线首次集成必须带模块级综合估算进 preflight。
- 复发: 0

### [2026-10-21] rtl: 交付只加宽叶子模块、中间跳冻结——构建线必须给整条宽度链每一跳加宽，synth 8-11365 named-port 缺失就是断点指纹
- 症状: r12 synth：shim OOC 报 `Synth 8-11365 named port connection 'cv_slot' does not exist`（u_eng 实例）；同时被钉死的中间模块端口停在旧位宽（12/9/13/5b），把已加宽叶子（14/11/15/6b）的高位静默截断——R63 深于 4096 的地址永远够不到。
- 根因: M11a 交付只把**叶子**（issuer）加宽到 v2.4 位宽并新增 cv_slot 消费口，中间两跳（intra_top/intra_axi_top）「冻结」在 r10 位宽。Verilog 端口位宽不匹配只告警不报错：链上任何一跳没加宽 = 该跳以上全部高位丢失，且**不写新口的那一跳**会以 8-11365 硬错现形。加宽链的断点有两种形态：缺口的（硬错）和收窄的（静默截断），后者更毒。
- 修复: r12 构建线把四个文件全部加宽（top/shim wrapper + 两个冻结中间跳），逐跳 `input/output [N:0]` 声明 + 实例连接；netlist 门用 G0W 宽度表逐网核对。
- 检测门: 交付物审查必查「叶子新位宽/新口 vs 中间跳端口表」闭包——从消费叶子倒推每一跳；构建 tcl 的 G0 宽度门覆盖链上全部网名；synth log grep `8-11365|truncat` 全为 0 才算链通。
- 预防规则: 宽度/新口链 = 全链逐跳加宽，禁止只改两端；冻结中间件在加宽需求面前不是圣物，构建线有权加宽但必须换钉（新 sha + must-differ 旧钉双门）。
- 复发: 0


### [2026-10-21] sim: 最坏臂刺激"周期性图案 × 单元消费相位"隐性相关——双不利组合从未命中，fail_cnt=0 假全绿（a3s 复测 armA v1→v2 实案）
- 症状: 为 gemm M_a 乘法构造最不利臂：mult 按 i%4 周期图案（i%4==3→0x80000000 最负、其余 0x7FFFFFFF），a/w 均匀负/正使 acc byte3 恒负；双实例探针 fail_cnt=0 判绿。逐拍取证（acc_r × m_col_r6 全程迹）实锤：M_a 有效事件（acc_r≠0）全部落在 pe_col≡0 (mod 4) 相位，恰好只吃 mult 正臂——负 acc × 负 mult byte3 双不利 0 次同拍。
- 根因: 流水单元的消费相位（哪一拍/哪一列槽消费第 i 个激励）由内部调度决定，与激励文件的索引周期完全独立；周期图案的"覆盖所有 i%4 余数"只在激励域成立，投影到消费域后可能塌缩到单一相位。fail_cnt=0 只证明"实际命中的臂全对"，不证明"想构造的臂被命中"。
- 修复: 最不利参数改非周期全量值（mult 全 0x80000000），a/w 按址混合幅值扫描（值域扫描替代相位扫描）；新增逐拍取证探针（关键寄存器全程迹 + 双不利同拍计数器）命中确认：neg_acc=563 / 负系数臂 w2_act=562 / 双不利同拍 ≥51 后，双实例判绿才算数。
- 检测门: 任何"构造性最坏臂"刺激，探针必须带命中取证（计数器或全程迹），报告里出现"构造臂≠命中臂"即判测试无效重设计刺激；周期图案刺激过审前先在消费域（DUT 内部信号）验证图案投影未塌缩。
- 预防规则: 构造臂≠命中臂——最坏臂刺激的验收对象是"命中取证"而非"刺激文件本身"；周期性图案是相位相关高危品，优先全量非周期值+值域扫描。
- 复发: 0

### [2026-10-21] rtl: font16.hex 字模实为 bit0=左像素——凡按"bit15=左"提取必逐字左右镜像（字序不受影响），上板前必须把字模渲成 ASCII art 目检
- 症状: t1_label_osd 上板后用户目检"每个字都左右镜像，但字顺序是对的"；v3 文本引擎用同一字库配 `font_bits[15-fx]` 提取，即 v3 起屏显文字一直是镜像的，只因无人目检/文字短暂而从未暴露。
- 根因: font16.hex 的 16 位半字**实际位序是 bit0=最左像素**（与代码注释、生成器假设的 bit15=左相反）。逐字镜像而字序正确的原因：镜像按字均匀发生，字间排列由字地址序决定、与位序无关。仿真验不出来——TB 期望图与 RTL 用同一（错误）约定从同一 hex 提取，自洽全 PASS；数据级错误只有人眼能判。
- 修复: gen_label_rom.py 的 glyph_row() 加 rev16() 位反（字库位序→文件内部 bit15=左约定），重生成 hex；RTL 零改动。修复前用"从 hex 渲染 ASCII art"做地面真值核验（N 的斜杠必须左上→右下，p 的碗必须在左）。
- 检测门: 任何位图字库进 OSD/显示类 IP 前，先写 10 行脚本按候选位序渲 'N'/'p'/'Up' ASCII art 目检非对称字；TB 全 PASS 不构成字形正确性证据（期望数据与 DUT 同源提取）。
- 预防规则: 位图字体位序是数据契约，注释/先例代码都不可信，只信 ASCII art 渲染或硅上照片。
- 复发: 0

### [2026-10-20] rtl: 分段视频链寄存器级数不等 → 覆盖像素与底图错一拍（两阶段拆分必配等延迟对齐）
- 症状: 文字 OSD 拆成 gen(word_valid/word_data) + mux 两级后像素门 FAIL 2600+：背景像素当前拍正确、文字路径晚一拍，首拍 got=当前像素 vs exp=0。
- 根因: 上游 gen 把 word_valid/word_data 寄存一次，mux 若直接 `hdmi_data <= word_valid ? word_data : vio_data`，背景路径只过 1 级寄存器、文字路径过 2 级——两条路径寄存器级数差 1，覆盖像素相对底图右移 1 pixel，DE/HS/VS 又只随 1 级走。
- 修复: mux 先加一级输入捕获寄存器（vio_d/act_d），文字与底图都延迟到同一拍再选；输出寄存器统一打齐 DE/HS/VS。检测侧 TB 用"前一拍期望值"流水（exp_dly/de_dly）核对。
- 检测门: 像素精确门若出现"首拍 got=当前像素 / 其余全错一拍"指纹即级数不等；画覆盖像素前对两条路径数寄存器级数。
- 预防规则: 视频链任一模块拆分/插入后，逐路径数寄存器级数，不等就在短路径上加对齐寄存器再出门。
- 复发: 0

### [2026-10-19] rtl: Verilog 移位结果宽 = 左操作数自身宽，外表达式语境不拓宽（窄寄存器直移丢高位）
- 症状: 切片乘法重构后逐位门 FAIL 10 万+/15 万（v34k 案）；位宽已加宽到 71bit 后失败值仍逐位相同。
- 根因: `a <<< k` 的结果位宽取左操作数**自身**声明宽，外层 71bit 赋值语境**不**先把窄操作数拓宽再移——`aglB_r(57b) <<< 9` 在 57b 域内移，高 9 位截掉。
- 修复: 部分积寄存器一律按全装配宽声明（71b），赋值自拓宽、移位在全宽域进行；装配式 `sum(slice_r <<< off)` 全部核查左操作数宽。
- 检测门: 切片重构后 diff 首错样本用 python 整数对照定位到具体 partial；splittest 最小复现件随案归档。
- 预防规则: 移位/乘法的左操作数寄存器按**目标装配宽**声明，不靠上下文隐式拓宽。
- 复发: 0

### [2026-10-19] rtl: 无符号幅值低片 `$signed(slice)` 误读负（≥2^(w-1) 的值翻号）
- 症状: v34k2 切片门 FAIL：B/C/D partial 全对、A 路差一个固定大数（+2663935119450 vs 期望 −6428963421606）。
- 根因: 非负操作数（klo/mgl）的低字节片是无符号幅值，`$signed(9'h16A)` 读出 −150（362 的最高位被当符号）；乘法内任一操作数无符号化会使整个乘法按无符号。
- 修复: 非顶字节片一律 `$signed({1'b0, slice})`；仅带符号操作数的**顶字节片**保留裸 `$signed`。顶/低片清单写进 RTL 头注纪律。（2026-10-22 声明层变体修复：幅值载体改无符号声明，消费点显式正化——见同日独立条目。）
- 检测门: 切片门首错样本 python 整数分解到 partial 级；含 ≥2^(w−1) 样本的向量集必炸此类错。复发变体检测：RTL grep——lo/low/mag/幅值语义载体声明禁带 signed；Python 抽象全验须建模 $signed/LHS 截断语义。
- 预防规则: 切片前先判定该片的符号语义；无符号幅值片必须显式补 0 符号位再 $signed。符号性只允许经"顶片裸 $signed"或"显式 {1'b0,}" 两个出口注入，禁经声明层。
- 复发: 1（2026-10-22 棒B 批2 FAIL#2：声明层 signed 注入变体，pmlo_c 幅值被 signed 化致恒定欠 K×2^17，50 万向量抽象全验未逮）

### [2026-10-19] rtl: 多项行为加被 abc 线性化成深链（>4 项慎用，时序爆炸）
- 症状: 8 项移位装配的行为加 `pc_full` STA 从 17.5ns 劣化到 24,330ps/66 级（41.1MHz）。
- 根因: abc 对 4 项以上加法不按平衡树展开，线性串行化；级数 ∝ 项数。
- 修复: 回退到 ≤4 项的两级装配（每级 ≤4 项平衡加）；时序关键装配纪律写 RTL 头注。
- 检测门: regate 后 summary 的 worst path levels 与改前同级对比，级数涨幅 >20% 即回退。
- 预防规则: 时序关键路径上的行为加 ≤4 项；更多项用显式树结构分层。
- 复发: 0

### [2026-10-19] rtl: 逐元素流水对齐取证法——元素 ID 窗模型 + 穷举交叉定位（寄存器层数差决定对齐，捕获窗移动是 no-op）
- 症状: ln v34 对齐错：even/tb 两路各错一元素，逐拍肉眼对不上。
- 根因: 对齐由**寄存器层数差**决定；把捕获从一个窗移到重叠的另一个窗不改变任何沿的消费值（窗内内容相同）——"把捕获往后挪一拍"类修法无效。
- 修复: 元素 ID 窗模型（s_k = mc3∈[k,63+k]，NBA 旧值语义，content(R,k)=mc3=k−1 写入值）+ 对 res/gamma/beta 三流做 Δ∈[−1..2] 穷举交叉，唯一解 (j+1,j,j+1) 10/10 样本双向验证。
- 检测门: 流式单元逐位门首错呈"固定相位平移"指纹时，建窗模型穷举交叉，禁止拍脑袋挪捕获。
- 预防规则: 改流水先数寄存器层数差；捕获点移动只在跨越窗边界时才有语义。
- 复发: 0

### [2026-10-19] sim: 集成门 TB 与 RTL 同代演进——复跑旧 do 前先核对 TB 血统（层次探针撞 RTL 即破）
- 症状: 全链门复跑编译即炸：`Failed to find 'sat_cnt_o' in /dut/u_ln/`（10-18 旧 TB 撞 S2 换装后的 layernorm_unit_v3 观察口改名 ln_sat_cnt_o/res_sat_cnt_o）。
- 根因: 门 TB 用层次路径直探 DUT 内部信号/观察口；RTL 重构（单元换装/端口重命名/层级调整）即破，而 do 文件里的编译清单不报错到点子上（错在 vopt 加载期）。
- 修复: 用同代舰队 TB（本案 = 2026-10-19_v34_fleet/s3_gate/tb_acc_top_v3_task6_v34.v，含 +incdir vh）；复跑他人旧 do 前先 diff TB 的层次引用与现 RTL 端口清单。
- 检测门: 复跑前 `grep -o "dut/u_[a-z]*/[a-z_]*" TB | sort -u` 与 RTL 实例端口逐一对账。
- 预防规则: 门 do/TB 与 RTL 同代绑定存档；跨代复跑必须先做层次引用对账。
- 复发: 0

### [2026-10-19] rtl: E203 rdcycle(0xC00) 静默读 0——程序侧帧拍卡尺须用 mcycle(0xB00)
- 症状: testcase 内 rdcycle 逐帧卡尺全部读回 0（raw/delta 皆 0），程序不异常、照常 PASS；wrapper 自带 cyc 计数与 TB cycle_count 正常增长，初判易以为是存储/握手 bug（S5 A2 run01  cyclog 排查实况）。
- 根因: 该 E203 版本 CSR 文件只译码 M 态 0xB00(mcycle)/0xB02(minstret)（e203_exu_csr.v L329-332），ISA 影子寄存器 0xC00(cycle)/0xC02(instret) 未实现，且此版本无非法 CSR 读陷阱逻辑——未命中读选择器输出全 0。mcycle 本体在 clk_aon 上正常累加，0xB00 可读真值。
- 修复: 帧拍测量改 `csrr s5, mcycle`（0xB00）；TB 侧并列保留 wrapper 计数交叉对账。
- 检测门: 任何"程序侧 cycle 记录"落盘前，首帧 raw 值硬门非 0（==0 即停跑查 CSR 译码），并与 wrapper/TB 计数对账同量级。
- 预防规则: E203 bringup 上 rdcycle/rdtime/rdinstret 一律视为不可信，统一 csrr mcycle(0xB00)；**既有 testcase 里 rdcycle 等差断言可能恒真空转（0==0 恒真）**，凡用其作防假过门须复核门价值。
- 复发: 0

### [2026-10-18] rtl: 手抄大常量数组进 TB 期望表 = 转写错一位，硬断言精准报但定位绕弯（S2 OLD1[10] 案）
- 症状: S2 收益门 run3 恰报 2 项 CYCLE_FAIL（L10 层距 + 帧，均差恰 128），数据门/sat 全绿； OLD1[10] 把探针实测 101903 手抄成 101775。
- 根因: 期望常量表（11 层 OLD1/OLD2 数组）从另一工具的文本输出人肉转写，无自校验；错误被"距离恒等式 Σ 恰合帧"半程掩盖——ΣOLD 对了、单项错了时，帧断言过、层断言精准点破。
- 修复: probe2 全态插桩（S1ALL 逐态行）重测定案 ±128 归属后，按定案值改单项；跑前先用恒等式脚本对数组做 Σ/逐项双向自校验。
- 检测门: 门 TB 期望常量表落盘后，跑前用脚本重算"S1D − OLD1 − OLD2 + 2×C_ARM 逐层==已登记期望值"与"ΣOLD − 12×2×C_ARM == S1_FRAME − 期望帧"两个恒等式，不符即先查表再烧仿真时长。
- 预防规则: 跨工具转写 >5 个数值必走机器搬运（脚本生成 init 块或文件 include），禁止手敲；手抄残留必须过恒等式自校验门。
- 复发: 0

### [2026-10-18] rtl: 门 TB 比对臂锚定被消趟状态码 = 比对臂静默消失（fails=0 假全绿）
- 症状: S2 LN 融合消趟后链级门 156-wire 实测只比 132 arm：attn/h2 两臂整层消失，fails=0、sat/拍数断言照过——绿色里缺臂。
- 根因: RTL 消趟（S_ADD1/S_ADD2 拆为不可达码）后，比对调度挂在 4'd6/4'd11 进入拍的 cmp 任务随态不可达永不再执行；而 fail 计数对"没执行"免疫，所有数值断言照常通过。
- 修复: attn 锚点挪至 S_FFN1 进入拍、h2 挪至 S_WRITE 进入拍（窗口只读、时序证明未被覆写），res 抽头改 res_obs 捕获另锚。
- 检测门: 门 TB wire_n 总数硬断言 == 声明臂数（13x12=156）；跑完 grep "wire.*PASS" 计数 == 臂数。
- 预防规则: 任何消趟/状态图改造，门 TB 比对调度逐口核对其锚定态在新状态图可达；wire 计数断言先于数值断言信任。
- 复发: 0

### [2026-10-18] rtl: conv y_scatter 槽瓦像几何上不可产 CHW 平面（scatter→CHW repack = M11 前置项）
- 症状: M10.4 SPPF 4a 想"cv1 出 y_scatter → mp5 直读零新 RTL 交接"，几何证明不可行， escalate 后用户裁定 (c) 改岛级范围。
- 根因: y_scatter 槽内字节律 byte=r*vc+cv（vc≤16 由 5b 位宽钉死），槽基 obuf+stride*b（m9_cmd_issuer sc_base）→ [128,10,10] 产出 addr(c,y,x)=10c+1280y+x 的槽瓦像 = (c,y) 转置；mp5 rd_req 是单发线性 (in0_base, CHW) 读（ppu_mp5_engine S_RREQ），通道间距需 H*W=100，槽内间距最多 vc≤16，stride 只缩放槽号不缩放槽内 r——卡几何补不上 6 倍缺口。3 路独立证明（仿射系数/描述符 (c,h,w) 置换/转置语义）。
- 修复: 4a 范围改岛级+conv ROM 卡（spec §7.0 裁定增补）；scatter→CHW repack 模块（~300 行 .v）债记 M11 前置 RTL 项随 r11 构建合并。
- 检测门: 任何"产者 scatter 槽瓦像 → 消费者线性 CHW 读"的零胶合提案，先算通道间距：槽内间距上限 vs 消费者所需间距，不足即结构性不可行，直接走 repack 立项而非卡几何。
- 预防规则: PPU↔conv 数据面交接设计第一式=写出双方地址仿射式对比；PPU→conv 方向（cat 线性 CHW 产）干净、conv→PPU 方向（scatter 消费）干净，仅 conv 产→PPU 消费要 repack。
- 复发: 0

### [2026-10-17] rtl: K>1024 卷积只能在 walk 门执行——单 conv 金标准遇 2 段 K 剖分 = 结构性死锁
- 症状: 单 conv 独立批（3×3 ic=128 → K=1152）xsim：x/w 流各走满 K tap 后引擎 busy 永不清、y 通路 0 字节、issuer 停在 STATUS 轮询态 prog=0，watchdog 全静止。
- 根因: 操作数 bank 物理深度 1024（写址 [9:0] 回卷），K>1024 的 conv 表自带 2 段 K 剖分（首段 jc=first-无-last + 末段 jc=last/换组）；段对只有 walk 门（cfg_nconv>1，conv 表 nseg 字段 1..3）会执行。单 conv 走 legacy 门：nseg 强制 1，一次 fire 出 first-无-last 的 jc → 阵列累加完一趟即停 S_WAIT 等永不来的末段块，busy 不清，轮询死锁；即便强改单发 jc=first+last，1024 深 bank 也回卷腐数据（长度收口 13b 不报错）。
- 修复: 驱动侧 run-door 律——nseg>1 的普通路径 conv 以 2-conv walk 发射（卡片逐字复制：第二 X/W staging + 第二 obuf 页写同字节 = 跑两遍确定性见证）；全梯回归绿。板级先例 = m94 B06（10x10 vc10 K=1152 6-conv walk）与 5d J04 conv0。
- 检测门: 发射前断言「`len(segs)==1` 或卡片数>1」；golden csr_ref 出现成对 `GEOM=1024/jc=03 + GEOM=128/jc=1D` 而 exp_meta TOTAL nconv=1 = 直接红灯（金标准与运行门不一致）。
- 预防规则: 金标准不止数据要对，运行门必须可达——csr_ref 里的段序必须与 exp_meta 派生的 nconv/nseg 门一致；K>1024 的 conv 永不单卡发射。
- 复发: 0

### [2026-10-17] rtl: TB 空拍条件用待推进发送索引自指 = 恒真死锁
- 症状: 流式 TB `gap = (sx % K == R); if (!gap) sx++;` 在首个 gap 拍后 sx 停推、条件恒真，仿真看门狗触发 rx=5/N 停收。
- 根因: gap 决策依赖的计数器与推进计数器是同一个——gap 拍不推进使条件永远成立（自引用不动点）。
- 修复: 空拍条件改用独立拍计数器 `cyc`（每拍无条件 +1），发送索引仅在不空拍时推进。
- 检测门: TB 看门狗报"rx 停在小数值"即查发送循环的条件自指；门 = 仿真结束必须打印 sent/received 双计数。
- 预防规则: 流式驱动器的节奏控制量与数据推进量必须是两个计数器。
- 复发: 0

### [2026-10-17] rtl: TB `!==` 严格比较挂在比端口宽的连接网 = 未驱高位 Z 假错
- 症状: 源盘 TB 跑 FAIL，定位打印显示权重字节全对、只有 bias/mult 比较挂；值为 Z。
- 根因: TB 网声明 64 位而 DUT 端口只有 40/32 位——output 端口只驱低位，TB 网高位悬空为 Z，`!==` 对任何 Z 位判不等（仿真静默不告警，只有 PCDPC 宽度 warning）。
- 修复: TB 网宽改到与 RTL 端口逐位一致后同向量 PASS；旧 TB 对新 RTL 的端口位宽漂移属陈旧 TB 签名。
- 检测门: 跑第三方/历史 TB 前 `grep "wire.*\[.*\].*<sig>"` 与 DUT 端口声明逐对核宽；vsim PCDPC 宽度 warning 出现时视为可疑而非无害。
- 预防规则: TB 信号声明必须逐端口从 RTL 抄位宽，禁凭旧记忆写宽。
- 复发: 0

### [2026-10-17] rtl: 同拍跨 always 块消费对侧事件寄存器 = 陈旧值 corruption（双槽所有权双连坑）
- 症状: V2 双槽预装仿真挂死 S_QKV/qkv_sub=1；slot0 刚 READY 下一拍被打回 FILLING；请求队列层序错位（layer 0 被装两遍、层序顺延）；q GEMM 能跑（数据已就绪）但 k 的 g_start 被 cur_slot_ready=0 永久门住。
- 根因: ①装载启动拍上，槽状态块 `slot_st[fill_slot]<=FILL` 读到的是**上一轮** fill_slot 寄存器（NBA 跨 always 块同拍可见性=旧值），把刚就绪槽打回填充态；②请求队列 push（ld_req 脉冲）与 pop（fill_start）同拍时 `if(push)...else if(pop)` 吞掉 pop，FIFO 头指针不推进、层序整体错位。
- 修复: 槽状态写改用组合 `fill_slot_sel`（当拍空闲槽译码，与装载块同拍采样同一组合量）；队列 push/pop 改独立 if + `case({push,pop})` 计数（2'b11 净零）。
- 检测门: 跨 always 块同拍握手，消费侧一律用组合选择信号而非对侧寄存器；任何 FIFO 入口必查 push&pop 同拍分支覆盖（case 缺 2'b11 即洞）。
- 预防规则: 双 always 块握手协议中，同拍生效的选择信号必须组合化；队列计数逻辑禁止 if/else-if 链结构。
- 复发: 0
### [2026-10-14] rtl: IP 例化逐端口对 .veo / 手册先行
- 症状: 猜端口名/位宽 → 隐性错。
- 修复: 例化逐端口对生成的 .veo 模板核对；存储/时钟一律官方 IP；用 IP 前查 PG/DS。
- 预防规则: 禁推断式例化（与 prefer-ip-and-manual-first-design、ip-instantiation-from-veo 同源）。
- 复发: 0

---

## board（板上操作）

### [2026-11-05] board: 部署整目录 scp 碾掉板端本地适配——适配面不完整的源（冻结包/旧候选）上传=三连环崩
- 症状: PSPL 驻留链部署后三连崩：①服务端链接缺 `GOMP_parallel/omp_*`（冻结 build 脚本无 `-fopenmp`）；②`SERVER_EXTRACT_FAIL id=1`（冻结 .cpp 覆盖适配版，`find_blob_index_by_name("output0")` 失败，首个请求即断连）；③blob 名变 `"output0\n"`（手修注册表被冻结版覆盖，尾换行读进输出名）。三崩分属三个文件，同一条 scp 命令注入。
- 根因: 板端在部署间演化出**本地适配层**（build 脚本加编译开关、.cpp 改特征抽取节点+关 light mode、注册表去尾换行），而部署源（冻结包/旧候选）不含这些适配；`scp -r <src>/sw <src>/models` 按字节覆盖即碾除。时间戳副作用还会触发重建（.cpp mtime 新于二进制→按缺开关的脚本重编）。
- 修复: 候选覆盖面逐一补全三件适配（加入 scp 清单）后重建重启即通；根治=固化时把全部适配收编进包（包=完整覆盖面），部署脚本改为钉 SHA 校验关键件。
- 检测门: 部署前对账——`sha256sum` 板端现役关键件 vs 上传源同路径件，任一不等先问"差异是不是适配"再传；部署清单必须覆盖 RUN_STATUS/适配台账里列出的**每一个**板端改动文件；传后即时 `sha256sum` 复核+首请求烟测。
- 预防规则: 整目录 scp 只许从「适配收编完整」的源发出；板端任何手修必须在部署清单与 run 记录留名，否则下次部署必被碾。与下条（活补丁竞态）互为连体：先停链，再用完整覆盖面上传。
- 复发: 0

### [2026-11-05] board: scp 覆盖运行中链的脚本/runpy 目标=活补丁竞态——旧链读半态文件 FileNotFoundError rc=9×3 自杀
- 症状: 12:12 部署 scp 覆盖 `p_structural_heads_resident.py` 瞬间，运行中链（PID 20533）连续 3 帧 `FileNotFoundError` RC=9，3-strike 自杀弃测；被覆盖文件恰含冻结版已知路径缺陷（PROG=D 布局路径），旧链读到的是"新文件+旧进程状态"的半态。
- 根因: 运行中进程的每次 runpy/解释器重入都会重读目标文件；scp 覆盖与进程读取之间无任何同步——覆盖窗口内读到的可能是部分写入/语义不配对的版本。与上条同族不同机制：上条是"碾适配"，本条是"活体上换零件"。
- 修复: 部署序列改为**先停链后上传**（pkill 链+服务 → 确认死透 → scp → 钉 SHA → 正典脚本重启）；v2 `deploy_from_package.sh` 已把该序列编码为 step 0。
- 检测门: 任何 scp/覆盖命令发出前 `pgrep -f <链脚本名>` 必须为空；部署脚本无"停链-确认"前置段即禁跑。
- 预防规则: 运行中链的目标文件一律冻结不改；要换文件=先停链（连带 ncnn 服务同生共死对），换完走正典启动。
- 复发: 0

### [2026-11-05] board: 空背景 FP 框几何会跨会话漂移——绝对尺寸阈值过滤被穿透，过滤规则必须锚「结构签名」而非固定尺寸
- 症状: v8n 头空背景 Stop 误检（conf 0.56-0.71）第一会话框高 h=400-417，按 >80% 帧高（>384）布防后下一会话 FP 框缩到 h≈339-343（x0≈5-8 贴左缘、y0=0.0 精确贴顶、w≈215）——20 帧 FP 全部穿过滤滤显示在屏（0 reject），用户看到 0.6+ 置信度误检。
- 根因: FP 是模型对画面左缘竖直结构的伪响应，其框尺寸随场景/锚点选择漂移，**不变的是结构签名**（精确贴某条边 + 跨该轴大比例 + 高置信度）；用绝对尺寸当判据等于把阈值校准在「上一次的观测」上，签名漂移即失效。真手势是紧凑框，从不钉边角。
- 修复: 过滤规则改为签名复合判定——贴任一显示边（±8px）且跨该轴 >60%（640×480 合同下 h>288/w>384）即拒显，保留 >80% 绝对规则兜底；每次拒发 `BOX_PLAUSIBILITY_REJECT` 事件（含 xyxy+conf）留证可调参。nanodet 同策略统一过滤。
- 检测门: 部署后空背景静置 ≥2 分钟断言 `BOX_PLAUSIBILITY_REJECT` 计数与屏上无 FP 框一致（有 FP 过置信门必有 reject 计数对齐）；reject 事件零出现且屏上有 FP = 规则失效立即回炉。
- 预防规则: 几何过滤的判据锚「与帧边缘的空间关系+跨度比例」这类不变签名，不锚绝对像素尺寸；阈值上线前用两个不同会话的实测框分布双向验证（旧签名框与最新签名框都必须命中）。
- 复发: 0

### [2026-11-05] board: merged_v65 手势数据集左右 GT 为演员视角（视觉指左=GT "Right"）——解码出口必须 1↔2 重映射，板上逐项实测为终审
- 症状: 七手势链用户实测「手指向左识别为右、指向右识别为左」；框位置正确（在手上），排除输入镜像；训练侧 v8n 曾现 "Right→Left 塌陷" 同源征兆。
- 根因: merged_v65（及 lrfix/lraug 派生）GT 语义=演员视角：视觉指向左的样本标注 "Right"（人对着自己看方向反转）；lr_retrain 的 mirror-swap 增强忠实保留了该约定（person-pointing-left 样本 GT=Right×2），yaml 类名序 `['Down','Left','Right',…]` 与解码端一致——训练与解码自洽，错的是**语义对观察者的朝向**。
- 修复: 解码出口 `LR_CLASS_REMAP={1:2,2:1}`（显示/判定/top1 全部统一为观察者视角）；用户板上逐项复测「左右已正确，七手势全部验证通过」。
- 检测门: 任何新手势链上板必做**全部 7 类逐项实测且左右各指一次**（含方向类语义核对），仅凭 val AP/连续检出不算过；换数据集先抽查 10 张方向类样本的 GT 标签 vs 人眼看图方向。
- 预防规则: 方向类（左右/上下）标签语义必须以「标注者视角约定」显式记录进数据集 README；板上逐项实测是方向语义唯一终审。
- 复发: 0

### [2026-11-03] board: 把 net3 的「动作触发门」搬上「显示路径」——真手势被全量压掉，模型无退化却表现为"识别奇差"
- 症状: 三任务链手势任务：模型持续检出真手势（Up 0.66-0.69、Thumbs up 0.60-0.66，HEARTBEAT detections=1 连续多帧），但 GESTURE_SHOWN 几乎不触发（2 分钟仅 2 次 ~0.7 的 Stop），HDMI 表现"好多动作识别不出来"；仅 ~0.7 高分偶发出框。
- 根因: net3 原链（`t1_gesture_main.py:1328-1341`）显示策略=**过解码阈值即显示**+防闪 hold，其 min-margin 0.15 是 `--conf` 之后的**动作防翻转门**（1350 行，控蓝牙动作），从不管显示；移植到多任务链时把动作门误搬进显示路径并加严（全类 0.2、拇指类再加 margin≥0.25 且 score≥0.58）——真手势的次类分数常贴近（易混类），margin 门成主要压制面，解码阈值 0.55 之下另有第二层丢失。
- 修复: 回归 net3 正典：解码过阈值即显 + hold 1.5 s，仅拇指类 4/5（空背景误检祸首家族）保留 margin≥0.15 守门（net3 自身防翻转值）；`--min-margin` 默认 0.2→0.15，删除 `--gesture-display-score/--thumb-min-margin/--thumb-min-score` 三个死参数。部署 30 s 内 Up 0.61/Thumbs up 0.69 连续出框。
- 检测门: 移植任何"门"前先读源链源码定位其作用面（显示 vs 动作），以 `grep -n 'margin\|osd\.show\|SHOWN' 源链脚本` 对齐；改显示策略后必须以「模型检出分数分布 vs GESTURE_SHOWN 频次」板端对账（HEARTBEAT top 连续有检出而 SHOWN 稀少 = 门过严的直接指纹）。
- 预防规则: 门控参数移植时禁止顺手加严；"检出但不上屏"类用户反馈先查显示门再怀疑模型。
- 复发: 0

### [2026-11-03] board: 板端回迁多项目共用板卡时孤儿 ncnn 服务器抢占推理端口——链在引擎探测即 ConnectionReset 崩死
- 症状: v3 BIT 部署后链崩：`PL_LOADED` operating 正常，随后 `pose_engine.probe()` → `ConnectionResetError: [Errno 104]`（flex_ncnn.py sendall 至 127.0.0.1:5003）；`ss -ltnp` 见 5003 被 `t1_ncnn_server_hybrid 5003 …/PSPL_YOLOV8N_DUAL/models/c2_registry.conf`（root 起、无消费者）占用。
- 根因: 两个 ncnn 服务为手工长驻（无 systemd 自启），跨项目回迁/他session 部署后旧服务器不清理即被新服务器抢注端口；hybrid 不识别 flex 协议/模型 ID（2=pose pre 等）→ 收包即重置连接。PL/BIT 与 PS 脚本均无缺陷，纯服务拓扑冲突。
- 修复: 杀孤儿（sudo kill，root 属主需 sudo；占位符密码经 `sudo -S` 会静默失败，必须真值经 `$BOARD_PW` 本地展开）→ 原参数重启正主 `nohup setsid t1_ncnn_server_flex 5003 …/pose_registry.conf`（`SERVER_READY port=5003 models=6`）→ 再拉链（ENGINE_READY 全对）。5002 侧 `t1_ncnn_server_multi` 全程未受影响。
- 检测门: 拉链前必查 `ss -ltnp | grep -E ':5002|:5003'` 核对**归属进程+注册表路径**（只看 LISTEN 不够，必须是谁在听）；链日志见 ConnectionReset 于引擎探测段 = 先查端口归属再查代码。
- 预防规则: 共用板卡跨项目切换时，旧项目服务器进程随旧链一并清场；部署脚本 pre-state 段固定输出 `pgrep -fa ncnn_server` + 端口归属快照。
- 复发: 0

### [2026-10-23] board: 板端触发余量薄时 val AP50 是掩盖型指标——不作验收凭据，以板上逐项实测为准
- 症状: v8n PTQ int8 val 掉点仅 -0.20pt（过 ≤2pt 门）但板上左右不分+空场误检；NanoDet-mM val Thumbs up AP50 75.2「及格」但板上 TUP/TDOWN 无法识别（FIRE 置信度仅 ~0.60）。一日两例。
- 根因: val59 小集 AP50 只度量「排序质量」，不度量「触发余量」；板上链路有 score 0.55 + debounce 2 + min-margin 0.2 三级门，余量薄的类在真实背景下过不了门——val 与板端决策是两套阈值体系。
- 修复: 模型验收以板上逐项实测为终判；val 仅作训练对比与初筛。int8 误检按裁决树走 QAT 重训（非调阈值/换 PTQ 参数）。
- 检测门: 上板前查两件——① val 低置信段检测占比（conf∈[0.25,0.55) 的 n_detections 对比 fp32 基线，>1.3x 标记可疑）；② 板上 evidence 的 per-class FIRE score，任一类均值 <0.65 标记「板上必测」。两件其一命中即不得凭 val PASS 上板归档。
- 预防规则: 触发余量 < 安全带的类，val AP50 一律不作验收凭据。
- 复发: 2（2026-10-23 NanoDet v2 int8 PTQ 靶签名定量复现：aciq + infix + 融合头卷积 fp32（nanodet-plus 39ch 头 = 7 分类 QFL + 32 积分回归 logits 同卷积不可分，整体保留）val mAP50 仅 −0.22pt（掉点门过），但低置信段（<0.4）检测数 2.0x（触发余量门 1.3x 判 FAIL）；逐类诊断为跨类广泛背景噪声且 head fp32 后仍膨胀 ⇒ 源在 backbone/neck int8 噪声。**「回归/DFL 头保留 fp32」律防得住砸框、防不住低置信背景膨胀**；段计数比是独立于掉点门的必查项，int8 误检按裁决线走 QAT。run: 2026-10-23_mcontract_nanodet_v2_int8_ptq_run01；2026-10-23 NanoDet v3 int8 PTQ 同签名复发且更重：v3（空场 hard-negative 微调件，fp32 板上已过关）同款 aciq+infix+融合头 fp32 配方，低置信 <0.4 检测数 491/128=3.84x（v2 2.0x，朴素 aciq 4.22x）；G1 掉点门过（管内 −1.33pt）、G4 过、空场保持门过（留出 60 负帧 TDOWN max 0.183<0.40，hneg 抑制经受住 int8，TUP 尾部 fp32 2/60≥0.55 在 int8 反降为 0/60）——唯低置信背景膨胀 + Right 类 in-pipe −9.5pt（49.5 vs 58.98）阻门 ⇒ v2→v3 换权重不改 PTQ 结论，nanodet int8 线须走 QAT 重训。run: 2026-10-23_mcontract_nanodet_v3_int8_ptq_run01）

### [2026-10-23] board: ssh 远程单行里 `pkill -f <pattern>` 模式串同时出现在自己 shell 的命令行里——自杀式匹配把自己的 remote bash 杀掉（exit 255），且连锁暴露 ncnn server 重启=链主必死（单发重连，ConnectionRefusedError 未兜住）
- 症状: 板上换权重流程 ssh 单行 `pkill -f t1_ncnn_server_multi; sleep 2; …重启server…`，pkill 瞬间 exit 255 无输出——remote bash 自己被杀了（其后 mv 日志/重启全部没执行，板面半态：server 死、链随后也死）；链日志 `ncnn_server closed connection` 重连一次后 `ConnectionRefusedError: [Errno 111] Connection refused` 未捕获直接崩（t1_gesture_main.py 只有单发重试，server 未起就死透）。
- 根因: `pkill -f` 匹配"整条命令行含模式串"的进程；ssh 远端 `bash -c '…pkill -f t1_ncnn_server_multi…'` 自己的命令行就含该串 → 自杀。机制面二：t1_gesture_main 的 NcnnTcp 重连是"断连重发一次"级别，对端进程消失（server 重启窗）时没有存活等待循环 → 链必死，所以 **server 重启动作在规划上就等于"server+链双重启"**（10-20 条目修的是"被占线饿死"，本条的"对端消失"是另一个注入路径）。
- 修复: pkill 一律用自守卫字符类写法 `pkill -f "[t]1_ncnn_server_multi"`（模式串不再字面出现在命令行，匹配不到自己）；远程多步脚本必须先落盘成 .sh 再执行，不在 ssh 单行里串 pkill+重启。server 已重启导致链已死时，重拉链必须走 10-21 条目的 quiesce 正典（ees331-camera stop + vdma_halt 寄存器门），不得裸 setsid。
- 检测门: 任何含 `pkill -f` 的板上命令，grep 其模式串若为字面串（非 `[x]` 自守卫）即禁跑；任何"重启 t1_ncnn_server"的计划里若链在跑，必须同时声明"链随后用 quiesce 正典重拉"，否则方案不完整。
- 预防规则: pkill -f 远程用=自守卫 `[x]` 写法 + 多步脚本落盘执行；ncnn server 与链主是同生共死对，动 server 预算里必须含链的重拉预算（含 quiesce 三闸）。
- 复发: 0

### [2026-10-22] board: 多步板测长脚本必须逐步可续跑——r7 第五步 ssh 瞬断 255 把已完成的四步置于"半态"（registry 已换 int8、server/chain 双死），靠续跑脚本 r7b 无损补齐
- 症状: int8 板测 r7 连过 4 步（fp32 双基线 p50 落盘、int8 上传 SHA 对、registry 换挂）后第五步首 ssh 瞬断（exit 255，无输出无自匹配——pkill 已有 [i] 自守卫，机制未定级为瞬断），脚本死，板面停在半态：fp32 链/服务双死、registry= int8。
- 根因: 脚本设计为"一条 set -e 跑到底"，任一步挂死=前功尽弃且板面停在不可预期中间态；瞬断（网络/板端 sshd）在多 ssh 会话长脚本中必然偶发，不是"修好这次"能消灭的。
- 修复: 续跑脚本 `continue_int8_r7b.sh`（同 run 目录，证据连续）：从第五步入口恢复（server 起 int8 registry→int8 双腿测量→registry 还原 fp32 备份→server 重启→as-found 链 relight→终检普查），每段独立可重入。
- 检测门: 板测脚本 >3 步即问一句"第 N 步挂了，我能从第 N 步续吗？"；每步产物落盘（registry 快照/备份）使续跑有锚。
- 预防规则: 多步板测=步骤间锚点（快照/备份文件）+ 续跑入口设计；set -e 长链不配无锚续跑=半成品风险。
- 复发: 0


### [2026-10-21] board: 重启/冷启动后相机服务持久存活，此刻下载 overlay = mid-AXI 重构 → PS 整体静默死亡（ARP 全无声），重链脚本必须先 quiesce + 寄存器级 VDMA 停机门
- 症状: 手势链 v4 首次上板 20 分钟全健康；用户断电重启后，两次"杀链→重拉链"均在启动后 ~40s 网络整体消失（ping/ssh/ARP 全无、/24 扫描无邻居、本机网卡 Up 1Gbps），第二次还在 sudo 提示符中途收到 `Connection reset by peer`；两次死亡都紧跟**重启后**的链启动，第一次（相机服务已死的会话现场）则平安。
- 根因: 2026-10-02 交换机重接线后 ees331-camera 服务的 UDP 对端（PC 192.168.240.2）可达，服务**持续推流不再自灭**（旧"~70s failed-terminal"画像已作废）；zocl 锁 ~54s 自动释放后其 VDMA 仍在 HP 口裸跑。此时 `Overlay.download()` 重构 PL = M13 实证的整机死亡（0-byte console、无 sentinel、ARP 静默，10-02 杀过两轮 S3d）。我们的 relaunch/launcher 脚本完全没有 quiesce 步骤，重启后一拉链就撞雷。
- 修复: 重链脚本（run01/deploy/relaunch_chain_c2_v4.sh）升级为完整 EES-331 quiesce 正典：`systemctl stop ees331-camera`（只 stop 不 disable）→ 进程级确认 → vdma_halt_check.py 寄存器门（MM2S_DMACR/S2MM_DMACR RS bit0 经 /dev/mem 读，双 0 才放行）→ 才准 launcher 下载 bit；launcher 本体加双保险（服务 active 或 camera.py 活着即 FATAL 退出，且**文件内禁写密码**，sudo 密码由调用方 stdin 管道）。同时删除链存活期独立 MMIO 回读 TLBL 段（链持 PL 设备时二次映射必 SIGBUS，硅上 ID 证明已由链内 PlTextOsd 初始化的 PL_TEXT_OSD_READY present:true 承担）。
- 检测门: 任何"下载 overlay 前"的板上脚本必须存在并可执行：`systemctl is-active ees331-camera != active` && `pgrep -f camera.py` 空 && MM2S/S2MM RS=0 三门全过；缺一门即 abort。launcher 文件 grep `echo.*xilinx` 必须为 0 命中（密码落盘检查）。
- 预防规则: 板重启后第一次拉链 = 高危窗口；默认假设相机 VDMA 活着，先证伪再下载。ees331.md 的 M13 条目是本条的机制正典，复发时先重读它。
- 复发: 1（2026-10-22：int8 评测 relight 新写脚本未复用正典三闸，复电后 ssh 一通直拉链 → 整机静默死亡再次复现（reachability 看门狗 30min BOARD_STILL_DOWN，用户两次复电）。检测门强化：任何含 chain relight / Overlay 下载的板上脚本，执行前必须 grep 命中 `vdma_halt_check` 三闸序列，未命中即禁跑；「复用正典脚本」优先于「重写新脚本」）

### [2026-10-20] board: VDMA 3 槽 ParkPtr 欠采样同 index 连胜 ≠ 流停滞——fps 比近槽数倍数时 index 混叠锁定，必须二次用 ring 内容仲裁
- 症状: 手势链反复 "VDMA_STREAM_STALLED slots=[2,0]" 自杀（帧 114/231/278）；零写入隔离 run 死于 114 帧，而同一 bit、同一 --no-text-osd、仅把检测从"8 自杀"放宽为"8 转储/16 自杀"的取证 run 活过 1400+ 帧（30 分钟+），远超全部历史死亡窗；日志只见 4~7 连胜 WARN 后自愈，8 连胜转储从未触发。
- 根因: 检测按推理节拍（~0.87fps）采样硬件 ParkPtr(0x28)；相机 ~30fps 时 fps_cam/fps_read≈33.6 接近 3 的倍数，index 采样**混叠锁定**，比率漂移即"自愈"。无写场景的三次死亡全是稳定推理窗内 8 连胜假阳性→链自杀。与上条 genlock 写环冻结是**叠加的两种机制**（写环真冻时 ring 内容同样停止变化，内容仲裁照抓不误，复发①的 5s 真冻不因本修复漏报）。
- 修复: 同 index 连胜时对 S2MM 驻留槽做内容采样（pynq buffer invalidate + 4KB 比对）：内容变=混叠，复位计数（VDMA_ALIAS_RECOVERED）；index+内容双冻才算停滞。写环禁令不变（常驻/周期 PS 写环仍是硬件真冻诱因，静态文字走 PL OSD——C4 已按双阶段 word_valid/word_data 架构落地）。
- 检测门: 任何"按周期采样离散索引判活"的检测器，先算 fps_上游/fps_采样 mod 槽数是否≈0；集成测试用近公度比率压 8+ 连胜场景；对照实验固定其余变量只动检测阈值。
- 预防规则: 欠采样离散状态判活必须配与索引独立的内容/计数仲裁信号，二者同冻才报警。
- 复发: 0

### [2026-10-20] board: genlock VDMA 显示环帧率级 PS 写入（pynq flush 或无缓存 store）冻结整环——TextOsd 必须变更触发、严禁周期写环
- 症状: C2 板端链（ps-preproc）跑 2~26s 随机 `VDMA_STREAM_STALLED`（PARK 双指针冻结）→ HDMI 黑；camera.py 任意 bit 4/4 稳（70s~30min）。完整对照矩阵：① 链+TextOsd **每帧 flush**（pynq buf.flush() 清 CMA 显示环缓存）13s/5.5s 死 2/2；② TextOsd 改 /dev/mem O_SYNC 无缓存直写（零 flush）后：62s 稳、26s 死、7s 死（服务 bit 也死）——**冻结跟随"帧率级写环"而非 bit**；③ TextOsd 全禁（E1）T1 bit 80s+ 稳；④ 无文本=无写（横幅空）62s 稳；⑤ 服务器 80s 满载锤击下 camera.py 稳（PS 负载无罪）；⑥ T1 bit+camera.py 70s 稳（bit 静态无罪）。C1 48min 长跑无此难的原因：C1 横幅无检测时为空串，TextOsd 空转、零写环。
- 根因: 机制未到底层（疑与 genlock 主从同步在 CPU 突发访问 HP 口时的 race/仲裁有关），但**统计律硬**：帧率级写显示环 5/7 死（≤26s），不写环 0/9+ 稳（含 camera.py 4/4、E1、空横幅、90s 服务 bit 链——后者 TextOsd v3 化前 90s 稳系横幅常 burn 无检测即变体差异，样本已修订为写环即险）。pynq flush() 帧率化显著加速死亡（2/2 ≤13s），无缓存写只降频不死绝 → flush 与周期写是叠加因子非必要因子。
- 修复: TextOsd v3（t1_gesture_main.py）：**变更触发**（label 文本变化才 burn，轮换/检测出现才写，检测保持期按 C1 先例逐帧随分数变更新烧）、20ms 轮询、/dev/mem O_SYNC 无缓存写、永不 flush、烧全 3 槽延长闪现。部署后 T1 bit 三网轮换 run 待验证。
- 检测门: 链日志 `VDMA_STALL_WARN` 连发→`VDMA_STREAM_STALLED`=环冻结指纹；任何对 VDMA 环的 PS 写路径评审必查"写频率"（帧率级=拒；**常驻=拒——见复发①，0.83Hz 常驻也 5s 死**）；冻后恢复=服务 bit 重载或重启链（重新 VDMA start）。
- 预防规则: 流式 genlock VDMA 环在跑时**禁止一切非事件驱动的 PS 写入**——律条精化：不是"帧率级"才禁，而是"内容不变的周期性重写"必死（v3.1 复发①：空闲横幅 1.2s 定时重烧同一内容，启动 ~5s/第 4 次 burn 即冻，0.83Hz 与 5Hz 同罪）；**只允许内容变化触发的 burst**（C1 检测保持期短 burst 28 次/48min 为安全上限参照，单次 episode 预算 ≤10 burns）。常驻 OSD 文字需求走 PL 侧（C4），PS 侧只保留闪现级标注 + 检测保持期预算内续命。排查环冻结先二分"谁在写环"（grep buf.flush/copyto/mmap 写环路径 + 定时器 reburn），再看 bit/负载。
- 复发: 1（①2026-10-20 当日：v3.1 TextOsd 给常驻横幅加 1.2s 定时 reburn → 启动 ~5s VDMA_STREAM_STALLED 复现；修 v3.2=空闲空 label 零写 + persist 预算 ≤10 burns/episode + 模型标识仅切换时一次性闪现。律条由"禁帧率级"精化为"禁常驻周期写、burst 预算化"）

### [2026-10-20] board: t1_ncnn_server_multi 单客户端串行——链持有长连接时任何外部客户端永久饿死，链 30s 超时自杀
- 症状: C2 链正常跑着，PC 经 ssh 端口转发连上 :5002 发批量评测请求；链几秒内 `TimeoutError`（sock.recv 30s）直接崩溃退出，HDMI 画面冻结。pgrep 一度显示进程还在（setsid sudo 包装残留假象），实为已死。
- 根因: 服务器 accept 后进入该连接的请求循环直到对端关闭才回到 accept；**链的 NcnnTcp 连接是长连接（永不关闭）**，所以链一旦连上，后续任何客户端的连接都只能在 listen backlog(=1) 里排队、永不获服务。批处理客户端持有连接连续发 120 请求 ≈ 100s+，链的推理请求全部饿死 → socket.timeout 未捕获 → 主循环崩。
- 修复: ①NcnnTcp.infer 对 timeout/断连一次性重连重发（链不再因服务器被占而崩，t1_gesture_main.py）；②工程律：板上评测必须**链停采**（或批客户端逐请求短连接且确认无人占线）；根治需服务器改并发（fork/select），记 C2 维护项。
- 检测门: 计划让第二个客户端连 t1_ncnn_server(_multi) 时先确认链未运行（pgrep）；链日志出现 sock.recv TimeoutError 即此指纹。
- 预防规则: 该服务器=单客户端独占资源；任何"边跑链边评测"的设计直接判不可行，不用试。
- 复发: 0

### [2026-10-20] board: 活链状态下复用探针脚本——Overlay() 默认 download=True 热重配 PL，AXI 主机挂死整板
- 症状: 手势链正在跑（VDMA/推理活跃）时，为做"独立活性复验"执行旧 stage3_liveness.py：脚本
  第 4 行 `Overlay("...bit")` 无 download=False → 构造即重下载 bitstream；数秒后板卡失联——
  ping 100% 丢包、无 ARP 项、ssh connect timeout，PS 级硬挂，只能物理重新上电。
- 根因: pynq `Overlay(path)` 构造默认 **download=True**（静默重配 PL）。链仍持有 PL（VDMA 在传、
  CPU 可能正阻塞在 AXI 事务上）时重配 fabric = 打断在途 AXI 主机事务；Zynq 上 AXI 主机挂死不可
  软件恢复，连带拖垮内核网络栈 → 整板无响应。探针本意只是 MMIO 读 CSR，重配纯属脚本副作用。
- 修复: 板上活性复验一律用 MMIO-only 探针，或 `Overlay(path, download=False)`；旧脚本复用前
  先通读全文再执行。已挂死的板无软件恢复路径，物理重新上电后按 quiesce→重传验 sha→重启链流程走。
- 检测门: 任何将上板执行的 .py 先 `grep -n "Overlay("`，凡无 `download=False` 且板上已有链/服务
  持有 PL → 禁跑；判据=运行态 `pgrep -af gesture_main|ncnn_server` 非空即触发门。
- 预防规则: 对活系统只读探针禁止构造 Overlay；Overlay 构造=重配动作，与"下载 bit"同级管控
  （先 quiesce 全部 PL 属主，再重配）。
- 复发: 0

### [2026-10-20] board: UDP 传输层"单 recvfrom + 不读 socket 的 drain"——一次失步终身失步，回读恒定滞后一拍
- 症状: 手势链经 PC 桥下发机械臂：臂实际动作全对（位置链逐次累计=写帧被收），但每个动作 final 位置回读必超时（ACTION_DONE `ok=false, final=null`）；下一动作的 pos0"读到的"恰是上一动作的最终位置（跨类逐值对上，如 1335→1411→1491）；偶发 `no_readback`（滞留帧不含所查舵机号时）；同代码上午会话曾 13/13 全过——单次失步后不可逆。
- 根因: `UdpBle`（t1_gesture_main.py）传输层设计缺陷：`send_frame` 每帧只 `recvfrom` 一次把应答存 `_pending`，`rx_drain` 只派发 `_pending`、**从不真正读 socket**。正常时请求/应答严格交替无碍；但 UDP 任一失步事件（重复包/丢包/空 ACK/上电通知积压）后，一个应答滞留在 OS 缓冲里，此后每次 `recvfrom` 都吃前一帧的应答——错位管道自我永续：pos0 收上一 final（误显示为成功），final 收到写帧 echo（模式不匹配）→ 恒 null。无再同步能力，重启进程才清零。对照 `BleUart`（MMIO 环形缓冲 drain）无此缺陷。
- 修复: `rx_drain` 改为非阻塞 `recvfrom` 循环真正排空 OS UDP 缓冲（finally 恢复 `settimeout`）。修复后同一板同桥 8/8 动作 ok=true（含 6/6 HOME 回读，final 与 target 差 ≤5us）。
- 检测门: 臂链日志出现「pos0 == 上一动作 target/final 值」或「全部 final=null 但臂确实在动」即此失步指纹；判据命令：`grep ACTION_DONE chain.log | grep -c '"ok": false'` 连续 >0 且桥日志每笔有应答。
- 预防规则: UDP（或任何流式传输）的 drain 必须真正消费 socket，不得只派发单次 recv 的缓存；"请求-应答锁步"设计必须自带再同步（每次 drain 清空缓冲），否则按单次失步=会话报废论。
- 复发: 0

### [2026-10-18] board: ppu_shell_top 错误上报粘着至 rst —— 岛错误探针之间必须整岛硬复位全愈合
- 症状: M10.4 岛级 xsim 梯首个 loader 错后，后续一切派发（含好表）全 abort 或挂死：负例梯 N1 错码 01、N3 变 0x26，walker 永不回 idle。
- 根因: ppu_shell_top 错误上报（ldr_err_valid_o/dma_halted_o）**粘着至复位**（"错误上报（粘着至复位）"头注），粘着后壳拒发一切新任务；walker 的 eng_err=ldr_err(电平)||dma_halted(电平) 每派发即触发，码还停在首错值。CTRL 软复位只 wash DMA/壳 16 拍（f7_top swash），xsim 内最稳=整岛硬复位。M10.3 烟 TB 当时把负例排最后所以没炸——顺序依赖不是豁免。
- 修复: TB/板梯律：任何错误探针（期望 abort 的负例）之后、下一探针之前=整岛硬复位+CTRL/DMA_CFG 重臂+表重装（板律4"全愈合"同款正典）。M10.4 梯照此改后 61 检查全绿。
- 检测门: 岛梯出现"错码与期望不符/好表也拒"时第一查壳错误粘着面（XMR ldr_err_valid_o/dma_halted_o 电平）；判据=负例探针序列中每探针独立复位。
- 预防规则: 岛级负例永不背靠背；错误探针=一次性脏岛，愈合成本计入探针预算。
- 复发: 0

### [2026-10-18] board: PPU 岛板上四律（M10.4 岛级梯固化，须嵌入一切岛探针脚本）
- 症状/根因/修复: ①帧首探针必须 MP5-first（帧首 CAT 是动移植裁决遗留已知错因；MP5-first 不过则 ADD-prepend 降级并记台账）；②量化 profile 死端口 {0x14,0x15,0x17,0x18} vs 活集 {0,3,4,9,A,F,10,13,16,19,1A-1F}——pack 构建期断言所有 desc w5 与段 prof 合法性（mk_pack_sppf assert_port_legality 内建）；③ring-31：每帧 wr(0x060,1) ACK + arm 轮询 drain(0x064==0x068) + 错误字 W1C 0x018；④探针间全愈合（粘着错壳见上条；半净窗写会 SIGBUS）。
- 检测门: 岛探针脚本评审单四律逐条打勾；pack 无端口合法性断言=不予上板。
- 预防规则: 四律进 overlay skill 岛侧检查单（PPU_ON bit 类构建全适用）。
- 复发: 0

### [2026-10-17] board: fclk 重钉静默失败三连环 —— pynq Clocks 残 / SLCR 锁吞写 / div1 掩码漏 bit
- 症状: 重启后整条八门梯跑在 31.25MHz（zocl 下载默认）而门脚本无任何报错——fclk 重钉"成功"假象；自行 SLCR 直写后 TICK 又测出 10.000MHz（div0=20 却按 50 报）。
- 根因: 三坑叠加。①pynq `Clocks` 重启后残（`RuntimeError: No Devices Found`），setuptools 路径全断，不能依赖。②Zynq SLCR 默认写锁：直写 FPGA0_CLK_CTRL(0xF8000170) 前必须先写 UNLOCK(0xF8000008)=0xDF0D，否则**写入被静默吞掉且读回旧值**——纯假回读，无任何报错。③div1 字段 [25:20] 的清除掩码写成 0x3F3F00 漏 bit22，旧 div1=4 残留 | 新 div1=1 → div1=5 → 20×5=100 分频 = 10MHz。
- 修复: `board/fclk_pin2.py` 正典=unlock→(before & ~0x3F003F00)|(div0<<8)|(1<<20)→读回→可选 relock(0x767B@0x04)→TICK 实证门（真 50.000 = div0=20 div1=1，×2/3 律下=请求 75）。
- 检测门: 凡下载后必跑 TICK 实测（0x43C10000+0x54 计数器 2s 窗）；TICK 数 ≠ 50.000±1 时第一动作查 SLCR_FPGA0_CLK_CTRL 实际 div0/div1（读回可能撒谎=被锁吞写，需结合 TICK 交叉验证）；时钟相关门全部 FAIL 而 TICK 非标称值时先修时钟再判门。
- 预防规则: 板上 fclk 只走 fclk_pin2.py 正典；pynq Clocks 类高层 API 用前必探活（try/except 落证据）；SLCR 写后永远 TICK 交叉验证，禁止"读回==写入"即验收。
- 复发: 0

### [2026-10-17] board: sticky-err 幽灵 —— 锁存类 err  brick 后续所有帧，"polls=1 即死"优先疑状态残留
- 症状: 同一硅片上连跑多个门，某门失败后后续**所有**门（含必过的基线门）都在 polls=1 即死、err 码相同（如 err=6/prog=80），换时钟/重跑均复现；prog=80 与任何本门逻辑无关。
- 根因: issuer `S_IDLE: if (start && err==8'd0)`——err=6/7/9 类（S_HALT）**锁存至复位**，锁存期门铃全被忽略；后续门 poll 循环第一次读 STATUS(0x3C) err[15:8] 即见旧 err → `final_err != expect_err` 立即 die；prog(0x40) 是上一跑到终值的进度残影。err=11（hbuf OVF）报告级不锁存，不 brick。
- 修复: 门梯序中凡遇锁存类 err（6/7/9 及一切 S_HALT 码）→ 判该门后**必须重下载净硅**再继续后续门；判门先看"polls 是否=1 + err 是否前一门同款"，是则该 FAIL 记为状态残留伪证、本门须净硅重测才有效。
- 检测门: "polls=1 即 FAIL"永远先查硅片 sticky 态（读 0x3C err 再空打一门铃看 err 是否保持非零）再疑本门缺陷；多门梯 RUNBOOK 必须显式标注每门 err 码的锁存性（报告级 vs S_HALT 级）。
- 预防规则: 驱动层加"门铃前 err 探活+非零即重下载"或每门独立进程+下载（慢但免疫）；RTL 文档侧给 err 码表加"锁存性"列。
- 复发: 0

### [2026-10-17] board: mmap 字写入铁律二犯 —— 驱动 w32 用 struct.pack_into，AXI-GP 上确定性 scrambling
- 症状: v2b_rel 驱动（2e 时代遗留）在 g3r8 硅片上所有写 cfg 的门全在 polls=1 死于 err=6（门铃采样 cfg 全零→legacy nseg 卫）；同 cfg 用 5d 驱动（numpy 写法）则正常行走。修后（numpy uint32 视图）同一驱动 err=6 消失。
- 根因: `struct.pack_into("<I", mmap, off, val)` 4B 写在 AXI-GP CSR aperture 上字节 lane 确定性错位（scrambling）；`np.frombuffer(mmap, uint32)[off//4] = val` 为唯一正典写法（板上 mmap 字写入铁律）。5d 驱动本来就是对写法，新旧驱动并存时对比即定位。
- 修复: v2b_rel w32 换 numpy 视图（与 5d 对齐）；症状"写后读回乱序字节/全零效应"一律先 grep 驱动 w32 实现。
- 检测门: 板侧驱动合入前静态扫 `struct.pack_into.*mmap\|pack_into.*<I` 模式；门 FAIL 且"写入疑似未生效"时先回读所写寄存器验字面值，再疑硬件。
- 预防规则: 板上驱动模板统一从 5d Window 类（numpy aw 视图）派生；铁律入 overlay skill 板侧检查单。
- 复发: 1（铁律已知，驱动副本未统一根治）

### [2026-10-14] board: 计数器口径混用 —— 每帧自清计数器当累计计数器做 delta，帧 2 起恒 0
- 症状: 语义链板上数据面全绿（arena 逐字节、err=0、ledger 全对）唯独 per-frame chain delta 从帧 2 起恒 0，门 FAIL；单帧仿真/单帧板跑永远正常。
- 根因: CHAIN_CNT 是**每帧绝对**计数器（硬件在每次 doorbell start 沿清零、帧内累计本帧交付字节），驱动却仿照真累计 ABI 计数器（0x44/0x48/0x4C）做 running-cum wrap delta → 帧 2 起 abs(8192)-cum(8192)=0 构造性归零。xsim TB 只跑单帧，仿真侧不可见。
- 修复: 该计数器直接取绝对读数做门（驱动 sha 06f37878）；「先探活寄存器再定口径」——probe 出 0x58=mask 未清、0x5C=8192 绝对值后才定位到驱动而非 RTL。
- 检测门: 任何「帧 N 起恒 0/恒定」型计数异常，先问该计数器清零边在哪（start 沿？帧尾？代际？）；多帧板跑必须进验收（单帧仿真掩盖此类口径错）。
- 预防规则: 给每个 ABI 计数器标注口径（累计/每帧绝对/事件 sticky）进 SPEC；驱动 delta 表按口径分行，不共用一个 wrap-delta 模板。
- 复发: 0

### [2026-10-14] board: 修好的文件传错副本 —— 修在 A 目录、上传 B 目录的陈旧拷贝，sha 相同=同一个旧文件
- 症状: 「修复」上传后板端行为零变化，排查两轮才发现上传物 sha == 旧文件 sha。
- 根因: 同一驱动存在多份副本（board/ 根 vs c01b_staging/），编辑了根副本，scp 却从 staging 拷贝取材；两副本同名同角色。
- 修复: 上传后 sha256 的对象必须是**被改过的那个文件**；在板端 grep 目标定律（如 chain=chain）确认命中再跑。
- 检测门: 上传后比对「host 被编辑文件 sha == board 收到 sha == 期望新 sha」，三者缺一即停。
- 预防规则: 单一批次只保留一份登台拷贝（多余副本当轮删除或软链）；上传命令路径从编辑路径复制粘贴，不手拼。
- 复发: 0

### [2026-10-14] board: 链式语义在分裂 arena 上必 OVF —— 地址空间归属是 RTL 契约，不是驱动能绕的 —— 地址空间归属是 RTL 契约，不是驱动能绕的
- 症状: C01b 语义链板上 `BOARD_FAIL err=11 (E_CHAIN_OVF)`，prog=8 即黏住；xsim 同一 golden 全 PASS。CAP0/计数器全对，唯独链 serve 全零响应。
- 根因: hbuf 窗口检查 `head_addr[31:15]==slot_base[31:15]` 在**原始 X 读地址**上做。冻结发行者用 `cfg_xbase+plan偏移` 发链式 X 读，而 slot_base 捕获自 `cfg_ybase+同一plan偏移`（原地链）。TB 把 X/Y 共址同一 arena（xbase==ybase==0，plan_base 复位 0）两空间重合所以仿真必过；板驱动默认分裂 arena（x@0x20000000 / y@0x22000000，相差 32MB）→ 窗口必不匹配 → 每条链读都 OVF。曾试驱动侧把 X 平面搬进 Y arena 共窗绕过：X 足迹 [0,x_tot) 落进 golden 比较窗（该处 golden=0x5C 毒尾）→ arena_err≠0，且「跑后重写回毒尾」是伪造比较，被诚实门否决。
- 修复: adapter 层地址平移 `hb_lr_addr = lr_addr - cfg_xbase + cfg_ybase` 后送 hbuf（m9_intra_axi_top_v3）。基差 32KB 对齐（生产者槽对齐律）→ 窗口位 [31:15] 1:1、BMG 索引位 [14:3] 不变；TB 恒等（0-0+0）golden 不动；plan 内部偏移错配类（T2 OVF/T3 stall）不受影响（平移是每帧常量）。DDR 路径永不平移。
- 检测门: 凡「同一 plan 偏移经两个不同基 CSR 译址」的链路，先问两基是否同 32KB 窗；板门 err=11 而 xsim 同 golden 过 = 空间归属错配指纹。
- 预防规则: 设计窗口/槽类契约时把「地址空间归属」写成显式契约（谁的空间、何时平移）；TB 单 arena 拓扑天然掩盖此类错配，板门必须是验收的一部分（板上验证强制优先律）。
- 复发: 0

### [2026-10-14] board: TB/驱动的 golden 覆盖窗口定律
- 症状: arena_err=98304 但计数器全对 —— golden 只填了 64KB，比较窗 163840，后半窗 poison vs exp=XX。
- 根因: 驱动 y_tot 只算 cards×obuf_stride，没对齐 TB 的 Y_TOT 比较窗。
- 修复: `y_tot = max(cards*stride, TB_Y_TOT)`，poison 填充。
- 预防规则: golden 生成器的覆盖窗永远 ≥ TB 比较窗，poison 填充缺口。
- 复发: 0

---

## toolchain（脚本/编码）

### [2026-10-27] toolchain: 跨目录 glob 未展开且循环未断言预期数量——`sha256sum` 报错后仍打印 6/18 伪 PASS
- 症状: run06 基线核验循环写 `for f in ... scripts/*.py`，但当前工作目录不是目标目录；通配符保持字面量，`sha256sum .../scripts/*.py` 报 `No such file or directory`，后续仍输出 `RUN06_BASELINE_IDENTITY_PASS files=6 pyc=0`，实际只核了五文档和零个脚本。
- 根因: shell glob 相对**进程当前目录**展开，不是相对循环中拼接的 `$dst`；终行仅打印累计 count，未断言预期 18，单项命令失败也未形成独立总门，导致错误输出后仍能生成 PASS 文案。
- 修复: 保留 iter01 失败原件；五文档与脚本分组，脚本用 `"$dst"/scripts/*.py` 在目标目录实际展开，再由 `${p#$dst/}` 求相对名；终门同时要求 `count==18 && pyc==0`，否则非零退出。修正后实测 18/18 一致。
- 检测门: 批量 hash/copy 审计必须打印实际展开清单并断言精确数量；任何 `No such file`、字面量 `*` 或数量不足均使整批 `HARNESS_INVALID/FAIL`，不得继续写 PASS。跨目录 glob 一律对绝对目标模式展开。
- 预防规则: 不把 `set -e` 或终行文案当作批量完整性门；数量、精确集合和逐项命令结果必须独立闭合。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: RTL 改名后拍数表端点名不跟改——闭链仪查表落空回落 1 拍默认绑，viol 虚增 +72 呈假"越线恶化"（sta_l aghB_r 顶替 lo/hi@3 实案）
- 症状: submission26 呈报 150MHz v5 FF viol 389→442（+53），归因"remap 轮盘"呈报；审计独立仪器复算=370，差 +72 全部落在 aghB 族路径——拍数查表落空的路径按 1 拍默认绑（15,088.7/1拍）全部虚增为 viol。连带"施加态 min period=15,088.7 FAIL"亦为同一假象。
- 根因: 闭链适配器从旧版抄 V4 拍数表时，键 `aghB_r`（刀A 前旧名）顶替了改名后的 `aghB_lo_r`/`aghB_hi_r`（@3 拍）——活树早已无 aghB_r（L1358-1360 仅 lo/hi），表键与活树漂移后**无人对账**；`dict.get(key, 1)` 的默认 1 拍绑把"查不到"静默变成"按最紧绑"， viol 只涨不降，天然像"轮盘恶化"被误归因。复制-改写仪器时手抄表键=第二漂移源（第一源=RTL 改名本身）。
- 修复: ①表键勘正（lo/hi@3，对照 sta_j 正确版逐字核）；②仪器内置**拍数表端点名对账门**：表内每个端点基名 grep 活树 rtl/ 全树（`\b<name>\b`），缺席即 FAIL 非零退出（sta_l 版已实施，17 名全过）；③勘正块机制同 submission24——原报保留标 supersede，真值重出，净额与收口不受影响。
- 检测门: 闭链仪/段表仪器输出头必须有 GATE 行（端点名核查数+缺席名单）；跑任何呈报前 grep 仪器拍数表键集合 vs 活树寄存器声明（`grep -c "reg.*<名>" rtl/**/*.v` 为零即拦）；viol 环比异常**只涨**且集中单族=先疑查表落空（默认绑），再疑轮盘。
- 预防规则: RTL 落刀含改名/拆寄存器（*_r→*_lo_r/*_hi_r）时，拍数表/SDC/仪器三处同批改并进落刀 checklist；复制适配器**禁止手抄表键**——必须从上一正确版仪器 diff 拷出，拷后必跑对账门。审计裁定升级为落刀后固定检查项。
- 复发: 1（首案 2026-10-23 submission24 analyze V3-only 假 FAIL——同族"表版本与 RTL 版本不跟改"病；本条目为第二实案，对账门为根治件）

### [2026-10-23] toolchain（脚本/编码）: ncnn2table 表激活行=层输入(bottom-blob)尺度，非输出尺度——拿它当本层输出 fq 尺度会把 conv0 输出剪到 ±0.502、cls 支路整体塌零
- 症状: 伪量化 QAT 模型 val mAP50 崩到 ~0.25→0；逐层探针见首层 out_absmax==输入 absmax(0.502)，box 支路存活仅 cls 塌。
- 根因: ncnn2table 对每层只记录 bottom-blob 统计——KL log 里 /model.0/conv/Conv 的 max=0.501961(=128/255 输入 absmax)、/model.1 的 max=46.34 才是 conv0 真实输出范围；表行=该层输入再量化尺度（fix_input_scale 补丁能修首层输入剪裁即因此）。层间输出requant由下一 conv 的输入行体现。
- 修复: 伪量化只 fq 本层输入（行尺度）+ per-out-channel 权重 fq；输出不做 fq。修后伪量化 cls_max 0.7126 vs fp32 0.7054、argmax 5/5。
- 检测门: 对照 KL log 首行 max 是否==输入 absmax（128/255）判行语义；QAT 冒烟探针 conv0 out_absmax 必须 >1（≈输入 absmax 即剪错）。
- 预防规则: ncnn 表行一律按「消费层输入尺度」用，禁止当生产层输出尺度。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: 评测推理缓存按输出路径键控——工件同名再生成时静默复用旧原始输出，跨候选指标逐位相同伪装成「两候选等价」
- 症状: QAT 第二轮（qat02）导出新权重后，val59 评测的 fp32/int8 两 cell mAP50/ndets/lowconf 与第一轮（qat01）**逐位相同**（0.8863991098102281 级 16 位一致），gate 电池结果完全复现；一度据此误判「两轮 best 都是 ep1 所以权重相同」。
- 根因: eval 推理脚本缓存命中条件=输出文件存在（按 cell 目录路径键控），工件 param/bin 同名覆盖再生成后缓存不失效；第二轮 118 张 raw 输出全部「cached」直接跳过推理，评测的是第一轮工件。两候选数字相同是缓存假象，不是权重相同（SHA 实则不同）。
- 修复: 缓存键改 sha256(param+bin) 存 `_artifact.sha256`，变了即清重推；打印 old->new stamp。
- 检测门: 任何「同名工件再评测」流水线，复测数字与前次逐位相同且推理日志出现 cached/跳过即缓存命中——必须打印工件 stamp 并断言变化后重推；跨候选对比表两列 16 位一致=先查缓存再下结论。
- 预防规则: 评测/推理缓存一律工件内容寻址（sha256），禁止纯路径寻址；「两候选指标完全相同」默认是 bug 直到证明不是。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: M 合同 QAT 训练器必须继承 MContractTrainer（preprocess_batch 不 /255）——继承 DetectionTrainer 双重 /255 训练致模型适配 ±0.002 输入、val 0.87→0
- 症状: QAT 训练 loss 稳步下降（box 3.5→2.7）但 epoch val mAP50 0.248→0.0006→0；存档 EMA 模型在正确尺度 blobs 上 cls_max≈0.002（=0.7054/255 量级）。
- 根因: M 前端 m_front_uint8 已产出 (u8-128)/255，MContractTrainer.preprocess_batch 只 .float()；DetectionTrainer.preprocess_batch 额外 /255.0 → 训练输入被二次缩小 255x，模型权重适配该错误尺度，正确尺度输入下输出塌零；训练 loss 正常反而掩盖。
- 修复: QATTrainer 基类改 get_trainer_class()（MContractTrainer）。
- 检测门: QAT/任何自继承 trainer 首 epoch val 必须≈起点权重 val（±5pt）；存档模型在 eval blobs 上 cls_max 必须≈fp32 参考（0.7 量级），<0.01 即尺度错配。
- 预防规则: M 合同链一切 trainer 子类必须从 m_letterbox_dataset.get_trainer_class() 派生。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: ultralytics 8.4 训练器末段 "Validating best.pt..." 重载 ckpt 并 model.fuse()——inner Conv 被 delattr('bn')，QAT/自定义 wrapper 直接 AttributeError
- 症状: 训练循环与 epoch 内验证全过，末段重载 best.pt 打 "Model summary (fused)" 后崩 'Conv' object has no attribute 'bn'。
- 根因: BaseModel.fuse() 对 Conv 做 fuse_conv_and_bn 后 `delattr(m,'bn')` + 换 forward_fuse；trainer 最终验证从盘重载权重走 fuse 路径。epoch 内验证用内存 EMA（未 fuse）所以不触发。
- 修复: wrapper 的取参改 getattr(inner,'bn',None)，bn 缺失即按已折入态用 conv.weight/bias（正是部署语义）。
- 检测门: wrapper 对「无 bn 的 Conv」冒烟前向必须过；is_qat() 只认 ModelOpt TensorQuantizer，自研 wrapper 不享受 fuse 跳过。
- 预防规则: 给 ultralytics 模型挂 wrapper 时，参数访问一律 getattr 带默认值并兼容已 fuse 态。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: ultralytics 8.4 ckpt["model"]=None、训练权重在 ckpt["ema"]（fp16 存储）——后处理脚本取错键即 NoneType/半精度炸
- 症状: torch.load(best.pt)['model'].eval() → AttributeError 'NoneType'；取 ema 后前向炸 "Input type float and bias type Half"。
- 根因: 8.4 存盘结构 ckpt={'model':None,'ema':<EMA module .half()>,...}（省盘/加速加载设计）。
- 修复: model=(ckpt.get('ema') or ckpt['model']).float().eval()。
- 检测门: 任何消费 ultralytics ckpt 的脚本先打印 keys 与取值类型；前向前 assert 参数 dtype==float32。
- 预防规则: 8.4+ ckpt 一律 `ckpt.get('ema') or ckpt['model']` + .float() 后再用。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: M 合同前端 transform 类为 _MComponents.build() 闭包局部定义——Windows spawn 下 dataloader workers>0 pickle 必炸，训练/验证 workers 必须 0
- 症状: workers=4 启动即 AttributeError "Can't get local object '_MComponents.build.<locals>.MContractFormat'"。
- 根因: m_letterbox_dataset 惰性构建的 MContractFormat/MContractDataset 是函数内局部类，不可 pickle；Windows spawn 模式 dataloader 子进程需 pickle dataset（含 transforms）。
- 修复: workers=0（与蓝本一致，单进程加载）。
- 检测门: M 链任何训练启动前确认 args workers==0；报 Can't get local object 即此坑。
- 预防规则: M 合同链训练 workers 恒 0，提速只能靠其它路径。
- 复发: 0

### [2026-10-23] toolchain（脚本/编码）: QAT 权重 fake-quant 尺度每前向跟随当前 absmax——单通道权重逃逸自激放大（实测 4004x）引发缓燃后断崖式塌训
- 症状: 伪量化 QAT 训练 val mAP50 稳定 0.84-0.89 十余 epoch 后单 epoch 断崖（0.82→0.33→0.07），train loss 同步跳升后卡死（cls 4.4）；降 LR 只推迟断崖（ep6→ep12）不治本。
- 根因（两层）: ①权重 fq 尺度 s=absmax(w)/127 每前向从当前权重重算时，通道内最大权重经 STE 获得「未量化自由生长」通道（它定义 s，自身恒不被量化），持续梯度+权重衰减失衡下单调长大→整通道其它权重被粗化到 0→特征塌。实证：塌训 ckpt 的 model.0 通道 absmax 4003.85（健康值个位数）。②**更深一层：即便 s 冻结，STE 在 clip 边界仍无不动点**——clip 后的前向保持产出同一边界梯度（dL/dq|边界），经 STE 直通原权重，把已饱和权重持续推出边界（权重衰减是唯一回拉力，失衡即逃逸）；断崖延迟 ∝ 1/lr（lr5e-3→ep6、1.5e-3→ep12、8e-4→ep22），伪装成「降 LR 有效」。
- 修复: ①权重尺度 wrap 时按折入 BN 后权重一次性标定、register_buffer 冻结（ModelOpt 同型设计 amax-as-buffer）。②**raw 权重每前向投影到 ±127·s（逐出通道）**：forward 内 no_grad 就地 clamp conv.weight 到 ±(127·w_scale/sf_bn)（WGAN 式 lazy projection）；边界处梯度归零、只有 wd 回拉，构成真不动点。标定初值处数学上 clip 恒为空操作（folded absmax 是逐位置上界）。
- 检测门: QAT 训练中途 ckpt 抽查 max(per-channel weight absmax)（健康=标定值量级，>100x 即逃逸）；val 连续 3 epoch 降幅 >0.1 即停查；断崖延迟随 lr 减半而翻倍 = 本坑特征指纹，不是「lr 选对了」。
- 预防规则: 一切自研 fake-quant QAT 的权重尺度必须冻结为 buffer，禁止每前向 absmax；且必须配套原始权重投影（±127·s，折入 BN 因子换算回 raw 域），「冻结尺度即自限」是错觉。
- 复发: 1（2026-10-23 v8n QAT qat02：冻结尺度后 lr8e-4 仍 ep21→24 断崖 0.84→0.03，延迟恰≈1/lr；按层②机制回填本条，不建新条目）

### [2026-10-23] toolchain（脚本/编码）: OSS CAD Suite yosys.exe 裸调缺 libreadline8.dll——bin 之外还须 lib 上 PATH（environment.bat 两目录同设）
- 症状: sta_c 跑批 `yosys: command not found` → 补 bin 后 `error while loading shared libraries: libreadline8.dll: cannot open shared object file`——两次起爆才进综合（sta_b 期脚本为何能跑：上次会话 shell 残留环境变量，新会话必复炸）。
- 根因: 6_tools/yosys 是 OSS CAD Suite 绿色包，DLL 全在 lib/（bin 无副本）；Windows 加载器只搜 exe 所在目录+PATH，bin 单独上 PATH 不够。environment.bat 的 `PATH=%ROOT%bin;%ROOT%lib;%PATH%` 两目录同设是权威配置，任何"只加 bin"的精简都踩。
- 修复: 跑批脚本 `export PATH=/f/chip_design/6_tools/yosys/bin:/f/chip_design/6_tools/yosys/lib:$PATH`（bin+lib 同设）。
- 检测门: 新会话首跑 yosys 前 `yosys.exe -V` 冒烟（连版本号都出不来=环境没设全）；写 yosys 跑批脚本时 grep 是否同时含 yosys/bin 与 yosys/lib。
- 预防规则: 绿色包工具链一律按 environment.bat 全量设 PATH 再跑批，不信 shell 残留环境。
- 复发: 0

### [2026-10-22] toolchain（脚本/编码）: `local a=$1 b="...${a}..."` 同句引用 + set -u = bash5 unbound variable，且 Git Bash python3 可能是 Microsoft Store 存根
- 症状: 板测脚本 r1：`local mid=$1 name=$2 ev="...${mid}..."` 函数入口即报 `mid: unbound variable`（set -euo pipefail 下整个测量零执行）；r2：`python3 - <<EOF` 打统计报 "Python was not found; run without arguments..."（Store 别名存根）。
- 根因: bash 的 `local a=.. b=..${a}..` 整条语句先求值后赋值——同句引用前面的 local 变量恒为空，set -u 下直接死（老 bash 宽容、bash5 严格，同脚本换环境才爆）；Git Bash 的 python3 默认解析到 Microsoft Store 别名 stub，真解释器要用绝对路径。
- 修复: local 拆句（先 `local mid=$1 name=$2` 再 `local ev="...${mid}..."`）；本机统计用 "C:/Users/Administrator/AppData/Local/Programs/Python/Python312/python.exe" + Windows 风格参数路径（E:/...，MSYS /e/ 路径 Windows python 打不开）。
- 检测门: bash 函数里 grep `local .*=.*\${`（同句引用型 local）；脚本首跑前 `python3 -c "import sys;print(sys.executable)"` 验证非 Store 存根。
- 预防规则: set -u 脚本里 local 一律拆句；Git Bash 调 python 一律绝对路径。
- 复发: 0

### [2026-10-21] toolchain（脚本/编码）: 同一 Vivado 会话重复 source 构建 tcl——`array set` 是合并不是重建，删键后的旧表键复活截停门
- 症状: r12 build tcl 第 6 次 source：M11A_SHA 表在文件里只剩 11 个键（两个改钉到新表），但门循环仍对 m9_intra_top_v3.v 报 m11a_pin_drifted——表内出现了文件里已不存在的第 12 个键。
- 根因: Tcl 的 `array set` 对已有数组是**合并键值**，不先清空；同会话上一次 source 残留的完整 13 键数组被静默保留，本次只覆盖同名字段。构建 tcl 在 MCP 长会话里被反复 source（门截停→修复→再 source 正典），数组只增不减的编辑永远炸不出来，只有**缩小表**时才现形。
- 修复: 每个 `array set` 前 `catch {array unset X}`（数组可能不存在）；7 张会话级表全量加装。
- 检测门: 发布前静态审查——构建 tcl 内 `array set` 的数量必须等于 `array unset` 数量（grep 对账）；任何「同会话重复 source」正典下，表定义一律视为有残留风险。
- 预防规则: 一切可能被重复 source 的 tcl 脚本：数组表先 unset 再 set；标量 `set` 无此险（覆盖语义）但数组/命名空间必须显式清零。
- 复发: 0

### [2026-10-21] toolchain: 并行重训共享源目录冒出第二份 labels.cache（用户裁定不追归因，已收口关闭）
- 症状: PL-front yolo11n 重训（2026-10-21_t1_plfront_yolo11n_run01）期间，共享源目录 merged_v65/train、dataset/valid 出现两份 labels.cache；其内容 sha256 与本 run 自有 ds_cache 产物**逐字节一致**；清除后 1-epoch 完整复现证实当前代码不再写源目录。
- 根因: 未定位到具体写入方（嫌疑=并行重训写竞争或 ultralytics cache 路径解析落源目录）。**用户 10-21 裁定：交付权重已过 mAP 门+net3_ps_only 板上全链验证，污染未达交付链，根因考古无意义，关闭。**
- 修复: 清除源目录多余 cache；1-epoch 完整复现实验证实当前训练代码路径不写源目录。
- 检测门: 训练开跑前对共享源目录冻结 cache 清单（`find <src> -name 'labels.cache' | xargs sha256sum` 存证），训练结束后 diff——任何新增/变体 cache 先取证（sha256 + mtime + 写入方 lsof/audit）再清除，禁止直接删。
- 预防规则: 并行重训共享数据集时，cache 写落点必须在开训前显式核定（args 落 run 目录）；共享目录出现陌生生成物一律按"并发写竞争嫌疑"处理，先取证后清理。
- 复发: 0

### [2026-10-20] toolchain: 生成器产物陈旧残留——生成脚本升级后磁盘 hex 从未重生成，缺陷被单字门掩盖
- 症状: font16.hex 仅 1520 行（63 字 0x20~0x5E），ROM/TB 数组声明 2048 词，0x5F 以后读 X；rtl/ 与 sim/ 两份 sha 一致（同一陈旧文件），排除拷贝失同步。门表现：G2 单字 "A"（大写、覆盖区内）像素级 PASS，G4 "Hi" 爆（小写 'i'=0x69 缺字区）。
- 根因: 磁盘 hex 是旧版生成器（字符域截到 0x5E、无词数断言）的残留产物；生成器后升级为 0x20~0x7E + 内嵌 assert 2048，但**产物从未随生成器升级重跑**——脚本与产物版本脱钩。
- 修复: 重跑 gen_font.py（assert 拦截词数），rtl/ 与 sim/ 双份重拷 + sha256 对账一致；门 rerun 全 PASS。
- 检测门: 引用任何脚本生成数据（hex/mif/coe/bin）上仿真/综合前，一律先重跑其生成器并核对 DONE 标记 + 行数/词数断言 + 双份 sha；`wc -l` 对不上期望值即停，不进门调试。
- 预防规则: run 目录里来历不明的生成产物禁止直接引用——「先重跑生成器、后引用产物」是默认动作；排查"部分字符对、部分错"的图形缺陷先查字模覆盖域再查光栅化。
- 复发: 0

### [2026-10-20] toolchain: pyncnn 1.0.20260526 同进程第二次 Net 生命周期必段错误——ncnn 推理必须子进程隔离
- 症状: gate4 ncnn-vs-onnxruntime 数值门脚本第一个推理正常打印（RAND max_abs_diff=1.022e-03），随后 segfault（bash exit 139），无任何 Python  traceback；带 `with net.create_extractor() as ex` 上下文管理器路径与显式 del 路径均崩。
- 根因: pyncnn wheel 的 Net/extractor 对象在堆上累积损坏——首个 Net 完整生命周期（load_param/load_model/create_extractor/extract）后，同进程内创建第二个 Net 即触发原生层段错误（nanodet 线 10-18 只踩到"单 Net 重复 extract 段错误"并已绕，本次连"每调用新建 Net"也崩，属同族更深一档）。
- 修复: 每次 ncnn 推理 = 独立 `python -I g4_ncnn_worker.py in.npy out.npy` 子进程（脚本内只活一个 Net），父进程收 .npy 结果对拍；6 次推理零崩溃。
- 检测门: pyncnn 批处理脚本凡需 >=2 次推理，先跑 2 推理冒烟（循环两遍同输入对拍），exit 139 即切换子进程隔离；报告里禁止出现"进程内首个 Net OK"就推断批量 OK。
- 预防规则: E:/competition 全工作区 pyncnn 使用一律"一进程一 Net"；需要循环推理时直接写子进程 worker，不先试进程内复用。
- 复发: 0

### [2026-10-19] toolchain: 自由流水链验证——posedge 层次探针撞 NBA 竞态假绿；消费点必须按数据存活窗逐拍核对（V3.4 q01x 坑）
- 症状: V3.4 gemm requant 7 段流水，q01_r 压缩结果拍 T+1 产出、拍 T+3 被 wide 级消费时数据已前进到 T+1 列（q23_r 还是 T 列）→混积 ±1..±44，四形状 ~40% 写错；但 posedge 采样探针"验证通过"假绿。
- 根因: ①流水段间消费窗错位——中间结果寄存器的"生产拍"与"消费拍"之间隔着其他段推进，只验寄存器间恒等式（同拍读同拍比）验不出跨拍存活错位；②ModelSim posedge 时刻在层次引用上读 DUT 寄存器撞 NBA 更新竞态，采样值不定→假绿。
- 修复: q01x_r 保持级（对齐修复级）+ **negedge 逐拍全信号追踪**（tprobe.log 逐段比对定位）。
- 检测门: 自由流水链每个中间结果列出"生产拍/允许消费拍窗"，验证探针按存活窗跨拍对账；数值门 fails 数与分段预期写数独立核对（不能只看过/不过）。
- 预防规则: 流水 RTL 验证一律 negedge 采样；恒等式验证之外必须做端到端写值对账。
- 复发: 0

### [2026-10-19] toolchain: 观测口累积值类 bug 对逐元素流观测不可见——sat 差分与均值类累积必须端到端对账（ln P1 双驱动坑）
- 症状: ln P1 均值双驱动（退休窗与 mean/clear 同拍撞 sum1_r，NBA 后写优胜）静默丢元 63；res_obs 逐元素比对全对（流值本身正确），只有最终均值/累积和错。
- 根因: 观测口设计为逐元素流时，只覆盖"每个元素的值"，覆盖不了"元素如何被累积"；同拍多驱动在 NBA 语义下是后写优胜，仿真不报错、逐元素观测看不见。
- 修复: 尾拍独立（mc1=70）消同拍碰撞；sat 差分（ln_sat=43 语义）+ 均值端到端对账作门。
- 检测门: 凡有累积/求和/饱和计数的数据通路，门必须含累积结果端到端断言（对金标累积值），不能只验逐元素流。
- 预防规则: 与"不可观测断言"坑同族——观测口盲区清单化：逐元素流看不见累积类 bug，必须补端到端锚。
- 复发: 0

### [2026-10-19] toolchain: 解析回溯/报告输出做算术——首末行特殊格式（START FF/endpoint）是 regex 漏配高发区，缺守恒自检时残差静默挪账（1.7ns 坑，审计 W-1）
- 症状: 用 `re.search(r'arr=(\d+)ps', line)` 解析 mini-STA 逐单元回溯求时延分位：START FF 行格式是 `arrival=1344ps`（"arrival=" 不被 `arr=` 匹配），首单元 1,716ps 延迟整体漏计——comb 算成 48,111ps（真值 49,827ps），漏值被默默并入"每段固定开销"（1,602→3,318ps），推出的一套 fmax 表全部偏移；下游门槛/判据跟着错（本例衍生出预注册判据 11.6ns 自相矛盾，审计 W-2 另开）。
- 根因: 报告输出的首行（START FF）与末行（endpoint/path logic levels）格式与正文不同（键名 arrival/arr 混用、带斜杠分隔字段），单模式 regex 首行即漏；漏配不报错只少数据，做差/求和时残差静默流进另一个记账格，总量守恒（51,429=51,429）所以任何一行都看不出错。
- 修复: regex 双模式（同时匹配 `arrival=` 与 `arr=`）或按行类型分支解析；解析后**内置守恒自检**——comb 必须等于 sta_report 基准值（49,827ps=到达 51,171−ck→q 1,344），不符即 assert 死，不产出表。
- 检测门: 任何"解析回溯/报告→做算术"的脚本，输出表前打印 comb/总开销并断言与独立基准（报告摘要值）一致；切点/分位表的索引列与源文件行号抽查对位。
- 预防规则: 解析器带固定自检项（守恒 assert）；审计/复核方复跑脚本比对输出逐字一致（RERUN-IDENTICAL）作为第三方门；首末行特殊格式列入解析 checklist。
- 复发: 1（衍生 W-2）


### [2026-10-18] toolchain: ModelSim 10.1c $fgets 对宽 reg 字符串排布不可靠（截断/串位/出 X）——逐字节清单解析一律 $fgetc
- 症状: TB 用 `$fgets(linebuf, fd)`（`reg [8*1200:1]`）读清单文本：返回 nc 与行宽不符（64B reg 恒读 64、1200B reg 时字节落在非预期位置），首字节读出 00，低位字节出现 X；解析结果 0 条目或乱码，且 $display 看不出病因。
- 根因: 10.1c 的 $fgets 对「宽度远大于行长」的向量不是"左对齐填充+保持其余位"的干净语义（实测字节落位随 nc/宽度变化，并伴随未初始化 X 渗染），属实现层不可靠；不是文件编码、不是 BOM、不是索引算错（三项均已排除）。
- 修复: 逐字节 `$fgetc` 循环自解析（EOF=-1 退出；',' 切字段；CR/LF 切行；空白跳过；定位 part-select 写字节 `fstr[fcur][W-8*p -: 8]=c` 防序反）。
- 检测门: 清单解析后第一行 $display 帧数 + 帧 0 dir==预期路径的等值断言（frozen 门），不符即 FATAL 不进仿真。
- 预防规则: 10.1c 文本清单解析禁用 $fgets，只用 $fgetc；解析结果必须过等值自检门。
- 复发: 0

### [2026-10-18] toolchain: ModelSim 字符串字面量右对齐 vs 解析串左对齐——`==` 比对恒 0，但 %0s/$readmemh 照常工作（静默失效门）
- 症状: TB 内 `FROZEN_DIR = "F:/..."`（`reg [8*128:1]`）与逐字节解析出的同路径 `fdir` 做 `==` 判 frozen 臂，恒 0——冻结锚断言整块静默跳过；而同变量的 `$display("%0s")` 与 `$readmemh({fdir,"/g_x.hex"})` 都正常工作，仿真"全绿"且无人察觉锚未生效。
- 根因: Verilog 字符串字面量按普通赋值规则**右对齐**（末字符落在 LSB 字节），而逐字节定位写的解析串是**左对齐**（首字符在 MSB 字节）；ModelSim 的 %0s 与文件路径转换会跳过/压缩 NUL，两种排布显示与开文件都正确，只有逐位 `==` 暴露差异。
- 修复: 字面量赋入后先自测长度（从 LSB 数到首个 NUL）再 `<< 8*(W-len)` 左对齐化，然后比对。
- 检测门: frozen/锚类字符串比较前，$display 双方 %0s 之外再加 `==` 自检（解析首帧 dir==FROZEN_DIR 必须 1，否则 FATAL）。
- 预防规则: 宽 reg 装字符串做等值比较，一律先统一对齐（推荐一律左对齐化），禁裸 `==`。
- 复发: 0

### [2026-10-18] toolchain: 清单/脚本文本带 UTF-8 BOM（EF BB BF）——首行首字段被吃掉/污染，注释判定失效
- 症状: Write 工具产出的 .txt 帧清单首行 `#...` 被解析成数据行（9 行清单读出 9 帧、dir 首字节是乱码），`#' 开头注释门全部绕过。
- 根因: 文件头三字节 BOM（EF BB BF）被当作字段内容打包进 fstr[0]，首字节不再是 '#'；BOM 之后一切正常，所以只有首行中招。
- 修复: 解析器开局 `$fgetc` 首字节若是 0xEF 则连吞三字节 BOM；注释判定看字段首字节 == '#'。
- 检测门: 解析后 `nframes == 预期帧数` 硬门（不符 FATAL）；首帧 dir 等值自检同上一条。
- 预防规则: 任何自解析文本格式（清单/表/配置）解析器一律先剥 BOM；且解析结果必须帧数+首字段双自检。
- 复发: 0

### [2026-10-18] toolchain: vcover merge 6820 守卫把 vlog 路径分隔符风格当源码指纹
- 症状: `vcover merge` 多 UCDB 时 (vcover-6820) "Source code mismatch ... skipping code coverage merge for design unit work.X"——同一磁盘文件、同一库、同一宏集，仅跳过特定批次编译的 DU；合并视图退化为早批并集。
- 根因: vcover 的 DU 同一性指纹含 **vlog 命令行里源文件路径串的分隔符风格**（`F:\a\b.v` ≠ `F:/a/b.v`），与文件内容、库名、宏、时标、优化上下文、-f/显式传参均无关（逐项微探针排除）；vcover report 的 `File:` 展示层统一归一正斜杠、UCDB 内嵌源码逐字节相同，都不能证明指纹一致。第二坑：`vlog -f filelist` 把单反斜杠当转义符吞掉（ENOENT），filelist 内须写双反斜杠，`vlog` 解转义后记录的单反斜杠串才是指纹。
- 修复: 失配批次用与保留批次**完全相同风格的路径串**重编译重跑（本例 T1/T2 经 PowerShell 传 `F:\...`，T3 经 bash -f 传 `F:/...`，把 T3 filelist 改双反斜杠重跑后 6820 消失）。
- 检测门: merge 批处理脚本对 vcover 输出 `grep -c 6820`，非预期 0 即停；归因用单文件 10ns 微探针（vlog 两式 → vsim -coverage 存 UCDB → vcover merge 对踢）二分编译选项，勿从 report 展示层推断。并查合并产物有无 **mis-homing 假账**：任一输入 UCDB 单独 report 不存在的文件段出现在 merged by-file 视图（症状例：从未插桩的 TB 文件冒出大段 stmt 覆盖）即 10.1c 工件——skip 的 DU 覆盖错位挂到无关文件记录，by-file 头数作废，须重编译统一指纹后重 merge。实例级（byinstance）视图不受指纹门影响，可用作交叉判据。
- 预防规则: 同矩阵多跑次的覆盖率 UCDB 要可合并，**所有跑次 vlog 源路径串逐字符一致**（推荐全部走同一 runner 脚本）；跨 bash/PowerShell 混跑时把路径风格纳入跑次 checklist。
- 复发: 0

### [2026-10-18] toolchain: vsim 内核 localhost socket 被外部 HTTP 探测击杀（vish lost connection，多代理并发期高发）
- 症状: 长仿真跑到半途（死点每次不同）`** Fatal: (vish lost connection to vsim process / Kernel lost connection to front end process)`，包装脚本收非 0（127/1），log 无 RTL/TB 错误；重试可过、死点漂移 = 非确定性环境事件。变体（2026-10-18 S3 集成期）: 击杀发生在仿真启动前——vsim.exe 存活（内存 ~4MB 不动）、log 尾停在 `vsim work_xxx` 行、`run -all` 无任何输出、process_status 不生成，等同挂死。
- 根因: 外部 Go-http-client 类 HTTP 探测命中 10.1c 前端↔内核 localhost IPC socket；多代理同机并发仿真期碰撞概率显著上升。
- 修复: 原样重试；重试前 tasklist 核查残留 vsim——**先核对命令行归属再杀**（同机他代理 tb 会话与自家残留外形一致，误杀=毁别人跑次）。逮全机 vsim 清零窗口发车通过率最高。启动期变体: 杀残留 vsim.exe（确认归属后 taskkill //PID //F）→ 原脚本重跑。
- 检测门: log 尾出现 "lost connection" 字样 → 环境击杀定性；查 process_status 与门标记行缺失定位死点；功能判据（TEST_PASS/计数器逐值）缺席即该跑次无效。启动期变体检测门: 后台跑 vsim 后 log 文件 ~2 分钟体积不涨 + 无 "run -all" 后输出 + vsim 内存恒定在几 MB = 启动期击杀挂死，直接杀进程重试，不等超时。
- 预防规则: 多代理并发期安排 vsim 长跑，预期可能被击杀 1-2 次，超两次仍杀再升级（错开时段/申请独占窗口）；coverage 跑成败判据=UCDB 体积+门标记，不看 exit code。
- 复发: 4（2026-10-18 当日 mergedall fix v2 两连杀后第三跑过；2026-10-18 S3 集成 probe 启动期变体一次，杀残留重跑；2026-10-24 xsim 机制变体一次——兄弟 run 看守退火全局 taskkill 谋杀在飞 xsim，独立变体条见 vivado-sim 分区 [2026-10-24]，双向互链）

### [2026-10-18] toolchain: vsim 无错误静默中途退出（exit 1，transcript 停半途，vsimk 消失）
- 症状: ModelSim SE-64 10.1c 链级长仿真跑到 ~2/3（L7）无任何 ERROR/FATAL，vsimk 进程消失，包装脚本收 exit 1；重跑一次原样通过（PASS 且逐拍一致）。
- 根因: 瞬态进程崩溃（无错误输出、无 license 信息、同输入重跑即过）——非确定性环境层事件，与 TB/RTL 无关。
- 修复: 原样重试一次成功。
- 检测门: 包装脚本 process_status exit≠0 且 log 尾无 ERROR/FATAL/TIMEOUT → 记日志（原样保全）后原样重试一次；第二次同点失败才进入真排查（换工具/分段仿真）。
- 预防规则: vsim 长仿真一律后台跑 + 结果文件存在性门（CHIP_MODELSIM_RESULT 行），不以进程退出码单独定成败。
- 复发: 1（2026-10-18 当日，S2 集成门探针）

### [2026-10-18] toolchain: python 程序化补丁 TB/RTL 插块锚在用法之后 = vlog-2730 先用后声明
- 症状: vlog-2730 Undefined variable（always 块引用声明在下的信号）/'Formal must not be an array'；10.1c 按编译顺序解析模块内声明。
- 根因: 补丁脚本把新 always 块插在锚点（如 wire 声明）之前；同一坑 S2-prep 单元 TB 已踩过一次（run_note §7）。
- 修复: 声明/块位置互换（声明锚到文件前部既有声明群）。
- 检测门: 程序化补丁后先跑 vlog 单文件编译门或 pyslang 全层 elaboration（`UsedBeforeDeclared` 必须为 0）再启长仿真；vlog-2730 报错先看声明顺序而非逻辑。
- 预防规则: TB 补丁脚本的插入锚永远选"既有声明群/定义区"，新块插在最后一个声明之后；补丁即附编译门。
- 复发: 4（2026-10-18 当日 x2：S2 探针 TB + S2 门 TB；2026-10-28 wholegraph TB 九声明前移，pyslang 29 errors→0；2026-11-02 task_coco/pose_osd.v 块搬移——xvlog 2025.2 [VRFC 10-3380] V2001 与 -sv 双模式皆拒用法先于声明，always 块移至全部声明后解决）

### [2026-10-18] toolchain: xsim $readmemh 文件缺失只警告 = ROM 保留 X → 表全写 X → walker 读 w0=X 静默卡 W_ENG
- 症状: M10.4 岛梯 LCHAIN 腿 walker 进 W_ENG 但 req 永不脉冲、零 AXI 流量、done 30M 拍超时；诊断 XMR w0_q=xxxxxxxx。文件是 prep 生成器写成 desc_CHAIN.hex 而 TB 找 desc_LCHAIN.hex——一个名字的差别。
- 根因: xsim $readmemh 打不开文件**只打 WARNING 不失败**，ROM 数组保留旧值（首腿=X）；TB 随后把 2048 个 X 词写进 desc 表 CSR，port A 读回校验过（读的是 X？不——读回校验 vs desc_rom 同 X 同值"自洽通过"），walker port B 读 X → w0_valid=X → if(x) 走 else 分支进 W_ENG 又不派发。
- 修复: 生成器改名对齐 + TB load_leg 加 $fopen 存在性硬门（fail 计数）+ N 腿显式别名文件。
- 检测门: TB 一切 $readmemh 前置 $fopen(f,"r") 存在断言；仿真日志 grep "cannot be opened" 必须为 0（CI 门）；ROM 全写后抽 1 词与独立源比对防 X 自洽。
- 预防规则: ROM 文件名契约（生成器/TB 同名表）入 prep 生成器单一事实源；xsim 日志 WARNING 段逐条评审。
- 复发: 0

### [2026-10-18] toolchain: 并行线就改共享 rtl 树 = 构建基线漂移（冻结快照门）
- 症状: M10.4 岛梯跑到一半 xelab 突然报 Module ppu_seg_done not found（f7_top 被加 M10.6 seg_done 例化），而该模块不存在于任何 compile list；前后两轮 elaboration 结果不可比。
- 根因: 5b src/rtl_ppu 活树被并行的 M10.6 线就地改（ppu_f7_top/shell/walker/engine_mux + 新增 ppu_seg_done.v，全未提交）；共享树在多线并发期不是稳定基线。
- 修复: 把 git HEAD 已提交态（b6901b9f M10.3 状态）整树拷进本 run src_rtl_snapshot/ + compile list 指向快照 + sha256 记台账；活树脏文件归并行线所有，绝不代清。
- 检测门: 跨线共享 RTL 树参与仿真的 run，开工时 sha256 全树登记，收官比对——中途变化即快照重来；elaboration 报错含"Module not found"且名单外=先疑基线漂移。
- 预防规则: 仿真/构建 compile list 只指向 run 内快照或已提交态（git show HEAD 导出），不指活树相对路径。
- 复发: 0

### [2026-10-17] toolchain: vsim -c do 内 $stop 暂停宏 = backend 挂死等 process_status
- 症状: run_modelsim_backend 跑满 TimeoutSeconds 抛 launcher 超时；log 尾停在 "MACRO ./xx.do PAUSED at line N"，process_status.txt 永不生成。
- 根因: `vsim -c -do` 批处理中 TB 的 `$stop` 暂停 do 宏执行（断点语义），宏剩余行（含 quit）不执行，vsim 不退出 → 包装脚本等 vsim 退出码写状态文件等死。
- 修复: 复用/移植第三方 TB 时把 `$stop;` 改 `$finish;`（我的副本可改）；必须在 .do 里 quit 的场景改用 $finish 收。
- 检测门: backend 超时 → 先 grep log "PAUSED at line" 命中即此坑；TB 入库前 grep '\$stop' 清零。
- 预防规则: 所有走 backend 的 TB 以 $finish 收，禁 $stop。
- 复发: 0

### [2026-10-18] sim: TB AXI slave B 响应多挂一拍 → 岛侧 b_acc 双计数 → wr_done 精确等式永不成立 → PPU ADD S_FLUSH 静默挂死
- 症状: M10.3 3b b8main PPP 触发岛 ADD：读 320 拍/写 160 拍（期望值全到）后引擎永远停在 S_FLUSH（asm_idle=1 wr_done_all=0），walker W_ENG 静默等、issuer S_PPPW 停车，xsimk 100% CPU 空转，2s watchdog 要烧约 8 小时 CPU 才出 FAIL。
- 根因: TB m3 写 FSM state2 无条件续拉 bvalid 且仅以"看到 bvalid&&bready"退出——bvalid 每 burst 实际高两拍；岛 ppu_dma_master `bready=1` 常开，b_acc 每 burst 双计，b_cnt 走 2,4,6…；wr_done 判据是精确等式 `b_cnt_r+1==aw_cnt_r`（10 burst），偶数序列永远命不中 → wr_done 永不来 → 引擎 S_FLUSH（asm_idle&&wr_done_all）卡死。读通道无此病（state2 在退出同分支撤 rvalid）。
- 修复: 单周期 B 律——state2 收到 bready 当拍即 `bvalid<=0` 并回 idle（deassert exactly on accept）；写 FSM 与读 FSM 同构化。（更正：当时认定"读通道无此病"是错的——见下条 R 通道同款。）
- 检测门: 任何 AXI 响应通道（R/B）valid 必须在"被采样当拍"撤除；TB 挂死排查先数 beat 期望值（本案 rbcnt=320=2×160、wbcnt=160=1280B/8 全对即数据面无罪，锁定握手/完成锁存）；对"valid 高几拍"加 $display 拍级断言。
- 预防规则: AXI TB 从机 R/B 响应一律"接受当拍撤 valid"；对侧 DUT 用锁存型精确判据（等式/阈值）时，TB 计数器必须拍级对账（每 burst 恰好 1 响应）。
- 复发: 0

### [2026-10-18] sim: TB AXI slave R 通道"陈旧数据重放"竞态 → 岛引擎字节流静默错乱（serve log 完美反成烟雾弹）
- 症状: M10.3 3b b8main/b8mainf 岛 ADD 跑完但 add_diff=1247/12485（近全错）；serve log 逐拍对 golden 全对、AR/AW 地址全对、beat 数 3200/1600 全对——数据面"零证据"却输出与任何 (a,b,quant) 线性组合无关（最小二乘 rms=20）。
- 根因: TB m3 读 FSM state2 收到 rready 后回 state1 装下一拍时**不撤 rvalid**——state1 整拍 rvalid=1 但 rdata 还是上一拍（NBA 装载在拍末）。岛 ppu_dma_master `rready=!r_skid_v`：上一拍落 skid 后若下游恰在窗口内取走（r_skid_v→0），state1 那拍 rready=1 → **同一拍被双收**。双收节奏随 funnel/FIFO 反压漂移 → 引擎字节流插入重复拍、从第 0 字节即错。serve log 写在 state1（每装载记一次），天然把重放拍滤掉，形成完美烟雾弹。ADD 引擎 V2.1 几何无关（chw 线性流），故烟测大 FIFO 深场景不发作、窄面必发作。
- 修复: R 通道同律——state2 收到 rready 当拍 `rvalid<=0` 再回 state1；state1 装载+置 valid，state2 纯呈现（每拍恰好一次握手，数据在呈现期稳定）。
- 检测门: "log 正确≠DUT 收到正确"——对偶计数器（TB 装载拍 vs DUT 侧 skid 收拍）必须对账；AXI 从机三律齐验：AR/AW 一请求一响应、R/B valid 接受当拍撤、rdata 在 rvalid 期间稳定（无装载拍泄漏）。
- 预防规则: TB AXI 从机 R/B FSM 一律两段式（装载拍 valid=0 / 呈现拍 valid=1），禁止"呈现-装载复用拍"。
- 复发: 0

### [2026-10-18] toolchain: TB 包文件 if/else 模式串全等 + SV `string.substr(i,j)` 含端点 → 静默载入错资产包伪装 RTL 存储腐坏（连踩两轮）
- 症状: xsim 岛级 TB 轮次 expect="pack23adv" 因 `expect_mode=="pack23"` 全等落入 else 分支载入 25 包；slot14 呈现"BRAM 内容由 0x112 变 0x114 且零写使能"的完美假腐坏。修复时改用 `substr(0,6)=="pack23"` 二踩——SV substr **含端点**，"pack23adv".substr(0,6)="pack23a"≠"pack23"——同一假象复现第二轮。
- 根因: ①模式枚举未穷尽（if/else 用全等把未知模式静默归入 else 默认资产）；②IEEE 1800 `substr(i,j)` 返回 i..j 含端点子串；③回读校验与加载同源（同一 rom 数组），错包也能"回读全对"，假象自我一致，四路探针全部指向"内容真变了"。
- 修复: 显式枚举 `=="pack23" || =="pack23adv"`；TB 加载后加数组级直探检查点（ARRPROBE）对磁盘文件差异字（本案词 448 即 14 号槽 w0）。
- 检测门: TB 开头横幅打印实际载入文件路径 + 轮次名；加载后直读 BMG memory[] 与磁盘 hex 逐字对（probe 模式）；任何 if/else 资产选择必须 else 分支 fail-fast。
- 预防规则: 轮次/模式字面量全部穷举且 else=fail；SV substr 一律 `substr(0,len-1)` 或改用显式比较；加载与回读校验必须跨源（磁盘文件≠内存数组）。
- 复发: 0

### [2026-10-18] toolchain: xsim.bat 参数吞噬三坑（-testplusarg 转义 / 裸 xsim.exe 静默空转 / 快照引用名）
- 症状: xsim.bat 传 `-testplusarg X=Y` 打印 usage "Expected a switch"；裸调 xsim.exe 零输出静默"假跑过"（exit 0 无仿真）；快照写 `work.snap` 报错。
- 根因: bat 包装对含 `=` 参数转义不一致；快照引用用裸名 + `-R`；xelab 顶层必须 `lib.top` 前缀。
- 修复: 轮次选择改编译期 `xvlog -d X1_ROUND_*`（禁 plusarg）；`xsim.bat <snap> -R -log <log>`；`xelab work.tb work.glbl -s <snap> -L <ip_lib> ...`。
- 检测门: 仿真日志开头必须有 TB 横幅（prep=... expect=...）+ LOAD 行，缺即假跑；CI 脚本 grep 横幅后再采信结果。
- 预防规则: xsim 启动脚本内置横幅自检门。
- 复发: 0

### [2026-10-17] toolchain: vsim -c 批处理 do 脚本遇 $finish 即终止整个 do（后续臂不执行）
- 症状: 双跑 do（两个 `vsim`+`run -all` 串联）第一个 TB $finish 后，第二个 TB 未运行 vsim 即退出，exit 0、无报错、缺第二个结果文件——静默缺臂。
- 根因: vsim -c 批处理模式下 TB 的 $finish 不只结束当前仿真，直接终止 do 宏执行（不返回提示符续行）。
- 修复: 每仿真臂独立 `vsim -c -l <arm>.log -do <arm>.do` 调用，外层 sh 串联并分别收集退出码。
- 检测门: 多臂 do 跑完必须逐一核对各臂结果文件存在且非 TIMEOUT 占位；process_status 汇总每臂退出码。
- 预防规则: 10.1c 正典 = 单 do 单臂；多臂用 sh 串联独立 vsim 调用，禁一个 do 写多臂。
- 复发: 0

### [2026-10-17] toolchain: Yosys 0.70 read_verilog -sv 不认 `parameter string` 关键字
- 症状: ERROR syntax error, unexpected TOK_ID 于 `parameter string X = ""` 行；同文件 ModelSim 10.1c vlog -sv 零错（方言差异）。
- 根因: Yosys SV 前端支持 parameter 但不识别 string 类型关键字；仅影响综合通道不影响仿真。
- 修复: 综合用 run 目录内副本 `sed 's/parameter string /parameter /'`（语义对 synth 等价，文件路径参数照常 chparam 覆盖）。
- 检测门: read_verilog 报 syntax error 时 grep 源文件 `parameter string`；.ys 一律指向 _synth 副本。
- 预防规则: 源 .sv 保 string 关键字（仿真正典），综合流一律走副本去关键字。
- 复发: 0

### [2026-10-17] toolchain: MCP 会话累积日志陈旧匹配 = 假裁决（put 前缀不复名的新角度）
- 症状: 梯跑看守 grep MCP 会话日志（非本轮日志文件），匹配到**昨晚同构脚本**的 M2SILAT_* verdict 行，提前 4 分钟报"SILAT_DONE + t22 FAIL"假裁决；与 cmp|awk 空输入假全同、MCP execute 幂等去重坑同族。
- 根因: ①MCP 会话日志跨轮累积永不轮转，历史 puts 永驻；②梯脚本复用时只 sed 改了日志文件名，**put 前缀字符串没复名**（M2SILAT_*/M2JJ_* 两代梯同名）；③看守取材自会话日志而非本轮 g3_*.log 文件。
- 修复: 本轮一切裁决只取自本轮 `g3_*.log` 文件；看守全部改成文件级（runme/xsim log），禁止 grep 累积会话日志取 verdict。
- 检测门: 看到 verdict 行先确认它出自本轮日志文件（mtime + 文件名前缀），不是会话日志；同族三坑互查（去重轮次变量/暂存门/本条）。
- 预防规则: 未来任何梯变体脚本派生时，put 前缀与日志文件名**同步复名**（当前 g3 梯脚本=证据文物不改）；watch dog 一律 `tail -f` 具体文件。
- 复发: 1（本会话 fork 实证）

### [2026-10-17] toolchain: `cmp -l A B 2>/dev/null | awk` 空输入假报"全同"
- 症状: 三路字节级比对脚本里，两路（跨目录取参考文件）awk 汇总输出 "identical"，第三路输出 2262 处差异——m10p2==r9 且 r9==golden 却又 m10p2≠golden 的逻辑矛盾。
- 根因: `cmp -l` 遇文件不存在/路径错把错误写 stderr（被 2>/dev/null 吞），stdout 为空；awk 的 END 分支按 n==0 判 "identical"——**cmp 失败与"零差异"共用同一条空输入路径**，假全同。
- 修复: cmp 的 stderr 保留可见；或改用 `cmp -s A B && echo IDENTICAL || echo DIFFER` 先探存在性再比对；缺失文件 fail-loud。
- 检测门: 任何"identical/零差异"结论出口前，必须 `ls -la` 两个输入确认非空且 mtime 符合预期。
- 预防规则: 差异比对一律两拍（存在性探活 → 真比对），禁止把"无输出"当证据。
- 复发: 0

### [2026-10-16] toolchain: torch c10.dll 在 BleakScanner 激活态加载必炸 WinError 1114
- 症状: 先起 bleak 扫描/连接（WinRT BLE），再 `from ultralytics import YOLO`（内部 import torch）→ `OSError: [WinError 1114] 动态链接库(DLL)初始化例程失败 ... torch\lib\c10.dll`；纯 import 或先 torch 后 bleak 均正常。烧掉两次实环（run02/run03）。
- 根因: torch 的 c10.dll 在 DLL attach 阶段初始化失败，触发条件=同进程内 WinRT BLE 广播 watcher 正活跃（回调线程/loader lock 冲突）；与内存/安装损坏无关（隔离验证：bleak+cv2 静态 import 后 torch 正常；扫描激活中 import torch 必炸；torch 先载后扫描 5s 49 条广播正常）。
- 修复: **ultralytics/torch 导入提前到任何 bleak/WinRT 活动之前**（模块顶导入），YOLO 相关 os.environ 也必须先于该导入设置（ultralytics import 时读）。opt1_loop.py 已按此结构。
- 检测门: 长链脚本冒烟顺序=先 `import torch` 再起 BLE；出现 WinError 1114 先问「进程里是否有活跃 BLE 扫描」。
- 预防规则: torch 与 bleak 同进程共存时，导入顺序=torch 第一、bleak 活动 afterwards；新写 PC 侧多模态脚本把重 DLL（torch/onnx/cv2）全部前置导入。
- 复发: 0

### [2026-10-16] toolchain: 被拒绝的前台长命令进程照样启动、脱钩续跑、断管早夭
- 症状: 用户 reject 前台 `python ... | tail` 长命令后，进程实际已在跑（run04 证据目录 events.jsonl 持续增长 2 分钟；run05 同型，臂连挥 14 次被目视确认）；且 stdout 管道（tail）随拒绝死亡 → 进程在下一次 print 时 BrokenPipe 早夭 → result.json 永远不落盘，只剩 events.jsonl。次生坑：误以为进程已死而删除证据目录（run04 1.3MB events 被删，那次是否触发 LOOP 不可考）。
- 根因: 工具拒绝终止的是「等待与回传」，不是已 spawn 的子进程；`| tail` 使 stdout 绑在随拒绝关闭的管道上。run05 无 result.json 的退出=print 撞断管（最后事件 11:13，进程 420s 未满即终）。
- 修复: 事后用 `tasklist`/`Get-Process` + 证据目录 events.jsonl 的 mtime/size 增长判定进程死活（run05 双检：tasklist 空但文件增长=活着；4 秒后尺寸不变=已终）；证据只读提取 verdict/时延（grep events.jsonl 即可重建 result）。
- 检测门: 任何被 reject 的长命令，下一步动作前先双检（进程表 + 证据文件增长）；证据目录非空时**先读后删**，含增长中的 events 文件一律不删。
- 预防规则: 长交互跑位一律 `run_in_background`（输出落文件、生命周期受管）或 `>logfile 2>&1` 重定向（不接 tail 管道）；「reject=没跑」是错误心智模型。
- 复发: 2（2026-10-16 当日 run04/run05）

### [2026-09-21] toolchain: PowerShell 5.1 无 BOM UTF-8 中文炸 parser
- 症状: .ps1 含中文注释直接解析失败。
- 修复: .ps1 纯 ASCII；含中文 .tcl 派生用 Copy-Item+Edit，禁文本往返。
- 预防规则: PS 脚本零中文；tcl 从模板 Copy 改。
- 复发: 0

---

## env-path（环境/路径/传输）

### [2026-10-29] env-path: OOC 子运行继承未设置的 Tcl Store 路径——`Common 17-354 Could not open 'C' for writing`
- 症状: 主综合启动后，多个 IP OOC 子运行的 `runme.log` 报 `Common 17-354 Could not open 'C' for writing` 和 `tclapp::load_apps failed`；父进程实测 `XILINX_LOCAL_USER_DATA=<unset>`。
- 根因: Vivado OOC 子进程继承父进程环境，未隔离的默认 Tcl Store 在当前 Windows 运行上下文不可写；主 run 状态不能替代子运行原始日志判断。
- 修复: 在 launch 前把 `XILINX_LOCAL_USER_DATA` 设置为当前 attempt 内独立目录并创建它，使父子运行共用该可写 Tcl Store；后续 OOC 原始日志越过此错误并完成主综合。
- 检测门: 发射前 Tcl 打印并断言该环境变量位于当前 attempt 且目录可写；终态必须检查所有 OOC `runme.log` 无 17-354，而非只看 MCP progress。
- 预防规则: Windows Vivado OOC 构建一律使用 attempt 内独立 Tcl Store；父/子环境同源，禁止依赖默认用户目录。
- 复发: 0

### [2026-10-29] env-path: 深 attempt 绝对路径被 OOC run 重复拼接——`Common 17-680` 超过 Windows 260 字节
- 症状: 多个 BD interconnect OOC 子运行报 `Common 17-680 Path length exceeds 260-Byte maximum allowed by Windows`；错误文本显示在已经很深的 run 目录后再次拼接绝对 run 路径，并建议使用 `subst`。
- 根因: Windows 普通路径 260 字节上限与 Vivado OOC 的绝对路径拼接叠加；设计、器件和接口均未失败，单纯物理证据根过深即可使子运行无法创建文件。
- 修复: 保持物理证据位于规定 attempt，用 `subst` 把整个 attempt 映射为短盘符，再以短路径作为 Vivado working/argv 根；同一 Tcl 随后完整生成 BIT/XSA。
- 检测门: 发射前核对短盘符映射目标恰为当前空 attempt，Vivado working/argv 均为短根；原始 OOC 日志无 17-680，物理产品和日志仍回写到规定证据目录。
- 预防规则: 深层 Vivado run 不放宽路径预算、不搬出证据根；优先 `subst` 缩短执行视图，禁止把长路径失败误归为设计资源问题。
- 复发: 0

### [2026-10-24] env-path: plfront 编译链须用 D:/work/Python/python.exe——默认 Python312 无 torch，import torch 即炸
- 症状: plfront 链（p2_compiler_plfront / build_s4_board_pack / m9_m94_batch_driver 等）用系统默认 Python312（C:/Users/Administrator/AppData/Local/Programs/Python/Python312）跑，import torch 即 ModuleNotFoundError。
- 根因: torch 只装在 D:/work/Python 环境；本机多解释器并存，「python」按 PATH 解析到无 torch 的那个，且失败点在 import 期、与脚本逻辑无关，易误判为脚本坏。
- 修复: plfront 链脚本调用一律写死 D:/work/Python/python.exe 绝对路径。
- 检测门: run 脚本开工前 `D:/work/Python/python.exe -c "import torch"` 预检门。
- 预防规则: 本机多 Python 环境并存，任何 ML/编译链脚本开工前先锚解释器再谈逻辑。
- 复发: 0

### [2026-10-23] env-path: 重训复用的数据生成器把源数据集锚在旧 run data/ 下——源目录被清理后重跑生成器即炸；增强数据集应硬链接克隆不重生
- 症状: v8n lrfix run（2026-10-23_mcontract_v8n_lr_retrain_run01）照抄 y11n 重训的 make_lr_mirror_aug.py，其 SRC_TRAIN 指向 2026-10-18_t1_gesture_nanodet_train_run01/data/merged_v65/train，重跑第一步 os.listdir 报 WinError 3 系统找不到指定路径；该目录两周前还在（y11n 重训刚消费过）。
- 根因: run 目录下的 data/ 源数据子目录不是受保护资产（受保护的是模型权重与产物），会被磁盘清理删掉；生成器把跨 run 源路径写死，等于把不可再生输入锚进被清理区。而下游 run 的增强输出（merged_v65_lraug：原图硬链接+镜像副本）自含全量 5942 图，本就是源的全等价物，不需要源再生。
- 修复: 不重跑生成器；从 y11n retrain run 的 merged_v65_lraug 全量硬链接克隆进本 run data/（零额外磁盘），克隆后 (images=5942, labels=5542) 计数与源 augment_report.json 的 total_images / (n_with_labels+n_mirror_copies) 逐项对账一致，augment_report.json 随附拷贝、README 记 provenance。
- 检测门: 复用任何带跨 run SRC 路径的数据生成脚本前，先 Test-Path SRC；消费克隆增强集前核对 images 数 == augment_report.total_images、labels 数 == n_with_labels+n_mirror_copies_written。
- 预防规则: run 间复用增强数据集一律硬链接克隆自包含，不重新生成；新写生成器时 SRC/DST 默认本 run 内，确需跨 run 源必须在头部注释标注"源可被清理"风险。
- 复发: 0

### [2026-10-22] env-path: 训练进程 numpy "Unable to allocate 2.34 MiB" ArrayMemoryError = 整机 RAM 耗尽判据，非失败进程缺陷——先查整机空闲再动代码
- 症状: yolov9t M 合同训练 epoch 34 DataLoader 内 m_front_uint8 的 (320,320,3) float64 分配报 numpy._core._exceptions._ArrayMemoryError: Unable to allocate 2.34 MiB；失败进程自身 RSS 仅 ~600MB、batch=32 显存 1.4G，单看进程一切健康。
- 根因: 32GB 共享盒上 3 并发训练 + 各 dataloader/子进程 ~600MB/个 + 内存压缩活跃 → 物理内存/提交限瞬时被吃干，此后任何尺寸分配（含 2MB）都可能失败；失败落在哪个进程是随机的，不是该进程的泄漏或代码缺陷。
- 修复: 不 from-scratch 重跑——ultralytics 原生 resume：`YOLO(last.pt).train(resume=str(last_pt), trainer=自定义Trainer类, ...)` 从断点续跑（check_resume 只放行 batch/device/workers/patience 白名单覆盖，epochs 从 ckpt 恢复）；崩溃进程退出本身即回释放 2-3GB。
- 检测门: 训练日志见 ArrayMemoryError 时，先 `powershell "Get-CimInstance Win32_OperatingSystem | %% ... FreePhysicalMemory"` 看空闲物理内存——<5GB 即判整机耗尽路径；并 `tasklist | findstr python` 数进程×单进程内存估占用。
- 预防规则: 共享盒长训练一律「epoch 级 last.pt + resume 续跑」架构而非一次性长跑；crash 后第一动作是 resume 保已完成 epoch，不是 relaunch-from-scratch。
- 复发: 0

### [2026-10-22] env-path: ultralytics COCO 权重 github.com 直连 connect timeout（10054 后 30s ConnectTimeout ×3 重试全败）——ghfast.top / gh-proxy.com 镜像前缀直替
- 症状: `YOLO("yolov9t.pt")` 自动下载 WARNING Download failure, retrying 1/3... ('Connection aborted.', ConnectionResetError 10054) → 继而 ConnectTimeoutError('Connection to github.com timed out')，3 次重试后 raise ConnectionError: Download failure。
- 根因: 本机到 github.com:443 直连被掐（connect 30s 超时）；与 ultralytics 无关，同盒早先 yolov8s.pt 能下只是时段网络差异，不能据此判定"网是好的"。
- 修复: `curl -sL "https://ghfast.top/<原 github URL>"`（gh-proxy.com 同效，均验证 HTTP 200）下载到 run 目录，启动器权重路径指本地文件绕过 attempt_download；下载后 torch.load 校验（params 数与 stock yaml 头一致）+ sha256 记入 run 台账。
- 检测门: ultralytics 下载重试日志出现 10054/ConnectTimeout 时，先 `curl -sI --max-time 12 https://github.com` 探直连；不通立即用镜像前缀重拼同一 release URL，不再等进程内重试。
- 预防规则: 共享训练盒上凡 ultralytics/HF 自动下载件，第一选择镜像直下到 run 目录 + sha256 留证，不依赖进程内 attempt_download 的 3 次重试。
- 复发: 0

### [2026-10-22] env-path: Git Bash 下 SSH_ASKPASS 给 MSYS 路径（/e/...）原生 Windows ssh 执行不了——静默回退空口令双 Permission denied
- 症状: ssh 免密管道报两次 "Permission denied, please try again" 后 (publickey,password) 拒；同环境把 askpass 路径从 /e/competition/... 改成 E:\competition\... 立即通。
- 根因: SSH_ASKPASS 值是环境变量不经 MSYS 参数路径转换，原生 ssh.exe 拿到 /e/... 无法执行 → askpass 失败 → ssh 按无 tty 处理喂空口令。坑的反差点：命令行参数 MSYS 会自动转，环境变量不会。
- 修复: Git Bash 里 export SSH_ASKPASS 一律 Windows 路径（E:\... 或 E:/...）；脚本头部 ASKPASS 变量同律。
- 检测门: ssh 双 Permission denied 且已配 askpass 时，先 echo $SSH_ASKPASS 看是不是 /x/ 开头。
- 预防规则: 原生工具（ssh/scp/cmake/vivado）从 Git Bash 消费的环境变量路径，一律先 cygpath -w 或手写盘符路径。
- 复发: 0

### [2026-10-21] env-path: Windows glob 返回混合分隔符（E:/...\ip\name\），子串路径身份判定静默失效、守卫分支整段跳过
- 症状: r12 BD 宽度手术首跑：宽度改写全成（widths=1），但 6 个 cache xci 的 cv_slot 新口添加全部被跳过（cv_slot_added=0），无异常无告警；只有脚本末的「重读交叉门」以 cv_slot absent 报警。.bd 本体（无通配的直拼路径）却添加成功——同脚本两行为何分裂是定位钥匙。
- 根因: python glob 在 Windows 上保留字面段分隔符（E:/.../ip）而通配展开段用反斜杠（\ip\m9_sys_roms_0\）→ 路径含混合分隔符；脚本用 `'/m9_sys_roms_0' in path` 做 cell 身份判定 → 恒 False → cell=None → 添加分支被 `if cell` 守卫静默跳过。静默 no-op 律的路径形态：守卫条件失效时操作无声消失。
- 修复: 一切身份/子串判定前 `path.replace(chr(92), '/')` 归一化；删除未使用的同型残留变量。
- 检测门: 门脚本凡 glob 结果做 `in` 身份判定处，内置 self-check：对首个 glob 结果断言归一化后身份非 None；添加/改写类操作必须打印 per-file 计数并要求 >0（或显式「已在场」分支计数）。
- 预防规则: Windows 上 glob 路径先归一分隔符再做任何字符串身份比较；带守卫条件的操作必须带计数输出门，禁止无声跳过。
- 复发: 0


### [2026-10-27] env-path: Python `-I` 忽略 `PYTHONIOENCODING`，父进程 UTF-8、子进程 GBK 导致 `subprocess` reader 崩溃
- 症状: Windows 父进程以 `-X utf8 -I` 启动并用 `subprocess.run(..., text=True)` 读取子进程；中文负例 console 在 `_readerthread` 报 `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xca`，随后 `stdout=None` 诱发二次 `TypeError: data must be str, not NoneType`。只在父进程或 helper env 增加 `PYTHONIOENCODING=utf-8` 后仍逐字节复发。
- 根因: `-I` 隐含 isolated/`-E`，会忽略 `PYTHON*` 环境变量；子进程 argv 只有 `-I` 而没有 `-X utf8`，stdout 仍按系统 locale（GBK/cp936）编码，父进程却按 UTF-8 解码。功能负例本身已正确拒绝，故障是父子编码合同不对称。
- 修复: 独立重跑严格采用生产入口，让父子使用同一 locale/UTF-8 模式；或把 `-X utf8` 显式写进每一层子进程 argv。先用原始 bytes 重放最后一个缺 console 的 baseline/mutant 探针定位，不重跑整套凑结果，不把 harness 故障误写成合同反例。
- 检测门: 至少保留一个含中文错误 detail 的真实负例，断言 baseline rc=0、mutant 到目标错误、父进程无 `UnicodeDecodeError` 且 mutant console 非空；对 `python -I` 进程禁止把 env 编码设置当有效证据。
- 预防规则: Windows 多层 Python 的编码必须由每一层 argv/捕获解码共同固定；`-I` 下 `PYTHONIOENCODING` 与 `PYTHONDONTWRITEBYTECODE` 均不生效，分别使用 `-X utf8` 和 `-B`。
- 复发: 0


### [2026-10-18] env-path: python pathlib write_text 无 encoding= 落盘是 GBK，中文 JSON 自读自炸
- 症状: `pathlib.Path.write_text(json.dumps(d, ensure_ascii=False))` 写含中文的 JSON，同脚本族读回 `read_text(encoding="utf-8")` 炸 `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xc9`（位置在首个中文字符）；文件肉眼看似正常。
- 根因: Windows 上 `write_text`/`open()` 默认编码取 `locale.getpreferredencoding()`（简中机器=GBK/cp936），`ensure_ascii=False` 把中文按字面写盘 → 落盘字节是 GBK 流；读方显式 utf-8 即崩。JSON 内容本身无错，错在编码契约不对称。
- 修复: 一切非 ASCII 文本的写侧显式 `encoding="utf-8"`（write_text/read_text/open 三处成对）；或落盘用 `ensure_ascii=True`（纯 ASCII 转义，编码无关）。读侧永远显式 utf-8 不能省。
- 检测门: 产物含中文/非 ASCII 时，写后立即 `read_text(encoding="utf-8")` 回读一遍（build_manifest→gates 链天然成门）；或 `python -I -c "open(p,encoding='utf-8').read()"` 单行门。
- 预防规则: Windows 上写文本文件 = 永远显式 encoding；中英混排 JSON 尤其，"默认编码"不存在。
- 复发: 0

### [2026-10-16] env-path: 板上 sudo 裸 python3 无 pynq——真身在 pynq-venv
- 症状: M10.2 G4 板梯首次点火即炸 `ModuleNotFoundError: No module named 'pynq'`（sudo 与 xilinx 用户双双失败）；同日下午同板 DL_GATE_PASS 还曾成功，表象"环境一会儿有一会儿没有"。
- 根因: 本板（PYNQ 3.0.1 类镜像）pynq 3.0.1 只装在 `/usr/local/share/pynq-venv/lib/python3.10/site-packages`；venv 的 bin/python3 是 /usr/bin/python3 的符号链接，靠 venv 路径上下文获得 site-packages。`sudo python3` 走 secure_path 解析到 /usr/bin/python3（无 venv 上下文）→ 无 pynq。叠加剧毒：`/home/xilinx/pynq` 是一份缺 pydantic 的源码 checkout，cwd=/home/xilinx 时 `''` 于 sys.path 最前 → 影子包劫持真包，报缺 pydantic 的误导错。
- 修复: 板上一律 `sudo /usr/local/share/pynq-venv/bin/python3 <script>`；先 `sudo $V -c "import pynq"` 探活再跑正脚本。
- 检测门: 板上任何 python3 调用前，若不属于已知 venv 路径，先 `$V -c "import pynq, pydantic, numpy"` 探活；报错文本出现 `No module named 'pynq'`/`pydantic` 时第一动作=查 cwd 是否在 /home/xilinx（影子劫持）+ 是否用了 venv 解释器。
- 预防规则: 板载脚本执行律 = venv 解释器全路径 + cwd 避开 /home/xilinx 影子目录；写进 overlay 工作流的板侧检查单。
- 复发: 0

### [2026-10-16] env-path: 跨梯共享 golden94/ 被 stage_golden 覆写 = 假回归
- 症状: g3r8 RTL 上 G1 case0 突报 arena 3955 坏字节、case1 starts=1——RTL 两刀（sanity 寄存器化，空表恒等）在数学上不可能造回归，"证据"与"机制"矛盾。
- 根因: j01j02 仿真梯的 stage_golden 暂存直接覆写共享 golden94/（14 文件混入 v25_up2x.txt 等，11 个共有文件字节全不同）；g3r7 的 `;#` 链吞 bug 曾跳过 t6 复原步，污染跨轮残留。
- 修复: 从 golden94_g3bak 复原 11 文件 M94 原套 + 逐文件 sha256 核验 + 重跑 8/8 PASS。
- 检测门: 任何梯的 stage_golden 落盘后、跑用例前，golden94/ 文件数+sha256 清单必须与该梯声明的基准清单比对（不符=先复原再跑，不许带着污染判 RTL）；梯尾强制复原步（不可被 `;#` 链吞——独立行写盘）。
- 预防规则: 共享 golden 目录取"一写一验一复原"三拍律；暂存目录与 golden 目录物理分离，覆写走白名单。
- 复发: 0

### [2026-10-14] env-path: 工程目录层级换算少一级 = glob 静默落空
- 症状: TCL `glob` 返回空 → 门误报 absent；同一坑 10 分钟内两次（wrapper 路径、bd top 路径）。
- 根因: `.srcs` 与 `.gen`/`.runs` 是**兄弟目录**，从 bd 文件位置出发要数准层级；`glob -nocomplain` 空匹配不报错。
- 修复: 用 `ls`/`find` 实测路径后再写 glob；门脚本对 absent 一律 fail（已做）。
- 预防规则: 写任何相对工程文件的 glob 前先用 shell 实测绝对路径；层级 >2 必实测。
- 复发: 2（2026-10-14 当日）

### [2026-09-21] env-path: git 分支同形孪生拼写 + 出站 22 端口被劫
- 症状: push 到错分支 / push 挂死。
- 修复: 分支名按字节从 git 取；push 走 ssh.github.com:443 + ServerAliveInterval=30。
- 预防规则: 远端仅两条、日常推个人分支 codex/full/pipidandan-superman。
- 复发: 0

### [2026-09-19] env-path: GitHub 大仓库 clone 断连
- 修复: HTTP/1.1 协议降级解。
- 复发: 0

---

（持续回填。新条目按格式加在对应分区顶部。）

### [2026-10-18] rtl: AXI 4KB 边界 burst 长度计算位宽截断 -> 0 长 burst 跑飞挂死
- 症状: xsim 中写 master 在特定输出行（y=3, 平面地址 4KB 对齐）无限循环：AW->W 约 640 拍一轮、rem/ch 不前进；fetch 侧同类（row=8, 1920r+1024m≡0 mod 4096）。
- 根因: b4k=1024-(addr[11:2]) 取值 1..1024，截断取 b4k[8:0] 后 4KB 对齐地址（b4k=1024）变成 0；burst_len 比较链选中 0 → AWLEN=0-1=255、burst_beats=0 → W 通道等 wcnt==511 才收工且 rem 不减，死循环。
- 修复: burst_len=min(rem,256,b4k) 全 11 位比较后再截取，对齐时落到 rem 分支。
- 检测门: 任何 4KB 边界切分逻辑，先验算对齐地址（addr[11:2]==0）路径的 burst_len 不为 0；仿真含 dst/src 多对齐相位（行跨 4KB 的 y=3k 行必测）。
- 预防规则: 边界余量类信号比较前禁止先截位；截位只在最终赋值端。
- 复发: 0

### [2026-10-18] rtl: memory 索引 {slot,index} 拼接隐含 2^n 槽距，非 2 幂槽距越界
- 症状: 行缓存 3 槽×320 字，写 slot2/pair>63 越界丢失、读回 X/串槽，输出大面积错值。
- 根因: {wr_slot, wr_pair} 把槽距硬编码成 2^9=512，实际槽距 320 ≠ 2^n。
- 修复: 改算术索引 wr_slot*320+wr_pair。
- 检测门: 拼接索引前先写槽距断言（2^width == 槽距）；xsim $display 首槽首字比对。
- 预防规则: memory 多维索引一律算术式，禁用拼接式除非槽距恰为 2 幂并有断言。
- 复发: 0

### [2026-10-18] rtl: 字节装配流 {A,B} 拼接方向颠倒 = 字节循环移位
- 症状: 48b 行缓存字字节序成 (b4,b5,b0,b1,b2,b3)，像素通道全错位但帧级"像有数据"。
- 根因: 想要 word[47:16]=beat0,[15:0]=beat1[15:0] 时写了 {beat0, beat1[15:0]}——拼接左操作数占高位，恰与"低字节在前"的字节布局相反。
- 修复: word0={beat1[15:0], beat0}；word1={beat2, hold_hi}。
- 检测门: 装配逻辑用首组 3 beat 12 字节做黄金向量比对（打印 vs Python 期望值）。
- 预防规则: 字节流装配先写出目标字节的 bit 区间表再写拼接式；拼完用黄金向量门。
- 复发: 0

### [2026-10-18] rtl: 时序块内阻塞赋值读数据存储 = 晚一拍加载，整 burst 右移一位
- 症状: 输出 blob 从第 1 元素起整体右移：dst[0]=X、dst[k]=pixel(k-1)、末像素丢失；首拍 X 尾拍缺是指纹。
- 根因: rb_rd=rb[rd_idx] 写在 posedge always 内（阻塞），AW 握手拍属 ST_AW 分支不执行 → 首个 W 拍 rb_rd 仍是初值 X；且该赋值在 rd_idx NBA 递增同拍采样旧 idx，逐拍错位。
- 修复: 改组合读 wire[95:0] rb_rd=rb[rd_idx]（聚合缓冲读地址先行寄存）。
- 检测门: 输出比对出现"整体平移一位+X 首元素"指纹即查数据存储读路径时序化；burst 首拍数据加拍级断言。
- 预防规则: 数据面读存储一律组合读+寄存地址；时序块内禁用阻塞赋值当数据通路。
- 复发: 0

### [2026-10-18] rtl: 权重 0 抽头必须直通，X*0=X 传播污染
- 症状: y%3==0 行（不取第二输入行，行缓存槽为 X）输出全 X/0。
- 根因: blend_y 通用式 a*(256-w)+b*w+128 在 w=0 时仍计算 b*0，Verilog 中 X*0=X。
- 修复: w==0 直通 blend_y=a。
- 检测门: 插值/加权和核先做"权重 0 输入可为 X"思想实验；仿真注入未初始化邻槽跑一遍。
- 预防规则: 加权和核的零权支路用选择器直通，不靠乘 0 消项。
- 复发: 0

### [2026-10-18] sim: BFM R 通道在呈现拍推进计数 -> 末 beat 被撤除呈现，DUT 永等 RLAST
- 症状: DUT 读 master 挂死在 RCV（等不到 rlast），调度卡 FETCH_WAIT；与 10-18 B 通道条目同族，机制在 R 通道呈现侧。
- 根因: BFM 在"装载新数据拍"同时推进 rd_cnt 并在 rd_cnt==len 时撤 rvalid——末 beat 装载与被撤同拍，永不呈现在总线上。
- 修复: 仅在接受拍（rvalid&&rready）推进/收尾；呈现拍只装载，hold 拍保持。
- 检测门: TB 挂死先数 beat 期望值（本案数据面计数全对=握手层罪）；BFM 各通道"valid 撤除拍"必须==被采样拍。
- 预防规则: BFM 任何通道计数推进只允许挂在(valid&&ready)握手拍。
- 复发: 0

### [2026-10-19] timing: 枢纽寄存器=分析收敛点≠单切点，D 端锥切点看终点捕获方向
- 症状: 片级 STA 三锥（Q 端 stage2 37.36ns / D 端 pwin 数据 32.38ns / D 端 sc 配置 30.61ns）汇聚于同一 g_nat_q 寄存器，被表述为"对该寄存器打拍一揽子解决三锥"。
- 根因: 从"结构相似（同枢纽）"跳到"一步解决"的外推省略——输出侧加拍只切断以该寄存器 Q 为 launch 的锥；终点为该寄存器 D 的锥每拍捕获，输出侧加拍零缓解，切点必须上移（路由/入口/内部）。
- 修复: 三锥各自切点分别出方案（Q 侧打拍 / D 侧上游路由 / 准静态留 MCP）。
- 检测门: 切点提案三问——切点在捕获沿哪侧（Q launch 还是 D capture）？每拍捕获还是准静态（决定能否 MCP）？帧拍代价与 golden 影响真实落在哪条路径？
- 预防规则: 多锥共枢纽时按终点捕获方向逐锥分类，禁止"枢纽=单切点"表述进任何代价表/改派单；F 教训同族（结构相似⇏语义等价）。
- 复发: 0

### [2026-10-20] toolchain: `git push | tail` 管道掩码退出码+空输出假绿——推送完成判定必须 ls-remote 复核
- 症状: 四次后台推送全部报 exit 0"完成"，实际远程 ref 纹丝未动（落后 16 提交）；且推送段零输出、任务长时间不结束。用户问"怎么这么慢"时才发现。
- 根因: 双重——①bash 管道退出码取自末段（tail），`git push ... 2>&1 | tail -2` 里 push 挂起/失败被掩码成 0；②119MB pickle pkl 走 GitHub ssh-443 上传本就要十几分钟级，push 段在爬行期无行输出（进度走 stderr 且非 tty 时不打印），"零输出+未退出"被误读为"已完成但安静"。
- 修复: 推送一律裸命令+`echo PUSH_EXIT=$?` 落码，后台长跑；完成判据=`git ls-remote origin main` 与本地 `git rev-parse HEAD` 比对，不信任务退出码。
- 检测门: 任何"推送完成"报告前必须贴 ls-remote 实值；管道链里凡有 git push 禁止接 tail/管道（或显式 `set -o pipefail`）。
- 预防规则: 大产物提交（>20MB pkl/网表）推送预期=分钟级起步，直接 run_in_background + ls-remote 复核闭环；"exit 0"不是推送完成的证据。
- 复发: 0

### [2026-10-19] timing: 遮蔽测量（start-mask 单源播种）起点集完备性必须测量前核验——缺一项即系统性低估
- 症状: masked pwin 锥测量 32,178ps/76 级被判为 stage1 D 侧锥真值；全端点重提取后发现同锥真上游发射 bk_a_q（顶层 A 读组地址寄存器）起点路径 33,675.7ps/82 级——**低估 1,497.7ps**，切法段预算与解冻范围裁定建立在错值上。
- 根因: start-mask 测量按"预期起点名单"播种，名单缺项时该起点整锥不可见（到达永不从缺项传播）；而名单来自上一轮的锥归因，归因本身可能是被同一遮蔽机制污染的——闭环自洽但系统性偏低。全端点测量里该锥又被 max-arrival 单路径记录遮蔽（每端点只留最差一条，慢起点被快起点盖掉），两种测量互补地都看不到它。
- 修复: 全端点无 mask 重提取后用"起点基名分桶+桶级最差"替代端到端最差做锥清单；masked 专项值仅作单锥结构分析，数值一律以全端点分桶为准。
- 检测门: masked 测量报告必附两件——①起点名单与全端点最差 20 条路径起点基名的差集（差集非空=名单缺项，测量无效需重跑）；②同锥在全端点 pkl 中起点路径数=0 时触发"被遮蔽"告警（该锥在全端点 max 口径下不可见，须分桶统计而非端到端 max）。**姊妹门（2026-10-19 裁定 4 号案追加）**：段残余/段预算类测量禁止只取 prev 保留链单链——逐位总线须直读 arr[] 按位取最差（bk_a_q 案：保留链只见 eng_a_q[4]=3,783.7，arr[] 逐位最差 eng_a_q[12]=3,827.5，差 43.8ps 结论不变但口径必改；prev 树每网只留最大弧，逐位散布被剪枝隐藏）。
- 预防规则: 单源播种/masked 数值禁止直接进代价表段预算与解冻裁定；进档前必须过差集检测门。与"单元级→片级外推""均匀除法"同入外推族台账（审计裁定 3 号登记）。
- 复发: 0

### [2026-10-20] timing: chip 级段表按网名过滤 = 跨模块同名碰撞，归属裁定必须层次+位宽双证（审计 W-1 实案）
- 症状: A2 片级 STA 判问表（analyze_chip_a2.py 按网名 KEYS 子串过滤）第 1 名 `pcol→pp_r 14,189ps/42lv` 被收入"gemm 完成级/kacc 段表"，审计 W-1 据此定"gemm 64:1 读 mux+9×9 乘阵列合成入口锥、A1 按 14,189 落刀"——A1 棒反质疑后 netlist 直证：pcol[6:0]/pp_r[31:0]/q1_r/q_r 声明于 **softmax_unit_v3** 模块体内（regate_v34_netlist.v L1722245，module 头 L1702044，无中间边界），系 smax 域 exp/poly 遗留锥；gemm G3 的 pp_r 是 [0:15]/18b，位宽不同、纯名撞。同表 rs2_r→resv_r/rl1_r/rh1_r 三行实为 layernorm_unit_v3 域（L517807-517816，module 头 L476922）。gemm 域真 top=pe_col→s_ch 8,077/9lv（gemm_engine_v3 体内 L101083-101405 逐声明核实）。
- 根因: 网表跨模块重名（pcol/pp_r 在 smax 与 gemm 各存一份）；段表脚本 lbl() 取端点 cell 所连网名的首基名作标签，KEYS 子串过滤无层次/位宽校验 → smax 段误挂 gemm 表；复核方（审计）未做层次双证即采信标签下归属裁定，错上加错（W-1 更正本身含归属错误，二次勘误收场）。
- 修复: 归属裁定双证制——①端点声明行所属 module 边界直查（声明 L 行 + 最近前置 `module` 头，awk/Select-String 扫描无中间边界）；②网名位宽/维度比对（同基名多声明时位宽必分）。双证后 14,189 移交 smax D1 棒/复签盯防，gemm 落刀维持 8,077 实测口径。
- 检测门: 段表判问/落刀对象定稿前，top-N 行逐行跑双证；同一网名基名在网表中声明行计数 >1（`Select-String '^\s*wire.*\b<名>\b'` 命中多模块）即触发名撞告警——凡告警行未过双证不得进判据档/送审包。
- 预防规则: 网名只作候选索引不作归属判据；凡"按名字过滤出的段"默认带跨模块污染嫌疑，归属必须 cells_path/声明行级证据。审计侧同律：更正他人数字时，自己的更正同样要过全套检测门（本案教训主体是审计自己）。域成员判定必须用精确基名集合匹配，**禁子句串 `in` 匹配**（'c1_r' 会撞上 'rc1_r'）；段表打印与超预算计数**禁 top-N 截断**（漏报实案见复发①）。
- 复发: 2（①2026-10-20 A1：analyze_chip_a1.py `in_domain` 子句串匹配把 ln 域 `as_r→rc1_r 5,386ps/14lv` 误收入 gemm 片级判问表（'c1_r'∈'rc1_r'）；netlist 直证 as_r[7:0]/rc1_r 声明于 layernorm_unit_v3 模块体内（regate_v35a1_netlist.v L533808/533984，module 头 L493231），gemm RTL 无此二信号。同棒 analyzer top-30 截断致超段数少报 11 段（实 41 报 30）。max/FAIL 判定不受影响，错在归属与计数完整性。②2026-10-21 A1'：EXCLUDE_START 增 'mc1' 时注记"mc1→c1_r 按起点域归 acc_top"——netlist 直证 mc1[6:0] 唯一声明于 layernorm_unit_v3 体内（regate_v35a1p_netlist.v L578354，module 头 L536120），系 ln 窗控寄存器，全网表无 acc_top 副本；正确处置=归 ln（B1' 在册）。**新角度：排除动作对（非本域锥出表）但归属理由错 → 锥成孤儿（无 acc_top 棒可领）**；EXCLUDE/单列留痕必须附归属双证，"归某某域"句式无 module 证据一律视同未归属，挂"待双证"桶。）

### [2026-10-21] timing: 全局再综合映射漂移——锥 RTL 零改动，abc 重映射致锥深 3 倍级抖动（B1 as_r→rc1_r 实案）
- 症状: B1 只改 layernorm_unit_v3.v，as_r→rc1_r 锥 RTL 零改动——同流重综合后该锥 单元级 4,495ps/12lv → 7,891ps/27lv、片级 5,386ps/14lv → 12,672ps/40lv（审计独立双 pkl 直读复核：chip_precut_paths.pkl vs chip_b1_paths.pkl 逐值复现，pre=(5386,14) post=(12672,40)）。同网表"未触锥"res_hlf3_r→rhi_r 亦漂移 11,465→11,077（±3% 噪声级）。漂移后该锥从表列第 4 名跳升片级 max。
- 根因: abc 全局再综合对多位加/归并表达式的映射是全局优化解，局部模块任何改动都会重抽映射彩票——RTL 层多输入加（如 3 输入加）给 abc 自由线性化/重平衡空间（同族坑：2026-10-19 rtl "多项行为加被 abc 线性化成深链"），锥深由映射随机性而非 RTL 结构决定 → 跨棒段表对比（pre/post 切）在不触锥上失真。
- 修复: 时序敏感锥的加/归并结构用显式嵌套 2 输入加（位恒等）在 RTL 层钉死结构，压缩 abc 重平衡自由度；落刀/复签一律以当次综合当次网表实测为准，禁跨网表直接对比"未触锥"数字下漂移结论（须先证明映射稳定）。
- 检测门: 棒级 STA 交付时强制跑 pre/post pkl 同锥差分（同起点锚组 need 差 >10% 即映射漂移告警）；告警锥列"映射漂移"专项清单，其超段不计入本棒成效/退步判据，转结构修复项。
- 预防规则: 凡要靠 STA 数字跨提交/跨棒对比的锥，RTL 必须结构自锁（显式 2 输入加树）；接受段表"本网表本实测"口径，任何"较上次"表述先过映射稳定性门。
- 复发: 0

### [2026-10-21] rtl: 流水多窗串行链算子逐拍换元素——窗值续存与算子快照是两条独立对齐线，缺一不可（B1' v6 根因级，P3 同构链两案"幸存非正确"预言兑现）
- 症状: ln 16b 进位窗链（每窗一拍串行 cout 求和）仿真输出混合碎片——窗 j 在 k=5+j 求和，窗 0 加元素 e 是对的，窗 1 加 e+1、窗 2 加 e+2、窗 3 加 e+3；手算 rv2(e0) vs 实测（低窗=e0、中窗=e1 拼成 C221/D04C）即定位。P3 同构窗链三案（p1w/p1w2/p3csa）同病，前两案靠 token 级静态算子（每 token 装配一次，不换元素）幸存——幸存非正确，第三案复发显形。
- 根因: 设计级——串行窗链每窗拍消费的是"逐拍流动的算子"（ash2_r/bm1_r 拍 m 持元素 m−5），而窗链结构假设算子固定；"窗结果续存链"只把各自算错的窗值对齐到装配拍，错得更整齐而已。v2 引入、后续三轮修复均未触及。
- 修复: 算子快照链——每窗拍捕获算子入快照寄存器（d0/d1/d2 链），窗 j 用拍 j 的算子快照而非活值；窗值续存与算子快照两条对齐线独立存在缺一不可。rlo/rhi 同法（rop/hiop 快照）。
- 检测门: 流水线上任何"多窗串行链/多拍装配结构"，先问**算子换不换元素**——算子逐拍流时必须每窗拍快照；再问**窗结果寄存是否逐拍覆写**——覆写时装配拍必读同元素 echo 续存（隔拍数=各窗出生拍距，漏一条=混窗数×每窗元素数个错）。检测手法=手算首元素期望值与探针实测对账（一对手算即定位，比波形后验快一个量级）。
- 预防规则: "出生→消费画元素对齐线"纪律扩域：不仅单寄存器直读要画，**同一元素的多个并行窗装配**也要画（窗数≥2 且出生级不同就必须续存+快照双链）；凡依赖"结构同所以正确"的幸存件，一律按"尚未爆破"登记盯防。
- 复发: 2（P3 同构链 v8 复发实案，幸存非正确预言兑现；2026-10-22 V4.0 棒B3 批3 镜像复发=静态算子（续存侧无事）但窗结果寄存逐拍覆写、首版漏 echo 续存链混 3 元素 y=6237 错）

### [2026-10-21] rtl: 同寄存器两级双写=后写静默覆盖——窗 cout 载体不得复用，掩蔽层全对/非掩蔽层显形 ±1（B1' v10 根因级，幸存非正确第二例）
- 症状: rwc1_r 在 k=11 被窗 0 cout 写、k=13 又被窗 2 cout 覆写——LN1（ab32=0 掩蔽路径）仿真全对，LN2 显形 ±1 误差；两 LN 调用共用同一模块实例族，掩蔽差异决定 bug 可见性。
- 根因: 流水窗链给两个消费级复用同一寄存器载体，后一级写覆盖前一级值；两级写入间隔 2 拍，前级消费者若在读窗链尾段则读到被覆写值。LN1 掩蔽使错误路径不可达=全对假象。
- 修复: 窗 cout 载体一窗一寄存器（rwc1_r 拆分），不复用；覆写关系审查=逐寄存器列"全部写入点+各自存活窗"。
- 检测门: 同一寄存器出现在两个 always 块或同一 always 块两个分支写入时，强制列写入拍表（k=…各写什么、谁在读、读窗是否被覆写）；多调用实例（LN1/LN2）不得只用掩蔽层判绿——必须选非掩蔽臂跑门。
- 预防规则: 流水载体命名即归属（一窗一载体）；仿真门必须覆盖"每个实例族的最不利臂"，不能用一个调用全对推另一个调用全对。
- 复发: 0（LN1 掩蔽案为首发即定位，预防规则自本案立）

### [2026-10-21] git: 子目录内 `git add -A` 默认暂存全仓——在途代理产物被卷进无关提交
- 症状: 主会话在 4_logs/.../sdcv2/ 子目录执行 `git add -A`，把在途 D2/a3s 两棒整个工作目录（数百件 WIP 产物）卷入 SDC 文档提交；提交 7a95040 含 51+ 文件、SDC 提交信息名不副实。
- 根因: `git add -A`（无 pathspec）自 Git 2.0 起以**整个工作树**为作用域，与 cwd 无关；子目录内直觉"只加当前目录"错误。
- 修复: `git reset --mixed HEAD~1`（未推送可直接撤销）→ 按目录精确 `git add <path>` 重提交；远端核验未受污染（ls-remote 确认 remote 停在上一好提交）。
- 检测门: 多代理在途期间，`git add` 一律带显式路径参数；提交前 `git status --short | grep -v '^??'` 核对暂存清单与派单许改件集比对；提交信息名与暂存内容不符即中止。
- 预防规则: 提交前养成 `git diff --cached --stat` 过目习惯；含在途棒时禁止裸 `-A`/`.`，只加名单内路径。
- 复发: 0（首发即回滚修复，本规则立）

### [2026-10-20] rtl: 流水段重构图"只切语义不切入口胖锥"——STA 复签回退线踩穿
- 症状: 完成级链 17 段重构后功能门全绿，但 in-context 复签段 max 8,077ps
  > 3,908ps 回退线；违例全在入口结构（64:1 读 mux 8-10 级 6.5-8.1ns /
  写累加锥 20 级 ~7ns / 9×9 乘门级阵列 20-21 级 ~6.2-6.7ns），新流水段本身
  全部合规。
- 根因: 语义级重构（换加器结构/插流水寄存器）不改变入口 mux/乘法器的
  组合锥长；切法表的刀位（按实测累计延迟落刀）与"换结构"是两种动作，
  后者不覆盖前者。级均口径陷阱：mux/乘大片宽门实测 700-860ps/级 vs
  链路均值 308ps/级——按级数×均值估段长会低估胖锥 2.5 倍。
- 修复: 按裁定回退线整回退（A1 纯流水 22 刀）；胖锥的多级流水（选通提前
  /分组流水读/部分积打拍）才是落刀对象。
- 检测门: 流水化棒收官前必须跑 in-context regate+extract_paths 段表，
  逐段对 3,908ps 回退线；只报功能门全绿不算完。
- 预防规则: 重构完成级链时先列出"哪些组合锥原样保留"，逐项过段预算；
  保留锥 = 未切，不算刀数。
- 复发: 0

### [2026-10-20] rtl: RNA 补码递增锥直喂模块 b 脚——恒等式预锁存消锥
- 症状: 单元级 STA 段表 rndmag_r→CSL 双预测寄存器 11.6ns/33 级违例。
- 根因: rnda = wide[63] ? (~rndmag+1) : rndmag 的 64b 递增组合锥直接作
  模块输入，内部第一级寄存器把全锥吃进去；寄存器在"锥后"不在"锥前"。
- 修复: -(1<<(s-1)) = 64'hFFFF…<<(s-1) 恒等式预锁存（rndneg_r 同拍），
  选择退化为 2:1 mux（≤2 级）。时序中性（同拍可见），功能逐位恒等。
- 检测门: 段表中凡"源寄存器→模块内首级寄存器"超过 5 级即查模块输入
  脚的组合锥（尤其含 +/-1、移位、符号选择的预处理）。
- 预防规则: 模块输入脚不得带算术预处理锥；预处理一律预锁存或以
  恒等式化简为选择/布线。
- 复发: 0

### [2026-10-21] git: 并行棒活目录被整体 add 扫库——"按目录 add"在并发期=变体 -A
- 症状: 压力棒 1 验收提交 `git add 4_logs/2026-10-21_v35_stress/` 把并行
  UVM 棒的活仿真库（u1uvm/u1work 编译产物 58 件、含 .dbs 二进制）一并
  暂存入库并已推送（8a9da4d）。
- 根因: 棒级目录是共享命名空间——并行棒按战役根目录开自己的工作子目录
  （uvm_u1/），主会话 add 父目录即扫入他棒在途件。既有纪律"禁 -A/禁 ."
  只防了根级，没防父目录级。
- 修复: `git rm -r --cached`（盘上零损毁）+ 棒工作目录就地立 .gitignore
  （u1uvm/u1work/transcript/*.wlf）+ 清退提交（3949b8f）。
- 检测门: commit 前 `git diff --cached --stat` 逐件目检——出现他棒目录名
  （uvm_/q[0-9]_/别的臂前缀）即停手；在途 ≥1 代理时，add 只允许精确到
  **本棒臂级路径清单**（逐目录列参数），父目录整体 add 视同 -A 禁用。
- 预防规则: 派单时把"工作落点子目录名"写进派单参数；验收 add 用派单
  参数清单对账，清单外一律不 add。
- 复发: 1（7a95040 根级版 → 本次父目录级版，属同坑变体）

### [2026-10-21] board: ssh 单行内 `setsid cmd &` 起的服务随会话关闭即死——nohup+stdin 重定向+disown 三件套
- 症状: 部署脚本 ssh 远程 `setsid t1_ncnn_server_multi … >log 2>&1 &` 后
  本地脚本继续跑，30s 后 SERVER_READY 门超时；事后独立连接查：日志空/
  不存在、进程消失。链启动同样可能中招。
- 根因: ssh 会话关闭时对端 shell 退出，虽 setsid 换了会话，但部分
  PYNQ/systemd 环境下的进程仍随控制终端挂断收 SIGHUP；且后台进程
  继承 ssh 的 stdin/stdout 管道，管道 EOF/HUP 沿 fd 传播杀死进程。
- 修复: 三板斧缺一不可：`nohup setsid CMD >log 2>&1 < /dev/null & disown`。
  修复后服务器三模型注册 SERVER_READY 稳定存活。
- 检测门: 任何"ssh 起常驻进程"的脚本，起后必须用**独立第二条连接**
  pgrep 复核进程存活 + 日志非空；部署脚本的 READY 门不得与启动命令
  同一条 ssh。
- 预防规则: ssh 单行里起常驻进程一律 nohup+setsid+</dev/null+disown
  全配；复核一律独立连接。
- 复发: 0


## host-ncnn（PC 侧 ncnn 工具链 / pyncnn）

### [2026-10-22] host-ncnn: nanodet eval 前向与 _forward_onnx 图语义不一致（cls 内嵌 sigmoid）——torch-vs-导出图门必须手工复现 cls sigmoid，raw 直比必炸 32 级
- 症状: NanoDet-Plus torch-vs-ONNX 门报 max_abs_diff=32.1（阈值 1e-4），cls 通道（7 类）差异主导，reg 通道其实只有 1e-5 级。
- 根因: 两套前向语义不同源——eval 态 `head.forward`（nanodet_plus_head.py L134-148）返回 **raw** 拼接输出（cls logits 未激活）；而 `torch.onnx.export` 触发 `torch.onnx.is_in_onnx_export()` 走 `_forward_onnx`（L538-555），把 **cls 通道 [0:num_classes] 的 sigmoid 烤进图内**（reg 通道仍 raw）。raw logits（量纲 ±30）直比带 sigmoid 的图输出必差一个 logits 量级。此即 v65 README 记载的 "double sigmoid" 坑的另一半：解码端若再 sigmoid 一次会双压，而验证门若一次都不补则差整个 logits。
- 修复: 门侧在 raw torch 输出的 cls 通道上手写 sigmoid（`yt[:,:,:7]=1/(1+exp(-x))`）再比——修后 max_abs_diff=1.24e-05 PASS。旁证 probe_channel_diag：sigmoid(raw) vs ORT cls 差 1.2e-07、reg raw vs ORT 差 1.2e-05，逐通道块闭合。
- 检测门: nanodet 系（及其他「训练/导出双前向」架构）torch-vs-导出图数值门，先回答「eval forward 与 _forward_onnx 哪个算子有差」再定阈值；diff 呈「cls 大、reg 小」的反常分布（或恰好等于某激活函数的定义域）即激活归属指纹，禁止先怀疑权重/图坏。
- 预防规则: 导出图的数值验收门必须写明「raw 侧需要复现哪些图内激活」，注释里钉激活归属源码行号；对双前向架构，门脚本与导出脚本共用同一份 load+preprocess 代码路径。
- 复发: 0

### [2026-10-22] toolchain: nanodet load_model_weight 在「model.*+avg_model.* 并存」ckpt 上实际落在 EMA 权重——读代码推导 remap 会推错，一律张量级等值实证
- 症状: 复核 load_model_weight（check_point.py L24-58）源码推理「raw model.* 会被加载、avg_model.* 因 [6:] 剥前缀腐蚀被丢弃」，与实测相反：实载张量 == avg_model（EMA），torch.equal 级证据 ema_match=True / raw_match=False。
- 根因: remap 三段（avg 先弹出改名裸键 → module./model. 前缀剥离去全表应用）的键碰撞与 dict 插入序交互复杂，人肉推演不可靠；且 EMA 与 raw 权重本身仅差 max 1.77e-04，行为级对比几乎不可见，只有张量级 equal 能判。
- 修复: 以 `torch.equal(model.state_dict()[k], ckpt["avg_model."+k])` 抽样实证定案；导出脚本注释更正为「导出物 = EMA(ep25) 权重，与训练期 val 同源」。
- 检测门: 任何「ckpt 里并存双权重集（raw/EMA/teacher）」的加载路径，验收一律张量等值抽样（首层/中间/末层各一），不信源码阅读结论；训练代理报告的最终指标注明所用权重集。
- 预防规则: load_model_weight 类 remap 函数的语义结论以实证为准进文档；导出物与训练 val 权重集一致性写入 run manifest。
- 复发: 0

### [2026-10-20] host-ncnn: cv2 5.0 与 pyncnn 同进程必 segfault
- 症状: 同一 python 进程内先 import cv2 再用 pip 版 ncnn 推理，段错误。
- 根因: cv2 5.0 与 ncnn python 绑定的本地库冲突（2026-10-18 prep_images.py 已实测规避）。
- 修复: 预处理（cv2 读图/resize/归一化）与推理（pyncnn）拆两个进程，中间用 .npy blob + manifest.json 传递；本 run tools/smoke_prep.py + smoke_run.py 即此模式。
- 预防规则: 主机侧凡 pyncnn 推理脚本一律不 import cv2；需要真图输入时先跑独立 prep 进程落 blob。
- 复发: 0

### [2026-10-20] host-ncnn: pyncnn extract 输出 Mat 是 (C,A) 二维，不是 (1,A,C)
- 症状: decode 按 (1,2100,11) reshape 直接 IndexError。
- 根因: ncnn Mat 语义是 blob 维压缩表示，YOLO 解码头 output0 (1,2100,11) 到 pyncnn 变成 (11,2100)（C 在前）；np.array(out) 原样保留。
- 修复: d = out.reshape(C, A).T 得到 (A, C) 再切 box=[..., :4]、score=[..., 4:]。
- 预防规则: pyncnn 取输出后先 print shape 再写 decode；任何 (1,N,C) 预期都要防两维化。
- 复发: 0

---



---

（持续回填。新条目按格式加在对应分区顶部。）

### [2026-10-23] board: T1_DUMP_DIR 指纹 dump 是 NanoDet 输出形状专设——注册表切 yolo 槽即崩链黑屏
- 症状: 链带 T1_DUMP_DIR 重启后，板载按键切到 yolo 槽（MODEL_SELECT to mcontract-y11n）→ IndexError: too many indices for array（out[:, :7] 作用于一维 yolo 输出）→ 链死 → HDMI OSD 黑屏
- 根因: dump_maybe 假设 out 恒为 NanoDet [N,39+] 二维形状；注册表多槽热切换后 yolo 槽输出为一维，形状契约被违反（辅助路径未设守卫）
- 修复: 3_host/gesture_chain 正典 dump_maybe 加 ndim/shape 守卫（非 2-D 或 <7 列直接 return）；板上快照件随下次重冻带走
- 检测门: 给链 relaunch 加 T1_DUMP_DIR 前，先 grep 源里 ndim 守卫在不在；板侧判据=三槽各按一次键链不死
- 预防规则: 链内一切按模型形状假设的辅助路径，必须先过形状守卫再消费输出
- 复发: 0

### [2026-10-23] vivado-build: 共享工程容器形状漂移——异代构建 tcl 的检查门遇异代容器即 abort
- 症状: smoke bit（r11 形状 tcl）首跑即 M10SMOKE_BIT_FAIL rom_redepth pctl want=4096 actual=8832（容器被 r12 线改成 R63/coe63 形状，六 ROM xci 全漂移）
- 根因: yolo_v25_board 是全代际共享可变容器；各代 tcl 的 ROM 门为纯检查门（防漂移设计，不自带 retarget），容器现形状≠本代形状时按设计 abort；retarget 动作归本代 retarget tcl 所有
- 修复: 跑 X 代形状 tcl 前先 source 本代 retarget tcl 切容器回 X 形状（r12 生产 tcl 的 ROM 段幂等自感知，将来跑会自行重切 R63，动作可逆）
- 检测门: retarget/构建前先快照六 ROM xci Write_Depth 对照本代 SPEC（R10/R11 形状: pctl 4096/strip 512/lut 8192/iss 32/geo 32/wlay 32；R63 形状: 8832/1104/17664/69/69/69）
- 预防规则: 共享容器时代际构建「先切形状、后跑门」，顺序不能反；abort=门在正常工作，不是 tcl 坏了
- 复发: 0

### [2026-10-23] vivado-build: 共享容器 BD 的 r12-only 端口——ROM 可 retarget 拉回，BD 增量须用手术脚本自带快照回退
- 症状: r11 形状 smoke tcl ROM 门全过后 synth OOC 炸 Synth 8-11365：m9_sys.bd 带 r12 线独有的 cv_slot 端口（cell 端口/net/pin 共 5 处），r11 shadow 的 m9_plan_roms/m9_v25_bd_shim_v3 无此口，wrapper 重生成把 .cv_slot() 接进 r11 实例
- 根因: yolo_v25_board 是全代际可变共享 BD；r12 手术 r12_bd_width_surgery.py 加宽地址并**新增** cv_slot 端口；异代 tcl 的 RTL 无此口。ROM 有本代 retarget 正典（r10_ip_retarget.tcl），BD 增量没有 retarget 路径
- 修复: 回退到手术脚本三快照律首跑备份 .bak_pre_r12_width（m9_sys.bd + roms/shim 六 xci）；r12 线复工重跑 r12_bd_width_surgery.py（幂等）即恢复 r12 形状，动作可逆不损正典
- 检测门: 异代构建开跑前先 grep 容器 m9_sys.bd 有无 r12-only 端口（cv_slot）+ 六 xci 宽度口径；ROM retarget 过了也必须再查 BD 端口代际才能进 synth
- 预防规则: 「ROM 可拉、BD 靠快照」——共享容器跨代构建先核 BD 端口代际；回退永远用手术脚本自己的首跑快照，不手改 JSON
- 复发: 0

### [2026-10-24] toolchain: sed -i 就地改写归档驱动件——源文件被当克隆模板
- 症状: 计划 sed 克隆 gates_s→gates_t 时误对源归档件 gates_s/run_v41_gates_s.sh 用 sed -i，轮33 已执行 runbook 被改成 gates_t/submission34/TBD34 混合体（归档驱动件不再等于实际执行命令集）
- 根因: 复合命令里 sed -i 目标路径写错（源文件而非新文件）；链式替换无逐条断言、无跑后残余检查；归档件与工件同名同目录，视觉麻痹
- 修复: 从 gates_r 模板+原始变换序列重建 gates_s 脚本，逐行断言（submission33 轮次标记/307383b3 sha/TBD34 清零）后落盘
- 检测门: 任何 sed -i 跑后立刻 grep 源文件"应不变锚"（轮次标记/sha/ALL GATES DONE 行）；归档驱动件被动过即与执行日志对账；**轮换链（sed 多规则克隆）跑后 py_compile+干跑首步验证产物可执行，pkl/路径类引用逐一存在性断言**
- 预防规则: 克隆一律 sed 无 -i 重定向到新文件；sed -i 仅限显式单一目标+跑后锚点 grep；复合命令里每个 -i 目标单独一行书写；轮换 sed 规则集必须覆盖全部代际标记（文件名/目录名/轮次值），漏一条=静默错链
- 复发: 1（2026-10-24 同族变体：sta_t 克隆链漏 p150r 文件名规则→census 基线 pkl 路径错链 FileNotFoundError；双跑 diff 门被同构 traceback 骗过 exit 0——diff 门只比对输出不比失败，前置非零退出码断言立项呈裁中）

### [2026-10-24] toolchain: 纯卫生删件（零 netlist 账预期）仍触发 $auto 重编号 remap 彩票——RTL 删件=前网表节点序位移→映射种子随网名漂移
- 症状: 轮37 s_r 死寄存器退役刀（sm 三行删，sta_v netlist 中 s_r 已被 yosys 自然剪除、FF 双值同、零账预期）——sta_w 整芯重综合后 hier.json 非逐字同：sm-only 组合重排 +13 净 cell/类型级 60 项，area +205.197（反而变差），$abc$1150091 系→$1150072 系整体偏移（同名 70,871 中 7,118 换型）
- 根因: RTL 删件改变 fsm_map 前网表节点序列 → yosys $auto 自动编号系统性漂移 → abc 映射/再映射的种子（网名集合）漂移 → 纯组合重排。机制链与形态律同族（映射形态由 abc 对具体网名集合决定）；功能恒等由六门背书，STA 无感
- 修复: 审计裁案 B 回退（sm 回退 sha 等式=netlist 逐字同即恢复）；s_r 死件转 band43 观察档随下一振 sm 功能刀搭车清理（$auto 重编号反正发生，零边际）
- 检测门: netlist 逐字同比首门（runbook 常驻 cmp sta_N hier.json vs sta_N-1，非逐字同即停链呈裁）；V5.0 批 pre 包强制"netlist 同比预期"声明段（逐字同/DIFF 可解释/DIFF 未知三档+理由）
- 预防规则: 同文件卫生删件（死寄存器/死线消名/注释清理）必须搭车功能刀合并编辑，或预挂面积代价呈裁；零预期账≠零 remap 风险——凡动 RTL 即可能重摇 $auto 编号
- 复发: 0

### [2026-10-24] toolchain: abc 全芯片重综合面积方向不可从局部编辑面预测——est 只准报编辑面本体代价，禁报净值方向（§2b 常量折叠 est 证伪实案）
- 症状: 轮47 §2b 语义修复 pre est"46b 常量折叠 cells↓area↓ 低置信 ~20-60µm²"——实测 area Δ+546.774（ln +341.58/sm +205.20=轮37 彩票量级）、cells +88、越线档净+5 全芯片波及，方向完全相反
- 根因: 局部编辑（46b 符号复制→常量折叠）触发 abc 全芯片重综合，重综合净值=局部省账+全局 remap 波及账之和，后者量级/方向均不可从编辑面推出（与本区上一条 $auto 重编号彩票同机制面：映射种子漂移→组合重排）
- 修复: 审计 54 裁2④ est 注销；面积预期改走"编辑面本体代价（局部账）+netlist DIFF 三档声明（逐字同/DIFF 可解释/DIFF 未知）+cells×area 双列全口径实测对账"三件套
- 检测门: pre 包 netlist DIFF 预期声明段内 est 行凡出现"area↓/area↑ 净值方向"字样即拒；est 行只许"编辑面组合重写局部代价 ~Xµm²"形
- 预防规则: est 禁报全芯片净值方向——方向判据只来自落刀实测（stat 直出），预估只报局部本体；与"同文件卫生删件必须搭车功能刀"条同区互链
- 复发: 0

### [2026-10-25] board: 板端门脚本从「待下载新件」XSA 解析 VDMA 基址—— axi_vdma_0 只属现行负载（相机 overlay），fail-closed 门因此永远 abort
- 症状: AC1 复电窗三门序列 Gate B 必炸 `VDMA_CHECK_FAIL ip axi_vdma_0 not in HWH ip_dict: ['ps7','shim']` rc=2 → 整体 abort 禁下载；复原脚本 VDMA 读回段同 KeyError
- 根因: 门/复原脚本的 VDMA 基址解析源写成「待下载 AC1 件」的 XSA（AC1 设计无 axi_vdma，ip_dict 只有 ps7+shim）；VDMA 属**现行相机 overlay**（/home/xilinx/ees331_camera/overlay.bit+hwh @0x43000000）。ees331.md 正典本写明「resolve from the matching HWH」=匹配**当前在板负载**，非待载新件
- 修复: 修正副本以相机 overlay.bit 解析（patched_*_*.sh，原件未动）；同 boot 内实测：相机停后 RS=0 双证、下载+岛恒等+复原全链 PASS
- 检测门: 凡板端脚本要从 ip_dict 取 axi_* 口，先断言所用 HWH 源的负载身份（现役 overlay 的 bit/hwh vs 待载 XSA）；取不到即停呈，不硬编码地址
- 预防规则: 「VDMA 基址永远向现役负载的 HWH 要，向待载新件要不到」——写门脚本时解析源字段单独一行+注释钉负载身份
- 复发: 0

### [2026-10-25] board: sudo -S 经 PowerShell 内联 printf 投递="Sorry, try again"≠口令错；文件通道（上传脚本内 printf）为唯一可信形态
- 症状: AC1 复电窗两轮 BLOCKED_AT_SUDO：ssh 同口令过 sshd（shadow crypt 实证）、sudo -S 全链被拒；10-25 本轮复现+破解：同 boot 内「内联 printf "%s\n" 穿 PS→ssh」被拒、「probe 脚本文件内 printf」秒过（两次独立实证）
- 根因: PowerShell 5.1 向 native ssh 传参时对远程命令串内嵌双引号做剥离/转义变形（skill 台账 2026-09-18 已记此坑），远程 printf 收到的格式串与预期不符→喂给 sudo 的字节串错；sudo 对此的唯一对外表述="Sorry, try again"，与真口令错不可区分。叠加误诊链：sudoers/shadow mtime `2022-10-21 23:06`=**PYNQ 镜像构建时间戳**（出厂件从未被改），早前被读作「10-21 23:06 被改」并脑补 Defaults rootpw——年份误读+通道坑两因叠加造出「用户改了 sudoers」假因。faillock 已排除（pam.d 零命中、无 /var/run/faillock）。昨夜根因高度疑似同通道坑，但昨夜未留文件通道对照实证→定性未闭环，本条目复发计数不代昨夜记
- 修复: sudo 口令一律走「上传 bash 脚本、printf 在文件内」的文件通道；wrapper 内 run_sudo(){ printf '%s\n' "$PW" | sudo -S "$@"; }
- 检测门: 板端 sudo 测试/门脚本出现「ssh 远程命令串内嵌 printf|echo 喂 sudo」形态即停；时间戳取证用 `stat -c '%n %y %a'` 读全年份，禁从 ls 缩写推断年份
- 预防规则: 凭据投递「三禁」：禁 PS 管道直喂、禁内联引号串、禁从 ls 时间缩写读年份；sudo 被拒先换通道再怀疑口令
- 复发: 0
### [2026-10-25] toolchain: RTL shadow provenance 清单与盘内字节漂移——跨会话消费时行锚/成熟度论据随漂移失效（r12 shadow 6/15 件实证）

- 症状: plfront B 期呈件制备期实测 `2026-10-21_c3_r12_build_run01\rtl_shadow_r12\src\` 15 件在盘字节，与 `provenance_rtl_sha256.txt`（c3 代钉）**6/15 件不符**：m9_abi_v2_csr（7e8a4304→983a25b0）、m9_cmd_issuer（1f38e88d→f6efec80）、m9_intra_axi_top_v3（1ba849a8→75205119）、m9_intra_top_v3（4c660327→7c0b9730）、m9_v25_top_v3（a62ef641→9eb6a410）、**m9_page_tables（1b55fbdb→2df13f0c）**。其中 page_tables 为全树风险最高件（v2.0 页面面/仅 elab 冒烟/新增 301 行），v1.0 呈件曾漏计（只报 5 件），b6 R117 补正。
- 根因: c3 provenance 快照后 shadow 树继续演进（疑 v2.5 页面面落笔等合法编辑）未回写清单；provenance 文件本身**无 freshness 门/钉时点字段**，任何下游按清单钉 sha 或按 c3 行号引用（如 v1.1 §b-1.2 的 L125-143/L79-85 行锚）即系统性错位。
- 修复: 呈件/构建门一律以**消费时点实测字节**为钉（certutil/Get-FileHash 实测入 manifest）；c3 行锚一律改内容 grep 锚复核。产物内容由 sha 门保证确定性，漂移不产生产物差，但**成熟度/行锚类论据必须随实测重验**。
- 检测门: 消费任何血统 shadow/清单前，先 15 件（或清单全量）Get-FileHash 实测 vs provenance 对账，不符件数>0 即登记入呈件披露节（不得静默取 provenance 值）。
- 预防规则: 血统清单必须带「钉时 sha + 钉时点 + 钉人」三元组；跨会话消费「先实测、后引用」；provenance 漂移件中的最高风险件（本案 page_tables）的原因澄清挂账必答项，未澄清前其「已冒烟/已验证」论据按最保守口径读。
- 复发: 0（首登）

### [2026-10-25] toolchain: xvlog -f filelist 首行 UTF-8 BOM 失识别——43-4316 连环报错假象，BOM 非 α 选型证据
- 症状: plfront B 期前置 0 三臂烟 run01 轮 xvlog -f files_plfront.f 报 43-4316 "Can not find file: M11..." 连环错，首轮整体机械失败；files_plfront.f / tb_plfront_id_smoke.sv 初版带 UTF-8 BOM（PowerShell Set-Content -Encoding utf8 默认写 BOM），xvlog 对 -f 文件首行 BOM 不宽容致注释行失识别
- 根因: PowerShell 5.1 Set-Content -Encoding utf8 默认产 UTF-8 with BOM；xvlog filelist 解析器首行遇 BOM 失同步
- 修复: 剥 BOM 重跑（r2 轮补三件页面面 BMG sim 模型后 elab 全通）
- 检测门: 生成任何 xvlog -f filelist / RTL 源后查首三字节（EF BB BF），有即剥；filelist 首轮报错先分「编码机械失败」vs「真引用错」两类再归因
- 预防规则: PS 写文本产物禁 Set-Content -Encoding utf8（用 ASCII 或 [IO.File]::WriteAllText 无 BOM）；xvlog -f 文件与 RTL 源一律无 BOM 落盘
- 复发: 0

### [2026-10-25] toolchain: 构建门检查脚本 manifest 键名 bug——want 全 None 门首跑即停全链（B 期 run01 止于 bake 门）
- 症状: B 期 Vivado run01 全门梯止于 bake 门——bake_check_plfront.py 以文件名读 manifest 键，实际 manifest 键为面名 → 全部 want=None；got 侧全对，门无法判等即 fail-closed 停
- 根因: manifest schema（面名键）与检查脚本（文件名键）不同源，schema 侧演进未同步脚本；want 全空集是检查器故障形态而非真值不符
- 修复: 修键名 bug 后离线干跑 PASS；run02 全门梯绿灯
- 检测门: 门脚本首跑前用小样本 manifest 离线干跑，确认 want 非全 None；门停呈先分「检查器 bug」vs「真值不符」两类再定责
- 预防规则: 检查脚本与 manifest schema 共用同一常量源；want=None 全空集一律判检查器故障，禁据此对真值下结论
- 复发: 0

### [2026-10-25] vivado-build: OOC 独立 dcp 为 glue 占位零值形态——直读 utilization 全零不作数，真值须 open_run 链接实测
- 症状: B 期预算 HALT 归因普查需 ROM/页面面 BRAM census——直接对 OOC 生成的独立 dcp 读 utilization 得全零/占位值
- 根因: OOC synth 的独立 dcp 仅含 glue 占位逻辑（无完整网表），资源数无意义；真值在链接进整体设计后才存在
- 修复: open_run 链接 OOC 后实测（halt_utilization_full.txt + halt_bram_census_full.txt 两账）
- 检测门: 任何 OOC dcp 直读 utilization 为 0/占位 → 判「形态不作数」，转 open_run 链接实测门，禁以零值入账或外推
- 预防规则: OOC 件资源账永不经独立 dcp 直读；census 一律链接后 open_run report
- 复发: 0

### [2026-10-25] vivado-build: r12 CAP0 代际常数 v2.3→v2.4 演进——TB 期望滞后一代即烟测 FAIL（非 RTL 缺陷）
- 症状: B 期三臂烟 r3 轮暴露 G5CAP0 期望差：0x4D390230（v2.3 代）vs 实测 0x4D390240（v2.4 代 RTL 有意演进），TB 期望未同步即 FAIL
- 根因: RTL 代际演进（CAP0 身份/能力常数 0x230→0x240）属合法演进，TB 期望常量滞后一代未同步
- 修复: TB 期望同步至 0x4D390240 后 r4 轮三臂全 PASS
- 检测门: 身份字烟测 FAIL 先核判据常量与 RTL 实读是否同代（CAP0/版本字常量 grep RTL 源实读对拍）
- 预防规则: RTL 身份/能力常数演进时同步清单必含 TB 期望；TB FAIL 定性先分「期望滞后」vs「RTL 缺陷」再排障
- 复发: 0

### [2026-10-25] toolchain: 预算门锚定估计值自指陷阱——门须实测基线+物理余量地板；风险挂账面强制入预算算术
- 症状: B 期 BRAM 门 91.5 锚在「ROM 加深 +21-22 tile」估计上；实测加深 +25 → 即使无页面面 36 tile 也会 94.5>91.5 触门——门值因估计偏差自指失效（b6 R121 首抓）
- 根因: 门锚估计值而非实测基线，估计偏差直接转化为门失效；r12-only 页面面三表 36 tile 在呈件风险节挂账但未入预算算术（本可从三 BMG xci 深度/宽度/pack 方式事前推得，非不可知）
- 修复: 新门以实测 census 为基线+物理余量地板（b6 R121 C1 建议 ≤120/140 tile 给 P&R 留 ≥20）；逐选项 delta 算术入件；门解析器 synth 段修法（C3）：LUT 可解析即判、Slice 记 n/a 或外推旗标+impl 段硬判、parse_failed 保留为真解析失败专用
- 检测门: 预算门设立时问「锚是实测还是估计」——估计锚必配余量地板；呈件风险挂账面带 BRAM/LUT 者逐条对账预算算术是否已含
- 预防规则: 风险挂账面强制入预算律（R121 C2）：凡携带 BRAM/LUT 的新表面必须带显式估计+推导入预算算术
- 复发: 0

### [2026-10-25] toolchain: r11 截断形终局比对 4 行=结构性非判据（首见由存活首次解释）+ 裁决过滤谓词固化
- 症状: R83 S8 run01（r11 golden63 线**史上首个自然终局 run**，39.37M 拍 rc=0）门铃后 TB 打印终局比对 4 行——heads desc_done=1 expect=43 / bytes final vs 6475200 / REPACK_ZONE 全零计数 / errors=11 汇总（y_nerr=3774400=全图 m2 总量）——表面形似 FAIL 汇总
- 根因: 同一已知机理（TB expect 按**全图**校准 vs r11 程序为**截断镜像**形）的终局比对**首见 manifestation**——「seg=N bytes yb=」结构行 S5a/S7′ 前科已见；「首见」由**存活首次**解释（前五案均死于死亡区/db8 冻结/err07 收尸，终局比对代码路径首次被走到），非病灶首次
- 修复: 无需修复——competition-98 R125-C1 独立论证裁认**结构性非判据，不升级**（三点：同根已知类/可见性条件/判据自洽）；后续 r11 线任何自然终局 run **继承该分类不得重开审判**；TB 冻结零改动律不动
- 检测门（判定谓词固化，C2）: 终局比对 4 行出现 ≠ FAIL——r11 截断形验收电池**不系于终局绝对值**；db9 闭合判据=G4YSDONE 全数（恰 376）+conv 臂 16/16（max b=nb−1）+9th G5SEG cyc/yb（39373888/254624）+sc_done 实收 9/9。裁决脚本**必须内建结构行过滤谓词**（过滤 TB expect 全图校准类终局比对行），下轮起不得再发明该 bug
- 预防规则: r11 截断形（无 TB_R12_G5_PASS 横幅）任何自然终局 run，终局比对 4 行按本条**预分类**，直接引用不重审；新缺陷形态（非本 4 行结构）另立案
- 复发: 0（首登；归结构性类后继承不重修）
- 互链: R83 S8 run01 result.md sha 1d3f162e…；7_logs/2026-10-25/03 R125 节；competition-98 R125 裁定原文（四点裁项）

### [2026-10-25] xsim-guard: 看守终止宽词 TIMEOUT 撞启动横幅 TIMEOUT_MAX_PG 误收尸（变体 7）
- 症状: plfront C 腿二分 run01 attempt1 首心跳即被看守收尸——终止标记宽词 `TIMEOUT` 命中启动横幅常驻词面 `G5WDT ... TIMEOUT_MAX_PG`，死锁证据链本应自然成形即被砍（attempt2 修复后全链正常）
- 根因: 启动横幅词汇面带 TIMEOUT_MAX_PG 常驻，与终止宽词子串碰撞；台账看守族四变体（CIM cmdline 自匹配/xsimk 孤儿逃逸/守卫杀 scope 双变体）均未覆盖「横幅常驻词撞终止宽词」形态
- 修复: 终止标记改精确形 `' TIMEOUT cyc='`（前导空格+完整词+行内上下文三要素）；attempt2 起全链正常
- 检测门: 看守终止词表设立/复用时，先 grep 目标 TB 启动横幅与帮助文本全词面做撞词检查，子串碰撞即升级精确形
- 预防规则: 终止标记一律三要素精确形（前导空格+完整词+行内上下文），禁裸宽词；TB 横幅新词入库前过撞词检查
- 复发: 0

### [2026-10-25] vivado-sim: 手写 BRAM 行为模型未零初始化 vs 官方 blk_mem_gen C_INIT*_VAL("0") 零填契约
- 症状: B 期 run02 B3 树页面面 G2 梯首 PPP 门 S_PPPG->X（canon 为 S_PPPG->S_CVRD），ppp_hit_w 变 X；探针显示窗字1=X、其余字有效（tabX=1 常驻）
- 根因: 测试件手写 SDP 行为模型 mem 无 initial 初始化，未写行读 X；官方 blk_mem_gen 仿真产品无 COE 时 C_INITA/B_VAL("0")+C_DEFAULT_DATA("0") 零初始化——正典语义依赖 0-fill（op==0=EMPTY 门未中）
- 修复: 三模型加 `initial for (i=0;i<32;i=i+1) mem[i] = {WIDTH}'d0;`（logs/b3_rtl_surgery.txt 末节）
- 检测门: 任何手写 BRAM 模型上岗前 grep `initial`+`mem[` 零填；对拍官方模型参数 C_INITA_VAL/C_INITB_VAL/C_DEFAULT_DATA
- 预防规则: 手写存储模型必须复刻官方初始化契约（零填/COE），不许裸 reg 数组上岗
- 复发: 0

### [2026-10-25] rtl: RMW 行合并基值错置零（dina=全 0 而非旧行）
- 症状: B3 单元梯 T4/T5 join 行非目标词被清零（w0..w2=0、w19 在），窗面读未写行=X
- 根因: RMW MODIFY 拍 `dina_join` 基值写成常量 0，字节/lane 合并在零基上叠加，非目标词全清；正确基值=B 口读回的旧行（join_doutb_p）
- 修复: `dina_join = join_doutb_p`（按表同理核对 ppp/edge 基值）
- 检测门: RMW 单元测试必须含「非目标 neighbor 词保持」断言（T5 型）
- 预防规则: RMW 合并基值一律来自读回旧行，禁任何常量基值
- 复发: 0

### [2026-10-25] vivado-sim: xvlog 模块作用域 use-before-declaration 报错（声明序敏感）
- 症状: xvlog 报 `identifier 'rd_pend' is used before its declaration`，指向模块作用域 assign 行
- 根因: SystemVerilog 模块作用域 continuous assign 引用后声明的 net/reg，xsim 的 module-scope 声明序敏感
- 修复: 被引用信号声明块移到首个 assign 之前
- 检测门: xvlog ERROR 首查声明序；模块作用域「先声明后引用」一律前置
- 预防规则: 模块作用域 assign 链的 operands 声明统一放模块头部
- 复发: 0

### [2026-10-25] org/process: 台账三副本同步后被并行线追加条目→副本间漂移（申报 sha 与实物不符被审计打回）
- 症状: 主工程席申报「三副本 sha=00367cd3 同步」，审计三方亲算发现 1_docs 与 ~/.claude/skills 两副本=2fcedb58（多 2 条目：vsim 后台 stdin 挂死条+Git Bash cp CRLF 字节损坏条），6_skill 副本落后。
- 根因: 三副本法的天然抗漂移场景——同步时点之后，另一并行工作线向其中两个副本追加条目，与主同步流相擦；申报人只重算了自认为刚写入的副本。
- 修复: 处置口径=以并集为准补齐落后副本（Copy-Item 全文覆盖，不手工插行），三方复验一致后再申报新 sha。
- 检测门: 申报三副本同步前，必须对三个路径现场 Get-FileHash 逐一核对，不得以"上次同步时的 sha"或单副本重算代替；审计打回即按并集口径处置不争论。
- 预防规则: 台账写入实行"单写者+写后三方即时复验"律；并行线需追加条目时先取当前三方 sha，追加后三方同步并复验；跨会话协作场景下任何一方申报同步 sha 都被对席独立重算。

### [2026-10-25] rtl: 恒等仪平行模型签名≠RTL 函数声明序——调用实参错位实案（round62 刀B rnd 窗）
- 症状: V4.1 轮62 刀B（rnd 掩码链 64b×42→7b×21 指针化）落刀后六门 5/6 FAIL：task2 纯 GEMM 四 shape 约 50% 输出值错（y[1] act=dc26 exp=dbe6），写地址/拍数账一字不差；而落刀前后 Python 恒等仪三重型（L1 掩码/L2 消费窗/L3 结构）全空间 ALL PASS
- 根因: Verilog 函数声明 `rnd_pwin(input [6:0] b, input [6:0] k)`（基址 b 先、索引 k 后），22 处消费调用却写 `rnd_pwin(rdk_ch[i], 7'dB)`（索引先、基址后）——实参序与形参序整刀相反：哨兵判 `k<64` 落到常量基址上恒真、等值判 `b+m==k` 拿索引当基址，消费窗几乎全错。恒等仪 Python 模型签名 `rnd_pwin(k, b)`（索引先）恰与 RTL 调用序同而与 RTL 函数声明序反——仪验的是"平行模型自洽"，从未触达 RTL 实例化面，故三重型全过而硅上全错
- 修复: 22 处调用纠正为 `rnd_pwin(7'dB, rdk_ch[i])` 形（双树 sha 35c5fb98）。二分佐证：摘刀A留刀B 失败指纹逐字不变（task2 fails 1250/12615/3167/242）；修复后 task2 四 shape fails=0 复绿
- 检测门: 凡"函数化再生"刀，恒等仪除模型层外必须加「实例化面核对」——脚本 parse RTL 源全部调用点实参序 vs 函数声明形参序自动比对（grep 调用+声明两处成对核，禁目检）；且落刀后首门用真 RTL 功能门（task2 级）先于 STA 链
- 预防规则: 平行模型恒等仪只证数学等价不证接线等价；函数签名以 RTL 声明形参序为正典，模型/调用/声明三处签名不一致即停手核
- 复发: 0

### [2026-10-26] board: PYNQ 3.0.1 同基名 .xsa 遮蔽——Overlay(裸 bit) 走 is_xsa 分支对 .bit 调 Metadata 必崩（10-25 sidecar 条目变体①）
- 症状: Overlay("/…/x.bit") 抛 UnknownInputFileExtension（bit/hwh sha 双验均过、sidecar 在旁仍崩）；10-25 探针未中枪仅因配套 xsa 基名不同（pfr8_companion.xsa）
- 根因: BitstreamHandler.is_xsa() 仅按 <基名>.xsa exists() 判定；同目录同基名 .xsa 存在⇒is_xsa=True⇒hwh 分支被跳过⇒elif is_xsa 支对 .bit 路径调 Metadata，pynqmetadata 只认 .hwh/.xsa/.json⇒必崩
- 修复: 板上 staging 改名破除同基名（xsa→a8_companion.xsa，sha 不变）；铁律升级="同基名三件套 .bit+.hwh+.xsa 同目录=崩"。2026-10-29 v20 复发后改 companion XSA，并在 Overlay(BIT) 前增加 same-base XSA 存在即退出的 DL_GATE；attempt02 下载/identity 实测 PASS
- 检测门: 裸 bit staging 门=ls <dir> | grep -c "<bitbase>\.xsa" 必须为 0；下载脚本 DL_GATE 段加该 ls 硬门。**打包/manifest 生成时也必须静态拒绝 same-base XSA，不能只靠板侧 staging 后检查**
- 预防规则: 裸 bit Overlay 目录禁放同基名 .xsa；xsa 一律 companion 命名
- 复发: 1（2026-10-29，v20 打包漏执行既有防呆门；PL 重配置前失败，companion+DL_GATE 后复测越过）

### [2026-10-26] board: ctypes from_buffer 导出未释放——mmap.close() BufferError 遮蔽已 PASS 的自检结论（语义全过形态像败）
- 症状: FSM 三件套自检全 PASS 打印后退出路径 m.close() 抛 BufferError: cannot close exported pointers exist，进程 RC=1
- 根因: (ctypes.c_uint8*N).from_buffer(mmap) 持有 buffer 导出，close 前必须 del 该 ctypes 对象；prep 侧只过 py_compile 语法门，清理段 bug 漏网
- 修复: 板侧单行 del wb（双版本存证），重跑即 PASS
- 检测门: 凡 ctypes from_buffer 包装 mmap 的板端脚本 close 前 grep `del <export>`；脚本门从 py_compile 升级="完整跑到进程退出码"
- 预防规则: mmap+ctypes 导出模式=close 前 del 导出对象
- 复发: 0

### [2026-10-26] board: 装载握手全绿+毒指纹 21 面+done 均匀性复现=消费层零产出停呈形态（A8 首次全图硅上实案，归因待裁 R150）
- 症状: 装载 FSM 36 事务/333 词全绿（done/err=0 逐字 busy 契约）+影子集拆除核验过+9 门铃字面 done/err=0+C2 全零，但 C3 0/21——heads+20 输出面全 0xA5 毒指纹；9 段 TICK 差仅 3 模值与 exp_cyc 脱敏
- 根因（先行归因停呈待裁）: 装载握手层全绿而消费层零产出⇒最自洽假说=四表内容已装但未被下游消费（候选 a：表内容语义/门铃受理链/start_cond/DESC 消费面）；G7 观测 LD_DATA 按 WO 读出全 0 不能分辨表空/表载（观测力边界不含糊裁定）
- 修复: 无（停呈留证禁现场修补）；下一步=TBL 读回真口定位/PL 侧 ILA/消费握手差分，均须审计放行
- 检测门: runner C3 POISON_REPORT+SEG_TABLE done 均匀性双指纹同现即此形态；禁拿 9/9 门铃字面 done 声明"全图跑完"
- 预防规则: R63 族整图验收=C3 21 面全绿才算数；门铃 done 只声明握手受理
- 关联: 探针 10-25 同形态 0/21 但装载面全红；本次装载面全绿形态未变=关键差异
- 复发: 0
- 症状: loadfsm_design_prep（R143 尾注）/impl_run01（R147-C1 漂移）/a8_board_window_prep（字节列非标）三现：manifest 哈希值本身全对，但行格式（尾注括号/注释列/字节列混入）使 `sha256sum -c` 解析失败
- 根因: manifest 手写拼装时把元数据塞进 hash 行，无"机验可解析"强制约束
- 修复: 注释一律独立 # 行；hash 行严格=64hex+两空格+路径
- 检测门: manifest 发布前必须真跑一次 `sha256sum -c` 且全 OK 才算 PASS（禁只肉眼对值）
- 预防规则: 台账正典格式条增列——凡 sha manifest 必 -c 机验可解析；非标即拒发退回
- 复发: 0
- 症状: R63 族同时存在三个 W 地址直方图同形的程序卷——①程序钉 9 门铃板卷（tb_setup_r11.txt 9be735fc/tb_setup.mem 457d9bfd，2499 词，R106 钉，bake 门 PROGPIN sha_ok=True 实证=本 bit 板面世界）②探针 3 门铃 R129 调查卷（1899f75b/3d6ec088，1802 词，PROBE 语义）③S8-sim 9 门铃卷（e87c8df4/c2bec795，纯 xsim r11 血统，layout c746cb99 heads 302400≠板面 149100）——肉眼不可分，arena 基址/段表/金面各异
- 根因: 三卷同族同形（E9×36/EA×333/boot 块同址），目录惯例（随手拷最近 run 的卷）无防呆；程序锚未钉死在验收件上
- 修复: 呈件/驱动一律以 PROGPIN（457d9bfd…）为唯一程序锚；金面/布局配 layout.json fcf421ce 一套；runner 启动打 BIT_PIN+卷 sha+segs/门铃数（本卷 9 门铃+H43）与呈件表对拍
- 检测门: 上传前四方对账必含 prog 三件 sha；runner 解析后门铃数不符即停呈
- 预防规则: R63 族板窗呈件程序卷只认 bake 门钉（PROGPIN），禁从探针/sim run 目录随手拷卷；呈件 §2 必录卷 sha+词数+门铃数三值
- 复发: 0
- 症状: 2026-10-26 01:20 发现双 Vivado 会话并行：旧 2.1 prep 代理（任务 5 小时前已 handback"完成"）持有的会话 PID 24156 仍在跑 attempt9 synth（01:20:13 启动），与合线段 01:23 自建的合法会话形成双 synth 抢机器
- 根因: 代理 handback/任务终结只交还代理层控制权，**它持有的 Vivado MCP 会话（及后台电池/重放）不随代理死亡**；线切换（2.1 prep→fix-B→合线段）时没有任何环节核对该线会话是否已释放；且该代理在 handback 中未披露自己还持有活会话+活电池，披露只在被追问后补交
- 修复: 协调员明示后由持有方 vivado_stop 自己的会话（PID 24156），tasklist 亲验进程树消失；合线段会话（01:23 簇）为唯一合法会话继续
- 检测门: 任何新 Vivado 会话启动**前**（不是启动后），`Get-Process vivado` 全量清点+逐会话核对持有线归属；新线启动报备必须含"现存会话清单为零或已过户"一句
- 预防规则: ①线切换交接单强制含会话状态（会话 ID/PID/在跑 run/处置=过户或停止）；②代理 handback 模板强制披露"本人持有会话/后台进程"段，零持有也要写"零"；③长窗多线并行时，主席侧每线终了做一次进程级清点（Get-Process vivado CPU/StartTime 快照入 03）
- 关联: attempt8 产物（MERGE21_CANDIDATE，无装载 FSM）按 R146-N1 本就不能呈整图板验，且被 A8 线 supersede——孤儿跑的算力纯浪费（约 1.5h synth），幸而发现时还在 synth 段未污染任何正典件
- 复发: 0
- 症状: m9_page_tables JOIN 表 wr_row=a[9:5]/wr_widx=a[4:0] 对 20 词行；addr%32≥20 的词写丢读零（守卫只卡 addr<640 不卡行内孔）；装载 FSM 预检同界限故两臂同孔（G2 逐位等价不受影响，但孔是真实数据面）
- 根因: 行寻址宽度 32 槽位 vs 表 20 词/行密度不匹配，孔内地址无守卫拒绝
- 修复: 守卫收紧=设计变更另批（当前不越权）；现役处置=生成器/装载驱动禁发孔地址
- 检测门: 任何表写面（卷生成器/装载 FSM/板窗驱动）发布前扫描全部写地址，%32≥20 即拒发；canon/变体两形同检
- 预防规则: 新表写面设计时行密度与寻址宽度必须同契；孔地址要么守卫显式拒要么物理不存在，禁"静默写丢读零"第三态
- 关联: g2/g7 变体三元组旧账机理候选（R147-B②：canon 若用孔内词则行为分叉——重打 golden 立项优先验证假设；若中则旧账定性从测试基准债升级为真缺陷发现）
- 复发: 0
- 症状: fix-B C3 段 g2/g7 在 consumed 树 FAIL（g2 P2 ledge / g7 1/10 仅 case2）；v1.4 组与 alpha 对照组逐案签名 diff 为空（被测对象无辜）；r12 canon 基线 10/10 PASS
- 根因: 电池十五件门 deliberate 钉死的三件 plfront 变体（scatter 87ba25a4 / axi_wr 22b81ce5 / page_tables c61c7431）从未对 r12-canon golden94 重打基准——功能梯 golden 是 canon 形，对变体树=条件目标错配（run01 梯头 v1.1 ruling 2 早裁"r12 g2/g7 梯不适用 alpha 树"，R140-C3 未察觉该裁定，审计对称认账）
- 定性纪律: **测试基准债**——"变体行为是否真缺陷"未判定（=重打基准链待答问题），禁写成"已证无缺陷"
- 修复: 选项②（为三元组重打 golden）单独立项排期呈批（R144-C5），债不悬挂无主；不阻断 fix-B（v1.4 本体由 id 烟+编译/elab 门+M10SMOKE 真门守卫）
- 检测门: 任何被门钉死的变体树要上功能梯，先问"golden 是否对该树形重打过"；没有=按基准债 fail-closed 停呈，禁把梯失败直接读成被测对象失败（单变量对照：换回原形签名仍同=非被测对象引入）
- 预防规则: 门钉变体 ⇒ 同时钉配套 golden 重打义务；后续硬核门与在先 ruling 冲突时，以先裁为准并显式对账两条款（禁只按新门字面执行）
- 复发: 0——缺即 RuntimeError("Unable to find metadata for bitstream")
- 症状: 板端 `Overlay("/path/x.bit")` 抛 RuntimeError("Unable to find metadata for bitstream")
- 根因: PYNQ 3.0.1 embedded_device.set_bitfile_name 要求同基名 .hwh 存在于 bit 旁（XSA 分支自动解，裸 bit 分支不自动）
- 修复: 从配套 XSA 解出 m9_sys.hwh 复制为 <bit 基名>.hwh 同目录上传
- 检测门: 板端下载脚本启动前 ls <bit>.hwh；缺即补
- 预防规则: 裸 bit 上板必须携同基名 HWH sidecar（sha 入档）
- 复发: 0

### [2026-10-25] board: CSR 字节地址译码寄存器 PS 可达性——m9 命令口（EE/DE/E9/EA/EB）E9/EA 结构性不可达，自治整图装载阻塞（探针 run01 F1 实案，R141 机制修正版）
- 症状: PYNQ MMIO MemoryError("Unaligned write")；整图门铃空转、20 输出缓冲全 0xA5 毒指纹、岛 result_seq 0、HEAD_BYTES=0；三门铃 done 全落 ≈2.51M 拍（与各自 exp_cyc 2.29M/2.70M/6.25M 脱敏，均匀性本身佐证空转=F1）
- 根因（结构性主因，lane 模型无关，单独即充分）: CSR case 解码 awaddr[7:0]=字节地址（shim L210 亲读），卷面命令词驻留非字对齐地址；**字写 awaddr[1:0]=00 永不击中 8'hE9/8'hEA 臂**；窄写即使触发 case 也因捕获位片错位拼不出合法命令词（arm 捕 w[15:0] 等，无 WSTRB 门控）
- 机制注记（R141 §2 修正）: E1 读数按 RTL 算术解释=**车道正确**模型（byte05@E9→读回 0x05 唯一吻合 tbl_sel←1/tbl_cur[1]←0x100；复制模型预测 0x01、零填充预测 0x00 均不符）——"A9 子字存储车道复制"假说被 E1 日志证伪，禁作为事实入档；EE 验证格自洽（0xEE 落 bits[23:16]，byte 写三段硅上读回 OK）；**DE 格降级**：halfword 落 bits[31:16] 而 arm 捕 w[15:0]，大概率未送达，"可交付"无读回背书不成立 → **R151/D0 闭合（2026-10-26）**：sim 活现 cfg_up2x 恒 0（DE lanes[3:2] 值放 [31:16]），R141 伏笔坐实；修面裁定=驱动全字写+写后读回断言（up2x 载重：A 修复后 db4 多页帧物化 u2x 面，0x11 必须项）
- 根因续: PPP 触发表唯一写口=0xEA、复位零、lds 对齐面只写 EDGE/JOIN 不含 PPP → 表恒零 → walker 不跑 → 自治整图被装载通道阻塞
- 修复: E9/EA 需设计/构建层变更（lds 面扩 PPP / PL 内装载 FSM），呈批后实施；EE 可经 byte 窄写交付（已证）；DE 不可依赖
- 检测门: 任何新 CSR 寄存器图须过 PS-reachability 审计——每条 arm 落字对齐 awaddr 或有 WSTRB 门控捕获；重放前扫描卷面 W 地址 %4，EA 词计数>0 即告警"PPP 装载不可达"
- 预防规则: 板上自治卷必须显式证明其每条命令词的 PS 可达性；缺证明即按装载阻塞 fail-closed
- 复发: 0

### [2026-10-25] rtl: 新寄存器数组命名撞存量标量——yosys "Cannot add signal X because a memory with the same name"（轮64 M_a w1a_r/w1b_r/w2a_r/w2b_r vs G18/G19）
- 症状: 落刀后 yosys 整芯综合 ERROR: Cannot add signal `\w1a_r` because a memory with the same name was already created（首轮撞名即停，后续撞名被遮蔽未知）
- 根因: 新数组名 w1a_r/w1b_r/w2a_r/w2b_r 与模块内既有 G18a/G18b/G19a/G19b 标量寄存器同名（memory vs 标量同域冲突）；命名时只查了目标阵列族内重名，未做全树声明级撞名普查
- 修复: 撞名四名嵌域标改名（w1ma_r/w1mb_r/w2ma_r/w2mb_r）；索引形态 `名[` 与标量无索引形态双证区分，G18/G19 标量零误伤
- 检测门: 落刀前执行 `grep -cE "(reg|wire)[^;=]*<新名>" 全树` 逐名普查（含 generate 块内局部声明）；任何 ≥2 命中即停手改名；综合首轮 ERROR 即按本条目改名重跑，不得就地删旧声明
- 预防规则: 新寄存器命名强制全树撞名普查（含 wNa/wNb 式短名标量族），索引形态/标量形态双证区分后再落刀
- 复发: 0
