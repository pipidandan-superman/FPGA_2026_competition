# freeze_copy_rtl.ps1 - M4.2 boundary-scoped freeze copy of frozen 2_fpga YOLO RTL
# Copies hand-written RTL sources + IP contract files (.xci/.veo only; build
# artifacts like .dcp/.xml/sim_netlists are regenerable from .xci and are NOT
# copied) into 12_yolo_accel boundary dirs. Verifies byte equality via SHA256
# on every pair and writes rtl_ledger.json. Strictly read-only w.r.t. 2_fpga.
# Boundary map per replan section 6:
#   yolo_gemm    <- rtl root GEMM-path files + GEMM\ (incl tb, ip contracts)
#   yolo_dma_csr <- rtl root dma/csr/ctrl files + ps_axi_pl\ (incl tb, ip)
#   yolo_graph   <- PPU\ all hand RTL (add/f6/f7/maxpool5/requant/shell/tb/
#                   upsample2/xfer)
$ErrorActionPreference = 'Stop'
$src = 'E:\competition\2_fpga\3_yolo_zynq\rtl'
$dst = 'E:\competition\12_yolo_accel'
$entries = New-Object System.Collections.Generic.List[object]

function Add-Pair([string]$s, [string]$d, [string]$b) {
  $destdir = Split-Path $d -Parent
  if (-not (Test-Path $destdir)) { New-Item -ItemType Directory -Force $destdir | Out-Null }
  Copy-Item $s $d -Force
  $hs = (Get-FileHash $s -Algorithm SHA256).Hash.ToLower()
  $hd = (Get-FileHash $d -Algorithm SHA256).Hash.ToLower()
  if ($hs -ne $hd) { throw "hash mismatch after copy: $s" }
  $entries.Add([pscustomobject]@{
    boundary = $b
    src_rel  = $s.Substring($src.Length + 1)
    dst_rel  = $d.Substring($dst.Length + 1)
    sha256   = $hs
    bytes    = (Get-Item $s).Length
  })
}

# --- yolo_gemm boundary: rtl root GEMM-path files ---
$gemmRoot = 'yolo_acc.v','yolo_conv0_core.sv','yolo_conv_core.v','yolo_gemm_array.v',
            'yolo_pe_pack.v','yolo_requant.v','yolo_silu_lut.v','yolo_wbuf.v',
            'yolo_xbuf.v','yolo_engine_top.v'
foreach ($f in $gemmRoot) { Add-Pair "$src\$f" "$dst\yolo_gemm\rtl\$f" 'yolo_gemm' }

# --- yolo_gemm boundary: GEMM\ direct sources + tb\ ---
foreach ($f in (Get-ChildItem "$src\GEMM" -File | Where-Object { $_.Extension -in '.v','.sv' })) {
  Add-Pair $f.FullName "$dst\yolo_gemm\rtl\gemm\$($f.Name)" 'yolo_gemm'
}
foreach ($f in (Get-ChildItem "$src\gemm\tb" -File)) {
  Add-Pair $f.FullName "$dst\yolo_gemm\rtl\gemm\tb\$($f.Name)" 'yolo_gemm'
}
# --- GEMM IP contract files only (.xci/.veo) ---
foreach ($ip in (Get-ChildItem "$src\gemm\ip" -Directory)) {
  foreach ($f in (Get-ChildItem $ip.FullName -File | Where-Object { $_.Extension -in '.xci','.veo' })) {
    Add-Pair $f.FullName "$dst\yolo_gemm\rtl\gemm\ip\$($ip.Name)\$($f.Name)" 'yolo_gemm'
  }
}

# --- yolo_dma_csr boundary: rtl root dma/csr/ctrl files ---
$csrRoot = 'yolo_dma.v','yolo_dma_wr.v','yolo_addrgen.v','yolo_csr.v','yolo_ctrl.v'
foreach ($f in $csrRoot) { Add-Pair "$src\$f" "$dst\yolo_dma_csr\rtl\$f" 'yolo_dma_csr' }
foreach ($f in (Get-ChildItem "$src\ps_axi_pl" -File | Where-Object { $_.Extension -in '.v','.sv' })) {
  Add-Pair $f.FullName "$dst\yolo_dma_csr\rtl\ps_axi_pl\$($f.Name)" 'yolo_dma_csr'
}
foreach ($f in (Get-ChildItem "$src\ps_axi_pl\tb" -File)) {
  Add-Pair $f.FullName "$dst\yolo_dma_csr\rtl\ps_axi_pl\tb\$($f.Name)" 'yolo_dma_csr'
}
# --- ps_axi_pl IP contract files only (.xci/.veo) ---
foreach ($ip in (Get-ChildItem "$src\ps_axi_pl\ip" -Directory)) {
  foreach ($f in (Get-ChildItem $ip.FullName -File | Where-Object { $_.Extension -in '.xci','.veo' })) {
    Add-Pair $f.FullName "$dst\yolo_dma_csr\rtl\ps_axi_pl\ip\$($ip.Name)\$($f.Name)" 'yolo_dma_csr'
  }
}

# --- yolo_graph boundary: PPU\ all hand RTL (recursed, structure preserved) ---
foreach ($f in (Get-ChildItem "$src\PPU" -Recurse -File | Where-Object { $_.Extension -in '.v','.sv','.vh' })) {
  $rel = $f.FullName.Substring("$src\PPU".Length + 1)
  Add-Pair $f.FullName "$dst\yolo_graph\rtl\ppu\$rel" 'yolo_graph'
}

$entries | ConvertTo-Json -Depth 3 | Set-Content "$dst\rtl_ledger.json" -Encoding ascii
$g = $entries | Group-Object boundary | ForEach-Object { "{0}: {1} files" -f $_.Name, $_.Count }
"BOUNDARY COPIES:"
$g
"TOTAL: $($entries.Count) files"
"LEDGER: $dst\rtl_ledger.json"
