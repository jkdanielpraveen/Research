# Cortex XSOAR Secure Playbook Development

This document outlines security-specific practices for ensuring that playbooks do not introduce vulnerabilities or mishandle sensitive data.

## 1. Authorization & RBAC (Role-Based Access Control)

### Playbook Execution Permissions
*   **Role Restriction:** Not all playbooks should be executable by all analysts. Restrict "Remediation" or "containment" playbooks (e.g., "Block Firewall Rule") to Senior Analyst roles.
*   **Investigation Access:** Use RBAC to restrict who can view sensitive investigations (e.g., HR or Legal investigations). Playbooks running in these investigations must respect these boundaries.

### Approval Gates
*   **Human-in-the-Loop:** For destructive actions (Reboot Server, Isolate Host, Delete User), ALWAYS include a "Data Collection" or "Ask" task to require explicit human confirmation.
*   **Escalation:** If an automated decision has high confidence but high impact, consider sending a notification to a Slack channel/Email for passive visibility even if manual approval isn't required.

## 2. Sensitive Data & Context Handling

### Parameter Management
*   **Credential Handling:** NEVER accept credentials (passwords, API keys) as text inputs to a playbook.
    *   **Best Practice:** Credentials should be stored in the **Integration Instance** configuration or XSOAR **Credential Vault**. The playbook should simply reference the integration instance name.
*   **Masking Outputs:** If a task outputs sensitive data (e.g., "Get User Password"), ensure the task's specific "Log to War Room" setting is masked or disabled to prevent the secret from appearing in plain text in the incident timeline.

### Context Security
*   **Private Context:** Be aware that data in the Context is generally visible to anyone with access to the incident.
*   **Data Minimization:** Do not pull PII (Personally Identifiable Information) into the context unless necessary for the logic. If you just need to display it, print it to the War Room without saving it to Context (`ignore_output=True` in script).

## 3. Integration & Input Security

### Input Validation
*   **Sanitization:** If a playbook takes an input that is used in a CLI command (e.g., `hostname`), ensure the underlying automation script validates it to prevent **Command Injection**.
    *   *Playbook Level:* Use conditional tasks to verify the input format (e.g., "Is this a valid IP?") before passing it to the action task.
*   **Boundary Checking:** Validate values are within expected ranges (e.g., ensure "Ban Duration" isn't set to 100 years by accident).

### Least Privilege
*   **Specific Integrations:** If you have multiple instances of an integration (e.g., `Active Directory - ReadOnly` and `Active Directory - Admin`), force the playbook to use the `ReadOnly` instance for enrichment tasks.
    *   *Implementation:* Use the `using` argument in tasks to specify the exact integration instance.

## 4. Secure Development Lifecycle
*   **Review:** All playbooks should undergo a peer review, specifically checking for logic gaps (e.g., "What happens if this API returns empty?").
*   **Testing:** Test playbooks with "Mock" incidents to ensure they handle failure paths gracefully without leaking data or crashing.
