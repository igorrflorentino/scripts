-- ============================================================================
-- MediaToggle.applescript
-- Universal Play/Pause for macOS
-- Supports: Chrome, Safari, Firefox, Arc, Brave, Spotify, Apple Music, 
--           VLC, QuickTime, IINA, and any app responding to media keys
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
        set logPath to logDir & "/mediatoggle_debug.log"
        do shell script "echo '[MediaToggle] " & message & "' >> " & quoted form of logPath
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

-- Get the frontmost (active) application name
on getFrontmostApp()
    try
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
            return frontApp
        end tell
    on error
        return ""
    end try
end getFrontmostApp

-- ============================================================================
-- MEDIA KEY SIMULATION (Ultimate Fallback)
-- Works for any app that responds to system media keys
-- ============================================================================

on simulateMediaPlayPause()
    try
        -- Method 1: Use NowPlaying command line tool if available
        try
            do shell script "/usr/bin/osascript -e 'tell application \"System Events\" to key code 16 using {command down, shift down}'"
        end try
        
        -- Method 2: Simulate F8 (Play/Pause) media key via CGEvent
        -- Key code 100 = F8 (Play/Pause on Apple keyboards)
        do shell script "osascript -e '
            use framework \"Cocoa\"
            use scripting additions
            
            set keyCode to 16
            
            -- Create and post key down event
            set keyDownEvent to current application\\'s CGEventCreateKeyboardEvent(missing value, keyCode, true)
            current application\\'s CGEventSetFlags(keyDownEvent, 0)
            current application\\'s CGEventPost(current application\\'s kCGSessionEventTap, keyDownEvent)
            
            -- Create and post key up event  
            set keyUpEvent to current application\\'s CGEventCreateKeyboardEvent(missing value, keyCode, false)
            current application\\'s CGEventSetFlags(keyUpEvent, 0)
            current application\\'s CGEventPost(current application\\'s kCGSessionEventTap, keyUpEvent)
        '"
    on error
        -- Fallback: simple key code simulation
        try
            tell application "System Events"
                key code 16
            end tell
        end try
    end try
end simulateMediaPlayPause

-- ============================================================================
-- NATIVE APP CONTROLS
-- Uses 'run script' for optional apps to avoid compile-time errors
-- ============================================================================

-- Spotify (dynamically executed to avoid compile errors if not installed)
on spotify_is_playing()
    try
        if not my appIsRunning("Spotify") then return false
        set scriptText to "tell application \"Spotify\" to return player state is playing"
        return run script scriptText
    on error
        return false
    end try
end spotify_is_playing

on spotify_pause()
    try
        if not my appIsRunning("Spotify") then return false
        run script "tell application \"Spotify\" to pause"
        return true
    on error
        return false
    end try
end spotify_pause

on spotify_play()
    try
        if not my appIsRunning("Spotify") then return false
        run script "tell application \"Spotify\" to play"
        return true
    on error
        return false
    end try
end spotify_play

-- Apple Music (built-in, safe to reference directly)
on music_is_playing()
    try
        if not my appIsRunning("Music") then return false
        tell application "Music"
            return player state is playing
        end tell
    on error
        return false
    end try
end music_is_playing

on music_pause()
    try
        if not my appIsRunning("Music") then return false
        tell application "Music" to pause
        return true
    on error
        return false
    end try
end music_pause

on music_play()
    try
        if not my appIsRunning("Music") then return false
        tell application "Music" to play
        return true
    on error
        return false
    end try
end music_play

-- VLC (dynamically executed to avoid compile errors if not installed)
on vlc_is_playing()
    try
        if not my appIsRunning("VLC") then return false
        return run script "tell application \"VLC\" to return playing"
    on error
        return false
    end try
end vlc_is_playing

on vlc_pause()
    try
        if not my appIsRunning("VLC") then return false
        run script "tell application \"VLC\" to if playing then pause"
        return true
    on error
        return false
    end try
end vlc_pause

on vlc_play()
    try
        if not my appIsRunning("VLC") then return false
        run script "tell application \"VLC\" to play"
        return true
    on error
        return false
    end try
end vlc_play

-- QuickTime Player (built-in, safe to reference directly)
on quicktime_is_playing()
    try
        if not my appIsRunning("QuickTime Player") then return false
        tell application "QuickTime Player"
            if (count of documents) > 0 then
                return playing of document 1
            end if
        end tell
    on error
        return false
    end try
    return false
end quicktime_is_playing

on quicktime_pause()
    try
        if not my appIsRunning("QuickTime Player") then return false
        tell application "QuickTime Player"
            if (count of documents) > 0 then
                pause document 1
                return true
            end if
        end tell
    on error
        return false
    end try
    return false
end quicktime_pause

on quicktime_play()
    try
        if not my appIsRunning("QuickTime Player") then return false
        tell application "QuickTime Player"
            if (count of documents) > 0 then
                play document 1
                return true
            end if
        end tell
    on error
        return false
    end try
    return false
end quicktime_play

-- IINA (popular macOS media player) - uses GUI scripting only
on iina_is_playing()
    try
        if not my appIsRunning("IINA") then return false
        tell application "System Events"
            tell process "IINA"
                -- Check if playback menu item says "Pause"
                set menuItem to menu item 1 of menu "Playback" of menu bar 1
                return (name of menuItem) starts with "Pause"
            end tell
        end tell
    on error
        return false
    end try
end iina_is_playing

on iina_pause()
    try
        if not my appIsRunning("IINA") then return false
        if not my iina_is_playing() then return true -- Already paused
        tell application "System Events"
            tell process "IINA"
                click menu item 1 of menu "Playback" of menu bar 1
            end tell
        end tell
        return true
    on error
        return false
    end try
end iina_pause

on iina_play()
    try
        if not my appIsRunning("IINA") then return false
        if my iina_is_playing() then return true -- Already playing
        tell application "System Events"
            tell process "IINA"
                click menu item 1 of menu "Playback" of menu bar 1
            end tell
        end tell
        return true
    on error
        return false
    end try
end iina_play

-- ============================================================================
-- CHROMIUM-BASED BROWSER CONTROLS (Chrome, Brave, Arc, Edge, etc.)
-- ============================================================================

on chromium_has_playing(browserName, jsCheckPlaying)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            tell t to set res to execute javascript jsCheckPlaying
                            if res is true or (res as string) is "true" then return true
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error
        return false
    end try
    return false
end chromium_has_playing

on chromium_find_pause_return(browserName, jsFindPauseReturn)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return ""
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            tell t to set res to execute javascript jsFindPauseReturn
                            if res is not missing value and res is not "" then
                                set resStr to res as string
                                if resStr is not "" and resStr is not "null" and resStr is not "undefined" then
                                    return resStr
                                end if
                            end if
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error
    end try
    return ""
end chromium_find_pause_return

on chromium_pause_all(browserName, jsPauseAll)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            tell t to execute javascript jsPauseAll
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    end try
end chromium_pause_all

on chromium_play_first(browserName, jsPlayFirst)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            tell t to set res to execute javascript jsPlayFirst
                            if res is true or (res as string) is "true" then return true
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error
    end try
    return false
end chromium_play_first

on chromium_play_url(browserName, targetURL, jsPlayFirst)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                repeat with windowIndex from 1 to (count of windows)
                    set w to window windowIndex
                    repeat with tabIndex from 1 to (count of tabs of w)
                        set t to tab tabIndex of w
                        try
                            set tabURL to (URL of t) as string
                            -- More precise URL matching to avoid false positives
                            set baseTarget to my extractBaseURL(targetURL)
                            set baseTab to my extractBaseURL(tabURL)
                            -- Only match if base URLs are identical (not contains)
                            if baseTab is baseTarget then
                                tell t to set res to execute javascript jsPlayFirst
                                if res is true or (res as string) is "true" then return true
                            end if
                        end try
                    end repeat
                end repeat
            end tell
        end using terms from
    on error
    end try
    return false
end chromium_play_url

-- Play media in the ACTIVE tab of a Chromium browser
on chromium_play_active_tab(browserName, jsPlayFirst)
    try
        using terms from application "Google Chrome"
            tell application browserName
                if (count of windows) < 1 then return false
                -- Get the active tab of the frontmost window
                set activeTab to active tab of front window
                tell activeTab to set res to execute javascript jsPlayFirst
                if res is true or (res as string) is "true" then return true
            end tell
        end using terms from
    on error
    end try
    return false
end chromium_play_active_tab

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
    on error
        return false
    end try
    return false
end safari_has_playing

on safari_find_pause_return(jsFindPauseReturn)
    try
        tell application "Safari"
            if (count of windows) < 1 then return ""
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        set res to do JavaScript jsFindPauseReturn in tab j of w
                        if res is not missing value and res is not "" then
                            set resStr to res as string
                            if resStr is not "" and resStr is not "null" and resStr is not "undefined" then
                                return resStr
                            end if
                        end if
                    end try
                end repeat
            end repeat
        end tell
    on error
    end try
    return ""
end safari_find_pause_return

on safari_pause_all(jsPauseAll)
    try
        tell application "Safari"
            if (count of windows) < 1 then return
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        do JavaScript jsPauseAll in tab j of w
                    end try
                end repeat
            end repeat
        end tell
    end try
end safari_pause_all

on safari_play_first(jsPlayFirst)
    try
        tell application "Safari"
            if (count of windows) < 1 then return false
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        set res to do JavaScript jsPlayFirst in tab j of w
                        if res is true or (res as string) is "true" then return true
                    end try
                end repeat
            end repeat
        end tell
    on error
    end try
    return false
end safari_play_first

on safari_play_url(targetURL, jsPlayFirst)
    try
        tell application "Safari"
            if (count of windows) < 1 then return false
            repeat with i from 1 to count of windows
                set w to window i
                repeat with j from 1 to count of tabs of w
                    try
                        set tabURL to (URL of tab j of w) as string
                        -- More precise URL matching to avoid false positives
                        set baseTarget to my extractBaseURL(targetURL)
                        set baseTab to my extractBaseURL(tabURL)
                        -- Only match if base URLs are identical (not contains)
                        if baseTab is baseTarget then
                            set res to do JavaScript jsPlayFirst in tab j of w
                            if res is true or (res as string) is "true" then return true
                        end if
                    end try
                end repeat
            end repeat
        end tell
    on error
    end try
    return false
end safari_play_url

-- Play media in the ACTIVE tab of Safari
on safari_play_active_tab(jsPlayFirst)
    try
        tell application "Safari"
            if (count of windows) < 1 then return false
            -- Get the current tab of the frontmost window
            set activeTab to current tab of front window
            set res to do JavaScript jsPlayFirst in activeTab
            if res is true or (res as string) is "true" then return true
        end tell
    on error
    end try
    return false
end safari_play_active_tab

-- ============================================================================
-- FIREFOX CONTROLS (via GUI scripting - Firefox has limited AppleScript)
-- ============================================================================

-- Note: Firefox has very limited AppleScript support, so we can't reliably
-- detect playing state. We use GUI scripting as a best-effort approach.
on firefox_toggle()
    try
        if not my appIsRunning("Firefox") then return false
        
        tell application "Firefox" to activate
        -- Delay allows Firefox to become frontmost and focused
        -- Adjust if needed on slower systems (0.1-0.3 seconds typical)
        delay 0.15
        
        tell application "System Events"
            tell process "Firefox"
                -- Send space bar to toggle play/pause on video sites
                -- Note: This only works if media player has focus
                key code 49 -- space bar
            end tell
        end tell
        return true
    on error errMsg
        my logDebug("Firefox toggle error: " & errMsg)
        return false
    end try
end firefox_toggle

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Extract base URL (protocol + domain + path, without query params or hash)
on extractBaseURL(fullURL)
    set oldDelimiters to AppleScript's text item delimiters
    try
        set AppleScript's text item delimiters to "?"
        set baseURL to text item 1 of fullURL
        set AppleScript's text item delimiters to "#"
        set baseURL to text item 1 of baseURL
        set AppleScript's text item delimiters to oldDelimiters
        return baseURL
    on error errMsg
        set AppleScript's text item delimiters to oldDelimiters
        my logDebug("extractBaseURL error: " & errMsg)
        return fullURL
    end try
end extractBaseURL

-- Write to file with validation
on writeToFile(filePath, content)
    try
        do shell script "echo " & quoted form of content & " > " & quoted form of filePath
        my logDebug("Wrote to file: " & filePath)
        return true
    on error errMsg
        my logDebug("Failed to write file: " & errMsg)
        return false
    end try
end writeToFile

-- Read from file with validation
on readFromFile(filePath)
    try
        set content to do shell script "cat " & quoted form of filePath & " 2>/dev/null || echo ''"
        my logDebug("Read from file: " & filePath & " = " & content)
        return content
    on error errMsg
        my logDebug("Failed to read file: " & errMsg)
        return ""
    end try
end readFromFile

-- ============================================================================
-- MAIN HANDLER
-- ============================================================================
on run {input, parameters}
    -- Storage paths
    set storagePath to (POSIX path of (path to library folder from user domain)) & "Application Support/MediaToggle/"
    set storageFile to storagePath & "last_url.txt"
    set lastAppFile to storagePath & "last_app.txt"
    
    -- Ensure storage directory exists
    try
        do shell script "mkdir -p " & quoted form of storagePath
    end try
    
    -- JavaScript snippets (supports both video AND audio elements)
    -- Uses readyState check (>= 2 = HAVE_CURRENT_DATA, allows buffering media)
    set jsCheckPlaying to "(function() {
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
            if (!media[i].paused && !media[i].ended && media[i].readyState >= 2) {
                return true;
            }
        }
        return false;
    })()"
    
    set jsPauseAll to "(function() {
        var media = document.querySelectorAll('video, audio');
        media.forEach(function(m) { 
            try { m.pause(); } catch(e) {} 
        });
    })()"
    
    set jsFindPauseReturn to "(function() {
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
            if (!media[i].paused && !media[i].ended && media[i].readyState >= 2) {
                try { media[i].pause(); } catch(e) {}
                return window.location.href;
            }
        }
        return '';
    })()"
    
    set jsPlayFirst to "(function() {
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
            if (media[i].paused && media[i].readyState > 0) {
                var playPromise = media[i].play();
                if (playPromise !== undefined) {
                    playPromise.catch(function(e) { console.log('Play prevented:', e); });
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
    
    -- ========================================================================
    -- PHASE 1: Check what's currently playing
    -- ========================================================================
    
    -- Check native apps first (faster response)
    set playingApp to ""
    
    if my spotify_is_playing() then
        set playingApp to "Spotify"
    else if my music_is_playing() then
        set playingApp to "Music"
    else if my vlc_is_playing() then
        set playingApp to "VLC"
    else if my quicktime_is_playing() then
        set playingApp to "QuickTime"
    else if my iina_is_playing() then
        set playingApp to "IINA"
    end if
    
    -- If a native app is playing, pause it and save state
    if playingApp is not "" then
        my logDebug("Pausing " & playingApp)
        if playingApp is "Spotify" then
            my spotify_pause()
        else if playingApp is "Music" then
            my music_pause()
        else if playingApp is "VLC" then
            my vlc_pause()
        else if playingApp is "QuickTime" then
            my quicktime_pause()
        else if playingApp is "IINA" then
            my iina_pause()
        end if
        my writeToFile(lastAppFile, playingApp)
        my writeToFile(storageFile, "") -- Clear URL since we're using native app
        display notification "Media paused" with title "MediaToggle" subtitle playingApp
        return input
    end if
    
    -- Check browsers for playing media
    set browserPlaying to ""
    set foundURL to ""
    
    if chromeRunning and browserPlaying is "" then
        if my chromium_has_playing("Google Chrome", jsCheckPlaying) then
            set browserPlaying to "Google Chrome"
        end if
    end if
    
    if braveRunning and browserPlaying is "" then
        if my chromium_has_playing("Brave Browser", jsCheckPlaying) then
            set browserPlaying to "Brave Browser"
        end if
    end if
    
    if arcRunning and browserPlaying is "" then
        if my chromium_has_playing("Arc", jsCheckPlaying) then
            set browserPlaying to "Arc"
        end if
    end if
    
    if edgeRunning and browserPlaying is "" then
        if my chromium_has_playing("Microsoft Edge", jsCheckPlaying) then
            set browserPlaying to "Microsoft Edge"
        end if
    end if
    
    if safariRunning and browserPlaying is "" then
        if my safari_has_playing(jsCheckPlaying) then
            set browserPlaying to "Safari"
        end if
    end if
    
    -- ========================================================================
    -- PHASE 2: Handle based on current state
    -- ========================================================================
    
    if browserPlaying is not "" then
        -- Something is playing in a browser: PAUSE it
        my logDebug("Pausing browser: " & browserPlaying)
        
        if browserPlaying is "Safari" then
            set foundURL to my safari_find_pause_return(jsFindPauseReturn)
            my safari_pause_all(jsPauseAll)
        else
            -- Chromium-based browser
            set foundURL to my chromium_find_pause_return(browserPlaying, jsFindPauseReturn)
            my chromium_pause_all(browserPlaying, jsPauseAll)
        end if
        
        -- Save state
        my writeToFile(lastAppFile, browserPlaying)
        if foundURL is not "" then
            my writeToFile(storageFile, foundURL)
        end if
        
        display notification "Media paused in browser" with title "MediaToggle" subtitle browserPlaying
        return input
    end if
    
    -- ========================================================================
    -- PHASE 3: Nothing playing - try to RESUME
    -- ========================================================================
    
    -- Read last playing app and URL
    set lastApp to my readFromFile(lastAppFile)
    set lastURL to my readFromFile(storageFile)
    
    -- Try to resume native apps first
    if lastApp is "Spotify" and my appIsRunning("Spotify") then
        my logDebug("Resuming Spotify")
        my spotify_play()
        display notification "Resuming playback" with title "MediaToggle" subtitle "Spotify"
        return input
    else if lastApp is "Music" and my appIsRunning("Music") then
        my logDebug("Resuming Music")
        my music_play()
        display notification "Resuming playback" with title "MediaToggle" subtitle "Apple Music"
        return input
    else if lastApp is "VLC" and my appIsRunning("VLC") then
        my logDebug("Resuming VLC")
        my vlc_play()
        display notification "Resuming playback" with title "MediaToggle" subtitle "VLC"
        return input
    else if lastApp is "QuickTime" and my appIsRunning("QuickTime Player") then
        my logDebug("Resuming QuickTime")
        my quicktime_play()
        display notification "Resuming playback" with title "MediaToggle" subtitle "QuickTime"
        return input
    else if lastApp is "IINA" and my appIsRunning("IINA") then
        my logDebug("Resuming IINA")
        my iina_play()
        display notification "Resuming playback" with title "MediaToggle" subtitle "IINA"
        return input
    end if
    
    -- Try to resume browser by saved URL
    -- IMPORTANT: Try the SAME browser first (the one that was paused)
    if lastURL is not "" then
        set resumed to false
        
        -- First, try the EXACT browser that was playing before
        if lastApp is "Safari" and safariRunning then
            set resumed to my safari_play_url(lastURL, jsPlayFirst)
        else if lastApp is "Google Chrome" and chromeRunning then
            set resumed to my chromium_play_url("Google Chrome", lastURL, jsPlayFirst)
        else if lastApp is "Brave Browser" and braveRunning then
            set resumed to my chromium_play_url("Brave Browser", lastURL, jsPlayFirst)
        else if lastApp is "Arc" and arcRunning then
            set resumed to my chromium_play_url("Arc", lastURL, jsPlayFirst)
        else if lastApp is "Microsoft Edge" and edgeRunning then
            set resumed to my chromium_play_url("Microsoft Edge", lastURL, jsPlayFirst)
        end if
        
        -- If original browser didn't work, try others as fallback
        if not resumed and chromeRunning and lastApp is not "Google Chrome" then
            set resumed to my chromium_play_url("Google Chrome", lastURL, jsPlayFirst)
        end if
        if not resumed and braveRunning and lastApp is not "Brave Browser" then
            set resumed to my chromium_play_url("Brave Browser", lastURL, jsPlayFirst)
        end if
        if not resumed and arcRunning and lastApp is not "Arc" then
            set resumed to my chromium_play_url("Arc", lastURL, jsPlayFirst)
        end if
        if not resumed and edgeRunning and lastApp is not "Microsoft Edge" then
            set resumed to my chromium_play_url("Microsoft Edge", lastURL, jsPlayFirst)
        end if
        if not resumed and safariRunning and lastApp is not "Safari" then
            set resumed to my safari_play_url(lastURL, jsPlayFirst)
        end if
        
        if resumed then
            my logDebug("Resumed media from URL: " & lastURL)
            display notification "Resuming media from saved URL" with title "MediaToggle" subtitle lastApp
            return input
        end if
    end if
    
    -- ========================================================================
    -- PHASE 4: No saved state - try to find paused media ANYWHERE visible
    -- This handles multi-monitor, split-screen, and first-time use scenarios
    -- ========================================================================
    
    set playedMedia to false
    set frontApp to my getFrontmostApp()
    
    -- Fast path: try active tab of frontmost browser first
    if frontApp starts with "Google Chrome" and chromeRunning then
        set playedMedia to my chromium_play_active_tab("Google Chrome", jsPlayFirst)
    else if frontApp starts with "Brave" and braveRunning then
        set playedMedia to my chromium_play_active_tab("Brave Browser", jsPlayFirst)
    else if frontApp is "Arc" and arcRunning then
        set playedMedia to my chromium_play_active_tab("Arc", jsPlayFirst)
    else if frontApp starts with "Microsoft Edge" and edgeRunning then
        set playedMedia to my chromium_play_active_tab("Microsoft Edge", jsPlayFirst)
    else if frontApp is "Safari" and safariRunning then
        set playedMedia to my safari_play_active_tab(jsPlayFirst)
    end if
    
    -- If frontmost browser had no media, search ALL browsers
    -- (covers multi-monitor and split-screen scenarios)
    if not playedMedia then
        if chromeRunning then
            set playedMedia to my chromium_play_first("Google Chrome", jsPlayFirst)
        end if
        if braveRunning and not playedMedia then
            set playedMedia to my chromium_play_first("Brave Browser", jsPlayFirst)
        end if
        if arcRunning and not playedMedia then
            set playedMedia to my chromium_play_first("Arc", jsPlayFirst)
        end if
        if edgeRunning and not playedMedia then
            set playedMedia to my chromium_play_first("Microsoft Edge", jsPlayFirst)
        end if
        if safariRunning and not playedMedia then
            set playedMedia to my safari_play_first(jsPlayFirst)
        end if
    end if
    
    if playedMedia then
        my logDebug("Started paused media in browser")
        display notification "Started paused media" with title "MediaToggle"
        return input
    end if
    
    -- Nothing found anywhere - inform the user
    display notification "No media found in any browser and no previous session to resume." with title "MediaToggle" subtitle "Nothing to play/pause"
    
    return input
end run
