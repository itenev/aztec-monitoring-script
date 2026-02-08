# Security Improvement Plan

This document outlines a plan to address the security findings identified in the security audit report dated 2026-02-07.

## 1. Remote Code Execution

*   **Status:** In Progress
*   **Finding:** The script uses `curl | bash` to install Foundry and Docker.
*   **Action:**
    *   Remove the automatic installation of Foundry and Docker.
    *   Provide clear instructions for users to install these dependencies manually using their system's package manager.
    *   For any scripts that must be downloaded, provide checksums and instructions for users to verify the integrity of the script before execution.
*   **Progress:**
    *   Removed the automatic installation of Foundry and Docker from the `check_dependencies` and `install_aztec_node_main` functions. The script will now instruct the user to install these dependencies manually if they are not found.

## 2. `sudo` Usage

*   **Status:** In Progress
*   **Finding:** The script uses `sudo` to install dependencies.
*   **Action:**
    *   Minimize the use of `sudo` by identifying dependencies that can be installed without root privileges.
    *   For any remaining `sudo` commands, provide a clear explanation to the user about why `sudo` is required and what commands will be executed.
*   **Progress:**
    *   Removed `sudo` from `docker logs`, `rm`, and `ss` commands.
    *   Added a confirmation prompt before using `sudo` for package installation and firewall configuration.

## 3. Private Key Handling

*   **Status:** In Progress
*   **Finding:** The script handles private keys in an insecure manner.
*   **Action:**
    *   Add a prominent warning to the user about the risks of handling private keys in the script.
    *   Investigate the possibility of integrating with a hardware security module (HSM) or a key management service (KMS) for more secure key management.
*   **Progress:**
    *   Added a warning to the `generate_bls_keys` function to inform users about the risks of handling private keys.

## 4. User Input Validation

*   **Finding:** The script does not always validate user input properly.
*   **Action:**
    *   Review all user input fields and add appropriate validation to ensure that the input is in the correct format and within the expected range.

## 5. Complexity

*   **Status:** Done
*   **Finding:** The main script is very large and complex.
*   **Action:**
    *   Break down the `aztec-logs.sh` script into smaller, more manageable scripts with specific functionalities. This will improve readability, maintainability, and auditability.
*   **Progress:**
    *   The `aztec-logs.sh` script has been refactored into smaller, more manageable scripts. The new scripts are located in the `scripts` directory.

## 6. Hardcoded Addresses

*   **Status:** Done
*   **Finding:** The script contains hardcoded contract addresses.
*   **Action:**
    *   Move all hardcoded contract addresses to a configuration file (e.g., `config.json`). This will make it easier to update the addresses if they change.
*   **Progress:**
    *   Created a `config.json` file to store all hardcoded addresses.
    *   Modified the `aztec-logs.sh` script to load the addresses from the `config.json` file.
