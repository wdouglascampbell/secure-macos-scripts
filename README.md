# secure-macos-scripts
This repository contains a collection of Z shell scripts for securing macOS.

## Initial Setup
1. Download the [latest package](https://github.com/wdouglascampbell/secure-macos-scripts/releases/latest). *Note: Download the tar.gz source code.*
1. Use Finder to open your Downloads folder.
1. Double-click on the downloaded tar archive to extract its contents.
1. Press ```control ⌃``` and click on the extracted folder and select “New Terminal at Folder” from the menu.<br /><br />This will open Terminal at the location of the extracted folder.

1. At the shell prompt %, enter the following command to remove the quarantine attribute that is added to all files downloaded from the Internet.<br /><br />```xattr -r -d com.apple.quarantine .```

1. [Optional] Move the extracted folder to your Desktop folder for convenient access.

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

## u1-change-preboot-password.command

This script allows a user to change the password of the "Pre-Boot Authentication", aka preboot, account.

### Running The Script

1.  Double-click the script **u1-change-preboot-password.command**.
2.  If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
3.  Provide the requested passwords as prompted.
4.  Once the script has finished.  Press Command + Q to close "Terminal".

