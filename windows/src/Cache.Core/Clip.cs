namespace Cache.Core;

/// <summary>
/// One captured clipboard item.
///
/// Field-for-field the same shape as the macOS <c>Clip</c> SwiftData model, on
/// purpose: when sync eventually happens, the two stores should describe the
/// same thing rather than needing a mapping layer invented after the fact.
/// </summary>
public sealed class Clip
{
    public required Guid Id { get; init; }

    /// <summary>UTC. Stored as an ISO-8601 string so the DB stays human-readable.</summary>
    public required DateTimeOffset CreatedAt { get; init; }

    public required ClipKind Kind { get; set; }

    /// <summary>Text content, a newline-joined file path list, or a hex code — depending on <see cref="Kind"/>.</summary>
    public string? Text { get; set; }

    public string? ImageFilename { get; set; }
    public string? ThumbnailFilename { get; set; }

    /// <summary>
    /// Text recognised inside an image. Null means recognition never ran; empty
    /// string means it ran and found nothing. Backfill relies on that
    /// distinction to avoid re-scanning textless images on every launch.
    /// </summary>
    public string? OcrText { get; set; }

    public string? SourceAppName { get; set; }

    /// <summary>
    /// On Windows this is the executable path of the foreground process, which
    /// is the closest equivalent to a macOS bundle identifier.
    /// </summary>
    public string? SourceAppId { get; set; }

    public bool IsPinned { get; set; }

    /// <summary>User-created collection name. Null means plain History.</summary>
    public string? Category { get; set; }

    /// <summary>User-supplied name, shown instead of the contents.</summary>
    public string? Title { get; set; }

    /// <summary>How many times this clip has been pasted back. Drives "most used" sort.</summary>
    public int UseCount { get; set; }

    public DateTimeOffset? LastUsedAt { get; set; }
    public DateTimeOffset? ReminderAt { get; set; }

    /// <summary>Position for manual sort order. Null until the user drags something.</summary>
    public int? ManualOrder { get; set; }

    /// <summary>What the list shows for this clip when it has no title of its own.</summary>
    public string Preview => Title
        ?? Kind switch
        {
            ClipKind.Image => string.IsNullOrWhiteSpace(OcrText) ? "Image" : OcrText.Trim(),
            _ => Text?.Trim() ?? string.Empty,
        };
}
