# Sync-Windows-Roles-and-Features-Between-Servers-via-Powershell-Remoting

Connect to the source server, get its Roles and Features. Connect to the target server(s), install or remove Roles and Features so all the servers match the source.  All of this is accomplished via PS Remoting.  An optional XML output file can be created from the source server for later reuse as input. The target server pre-change configuration is saved to a text file in the users temp directory.  Specific features can be excluded during the install or removal process.  You can also run a simulation to see what changes would be made or recieve the difference between servers.

The intent of this script was to allow installation of Roles and Features on multiple servers simultaneously because Server Manager does not have this as an option.

This is a reposting from my Microsoft Technet Gallery.
