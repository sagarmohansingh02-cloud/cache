using System.Runtime.InteropServices;
using Cache.Core.Interop;

namespace Cache.Core;

/// <summary>
/// The password guard — the Windows counterpart of the macOS
/// <c>org.nspasteboard.ConcealedType</c> check, and just as non-negotiable.
/// Without it the database becomes a plaintext password log.
///
/// Windows expresses this as three registered clipboard formats that a copying
/// app can add alongside its data:
///
/// <list type="bullet">
///   <item><c>ExcludeClipboardContentFromMonitorProcessing</c> — "no clipboard
///   manager may record this". Its mere presence is the signal; it carries no
///   payload. This is what KeePass, Bitwarden and 1Password set.</item>
///   <item><c>CanIncludeInClipboardHistory</c> — a DWORD. 0 means "keep this out
///   of clipboard history", which is exactly what we are.</item>
///   <item><c>CanUploadToCloudClipboard</c> — a DWORD, about cloud sync rather
///   than local history. Honoured anyway: an app that refuses cloud sync is
///   telling us the content is sensitive.</item>
/// </list>
///
/// Every check runs <em>before</em> a single byte of content is read.
/// </summary>
public static class ClipboardPrivacy
{
    // RegisterClipboardFormat returns the same id for the same name for the
    // lifetime of the session, so these are resolved once.
    private static readonly uint ExcludeFromMonitorProcessing =
        Win32.RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");

    private static readonly uint CanIncludeInClipboardHistory =
        Win32.RegisterClipboardFormat("CanIncludeInClipboardHistory");

    private static readonly uint CanUploadToCloudClipboard =
        Win32.RegisterClipboardFormat("CanUploadToCloudClipboard");

    /// <summary>
    /// True when the copying app has asked not to be recorded.
    /// </summary>
    /// <remarks>
    /// Fails closed. If the clipboard cannot be opened to read the DWORD flags,
    /// we skip the item rather than record it — for a privacy guard, dropping a
    /// legitimate clip is a far cheaper mistake than saving a password.
    /// </remarks>
    public static bool ShouldSkip()
    {
        // Presence alone is the signal for this one, and it needs no clipboard
        // lock to test — so it is checked first and costs nothing.
        if (Win32.IsClipboardFormatAvailable(ExcludeFromMonitorProcessing))
        {
            return true;
        }

        var hasHistoryFlag = Win32.IsClipboardFormatAvailable(CanIncludeInClipboardHistory);
        var hasCloudFlag = Win32.IsClipboardFormatAvailable(CanUploadToCloudClipboard);

        // Neither DWORD flag is present, so there is nothing further to honour.
        if (!hasHistoryFlag && !hasCloudFlag)
        {
            return false;
        }

        using var clipboard = ClipboardLock.Acquire();
        if (!clipboard.IsOpen)
        {
            // Could not read the flags. Fail closed — see the remarks above.
            return true;
        }

        if (hasHistoryFlag && ReadDword(CanIncludeInClipboardHistory) == 0) return true;
        if (hasCloudFlag && ReadDword(CanUploadToCloudClipboard) == 0) return true;

        return false;
    }

    /// <summary>
    /// Read a 4-byte flag out of a clipboard format. Returns null when the value
    /// is missing or the wrong size. The clipboard must already be open.
    /// </summary>
    private static uint? ReadDword(uint format)
    {
        var handle = Win32.GetClipboardData(format);
        if (handle == IntPtr.Zero) return null;

        // GlobalSize is checked before reading: the format is documented as a
        // DWORD, but this is data written by another process and we are not
        // going to take its word for the length.
        if ((ulong)Win32.GlobalSize(handle) < sizeof(uint)) return null;

        var pointer = Win32.GlobalLock(handle);
        if (pointer == IntPtr.Zero) return null;

        try
        {
            return (uint)Marshal.ReadInt32(pointer);
        }
        finally
        {
            Win32.GlobalUnlock(handle);
        }
    }
}

/// <summary>
/// RAII wrapper over OpenClipboard/CloseClipboard.
///
/// Only one process may hold the clipboard at a time, and on a busy machine the
/// app that just wrote to it is often still holding it when our notification
/// arrives. Retrying briefly is the documented remedy; giving up after ~250ms
/// is better than blocking a background service indefinitely.
/// </summary>
internal readonly struct ClipboardLock : IDisposable
{
    public bool IsOpen { get; }

    private ClipboardLock(bool isOpen) => IsOpen = isOpen;

    public static ClipboardLock Acquire(int attempts = 10, int delayMs = 25)
    {
        for (var attempt = 0; attempt < attempts; attempt++)
        {
            if (Win32.OpenClipboard(IntPtr.Zero))
            {
                return new ClipboardLock(true);
            }
            Thread.Sleep(delayMs);
        }
        return new ClipboardLock(false);
    }

    public void Dispose()
    {
        if (IsOpen) Win32.CloseClipboard();
    }
}
