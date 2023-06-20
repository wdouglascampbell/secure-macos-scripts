# secure-macos-scripts
This repository contains a collection of Z shell scripts for securing macOS.

## Initial Setup
1. Download the latest package.
2. Insert a USB drive.
3. Extract the package to the USB drive.

## 1-ensure-secure-passwords-and-active-encryption.command

This script ensures that passwords for all active accounts meet our secure requirements and that FileVault encryption is active. The script provides two security levels: **HIGH** and **EXTREME**.

The **HIGH** level of security ensures that each active account is using a 16 character password that contains a combination of upper and lower case characters, digits and special characters and that each account has access to unlock the FileVault encryption.

The **EXTREME** level of security ensures that encryption is active and that only a special "Pre-Boot Authentication", aka preboot, account is able to unlock the FileVault encryption.  It also ensures that the password for this special preboot account is at least 30 characters long and that the passwords for all other active accounts are at least 8 characters long.

### Running The Script

1. Double-click "1-ensure-secure-passwords-and-active-encryption.command".
2. If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
3. Select the security level, **HIGH** or **EXTREME**, that you want to use based on the security at your location.
4. Follow the instructions presented and respond to questions and password requests.
5. When the script has completed its work you will be prompted to reboot the computer. You are strongly encouraged to reboot the computer and go through the new sign in process while these changes are fresh in your mind.
