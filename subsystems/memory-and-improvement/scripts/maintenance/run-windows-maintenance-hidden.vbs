Option Explicit

Dim shell, command, index, argument, exitCode
Set shell = CreateObject("WScript.Shell")

If WScript.Arguments.Count = 0 Then
    WScript.Quit 2
End If

command = QuoteArgument(WScript.Arguments(0))
For index = 1 To WScript.Arguments.Count - 1
    argument = WScript.Arguments(index)
    command = command & " " & QuoteArgument(argument)
Next

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

Function QuoteArgument(value)
    QuoteArgument = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
