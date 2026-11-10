# Security

Please report a vulnerability privately through [GitHub security advisories](https://github.com/p9k-io/agent-activity-monitor/security/advisories/new). Do not open a public issue for it.

The app runs as the current user, is not sandboxed, and can terminate that user's processes after a confirmation. Anything that lets a Cleanup run without a person's approval, or that makes the app store or reveal command lines, environment values or conversation content, is in scope.
