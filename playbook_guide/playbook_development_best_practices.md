# Cortex XSOAR Playbook Development Best Practices

This document outlines the industry standards for designing and developing robust, maintainable, and efficient playbooks within Cortex XSOAR.

## 1. Playbook Design & Structure

### Clarity & Naming
*   **Descriptive Task Names:** Avoid generic names like `Set` or `Conditional`. Use action-oriented names: `Set Severity to Critical` or `Is IP Internal?`.
*   **Self-Contained:** A user should understand what the playbook does just by looking at the flowchart, without opening task details.
*   **Modular Design:** Break complex workflows into **Sub-playbooks**. If a sequence of tasks (e.g., "Enrichment") is used in multiple places, make it a sub-playbook.

### Input/Output Management
*   **Formal Inputs:** Define playbook inputs clearly in the "Playbook Inputs" section (e.g., `IncidentType`, `IndicatorSeverity`). Do not rely on "Implied" context keys that might not exist.
*   **Structured Outputs:** When a playbook produces data for a parent playbook, use "Playbook Outputs". Return specific sub-keys (e.g., `File.Name`, `File.Size`) rather than dumping the entire context.

### Logic & Control Flow
*   **Avoid Complex Loops:** Loops in XSOAR can be performance-heavy. If you need to iterate over 1000+ items, use a Python script (Automation) instead of a playbook loop.
*   **Race Conditions:** Tasks generally run sequentially, but if you have parallel branches joining together, be careful when modifying the *same* context key. Use `Set` tasks carefully or merge branches before modifying global context.

## 2. Performance Optimization

### "Quiet Mode"
*   **Use Quiet Mode:** For high-volume playbooks or tasks (like heavy enrichment loops), enable "Quiet Mode". This prevents every single task execution from being logged to the War Room, significantly reducing database bloat and UI lag.
*   **Selective Logging:** Only log critical decisions or errors to the War Room.

### Indicator Extraction
*   **Disable Auto-Extraction:** By default, XSOAR extracts IOCs (IPs, URLs, Hashes) from *every* task result. This is often unnecessary and expensive.
    *   **Best Practice:** Disable "Auto-extract" on most tasks. Enable it ONLY on tasks that specifically fetch new indicators (e.g., "Get Phishing Email Body").

### Context Data
*   **Minimize Context Size:** Do not store massive blobs of data (like full HTML of a webpage or 10MB JSONs) in the Context.
    *   **Alternative:** Store the file in the War Room (File entry) and pass the `EntryID` around in the context.

## 3. Error Handling
*   **Task Retries:** Configure retries for tasks that interact with external APIs (e.g., "Retry 3 times with 30s delay") to handle transient network glitches.
*   **SLA Timers:** Set SLAs on critical branches. If a task (like "Analyst Approval") takes too long, have a timer branch to escalate or default to a safe action.
*   **Integration Checks:** Before running a specific vendor command, checking `IsIntegrationEnabled` can prevent "Command not found" errors if the integration is disabled.

## 4. Playbook Validation
*   **Use `demisto-sdk`:** Always validate playbooks before pushing.
    ```bash
    demisto-sdk validate -i Packs/YourPack/Playbooks/playbook-MyPlaybook.yml
    ```
    This tool checks:
    *   Valid YAML structure (not just syntax, but XSOAR schema).
    *   Unique IDs and proper versioning.
    *   Broken links (e.g., refering to a script that doesn't exist).
    *   Missing required inputs or outputs.

