#!/usr/bin/env python3
"""Prepare an isolated Vivado 2025.2 build from the delivered source snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FORMS = ('form1a_ble_bridge_j5','form1a_pl_preprocess','accelerator_ac1',
         'form1b_multitask_osd','form2_pl_continuous','form3_pspl_resident')

def tcl(value):
    value=str(value).replace('\\','/')
    if any(c in value for c in '\n\r'):
        raise ValueError('Unsupported Tcl path character')
    return '"'+value.replace('\\','\\\\').replace('"','\\"').replace('$','\\$').replace('[','\\[').replace(']','\\]')+'"'

def prepare(form, output, stage):
    output=Path(output).resolve()
    if output.is_relative_to(ROOT):
        raise ValueError('Build output must be outside the submission package')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Use a new empty output directory for every attempt')
    project=ROOT/'board'/form/'vivado_project'
    xprs=list(project.glob('*.xpr'))
    if len(xprs)!=1: raise ValueError('Expected exactly one XPR')
    tree=ET.parse(xprs[0]); refs=[]; seen=set()
    for fs in tree.findall('.//FileSet'):
        if fs.get('Name') not in ('sources_1','constrs_1') and fs.get('Type')!='BlockSrcs':continue
        for node in fs.findall('File'):
            attrs={a.get('Name'):a.get('Val') for a in node.findall('.//Attr')}
            attrs['UsedIn']=[a.get('Val') for a in node.findall('.//Attr') if a.get('Name')=='UsedIn']
            if attrs.get('AutoDisabled')=='1':continue
            raw=node.get('Path','')
            path=Path(raw.replace('$PSRCDIR',str(xprs[0].with_suffix('.srcs'))).replace('$PPRDIR',str(project))).resolve()
            if fs.get('Type')=='BlockSrcs' and (path.suffix!='.xci' or '/bd/' in path.as_posix()):continue
            if path.suffix=='.dcp':continue
            if not path.is_file() or not path.is_relative_to(project):
                raise ValueError('Missing or external source: '+raw)
            if path in seen:continue
            seen.add(path)
            refs.append((path.relative_to(project),'constrs_1' if fs.get('Name')=='constrs_1' else 'sources_1',attrs))
    output.mkdir(parents=True,exist_ok=True)
    def skip_generated_bd_ip(directory, names):
        # The BD stores the IP configuration. Regenerate its outputs instead
        # of importing stale generated XCI whose names depend on the old path.
        return ['ip'] if 'ip' in names and list(Path(directory).glob('*.bd')) else []
    shutil.copytree(project,output/'sources',ignore=skip_generated_bd_ip)
    # Module-reference XCI files preserve the BD interface boundary inferred
    # from RTL. Unlike vendor IP output products, they are source contracts.
    for source in project.rglob('*.xci'):
        try:
            metadata=json.loads(source.read_text(encoding='utf-8-sig'))
        except (OSError,ValueError):
            continue
        reference=metadata.get('ip_inst',{}).get('component_reference','')
        if not reference.startswith('xilinx.com:module_ref:'):
            continue
        target=output/'sources'/source.relative_to(project)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target)
    manifest=[{'path':p.relative_to(project).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(project.rglob('*')) if p.is_file()]
    (output/'input_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    part=tree.find(".//Configuration/Option[@Name='Part']").get('Val')
    top=tree.find(".//FileSet[@Name='sources_1']/Config/Option[@Name='TopModule']")
    top=top.get('Val') if top is not None else 'display_test_wrapper'
    defines=[n.get('Name') for n in tree.findall(".//FileSet[@Name='sources_1']/Config/Verilog_Define")]
    lines=['# Generated from the packaged XPR. All writes remain in this run.',
           'set run_dir '+tcl(output),'cd $run_dir',
           'if {[version -short] ne "2025.2"} {error "Vivado 2025.2 is required"}',
           'if {[info exists ::env(XILINX_VIVADO)]} {',
           '  set store [file join $::env(XILINX_VIVADO) data XilinxTclStore]',
           '  foreach p [list [file join $store support appinit] [file join $store tclapp xilinx xsim]] {lappend auto_path $p}',
           '}',
           'create_project -force submission [file join $run_dir project] -part '+tcl(part),
           'set_property target_language Verilog [current_project]',
           'set_property ip_output_repo [file join $run_dir ip_cache] [current_project]',
           'set_param general.maxThreads 4']
    for rel,fileset,attrs in refs:
        source=output/'sources'/rel
        # BD-owned XCI files are read through the BD, not added twice.
        if source.suffix=='.xci' and '/bd/' in source.as_posix():continue
        lines.append('add_files -norecurse -fileset '+fileset+' '+tcl(source))
        if attrs.get('FileType'):
            lines.append('set_property file_type '+tcl(attrs['FileType'])+' [get_files '+tcl(source)+']')
        if attrs.get('Library'):
            lines.append('set_property library '+tcl(attrs['Library'])+' [get_files '+tcl(source)+']')
        if attrs['UsedIn']:
            lines.append('set_property used_in [list '+' '.join(tcl(v) for v in attrs['UsedIn'])+'] [get_files '+tcl(source)+']')
    run_options=[]
    for run_name in ('synth_1','impl_1'):
        source_run='impl_ac1' if form=='accelerator_ac1' and run_name=='impl_1' else run_name
        run=tree.find(".//Run[@Id='"+source_run+"']")
        strategy=run.find('Strategy/StratHandle') if run is not None else None
        if strategy is not None:
            lines.append('set_property strategy '+tcl(strategy.get('Name'))+' [get_runs '+run_name+']')
        for step in run.findall('Strategy/Step') if run is not None else []:
            for option in step.findall('Option'):
                if option.get('Id')=='Directive' and form=='accelerator_ac1':
                    # Verified by read-only Vivado 2025.2 report_property of
                    # original synth_1 / impl_ac1; XPR numbers are enums.
                    value='Default' if run_name=='synth_1' else 'Explore'
                    prop='STEPS.'+step.get('Id').upper()+'.ARGS.DIRECTIVE'
                elif option.get('Id')=='MoreOptsStr':
                    value=option.text or ''
                    prop='STEPS.'+step.get('Id').upper()+'.ARGS.MORE OPTIONS'
                else:
                    raise ValueError('Unsupported run option: '+ET.tostring(option,encoding='unicode'))
                lines.append('set_property -dict [list '+tcl(prop)+' '+tcl(value)+'] [get_runs '+run_name+']')
                run_options.append({'run':run_name,'source_run':source_run,'property':prop,'value':value})
    if defines:
        lines += ['set_property verilog_define [list '+' '.join(tcl(v) for v in defines)+'] [get_filesets sources_1]']
    lines += ['set_property top '+tcl(top)+' [get_filesets sources_1]',
              'update_compile_order -fileset sources_1',
              'foreach bd [get_files -quiet *.bd] {',
              '  open_bd_design $bd',
              '  validate_bd_design',
              '  save_bd_design',
              '}',
              'report_ip_status -file [file join $run_dir ip_status.rpt]',
              'puts "PACKAGE_PROJECT_VALIDATION_PASS"']
    if stage=='bitstream':
        standalone=[output/'sources'/rel for rel,fs,attrs in refs if rel.suffix=='.xci' and '/bd/' not in rel.as_posix()]
        if standalone:
            lines += ['generate_target all [get_files [list '+' '.join(tcl(p) for p in standalone)+']]']
        lines += [
                  'foreach bd [get_files -quiet *.bd] {',
                  '  generate_target all $bd',
                  '}']
        if defines:
            lines += ['foreach fs [get_filesets] {',
                      '  if {[lsearch -exact [list_property $fs] VERILOG_DEFINE] >= 0} {',
                      '    set_property verilog_define [list '+' '.join(tcl(v) for v in defines)+'] $fs',
                      '  }','}']
        if form=='accelerator_ac1':
            lines += ['set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs m9_sys_shim_0_synth_1]']
        lines += [
                  'launch_runs synth_1 -jobs 4',
                  'wait_on_run synth_1',
                  'if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "SYNTHESIS_FAILED"}',
                  'launch_runs impl_1 -to_step write_bitstream -jobs 4',
                  'wait_on_run impl_1',
                  'if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "IMPLEMENTATION_FAILED"}',
                  'open_run impl_1',
                  'report_timing_summary -file [file join $run_dir timing_summary.rpt]',
                  'report_utilization -file [file join $run_dir utilization.rpt]',
                  'report_drc -file [file join $run_dir drc.rpt]',
                  'if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]]} {error "UNRESOLVED_BLACKBOX"}',
                  'foreach delay_type {max min} {',
                  '  set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1]',
                  '  if {![llength $paths]} {error "NO_TIMING_PATHS $delay_type"}',
                  '  if {[get_property SLACK $paths] < 0} {error "TIMING_FAILED $delay_type"}',
                  '}',
                  'if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} {error "DRC_ERRORS"}',
                  'write_hw_platform -fixed -include_bit -force [file join $run_dir submission.xsa]',
                  'puts "PACKAGE_BITSTREAM_BUILD_COMPLETE"']
    lines += ['close_project','puts "VITA_VIVADO_RESULT PASS"','exit 0']
    lines=['try {']+lines+['} on error {message options} {',
        '  puts stderr "VITA_VIVADO_RESULT FAIL: $message"',
        '  puts stderr [dict get $options -errorinfo]',
        '  exit 1','}']
    (output/'run.tcl').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    result={'form':form,'stage':stage,'inputs':len(manifest),'active_references':len(refs),'part':part,'top':top,'run_options':run_options,'tcl':str(output/'run.tcl')}
    (output/'preflight.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))
    print('Next: vivado -mode batch -source "'+str(output/'run.tcl')+'" -log "'+str(output/'vivado.log')+'" -journal "'+str(output/'vivado.jou')+'"')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--form',choices=FORMS,required=True)
    parser.add_argument('--output',required=True)
    parser.add_argument('--stage',choices=('validate','bitstream'),default='validate')
    args=parser.parse_args()
    prepare(args.form,args.output,args.stage)
