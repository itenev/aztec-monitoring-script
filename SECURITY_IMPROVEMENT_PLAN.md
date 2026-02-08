# Security Improvement Plan

This document outlines a plan to address the security findings identified in:

*   Security audit report dated 2026-02-07
*   PR-based security review (merge commits d8e7ce5, 15bb71e) dated 2026-02-09

---

## 1. Remote Code Execution

*   **Status:** In Progress
*   **Finding:** The script uses `curl | bash` to install Foundry and Docker and to fetch/run remote scripts (e.g. logo.sh, check-validator.sh, install_aztec.sh) without integrity checks.
*   **Action:**
    *   Remove the automatic installation of Foundry and Docker (or keep manual-install-only flow).
    *   For any script that must be downloaded, provide checksums (e.g. SHA-256) in the repo and instructions for users to verify before execution; avoid piping curl directly to bash.
    *   Prefer downloading to a temp file, verifying checksum, then executing; or document that users should clone the repo and run local scripts only.
*   **Progress:**
    *   Removed the automatic installation of Foundry and Docker from the `check_dependencies` and `install_aztec_node_main` functions. The script will now instruct the user to install these dependencies manually if they are not found.
    *   Added `scripts/generate_checksums.sh` to generate SHA-256 checksums for `start.sh`, `config.json`, and `scripts/*.sh`. Maintainers can run it to produce `SHA256SUMS`; users can verify with `sha256sum -c SHA256SUMS`. README Security section updated with integrity verification instructions.

---

## 2. `sudo` Usage

*   **Status:** In Progress
*   **Finding:** The script uses `sudo` to install dependencies.
*   **Action:**
    *   Minimize the use of `sudo` by identifying dependencies that can be installed without root privileges.
    *   For any remaining `sudo` commands, provide a clear explanation to the user about why `sudo` is required and what commands will be executed.
*   **Progress:**
    *   Removed `sudo` from `docker logs`, `rm`, and `ss` commands.
    *   Added a confirmation prompt before using `sudo` for package installation and firewall configuration.

---

## 3. Private Key and Secrets Handling

*   **Status:** In Progress
*   **Finding:** Private keys (validator), Telegram bot token, and RPC URL are stored and used in plaintext: in `~/.env-aztec-agent`, in generated `agent.sh`, and in `~/aztec/.env` / docker-compose env. The agent script and cron expose the Telegram token to anyone with read access to the agent file or crontab.
*   **Action:**
    *   Add a prominent warning (in README and at runtime) about the risks of handling private keys and tokens in the script.
    *   Restrict permissions on generated files: set `chmod 600` (or stricter) on `~/.env-aztec-agent` and on `$AGENT_SCRIPT_PATH/agent.sh` after writing; ensure the agent directory is not world-readable.
    *   Where possible, avoid embedding the Telegram token directly in the generated agent script; instead have the agent source a dedicated secrets file (e.g. `~/.env-aztec-agent`) that is already permission-restricted, and document that users should not run the script from a world-readable directory.
    *   Investigate integration with a hardware security module (HSM) or key management service (KMS) for validator keys; document the option for users who need higher assurance.
*   **Progress:**
    *   Added a warning to the `generate_bls_keys` function to inform users about the risks of handling private keys.
    *   **TODO:** Enforce and document restrictive permissions on `.env-aztec-agent` and `agent.sh`; add README/runtime warnings for token and key handling.

---

## 4. User Input Validation and Injection Prevention

*   **Status:** Done
*   **Finding:** User input is not always validated before use in `sed` or shell commands. In particular: (1) `check_proven_block.sh` uses `user_port` in `sed` and `nc` without validating that it is a numeric port; (2) `change_rpc_url.sh` uses `NEW_RPC_URL` in `sed` after regex validation—regex reduces risk but there is no explicit escaping for `sed` delimiters or newlines.
*   **Action:**
    *   **Port input:** In `check_proven_block.sh`, validate `user_port` so that only a valid port number (1–65535) is accepted (e.g. regex `^[0-9]+$` and range check). Reject or re-prompt on invalid input; do not use unvalidated value in `sed` or `nc`.
    *   **RPC URL:** Keep strict URL regex in `read_and_validate_url`; consider sanitizing or escaping for `sed` (e.g. use a different delimiter or escape `|` and newlines) when writing to env file, to prevent accidental injection if the regex is ever relaxed.
    *   **General:** Audit all `read -p` and similar inputs that are used in `sed`, `grep`, or shell commands; add format and range validation and, where applicable, escaping or allow-lists.
*   **Progress:**
    *   Port validation and sed escaping implemented in `check_proven_block.sh` and `change_rpc_url.sh`.

---

## 5. Sensitive Files in Version Control and .gitignore

*   **Status:** Done
*   **Finding:** `.env`, `.env-aztec-agent`, and `env-aztec-agent` are not listed in `.gitignore`. Users who run the script from a git working directory may accidentally commit these files and leak RPC URL, Telegram token, and other secrets.
*   **Action:**
    *   Add to `.gitignore`: `.env`, `.env-aztec-agent`, `env-aztec-agent`, and any other filenames used for local secrets (e.g. `*.env` if used).
    *   In README or setup docs, state that these files contain secrets and must not be committed; optionally add a pre-commit note or example `.gitignore` snippet for users who clone the repo.
*   **Progress:**
    *   `.gitignore` and README updated.

---

## 6. Safe Use of Temporary Files

*   **Status:** Done
*   **Finding:** Scripts use fixed temporary filenames (e.g. `/tmp/proven_block.tmp`, `/tmp/sync_proof.tmp`, `/tmp/peer_id.tmp`, `/tmp/gov_payloads.tmp`) instead of `mktemp`, creating a risk of race conditions or overwriting by another process/user.
*   **Action:**
    *   Replace fixed `/tmp/...` paths with `mktemp` (or `mktemp -t aztec.XXXXXX`) for all temporary files used by the scripts. Ensure temp files are removed after use (e.g. in a trap or explicitly before exit).
    *   Audit scripts in `scripts/` and legacy scripts in `other/` for any remaining use of predictable temp filenames.
*   **Progress:**
    *   Refactored to use `mktemp` in `check_proven_block.sh`, `find_peer_id.sh`, `find_governance_proposer_payload.sh`, and `start.sh`.

---

## 7. Telegram Token in URL (Low Priority)

*   **Status:** Done
*   **Finding:** Telegram API is called with the bot token in the URL path. Tokens in URLs can appear in logs, Referer headers, or proxy logs.
*   **Action:**
    *   Prefer passing the token in request headers (e.g. a custom header or body) if the Telegram API supports it; if not, document that token-in-URL is a limitation and recommend running the script in an environment where URL logging is minimized.
    *   Ensure no script logs the full Telegram API URL (with token); strip or redact token from any debug or error messages.
*   **Progress:**
    *   Telegram Bot API uses the token in the URL path for outbound calls (getMe, sendMessage, etc.). The `X-Telegram-Bot-Api-Secret-Token` header is only for verifying *incoming* webhook requests, not for authenticating outbound API calls. So token-in-URL cannot be avoided for our use case.
    *   Reviewed logging: no script echoes the Telegram token or the full API URL. Documented in this plan.

---

## 8. Complexity

*   **Status:** Done
*   **Finding:** The main script is very large and complex.
*   **Action:**
    *   Break down the `aztec-logs.sh` script into smaller, more manageable scripts with specific functionalities. This will improve readability, maintainability, and auditability.
*   **Progress:**
    *   The `aztec-logs.sh` script has been refactored into smaller, more manageable scripts. The new scripts are located in the `scripts` directory.

---

## 9. Hardcoded Addresses

*   **Status:** Done
*   **Finding:** The script contains hardcoded contract addresses.
*   **Action:**
    *   Move all hardcoded contract addresses to a configuration file (e.g., `config.json`). This will make it easier to update the addresses if they change.
*   **Progress:**
    *   Created a `config.json` file to store all hardcoded addresses.
    *   Modified the script to load addresses from the `config.json` file.

---

## Summary and Priority

| # | Topic | Priority | Status |
|---|--------|----------|--------|
| 1 | Remote code execution | High | In Progress (checksums done) |
| 2 | `sudo` usage | Medium | In Progress |
| 3 | Private key and secrets handling | High | In Progress (permissions, no token in agent) |
| 4 | User input validation / injection | Medium | Done |
| 5 | .gitignore for sensitive files | Medium | Done |
| 6 | Safe temp files (mktemp) | Low | Done |
| 7 | Telegram token in URL | Low | Done (documented) |
| 8 | Complexity | — | Done |
| 9 | Hardcoded addresses | — | Done |

Recommended order for implementation: **5** (.gitignore) and **4** (input validation) are quick wins; then **3** (permissions and warnings), **6** (mktemp), and **1** (checksums/verification); finally **7** (Telegram URL) as low priority. Implementation completed 2026-02-09 for items 4, 5, 6, 7 and progress on 1 and 3.
