# Public system interfaces only

Process facts come from `libproc` and `sysctl` for processes of the current user, and from `/bin/ps` for everything else. An unprivileged process gets `EPERM` from `libproc` for processes of other users, while `ps` is setuid root and can see them. We do not use private interfaces: not the responsible-process lookup that Activity Monitor uses, not `IOReport`, not the SMC.

## Consequences

- Fan speed and temperatures are not shown. System thermal state stands in for them.
- A helper process such as a browser content process is linked to the application that owns it by the files it has open, not by the system's own notion of responsibility.
- Only names of environment variables on an explicit list are ever read from other processes, and only where the system exposes them at all.
