"""Write the three LaunchAgents with plistlib, so no path can break or inject
into the XML. Usage: mkplists.py OUTDIR PREFIX CLAUDE RC_DIR HOME RC_PATH LOGDIR INSTALL_PREFIX DEBUG(0/1)"""
import plistlib,sys,os
out,pre,claude,rcdir,home,rcpath,logdir,prefix,debug=sys.argv[1:10]
sys_path='/usr/bin:/bin:/usr/sbin:/sbin'
rc_args=[claude,'remote-control']+(['--debug-file',f'{logdir}/remote-control.debug.log'] if debug=='1' else [])
agents={
 'remote-control':dict(ProgramArguments=rc_args,WorkingDirectory=rcdir,
    EnvironmentVariables={'HOME':home,'PATH':rcpath},RunAtLoad=True,
    KeepAlive=True,   # rc exits 0 after giving up on the network: restart on every exit
    ThrottleInterval=30,ProcessType='Interactive',Umask=0o077,
    StandardOutPath=f'{logdir}/remote-control.log',StandardErrorPath=f'{logdir}/remote-control.err.log'),
 'watchdog':dict(ProgramArguments=[f'{prefix}/bin/claude-rc-watchdog'],
    EnvironmentVariables={'HOME':home,'PATH':sys_path},RunAtLoad=True,KeepAlive=True,ThrottleInterval=10,Umask=0o077,
    StandardOutPath=f'{logdir}/watchdog.log',StandardErrorPath=f'{logdir}/watchdog.log'),
 'updater':dict(ProgramArguments=[f'{prefix}/bin/claude-rc-update'],
    EnvironmentVariables={'HOME':home,'PATH':rcpath},RunAtLoad=True,StartInterval=1800,Umask=0o077,
    StandardOutPath=f'{logdir}/updater.log',StandardErrorPath=f'{logdir}/updater.log'),
}
for name,d in agents.items():
    d={'Label':f'{pre}.{name}',**d}
    with open(os.path.join(out,f'{pre}.{name}.plist'),'wb') as f: plistlib.dump(d,f)
