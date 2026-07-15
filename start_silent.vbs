' Launches start_server.bat silently (no console window).
' Resolves the path relative to this script, so it works from any location.
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & scriptDir & "\start_server.bat" & chr(34), 0
Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
WshShell.Run chr(34) & ScriptDir & "\start_server.bat" & chr(34), 0
Set FSO = Nothing
Set WshShell = Nothing
