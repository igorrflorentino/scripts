-- ============================================================================
-- MediaFullscreen.applescript
-- Universal Fullscreen Toggle for macOS
-- Detects PLAYING media and toggles fullscreen on it
-- Supports: Chrome, Safari, Firefox, Arc, Brave, Spotify, Apple Music, 
--           VLC, QuickTime, IINA
-- ============================================================================

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Debug logging (set to true to enable)
property debugEnabled : false

on logDebug(message)
    if debugEnabled then
        -- Save logs to ~/Library/Logs/ (standard macOS location)
        set logDir to (POSIX path of (path to library folder from user domain)) & "Logs"
        do shell script "mkdir -p " & quoted form of logDir
        set logPath to logDir & "/mediafullscreen_debug.log"
        do shell script "echo '[MediaFullscreen] " & message & "' >> " & quoted form of logPath
    end if
end logDebug

on getProcessNames()
    tell application "System Events" to return name of processes
end getProcessNames

on appIsRunning(appName)
    tell application "System Events"
        return (name of processes) contains appName
    end tell
end appIsRunning

-- Check if a process name starts with a given prefix (for Chrome variants)
on processStartsWith(procNames, prefix)
    repeat with p in procNames
        if p starts with prefix then return true
    end repeat
    return false
end processStartsWith



-- ============================================================================
-- CHROMIUM-BASED BROWSER CONTROLS
-- ============================================================================

on chromium_has_playing(browserName, jsCheckPlaying)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            tell t to set res to execute javascript jsCheckPlaying
                            if res is true or (res as string) is "true" then return true
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error errMsg
        my logDebug("Chromium check error (" & browserName & "): " & errMsg)
        return false
    end try
    return false
end chromium_has_playing

on chromium_find_and_fullscreen(browserName, jsFindAndFullscreen, jsCheckPlaying)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            -- First check if this is the interesting tab (playing or fullscreen)
                            tell t to set isTarget to execute javascript jsCheckPlaying
                            
                            if isTarget is true or (isTarget as string) is "true" then
                                my logDebug("Found target tab. Activating before toggle...")
                                
                                -- 1. Activate the window and tab FIRST
                                tell application browserName to activate
                                set w's active tab index to tabIndex
                                set index of w to 1 -- Bring window to front
                                
                                -- 2. Short delay to ensure browser registers focus
                                delay 0.3
                                
                                -- 3. Try keystroke 'f' (most reliable), fallback to JS if permissions fail
                                try
                                    tell application "System Events"
                                        tell process browserName
                                            keystroke "f"
                                        end tell
                                    end tell
                                    my logDebug("Sent 'f' keystroke to " & browserName)
                                    return true
                                on error keyErr
                                    my logDebug("Keystroke failed (" & keyErr & "). Fallback to JS...")
                                    tell t to execute javascript jsFindAndFullscreen
                                    return true
                                end try
                            end if
                        on error jsErr
                            my logDebug("Execution error: " & jsErr)
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error errMsg
        my logDebug("Chromium fullscreen error (" & browserName & "): " & errMsg)
        return false
    end try
    return false
end chromium_find_and_fullscreen

-- ============================================================================
-- SAFARI CONTROLS
-- ============================================================================

on safari_has_playing(jsCheckPlaying)
    try
        tell application "Safari"
            if (count of windows) < 1 then return false
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        set res to do JavaScript jsCheckPlaying in tab j of w
                        if res is true or (res as string) is "true" then return true
                    end try
                end repeat
            end repeat
        end tell
    on error errMsg
        my logDebug("Safari check error: " & errMsg)
        return false
    end try
    return false
end safari_has_playing

on safari_find_and_fullscreen(jsFindAndFullscreen, jsCheckPlaying)
    try
        tell application "Safari"
            if (count of windows) < 1 then return false
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        -- First check if this is the interesting tab
                        set isTarget to do JavaScript jsCheckPlaying in tab j of w
                        
                        if isTarget is true or (isTarget as string) is "true" then
                            my logDebug("Found target Safari tab. Activating before toggle...")
                            
                            -- 1. Activate Safari and this tab FIRST
                            tell application "Safari" to activate
                            set w's current tab to tab j of w
                            set index of w to 1 -- Bring window to front
                            
                            -- 2. Delay to ensure focus
                            delay 0.5
                            
                            -- 3. Execute fullscreen toggle
                            set res to do JavaScript jsFindAndFullscreen in tab j of w
                            my logDebug("Safari toggle result: " & res)
                            return true
                        end if
                    end try
                end repeat
            end repeat
        end tell
    on error errMsg
        my logDebug("Safari fullscreen error: " & errMsg)
        return false
    end try
    return false
end safari_find_and_fullscreen

-- ============================================================================
-- FIREFOX FULLSCREEN (via GUI scripting)
-- ============================================================================

-- Note: Firefox has very limited AppleScript support, so we can't reliably
-- detect playing state via JavaScript. This is a best-effort approach.
on firefox_toggle_fullscreen()
    try
        if not my appIsRunning("Firefox") then return false
        
        tell application "Firefox" to activate
        -- Delay allows Firefox to become frontmost and focused
        delay 0.15
        
        tell application "System Events"
            tell process "Firefox"
                -- Send 'f' key to toggle fullscreen on video sites
                -- Note: This assumes user has a video focused/playing
                keystroke "f"
            end tell
        end tell
        return true
    on error errMsg
        my logDebug("Firefox fullscreen error: " & errMsg)
        return false
    end try
end firefox_toggle_fullscreen

-- ============================================================================
-- MAIN HANDLER
-- ============================================================================
on run {input, parameters}
    -- JavaScript to check if media is playing (not paused)
    -- Uses readyState >= 2 (HAVE_CURRENT_DATA, allows buffering media)
    set jsCheckPlaying to "(function() {
        // Priority 1: If already in fullscreen, we count this as 'active' (to allow exiting even if paused)
        if (document.fullscreenElement || 
            document.webkitFullscreenElement || 
            document.mozFullScreenElement || 
            document.msFullscreenElement) {
            return true;
        }

        // Priority 2: Look for playing media
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
            if (!media[i].paused && !media[i].ended && media[i].readyState >= 2) {
                return true;
            }
        }
        return false;
    })()"
	
    -- JavaScript to find playing media and toggle fullscreen
    set jsFindAndFullscreen to "(function() {
        // Priority 1: Exit fullscreen if active (regardless of media state)
        if (document.fullscreenElement || 
            document.webkitFullscreenElement || 
            document.mozFullScreenElement || 
            document.msFullscreenElement) {
            
            if (document.exitFullscreen) {
                document.exitFullscreen();
            } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
            } else if (document.mozCancelFullScreen) {
                document.mozCancelFullScreen();
            } else if (document.msExitFullscreen) {
                document.msExitFullscreen();
            }
            return true;
        }

        // Priority 2: Enter fullscreen for playing media
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
            if (!media[i].paused && !media[i].ended && media[i].readyState >= 2) {
                // Focus the element first to help with user activation requirements
                media[i].focus();
                
                if (media[i].requestFullscreen) {
                    media[i].requestFullscreen();
                } else if (media[i].webkitRequestFullscreen) {
                    media[i].webkitRequestFullscreen();
                } else if (media[i].mozRequestFullScreen) {
                    media[i].mozRequestFullScreen();
                } else if (media[i].msRequestFullscreen) {
                    media[i].msRequestFullscreen();
                } else if (media[i].webkitEnterFullscreen) {
                    media[i].webkitEnterFullscreen();
                }
                return true;
            }
        }
        return false;
    })()"
	
    -- Detect running processes
    set procNames to my getProcessNames()
    
    -- Check browser availability
    set chromeRunning to my processStartsWith(procNames, "Google Chrome")
    set braveRunning to my processStartsWith(procNames, "Brave")
    set arcRunning to (procNames contains "Arc")
    set edgeRunning to my processStartsWith(procNames, "Microsoft Edge")
    set safariRunning to (procNames contains "Safari")
    set firefoxRunning to (procNames contains "Firefox")
    
    set playingApp to ""
    set toggled to false
	

	
    -- Check browsers for playing media
    if not toggled and chromeRunning then
        if my chromium_has_playing("Google Chrome", jsCheckPlaying) then
            set playingApp to "Google Chrome"
            my logDebug("Toggling fullscreen for Google Chrome")
            set toggled to my chromium_find_and_fullscreen("Google Chrome", jsFindAndFullscreen, jsCheckPlaying)
            my logDebug("Chrome fullscreen result: " & toggled)
        end if
    end if
    
    if not toggled and braveRunning then
        if my chromium_has_playing("Brave Browser", jsCheckPlaying) then
            set playingApp to "Brave Browser"
            my logDebug("Toggling fullscreen for Brave Browser")
            set toggled to my chromium_find_and_fullscreen("Brave Browser", jsFindAndFullscreen, jsCheckPlaying)
        end if
    end if
    
    if not toggled and arcRunning then
        if my chromium_has_playing("Arc", jsCheckPlaying) then
            set playingApp to "Arc"
            my logDebug("Toggling fullscreen for Arc")
            set toggled to my chromium_find_and_fullscreen("Arc", jsFindAndFullscreen, jsCheckPlaying)
        end if
    end if
    
    if not toggled and edgeRunning then
        if my chromium_has_playing("Microsoft Edge", jsCheckPlaying) then
            set playingApp to "Microsoft Edge"
            my logDebug("Toggling fullscreen for Microsoft Edge")
            set toggled to my chromium_find_and_fullscreen("Microsoft Edge", jsFindAndFullscreen, jsCheckPlaying)
        end if
    end if
    
    if not toggled and safariRunning then
        if my safari_has_playing(jsCheckPlaying) then
            set playingApp to "Safari"
            my logDebug("Toggling fullscreen for Safari")
            set toggled to my safari_find_and_fullscreen(jsFindAndFullscreen, jsCheckPlaying)
        end if
    end if
    
    -- Show notification based on result
    if toggled then
        display notification "Fullscreen toggled in browser" with title "Media Fullscreen" subtitle playingApp
    else
        my logDebug("No playing media found")
        display notification "No PLAYING media found" with title "Media Fullscreen"
    end if
    
    return input
end run
