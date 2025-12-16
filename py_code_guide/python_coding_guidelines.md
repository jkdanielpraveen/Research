# Cortex XSOAR Python Coding Guidelines

This document outlines the industry standards for developing Python automations (scripts) and integration commands within Cortex XSOAR.

## 1. Style & Formatting (PEP 8)
We adhere to standard Python enhancement proposals (PEPs) with specific adaptations for the XSOAR environment.

*   **Indentation:** Use 4 spaces per indentation level.
*   **Line Length:** Limit lines to 79-120 characters to ensure readability in the XSOAR IDE and standard editors.
*   **Naming Conventions:**
    *   `Snake_case` for variables and functions (e.g., `get_indicator_data`).
    *   `CamelCase` for classes (e.g., `IndicatorClient`).
    *   `Upper_Case` for constants (e.g., `MAX_RETRIES`).
*   **Imports:** Group imports: Standard library -> Third-party -> Local application (XSOAR specific).

## 2. Type Hinting (PEP 484)
*   **Mandatory Type Hints:** All function signatures must use type hints. This acts as immediate documentation and validation.
    ```python
    def parse_incident_severity(severity: str) -> int:
        ...
    ```
*   **Complex Types:** Use `typing.List`, `typing.Dict`, `typing.Optional`, and `typing.Union` for complex structures.
    ```python
    def get_users(ids: List[str]) -> Dict[str, Any]:
        ...
    ```

## 3. Documentation (PEP 257)
*   **Docstrings:** Every function and class must have a docstring using triple double-quotes `"""`.
*   **Format:** Use the Google Style Python Docstrings or standard Sphinx format.
    ```python
    def update_ticket(ticket_id: str, status: str) -> None:
        """
        Updates the status of a specific ticket in the remote system.

        Args:
            ticket_id (str): The ID of the ticket to update.
            status (str): The new status to apply (e.g., 'Open', 'Closed').

        Returns:
            None
        """
    ```

## 4. XSOAR Specific Patterns
*   **Main Entry Point:** Always use a `main()` function wrapped in a global exception handler.
    ```python
    def main():
        try:
            # Logic here
        except Exception as e:
            return_error(f'Failed to execute script. Error: {str(e)}')

    if __name__ in ('__main__', '__builtin__', 'builtins'):
        main()
    ```
*   **Arguments & Params:**
    *   Use `demisto.params()` to retrieve integration configuration (credentials, URLs).

## 5. Development Tooling & Workflow
To ensure code quality and security before deployment, use the following local workflow:
*   **Virtual Environment:** Manage dependencies per project.
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    ```
*   **Development & Validation (Standard):**
    *   **Install `demisto-sdk`**: This is the official tool for linting and validating XSOAR content.
        ```bash
        pip install demisto-sdk
        ```
    *   **Linting:** Runs `flake8`, `mypy`, `bandit`, and `pylint` in a Docker container matching the integration's environment.
        ```bash
        demisto-sdk lint -i Packs/YourPack
        ```
    *   **Validation:** Checks structure and common errors.
        ```bash
        demisto-sdk validate -i Packs/YourPack
        ```

*   **Security Scanning (Supplemental):**
    *   `pip-audit`: Scans installed packages for known vulnerabilities.


