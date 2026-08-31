using System.Diagnostics;
using System.Runtime.InteropServices;
using Cache.Core.Interop;

namespace Cache.Core;

/// <summary>Raised when the system clipboard changes and the item is safe to record.</summary>
public sealed class ClipboardChangedEventArgs : EventArgs
{
    public required string? SourceAppName { get; init; }
    public required string? SourceAppPath { get; init; }
}

/// <summary>
/// The capture engine.
///
/// Worth contrasting with the macOS version, because this is where the two
/// platforms genuinely diverge. On macOS <c>NSPasteboard</c> offers no change
/// notification at all, so the app polls <c>changeCount</c> three times a second
/// forever. Windows gives us a real one: register a window as a clipboard format
/// listener and the OS posts <c>WM_CLIPBOARDUPDATE</c> when something changes.
///
/// Consequences: no timer, no poll interval, no battery-vs-AC tuning, and a
/// genuine zero idle cost — the thread sits blocked in <c>GetMessage</c>, using
/// nothing, until the kernel wakes it. Roughly 80 lines of macOS power-management
/// code have no counterpart here.
///
/// The one oddity is that Windows delivers this to a <em>window</em>, so even a
/// headless background service must create one. A message-only window
/// (<see cref="Win32.HWND_MESSAGE"/>) is the intended solution: it never renders
/// and is not enumerable, but it receives posted messages.
/// </summary>
public sealed class ClipboardMonitor : IDisposable
{
    private const string WindowClassName = "CacheClipboardListener";

    /// <summary>Fired on the monitor's own thread. Handlers must marshal to the UI themselves.</summary>
    public event EventHandler<ClipboardChangedEventArgs>? ClipboardChanged;

    private Thread? _thread;
    private IntPtr _hwnd;
    private uint _threadId;

    /// <summary>
    /// The delegate must be held in a field. If it were only passed to
    /// <c>RegisterClassEx</c>, nothing managed would reference it, the GC would
    /// collect it, and the first clipboard change would call into freed memory
    /// and take the process down. This is the classic P/Invoke callback trap.
    /// </summary>
    private Win32.WndProc? _wndProc;

    private readonly ManualResetEventSlim _ready = new(false);
    private volatile bool _disposed;

    /// <summary>
    /// Sequence number of a write we made ourselves.
    ///
    /// Pasting a clip back writes to the clipboard, which bumps the sequence
    /// number exactly as a user copy would. Without this the next notification
    /// would re-capture our own write and push a duplicate to the top of the
    /// list — the same problem <c>acknowledgeSelfCopy()</c> solves on macOS.
    /// </summary>
    private uint _selfWriteSequence;

    public bool IsPaused { get; set; }

    // MARK: - Lifecycle

    public void Start()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_thread is not null) return;

        _thread = new Thread(RunMessageLoop)
        {
            IsBackground = true,
            Name = "Cache.ClipboardMonitor",
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();

        // Block until the window exists, so a caller that immediately writes to
        // the clipboard cannot race ahead of the listener being registered.
        _ready.Wait(TimeSpan.FromSeconds(5));
    }

    /// <summary>
    /// Call immediately after writing to the clipboard on purpose, so the
    /// resulting notification is recognised as ours and ignored.
    /// </summary>
    public void AcknowledgeSelfCopy() => _selfWriteSequence = Win32.GetClipboardSequenceNumber();

    // MARK: - The message loop

    private void RunMessageLoop()
    {
        _threadId = Win32.GetCurrentThreadId();
        _wndProc = WindowProcedure;

        var wndClass = new Win32.WNDCLASSEX
        {
            cbSize = (uint)Marshal.SizeOf<Win32.WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = Win32.GetModuleHandle(null),
            lpszClassName = WindowClassName,
        };

        // A class name is per-process, so re-registering after a restart-in-place
        // fails with ERROR_CLASS_ALREADY_EXISTS (1410). That is harmless — the
        // existing registration is still usable — so it is not treated as fatal.
        var atom = Win32.RegisterClassEx(ref wndClass);
        if (atom == 0)
        {
            var error = Marshal.GetLastWin32Error();
            const int ERROR_CLASS_ALREADY_EXISTS = 1410;
            if (error != ERROR_CLASS_ALREADY_EXISTS)
            {
                Trace.TraceError($"Cache: could not register window class ({error})");
                _ready.Set();
                return;
            }
        }

        _hwnd = Win32.CreateWindowEx(
            dwExStyle: 0,
            lpClassName: WindowClassName,
            lpWindowName: null,
            dwStyle: 0,
            x: 0, y: 0, nWidth: 0, nHeight: 0,
            hWndParent: Win32.HWND_MESSAGE,
            hMenu: IntPtr.Zero,
            hInstance: Win32.GetModuleHandle(null),
            lpParam: IntPtr.Zero);

        if (_hwnd == IntPtr.Zero)
        {
            Trace.TraceError($"Cache: could not create the listener window ({Marshal.GetLastWin32Error()})");
            _ready.Set();
            return;
        }

        if (!Win32.AddClipboardFormatListener(_hwnd))
        {
            Trace.TraceError($"Cache: could not register as a clipboard listener ({Marshal.GetLastWin32Error()})");
            Win32.DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
            _ready.Set();
            return;
        }

        _ready.Set();

        // Blocks here. No CPU is used until a message arrives.
        while (Win32.GetMessage(out var msg, IntPtr.Zero, 0, 0) is var result && result != 0)
        {
            // -1 is a genuine error rather than a message; continuing would spin.
            if (result == -1) break;

            Win32.TranslateMessage(ref msg);
            Win32.DispatchMessage(ref msg);
        }
    }

    private IntPtr WindowProcedure(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case Win32.WM_CLIPBOARDUPDATE:
                HandleClipboardUpdate();
                return IntPtr.Zero;

            case Win32.WM_DESTROY:
                Win32.PostQuitMessage(0);
                return IntPtr.Zero;

            default:
                return Win32.DefWindowProc(hWnd, msg, wParam, lParam);
        }
    }

    private void HandleClipboardUpdate()
    {
        // Our own write, echoed back. Drop it.
        var sequence = Win32.GetClipboardSequenceNumber();
        if (sequence == _selfWriteSequence) return;

        if (IsPaused) return;

        // The privacy guard runs before anything reads content. Order matters.
        if (ClipboardPrivacy.ShouldSkip()) return;

        var (appName, appPath) = ForegroundApp();

        try
        {
            ClipboardChanged?.Invoke(this, new ClipboardChangedEventArgs
            {
                SourceAppName = appName,
                SourceAppPath = appPath,
            });
        }
        catch (Exception ex)
        {
            // A throwing handler must not escape into the window procedure —
            // an exception crossing back into native code terminates the process.
            Trace.TraceError($"Cache: clipboard handler threw — {ex}");
        }
    }

    /// <summary>
    /// Who copied. The Windows counterpart of <c>NSWorkspace.frontmostApplication</c>:
    /// find the foreground window, ask which process owns it.
    /// </summary>
    private static (string? Name, string? Path) ForegroundApp()
    {
        var hwnd = Win32.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return (null, null);

        _ = Win32.GetWindowThreadProcessId(hwnd, out var processId);
        if (processId == 0) return (null, null);

        try
        {
            using var process = Process.GetProcessById((int)processId);
            // MainModule throws for elevated or protected processes we cannot
            // open. The friendly name alone is still worth recording.
            string? path = null;
            try { path = process.MainModule?.FileName; }
            catch { /* not readable; name only */ }

            return (process.ProcessName, path);
        }
        catch
        {
            // The process can exit between the handle lookup and here.
            return (null, null);
        }
    }

    // MARK: - Teardown

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_hwnd != IntPtr.Zero)
        {
            Win32.RemoveClipboardFormatListener(_hwnd);
            Win32.DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }

        // Wake the loop so the thread can exit rather than sitting in GetMessage.
        if (_threadId != 0)
        {
            Win32.PostThreadMessage(_threadId, Win32.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        }

        _thread?.Join(TimeSpan.FromSeconds(2));
        _thread = null;
        _ready.Dispose();
    }
}
