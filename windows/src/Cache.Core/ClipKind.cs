using System.Text.RegularExpressions;

namespace Cache.Core;

/// <summary>
/// What a clip actually is. The string values match the macOS app's
/// <c>Clip.kind</c> exactly, so a history exported from one platform can be read
/// by the other without a translation table.
/// </summary>
public enum ClipKind
{
    File,
    Image,
    Color,
    Code,
    Link,
    Text,
}

public static partial class ClipKindExtensions
{
    /// <summary>Lowercase name stored in the database. Must stay in sync with macOS.</summary>
    public static string ToStorageValue(this ClipKind kind) => kind switch
    {
        ClipKind.File => "file",
        ClipKind.Image => "image",
        ClipKind.Color => "color",
        ClipKind.Code => "code",
        ClipKind.Link => "link",
        _ => "text",
    };

    public static ClipKind FromStorageValue(string? value) => value switch
    {
        "file" => ClipKind.File,
        "image" => ClipKind.Image,
        "color" => ClipKind.Color,
        "code" => ClipKind.Code,
        "link" => ClipKind.Link,
        _ => ClipKind.Text,
    };

    /// <summary>Label used in the filter bar.</summary>
    public static string DisplayName(this ClipKind kind) => kind switch
    {
        ClipKind.File => "Files",
        ClipKind.Image => "Images",
        ClipKind.Color => "Colors",
        ClipKind.Code => "Code",
        ClipKind.Link => "Links",
        _ => "Text",
    };
}

/// <summary>
/// The string half of type detection, ported rule-for-rule from the macOS
/// <c>ClipKind.swift</c>. Kept free of any Windows types so it can be unit
/// tested without a clipboard, a window, or a display.
/// </summary>
public static partial class ClipKindDetector
{
    /// <summary>
    /// Detection order is deliberate and matches macOS: colour, then link, then
    /// code, then text. A hex colour is also valid text and a URL is also valid
    /// text, so the most specific test has to run first.
    ///
    /// File and image detection do not live here — they are decided by which
    /// clipboard formats are present, not by the string. See ClipboardReader.
    /// </summary>
    public static ClipKind Detect(string text)
    {
        var trimmed = text.Trim();

        if (IsColor(trimmed)) return ClipKind.Color;
        if (IsLink(trimmed)) return ClipKind.Link;
        if (IsCode(text)) return ClipKind.Code;
        return ClipKind.Text;
    }

    /// <summary><c>#RGB</c>, <c>#RRGGBB</c> (hash optional), or <c>rgb(...)</c> / <c>rgba(...)</c>.</summary>
    private static bool IsColor(string value) =>
        HexColor().IsMatch(value) || RgbColor().IsMatch(value);

    /// <summary>
    /// Parses as a URL <em>and</em> is web-schemed. The scheme check is what stops
    /// every ordinary word being treated as a link.
    /// </summary>
    private static bool IsLink(string value)
    {
        if (value.Length == 0) return false;
        if (value.Any(char.IsWhiteSpace)) return false;

        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;

        return uri.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase)
            || uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Heuristic, deliberately conservative: a code marker on its own is not
    /// enough (a sentence can contain a semicolon), so the clip must also span
    /// multiple lines.
    /// </summary>
    private static bool IsCode(string value)
    {
        if (!value.Contains('\n')) return false;

        string[] markers = ["{", "}", ";", "=>", "def ", "func ", "import "];
        return markers.Any(value.Contains);
    }

    [GeneratedRegex(@"^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$")]
    private static partial Regex HexColor();

    [GeneratedRegex(@"^rgba?\([^)]*\)$", RegexOptions.IgnoreCase)]
    private static partial Regex RgbColor();
}
