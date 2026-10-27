# Captures OutputDebugString output (Windhawk mod logs) for some seconds.
# Usage: tools\dbwin.ps1 [-Seconds 60] [-Filter davinci-resolve-ru] [-OutFile path]
# With -OutFile, lines are appended to the file as they arrive.
param([int]$Seconds = 60, [string]$Filter = '', [string]$OutFile = '')

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class DbWin {
    [StructLayout(LayoutKind.Sequential)]
    struct SA { public int n; public IntPtr sd; public bool inh; }

    [DllImport("advapi32", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string s, uint r, out IntPtr sd, IntPtr z);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateEventW(ref SA sa, bool m, bool i, string n);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFileMappingW(IntPtr f, ref SA sa, uint p, uint hi, uint lo, string n);
    [DllImport("kernel32", SetLastError = true)]
    static extern IntPtr MapViewOfFile(IntPtr m, uint a, uint hi, uint lo, UIntPtr s);
    [DllImport("kernel32")] static extern bool SetEvent(IntPtr h);
    [DllImport("kernel32")] static extern uint WaitForSingleObject(IntPtr h, uint ms);

    static IntPtr ready, data, view;

    public static void Init() {
        IntPtr sd;
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            "D:(A;;GRGWGX;;;WD)(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGWGX;;;AN)(A;;GRGWGX;;;RC)(A;;GRGWGX;;;S-1-15-2-1)S:(ML;;NW;;;LW)",
            1, out sd, IntPtr.Zero);
        var sa = new SA { n = Marshal.SizeOf(typeof(SA)), sd = sd };
        ready = CreateEventW(ref sa, false, false, @"Local\DBWIN_BUFFER_READY");
        data = CreateEventW(ref sa, false, false, @"Local\DBWIN_DATA_READY");
        IntPtr map = CreateFileMappingW(new IntPtr(-1), ref sa, 4, 0, 4096, @"Local\DBWIN_BUFFER");
        view = MapViewOfFile(map, 4, 0, 0, UIntPtr.Zero);
        if (view == IntPtr.Zero) throw new Exception("MapViewOfFile " + Marshal.GetLastWin32Error());
    }

    public static List<string> Capture(int ms, string filter, string outFile) {
        var lines = new List<string>();
        var end = DateTime.Now.AddMilliseconds(ms);
        SetEvent(ready);
        while (DateTime.Now < end) {
            if (WaitForSingleObject(data, 200) == 0) {
                string line = Marshal.PtrToStringAnsi(view + 4);
                if (filter.Length == 0 || line.Contains(filter)) {
                    line = line.TrimEnd();
                    if (outFile.Length > 0) System.IO.File.AppendAllText(outFile, line + "\n");
                    else lines.Add(line);
                }
                SetEvent(ready);
            }
        }
        return lines;
    }
}
'@

[DbWin]::Init()
[DbWin]::Capture($Seconds * 1000, $Filter, $OutFile)
