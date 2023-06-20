# secure-macos-scripts
This repository contains a collection of Z shell scripts for securing macOS.

## Initial Setup
1. Download the [latest package](https://github.com/wdouglascampbell/secure-macos-scripts/releases/latest). *Note: Download the tar.gz source code.*
1. Insert a USB drive.
1. Copy and extract the downloaded source code archive to the USB drive.

## 1-ensure-secure-passwords-and-active-encryption.command

This script ensures that passwords for all active accounts meet our secure requirements and that FileVault encryption is active. The script provides two security levels: **HIGH** and **EXTREME**.

The **HIGH** level of security ensures that each active account is using a 16 character password that contains a combination of upper and lower case characters, digits and special characters and that each account has access to unlock the FileVault encryption.

The **EXTREME** level of security ensures that encryption is active and that only a special "Pre-Boot Authentication", aka preboot, account is able to unlock the FileVault encryption.  It also ensures that the password for this special preboot account is at least 30 characters long and that the passwords for all other active accounts are at least 8 characters long.

### Running The Script

1. Double-click the script **1-ensure-secure-passwords-and-active-encryption.command**.
2. If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
3. Select the security level, **HIGH** or **EXTREME**, that you want to use based on the security at your location.
4. Follow the displayed instructions and respond to the questions and password requests.
5. Once the script has finished, you will be prompted to reboot the computer. You are **strongly** encouraged to reboot the computer and go through the new sign in process while these changes are fresh in your mind.
