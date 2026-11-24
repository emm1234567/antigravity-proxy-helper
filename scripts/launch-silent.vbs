' Silent wrapper to launch launch.ps1 without flashing a console window.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launchScript = fso.BuildPath(scriptDir, "launch.ps1")

extraArgs = ""
For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    If InStr(arg, " ") > 0 Then
        extraArgs = extraArgs & " """ & arg & """"
    Else
        extraArgs = extraArgs & " " & arg
    End If
Next

cmd = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & launchScript & """" & extraArgs
shell.Run cmd, 0, False
