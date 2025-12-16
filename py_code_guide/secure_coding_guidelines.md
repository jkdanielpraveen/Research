# Cortex XSOAR Secure Code Guidelines

Security is paramount in SOAR workflows as they often handle sensitive data and have wide network access.

## 1. Input Validation & Injection Prevention
*   **Never Trust Input:** Treat all data from `demisto.args()` as untrusted. Validate types and formats (e.g., ensure an IP address string actually looks like an IP).
*   **Command Injection:** Avoid using `os.system()`, `subprocess.call()` with `shell=True`, or `exec()`.
    *   *Bad:* `os.system(f"ping {user_input}")`
    *   *Good:* Use native Python libraries or strictly validated lists for subprocess calls.
*   **SQL/Query Injection:** If constructing queries (e.g., for SQL databases or complex API query languages), use parameterized queries provided by the library rather than string concatenation.
*   **Deserialization:** Avoid `pickle` or `yaml.load()` on untrusted data. Use `json` or `yaml.safe_load()` to prevent arbitrary code execution.
*   **Path Traversal:** Validate file paths. When handling filenames from input, ensure they resolve to the intended directory using `Path.resolve()` and check for `..`.
*   **ReDoS (Regex Denial of Service):** Avoid nested quantifiers (e.g., `(a+)+`) in regular expressions that run on user input. Use safe, bounded patterns.

## 2. Secret Management
*   **No Hardcoded Secrets:** NEVER hardcode API keys, passwords, or tokens in the code.
    *   *Bad:* `API_KEY = "12345"`
    *   *Good:* `api_key = demisto.params().get('credentials', {}).get('password')`
*   **Secure Logging:** Do not log sensitive data.
    *   Ensure `demisto.debug()` or `demisto.info()` calls do not dump entire response objects that may contain secrets.
    *   Use the `mask_secrets` feature if available or manually filter logs.
*   **Format String Injection:** Avoid passing user input directly to logging functions.
    *   *Bad:* `demisto.info(f"User input: {user_input}")`
    *   *Good:* `demisto.info(f"User input: %s", user_input)` (let the logger handle formatting safely)
*   **Weak Cryptography & Randomness:**
    *   Avoid `md5` or `sha1`. Use `sha256` or stronger.
    *   Avoid `random` module for security/tokens. Use `secrets` module (e.g., `secrets.token_urlsafe()`).

## 3. Memory & Resource Management
*   **Container Limits:** XSOAR containers often have strict memory limits (e.g., 512MB or 1GB).
    *   **Avoid:** Loading entire large files (GBs) into memory strings.
    *   **Prefer:** Streaming files or processing data in chunks.
*   **Loop Efficiency:** Avoid infinite loops. When polling APIs, always implement a max retry count or timeout.
*   **Insecure Temp Files:** Avoid creating temp files with predictable names in shared directories like `/tmp`. Use `tempfile.NamedTemporaryFile()` with restrictive permissions.
*   **Broad Exception Handling:** Avoid bare `except:` or `except Exception: pass`. Always catch specific exceptions or log the error before handling it, to prevent hiding security failures.

## 4. Network Security
*   **SSL Verification:** Always verify SSL certificates (`verify=True` in `requests`) unless explicitly disabled by the user via an "Insecure" integration parameter.
    *   Pass the global `verify` parameter to your request methods.
*   **Proxy Support:** Respect the XSOAR proxy settings (`demisto.params().get('proxy')`) when making external HTTP requests.

## 5. Output Security
*   **War Room Encoding:** When outputting data to the War Room (Markdown/HTML), ensure user input is escaped to prevent Cross-Site Scripting (XSS) or HTML injection.

