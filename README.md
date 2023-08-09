# secure-macos-scripts
This repository contains a collection of Z shell scripts for securing macOS.

## Initial Setup
1. Download the [latest package](https://github.com/wdouglascampbell/secure-macos-scripts/releases/latest). *Note: Download the tar.gz source code.*
1. Use Finder to open your Downloads folder.
1. Double-click on the downloaded tar archive to extract its contents.
1. Hold down the ```control ⌃``` key and click on the extracted folder.
1. Select "New Terminal at Folder" from the menu.<br /><br />This will open Terminal at the location of the extracted folder and display a shell prompt %.

1. Enter the following command to remove the quarantine attribute.  This is an attribute that is added to all files downloaded from the Internet.<br /><br />```xattr -r -d com.apple.quarantine .```

1. [Optional] Move the extracted folder to your Desktop folder for convenient access.

## Security Scripts
### ```1-ensure-secure-passwords-and-active-encryption.command```

This script ensures that passwords for all active accounts meet our secure requirements and that FileVault encryption is active. The script provides two security levels: **HIGH** and **EXTREME**.

The **HIGH** level of security ensures that each active account on the computer is using a 16 character password that contains a combination of upper and lower case characters, digits and special characters and that each account has access to unlock the FileVault encryption.

The **EXTREME** level of security ensures that encryption is active and that only a special "Pre-Boot Authentication", aka preboot, account is able to unlock the FileVault encryption.  It also ensures that the password for this special preboot account is at least 30 characters long and that the passwords for all other active accounts on the computer are at least 8 characters long.

If FileVault has been enabled during the execution of the script you will be prompted to backup your recovery key.  **Do not skip this step!**

#### Running The Script

1. Double-click the script ```1-ensure-secure-passwords-and-active-encryption.command```.
1. If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1. Select the security level, **HIGH** or **EXTREME**, that you want to use based on the security at your location.
1. Follow the displayed instructions and respond to the questions and password requests.<br /><br />**Important: Do not skip backing up the recovery key file if prompted!**<br /><br />
1. Once the script has finished, you will be ask if you want to reboot the computer. You are **strongly** encouraged to reboot the computer and go through the new sign in process while these changes are fresh in your mind.

### ```2-configure-system-wide-security-settings.command```

This script ensures that system-wide settings are set to values appropriate for keeping the computer secure.  Most of the changes can be automated but some require manual intervention.

#### Running The Script

1. Double-click the script ```2-configure-system-wide-security-settings.command```.
1. If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1. Provide the requested passwords as prompted and follow the displayed instructions.
1. Press any key after reviewing the script results to close "Terminal".

### ```3-configure-user-specific-security-settings.command```

This script ensures that user-specific settings are set to values appropriate for keeping the computer secure.  Most of the changes can be automated but some require manual intervention.  **This script must be run for each account on the computer.**

#### Running The Script

1. Double-click the script ```3-configure-user-specific-security-settings.command```.
1. If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1. Provide the requested passwords as prompted and follow the displayed instructions.
1. Press any key after reviewing the script results to close "Terminal".

## Utility Scripts
### ```u1-change-preboot-password.command``` (use only for **EXTREME** configurations)

This script allows a user to change the password of the "Pre-Boot Authentication", aka preboot, account.

#### Running The Script

1.  Double-click the script ```u1-change-preboot-password.command```.
1.  If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1.  Provide the requested passwords as prompted.
1.  Once the script has finished.  Press Command + Q to close "Terminal".

### ```u2a-pre-update-prep.command``` (use only for **EXTREME** configurations)

This script is used to grant the current user privileges to unlock FileVault.  This is needed for performing system updates.  After system updates are completed the ```u2b-post-update-cleanup.command``` script should then be run to restore the system to a secure state.

Other tasks may also require this script to be run in order to work.  For example, enabling or disabling Find My Mac.  In general this script may need to be run if you are prompted for the current user password and after entering it the system fails to accept the authentication as if the password is incorrect.

This script also may need to be run if you are prompted for the preboot password when performing a task so that instead the computer will prompt you for the current user password for authorization.

#### Running The Script

1.  Double-click the script ```u2a-pre-update-prep.command```.
1.  If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1.  Provide the requested passwords as prompted.
1.  Once the script has opened System Settings to the Software Update pane, you may proceed to install available updates.
1.  If any of the updates require the system to restart, proceed with the restart and authenticate using your user account.
1.  After all updates and required system restarts have completed you need to run the ```u2b-post-update-cleanup.command``` script to restore the system to a secure state.

### ```u2b-post-update-cleanup.command``` (use only for **EXTREME** configurations)

This script is used to remove privileges for unlocking FileVault from the current user.  This is needed for restoring the system to a secure state after system updates have been performed.

1.  Double-click the script ```u2b-post-update-cleanup.command```.
1.  If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1.  Provide the requested passwords as prompted.
1.  Once the script has finished, the system will have been restored to a secure state.

### ```u3-remove-preboot-from-system.command``` (use only for **EXTREME** configurations)

This script is used to remove the Pre-Boot Authentication account from the computer.  If FileVault is enabled, it will remain enabled and grant all accounts for which a password has been provided with privileges to unlock FileVault.  Accounts for which a password has not been provided will not be granted privileges to unlocking FileVault and will be disabled from logging in.

1.  Double-click the script ```u3-remove-preboot-from-system.command```.
1.  If you are prompted with a dialog asking for permission to allow "Terminal" access to the files in the folder containing the script, click OK.
1.  Provide the requested passwords as prompted.
1.  Once the script has finished, the Pre-Boot Authentication account will no longer exist.
