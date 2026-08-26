# ==============================================================================
# File: Initialize-Terminal.ps1 (Private Helper)
# ==============================================================================

# Enable VT100 / ANSI Support for Windows Console hosts
if ($IsWindows) {
    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class TerminalConfiguration {
            const int STD_OUTPUT_HANDLE = -11;
            const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

            [DllImport("kernel32.dll", SetLastError = true)]
            static extern IntPtr GetStdHandle(int nStdHandle);

            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

            public static void EnableVT100() {
                IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
                if (handle != IntPtr.Zero) {
                    uint mode;
                    if (GetConsoleMode(handle, out mode)) {
                        mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                        SetConsoleMode(handle, mode);
                    }
                }
            }
        }
"@ -ErrorAction SilentlyContinue
        [TerminalConfiguration]::EnableVT100()
    }
    catch {
        # Fail silently if host environment does not support Win32 API calls
    }
}
