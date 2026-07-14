#Requires AutoHotkey v2.0

; Global variables
global targetWindowId := ""
global targetWindowTitle := ""
global changeTargetWindowHotkey := ""
global copyPasteHotkey := ""
global copyCiteFromResearchTrackerHotkey := ""
global helpHotkey := ""
global copyPasteNoLineBreaksHotkey := ""
global copyPasteNoLineBreaksNoReturnHotkey := ""  ; New hotkey variable
global copyPasteCurrentHeaderHotkey := ""  ; Hotkey for copy-paste current header
global copyURLAndPasteHotkey := ""  ; Hotkey for copying URL and pasting to target window
global applyF10 := true
global lastPasteWasProcessed := false

; Define default hotkeys
defaultChangeTargetWindowHotkey := "^+w"
defaultCopyPasteHotkey := "^+c"
defaultCopyCiteFromResearchTrackerHotkey := "^+z"
defaultHelpHotkey := "^+h"
defaultCopyPasteNoLineBreaksHotkey := "^+v"
defaultCopyPasteNoLineBreaksNoReturnHotkey := "^+b"
defaultCopyPasteCurrentHeaderHotkey := "^+s"
defaultCopyURLAndPasteHotkey := "^+d"

; Load or create hotkeys from INI file
iniPath := A_ScriptDir . "\Hotkeys.ini"
if (!FileExist(iniPath)) {
    ; Create the INI file with default values
    try {
        FileAppend "
        (
        [Hotkeys]
        SelectTargetWindow=^+w
        PerformCopyPaste=^+c
        CopyCiteFromResearchTracker=^+z
        ShowHelp=^+h
        PerformCopyPasteNoLineBreaks=^+v
        PerformCopyPasteNoLineBreaksNoReturn=^+b
        PerformCopyPasteCurrentHeader=^+s
        CopyURLAndPaste=^+d

        [Settings]
        ApplyF10ToProcessedText=1
        )", iniPath
        MsgBox("Hotkeys.ini created with default settings.")
    } catch as err {
        MsgBox("Failed to create Hotkeys.ini. Using default settings. Error: " . err.Message)
    }
}

; Now read the hotkeys and settings
changeTargetWindowHotkey := IniRead(iniPath, "Hotkeys", "SelectTargetWindow", defaultChangeTargetWindowHotkey)
copyPasteHotkey := IniRead(iniPath, "Hotkeys", "PerformCopyPaste", defaultCopyPasteHotkey)
copyCiteFromResearchTrackerHotkey := IniRead(iniPath, "Hotkeys", "CopyCiteFromResearchTracker", defaultCopyCiteFromResearchTrackerHotkey)
helpHotkey := IniRead(iniPath, "Hotkeys", "ShowHelp", defaultHelpHotkey)
copyPasteNoLineBreaksHotkey := IniRead(iniPath, "Hotkeys", "PerformCopyPasteNoLineBreaks", defaultCopyPasteNoLineBreaksHotkey)
copyPasteNoLineBreaksNoReturnHotkey := IniRead(iniPath, "Hotkeys", "PerformCopyPasteNoLineBreaksNoReturn", defaultCopyPasteNoLineBreaksNoReturnHotkey)  ; New hotkey
copyPasteCurrentHeaderHotkey := IniRead(iniPath, "Hotkeys", "PerformCopyPasteCurrentHeader", defaultCopyPasteCurrentHeaderHotkey)
copyURLAndPasteHotkey := IniRead(iniPath, "Hotkeys", "CopyURLAndPaste", defaultCopyURLAndPasteHotkey)
applyF10 := IniRead(iniPath, "Settings", "ApplyF10ToProcessedText", "1") = "1"

; Dynamic hotkey assignments
Hotkey changeTargetWindowHotkey, (*) => SelectTargetWindow()
Hotkey copyPasteHotkey, (*) => PerformCopyPaste()
Hotkey copyCiteFromResearchTrackerHotkey, (*) => CopyCiteFromResearchTracker()
Hotkey helpHotkey, (*) => ShowHelp()
Hotkey copyPasteNoLineBreaksHotkey, (*) => PerformCopyPasteNoLineBreaks()
Hotkey copyPasteNoLineBreaksNoReturnHotkey, (*) => PerformCopyPasteNoLineBreaksNoReturn()  ; New hotkey assignment
Hotkey copyPasteCurrentHeaderHotkey, (*) => PerformCopyPasteCurrentHeader()
Hotkey copyURLAndPasteHotkey, (*) => CopyURLAndPaste()

SelectTargetWindow() {
    ; Create a GUI to select the target window
    SelectWindow := Gui()
    SelectWindow.Opt("+AlwaysOnTop")
    SelectWindow.SetFont("s10", "Arial")
    SelectWindow.Add("Text", "w300", "Select the target window:")
    LB := SelectWindow.Add("ListBox", "w300 h200 vSelectedWindow")
    
    ; Populate the ListBox with open windows
    windowList := WinGetList(,, "Program Manager")
    for window in windowList {
        title := WinGetTitle(window)
        if (title != "") {
            LB.Add([title])
        }
    }
    
    SelectWindow.Add("Button", "w100 Default", "OK").OnEvent("Click", ProcessSelection)
    SelectWindow.OnEvent("Escape", (*) => SelectWindow.Destroy())
    SelectWindow.Show()

    ProcessSelection(*)
    {
        global targetWindowId, targetWindowTitle
        SelectedWindow := LB.Text
        if (SelectedWindow != "") {
            targetWindowTitle := SelectedWindow
            targetWindowId := WinGetID(targetWindowTitle)
            SelectWindow.Destroy()
            MsgBox("Target window set to: " . targetWindowTitle)
        } else {
            MsgBox("No window selected. Please try again.")
        }
    }
}

PerformCopyPaste() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey, applyF10, lastPasteWasProcessed
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID and title
    activeID := WinGetID("A")
    activeTitle := WinGetTitle("A")
    isZotero := InStr(activeTitle, "Zotero")  ; Determine if Zotero is the active window

    ; Check if the current window's title contains "Zotero"
    if isZotero {
        ; Clear clipboard before performing action
        A_Clipboard := ""
        Sleep(100)  ; Small delay to ensure the clipboard is cleared

        ; Perform the custom action for Zotero - Ctrl + 0 to copy
        Send("^0")

        ; Wait and retry for the clipboard to be updated
        if (!WaitForClipboardUpdate(3)) {  ; Try waiting for clipboard for 3 seconds
            MsgBox("Failed to copy from Zotero. Please try again.")
            return
        }
    } else {
        ; Standard copy-paste workflow
        A_Clipboard := ""  ; Clear the clipboard
        Send("^c")  ; Copy the current selection
        
        ; Wait for the clipboard to contain data
        if (!ClipWait(2)) {
            MsgBox("Failed to copy text to clipboard. Please try again.")
            return
        }
    }

    ; Get the clipboard content
    clipContent := A_Clipboard

    ; Process the text with retry mechanism
    processedText := ProcessTextWithRetry(clipContent)

    ; Reset the lastPasteWasProcessed flag
    lastPasteWasProcessed := false

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Press Return key
        Send("{Enter}")
        
        ; Wait a moment for any potential dialog to open
        Sleep(200)  ; Short delay for slower actions
        
        ; Paste the processed text
        A_Clipboard := processedText
        Send("^v")
        
        ; Wait for the paste operation to complete
        Sleep(200)  ; Short delay for slower actions
        
        ; Check if the text was processed (changed)
        if (processedText != clipContent) {
            lastPasteWasProcessed := true
            
            if (applyF10) {
                ; Select the pasted text
                Send "+{Home}"
                
                ; Apply F10 style
                Send "{F10}"
                Sleep(100)  ; Short delay for F10 to apply
                
                ; Move to end of line and add a newline
                Send "{End}{Enter}"
                
                ; Select the new empty line
                Send "+{End}"
                
                ; Apply F12 to clear formatting
                Send "{F12}"
                Sleep(100)  ; Short delay for F12 to apply
                
                ; Move cursor to the start of the new line
                Send "{Home}"
            }
        }
        
        ; If the active window wasn't Zotero, switch back to the original window
        if !isZotero {
            WinActivate("ahk_id " . activeID)
        }
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

CopyCiteFromResearchTracker() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey, applyF10, lastPasteWasProcessed
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID and title
    activeID := WinGetID("A")
    activeTitle := WinGetTitle("A")
    isZotero := InStr(activeTitle, "Zotero")  ; Determine if Zotero is the active window

    ; Check if the current window's title contains "Zotero"
    if isZotero {
        ; Clear clipboard before performing action
        A_Clipboard := ""
        Sleep(100)  ; Small delay to ensure the clipboard is cleared

        ; Perform the custom action for Zotero - Ctrl + 0 to copy
        Send("^0")

        ; Wait and retry for the clipboard to be updated
        if (!WaitForClipboardUpdate(3)) {  ; Try waiting for clipboard for 3 seconds
            MsgBox("Failed to copy from Zotero. Please try again.")
            return
        }
    } else {
        ; Standard copy-paste workflow with Ctrl+Q instead of Ctrl+C
        A_Clipboard := ""  ; Clear the clipboard
        Send("^q")  ; Copy the current selection with Ctrl+Q
        
        ; Wait for the clipboard to contain data
        if (!ClipWait(2)) {
            MsgBox("Failed to copy text to clipboard. Please try again.")
            return
        }
    }

    ; Get the clipboard content
    clipContent := A_Clipboard

    ; Process the text with retry mechanism
    processedText := ProcessTextWithRetry(clipContent)

    ; Reset the lastPasteWasProcessed flag
    lastPasteWasProcessed := false

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Press Return key
        Send("{Enter}")
        
        ; Wait a moment for any potential dialog to open
        Sleep(200)  ; Short delay for slower actions
        
        ; Paste the processed text
        A_Clipboard := processedText
        Send("^v")
        
        ; Wait for the paste operation to complete
        Sleep(200)  ; Short delay for slower actions
        
        ; Check if the text was processed (changed)
        if (processedText != clipContent) {
            lastPasteWasProcessed := true
            
            if (applyF10) {
                ; Select the pasted text
                Send "+{Home}"
                
                ; Apply F10 style
                Send "{F10}"
                Sleep(100)  ; Short delay for F10 to apply
                
                ; Move to end of line and add a newline
                Send "{End}{Enter}"
                
                ; Select the new empty line
                Send "+{End}"
                
                ; Apply F12 to clear formatting
                Send "{F12}"
                Sleep(100)  ; Short delay for F12 to apply
                
                ; Move cursor to the start of the new line
                Send "{Home}"
            }
        }
        
        ; If the active window wasn't Zotero, switch back to the original window
        if !isZotero {
            WinActivate("ahk_id " . activeID)
        }
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

ShowHelp() {
    helpText := "Fast Debate Paste Help`n`n"
    
    helpText .= "Current Hotkeys:`n"
    helpText .= "- Select Target Window: " . changeTargetWindowHotkey . "`n"
    helpText .= "- Perform Copy-Paste: " . copyPasteHotkey . "`n"
    helpText .= "- Perform Copy-Paste (No Line Breaks): " . copyPasteNoLineBreaksHotkey . "`n"
    helpText .= "- Perform Copy-Paste (No Line Breaks, No Return): " . copyPasteNoLineBreaksNoReturnHotkey . "`n"  ; New hotkey
    helpText .= "- Copy-Paste Current Header: " . copyPasteCurrentHeaderHotkey . "`n"
    helpText .= "- Copy Cite From Research Tracker: " . copyCiteFromResearchTrackerHotkey . "`n"
    helpText .= "- Copy URL and Paste: " . copyURLAndPasteHotkey . "`n"
    helpText .= "- Show This Help: " . helpHotkey . "`n`n"
    
    helpText .= "How to Rebind Hotkeys:`n"
    helpText .= "1. Open the Hotkeys.ini file in the same directory as this script.`n"
    helpText .= "2. Edit the values in the [Hotkeys] section.`n"
    helpText .= "3. Use AutoHotkey syntax for hotkeys:`n"
    helpText .= "   ^ = Ctrl, + = Shift, ! = Alt, # = Win`n"
    helpText .= "   Examples: ^c (Ctrl+C), ^+a (Ctrl+Shift+A), !f (Alt+F)`n`n"
    
    helpText .= "Current Settings:`n"
    helpText .= "- Apply F10 to Processed Text: " . (applyF10 ? "Enabled" : "Disabled") . "`n`n"
    
    helpText .= "How to Change Settings:`n"
    helpText .= "1. Open the Hotkeys.ini file.`n"
    helpText .= "2. Edit the values in the [Settings] section.`n"
    helpText .= "3. Set ApplyF10ToProcessedText=1 to enable, or 0 to disable.`n`n"
    
    helpText .= "Function Explanations:`n"
    helpText .= "- Select Target Window: Choose the window where text will be pasted.`n"
    helpText .= "- Perform Copy-Paste: Copy text (with Zotero support), process it, and paste to the target window.`n"
    helpText .= "- Perform Copy-Paste (No Line Breaks): Same as above, but removes all line breaks.`n"
    helpText .= "- Perform Copy-Paste (No Line Breaks, No Return): Same as above, but doesn't press Enter before pasting.`n"  ; New function explanation
    helpText .= "- Copy-Paste Current Header: Selects current heading and content in Word (Ctrl+Shift+O), then pastes to target window.`n"
    helpText .= "- Copy Cite From Research Tracker: Copies the cite created by the Research Tracker extension (using Ctrl+Q) and pastes it to the target window.`n"
    helpText .= "- Copy URL and Paste: Copies the current URL in Chrome (F6 to select), pastes to target window using F2, then closes Chrome tab.`n"
    helpText .= "- Show Help: Display this help dialogue.`n`n"
    
    MsgBox(helpText, "Fast Debate Paste Help")
}

WaitForClipboardUpdate(maxWaitSeconds) {
    ; Wait until the clipboard has some content or until the maximum time has passed
    maxWaitMilliseconds := maxWaitSeconds * 1000
    start := A_TickCount
    while ((A_TickCount - start) < maxWaitMilliseconds) {
        if (A_Clipboard != "") {
            return true  ; Clipboard has been updated
        }
        Sleep(100)  ; Check every 100ms
    }
    return false  ; Clipboard update failed
}

ProcessTextWithRetry(text, maxAttempts := 3) {
    loop maxAttempts {
        processedText := ProcessText(text)
        if (processedText != text) {
            return processedText  ; Regex matched and text was processed
        }
        Sleep(50)  ; Short delay before retry
    }
    return text  ; Return original text if processing consistently fails
}

ProcessText(text) {
    ; First, check if the text is just a number (including decimal points and multiple periods)
    if (RegExMatch(text, "^\d+([.-]\d+)*$")) {
        return "[EQUATION " . text . " OMITTED]"
    }
    ; If not just a number, check for the original pattern
    else if (RegExMatch(text, "i)^(\w+\.?)\s+([\d.-]+(?:[.-][\d.-]+)*)$", &match)) {
        return "[" . StrUpper(match[1] . " " . match[2] . " OMITTED") . "]"
    }
    ; If neither pattern matches, return the original text
    return text
}

PerformCopyPasteNoLineBreaks() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey, applyF10, lastPasteWasProcessed
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID and title
    activeID := WinGetID("A")
    activeTitle := WinGetTitle("A")
    isZotero := InStr(activeTitle, "Zotero")  ; Determine if Zotero is the active window

    ; Check if the current window's title contains "Zotero"
    if isZotero {
        ; Clear clipboard before performing action
        A_Clipboard := ""
        Sleep(100)
		
		; Perform the custom action for Zotero - Ctrl + 0 to copy
        Send("^0")

        ; Wait and retry for the clipboard to be updated
        if (!WaitForClipboardUpdate(3)) {  ; Try waiting for clipboard for 3 seconds
            MsgBox("Failed to copy from Zotero. Please try again.")
            return
        }
    } else {
        ; Standard copy-paste workflow
        A_Clipboard := ""  ; Clear the clipboard
        Send("^c")  ; Copy the current selection
        
        ; Wait for the clipboard to contain data
        if (!ClipWait(2)) {
            MsgBox("Failed to copy text to clipboard. Please try again.")
            return
        }
    }

    ; Get the clipboard content
    clipContent := A_Clipboard

    ; Process the text with retry mechanism
    processedText := ProcessTextWithRetry(clipContent)

    ; Check if the text was processed by the regex
    wasProcessedByRegex := (processedText != clipContent)

    ; Remove line breaks, replacing with space if not adjacent to existing space
    processedText := RegExReplace(processedText, "(?<!\s)\R(?!\s)", " ")
    processedText := RegExReplace(processedText, "\R", "")

    ; Reset the lastPasteWasProcessed flag
    lastPasteWasProcessed := false

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Press Return key
        Send("{Enter}")
        
        ; Wait a moment for any potential dialog to open
        Sleep(200)  ; Short delay for slower actions
        
        ; Paste the processed text
        A_Clipboard := processedText
        Send("^v")
        
        ; Wait for the paste operation to complete
        Sleep(200)  ; Short delay for slower actions
        
        ; Check if the text was processed by the regex (not just line breaks removed)
        if (wasProcessedByRegex) {
            lastPasteWasProcessed := true
            
            if (applyF10) {
                ; Select the pasted text
                Send "+{Home}"
                
                ; Apply F10 style
                Send "{F10}"
                Sleep(100)  ; Short delay for F10 to apply
                
                ; Move to end of line and add a newline
                Send "{End}{Enter}"
                
                ; Select the new empty line
                Send "+{End}"
                
                ; Apply F12 to clear formatting
                Send "{F12}"
                Sleep(100)  ; Short delay for F12 to apply
                
                ; Move cursor to the start of the new line
                Send "{Home}"
            }
        }
        
        ; If the active window wasn't Zotero, switch back to the original window
        if !isZotero {
            WinActivate("ahk_id " . activeID)
        }
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

PerformCopyPasteNoLineBreaksNoReturn() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey, applyF10, lastPasteWasProcessed
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID and title
    activeID := WinGetID("A")
    activeTitle := WinGetTitle("A")
    isZotero := InStr(activeTitle, "Zotero")  ; Determine if Zotero is the active window

    ; Check if the current window's title contains "Zotero"
    if isZotero {
        ; Clear clipboard before performing action
        A_Clipboard := ""
        Sleep(100)  ; Small delay to ensure the clipboard is cleared

        ; Perform the custom action for Zotero - Ctrl + 0 to copy
        Send("^0")

        ; Wait and retry for the clipboard to be updated
        if (!WaitForClipboardUpdate(3)) {  ; Try waiting for clipboard for 3 seconds
            MsgBox("Failed to copy from Zotero. Please try again.")
            return
        }
    } else {
        ; Standard copy-paste workflow
        A_Clipboard := ""  ; Clear the clipboard
        Send("^c")  ; Copy the current selection
        
        ; Wait for the clipboard to contain data
        if (!ClipWait(2)) {
            MsgBox("Failed to copy text to clipboard. Please try again.")
            return
        }
    }

    ; Get the clipboard content
    clipContent := A_Clipboard

    ; Process the text with retry mechanism
    processedText := ProcessTextWithRetry(clipContent)

    ; Check if the text was processed by the regex
    wasProcessedByRegex := (processedText != clipContent)

    ; Remove line breaks, replacing with space if not adjacent to existing space
    processedText := RegExReplace(processedText, "(?<!\s)\R(?!\s)", " ")
    processedText := RegExReplace(processedText, "\R", "")

    ; Add a space at the beginning of the processed text
    processedText := " " . processedText

    ; Reset the lastPasteWasProcessed flag
    lastPasteWasProcessed := false

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Paste the processed text
        A_Clipboard := processedText
        Send("^v")
        
        ; Wait for the paste operation to complete
        Sleep(200)  ; Short delay for slower actions
        
        ; Check if the text was processed by the regex (not just line breaks removed)
        if (wasProcessedByRegex) {
            lastPasteWasProcessed := true
            
            if (applyF10) {
                ; Select the pasted text
                Send "+{Home}"
                
                ; Apply F10 style
                Send "{F10}"
                Sleep(100)  ; Short delay for F10 to apply
                
                ; Move to end of line
                Send "{End}"
            }
        }
        
        ; If the active window wasn't Zotero, switch back to the original window
        if !isZotero {
            WinActivate("ahk_id " . activeID)
        }
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

PerformCopyPasteCurrentHeader() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID
    activeID := WinGetID("A")

    ; First select heading and content
    Send("^+o")  ; Press Ctrl+Shift+O to select heading and content
    
    ; Wait a moment for the selection to complete
    Sleep(200)

    ; Standard copy
    A_Clipboard := ""  ; Clear the clipboard
    Send("^c")  ; Copy the current selection
    
    ; Wait for the clipboard to contain data
    if (!ClipWait(2)) {
        MsgBox("Failed to copy text to clipboard. Please try again.")
        return
    }

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Press Return key
        Send("{Enter}")
        
        ; Wait a moment for any potential dialog to open
        Sleep(200)  ; Short delay for slower actions
        
        ; Paste the clipboard content
        Send("^v")
        
        ; Wait for the paste operation to complete
        Sleep(200)  ; Short delay for slower actions
        
        ; Switch back to the original window
        WinActivate("ahk_id " . activeID)
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

CopyURLAndPaste() {
    global targetWindowId, targetWindowTitle, changeTargetWindowHotkey
    
    if (targetWindowId == "") {
        MsgBox("Please select a target window first using " . changeTargetWindowHotkey)
        return
    }

    ; Store the current window's ID
    activeID := WinGetID("A")
    activeTitle := WinGetTitle("A")
    
    ; Check if Chrome is the active window
    if (!InStr(activeTitle, "Chrome")) {
        MsgBox("This function only works when Chrome is the active window.")
        return
    }

    ; Select URL bar with F6
    Send("{F6}")
    Sleep(100)  ; Small delay to ensure URL bar is selected
    
    ; Copy URL
    A_Clipboard := ""  ; Clear the clipboard
    Send("^c")  ; Copy the current selection
    
    ; Wait for the clipboard to contain data
    if (!ClipWait(2)) {
        MsgBox("Failed to copy URL to clipboard. Please try again.")
        return
    }

    ; Store the URL
    copiedURL := A_Clipboard

    ; Attempt to activate the target window
    if WinExist("ahk_id " . targetWindowId) {
        WinActivate("ahk_id " . targetWindowId)
        
        ; Wait for the window to activate
        WinWaitActive("ahk_id " . targetWindowId, , 2)
        
        ; Press Enter to create a line break
        Send("{Enter}")
        
        ; Wait a moment
        Sleep(100)
        
        ; Set clipboard content to the URL
        A_Clipboard := copiedURL
        
        ; Use F2 for paste without formatting
        Send("{F2}")
        
        ; Wait for the paste operation to complete
        Sleep(200)
        
        ; Switch back to Chrome
        WinActivate("ahk_id " . activeID)
        
        ; Wait for Chrome to activate
        WinWaitActive("ahk_id " . activeID, , 2)
        
        ; Close the current tab
        Send("^w")
    } else {
        MsgBox("The target window is no longer available. Please select a new target window using " . changeTargetWindowHotkey)
        targetWindowId := ""
        targetWindowTitle := ""
    }
}

; Initial prompt to select a target window
SelectTargetWindow()