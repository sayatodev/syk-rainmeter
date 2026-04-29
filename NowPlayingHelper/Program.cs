using System.Globalization;
using System.Text;
using Windows.Media.Control;

namespace NowPlayingHelper;

internal sealed class Snapshot
{
    public string Status { get; init; } = "EMPTY";
    public long UpdatedAtUnixMs { get; init; }
    public string PlaybackStatus { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public string Artist { get; init; } = string.Empty;
    public string AlbumTitle { get; init; } = string.Empty;
    public string SourceAppUserModelId { get; init; } = string.Empty;
    public long PositionMs { get; init; }
    public long DurationMs { get; init; }
    public string PositionText { get; init; } = string.Empty;
    public string LengthText { get; init; } = string.Empty;
    public string ErrorMessage { get; init; } = string.Empty;
}

internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        var outPath = ParseOutPath(args);
        var watch = HasFlag(args, "--watch");
        var intervalMs = ParseInt(args, "--interval-ms", 1000);
        if (string.IsNullOrWhiteSpace(outPath))
        {
            return 2;
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(outPath)!);

            if (watch)
            {
                using var mutex = new Mutex(true, BuildMutexName(outPath), out var createdNew);
                if (!createdNew)
                {
                    return 0;
                }

                while (true)
                {
                    await WriteSnapshotSafeAsync(outPath);
                    await Task.Delay(Math.Max(250, intervalMs));
                }
            }
            else
            {
                await WriteSnapshotSafeAsync(outPath);
                return 0;
            }
        }
        catch (Exception ex)
        {
            var snapshot = new Snapshot
            {
                Status = "ERROR",
                UpdatedAtUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                ErrorMessage = Sanitize(ex.Message)
            };

            await WriteTextAtomicAsync(outPath, Serialize(snapshot));
            return 1;
        }
    }

    private static bool HasFlag(IReadOnlyList<string> args, string flag) =>
        args.Any(a => string.Equals(a, flag, StringComparison.OrdinalIgnoreCase));

    private static int ParseInt(IReadOnlyList<string> args, string flag, int defaultValue)
    {
        for (var i = 0; i < args.Count - 1; i++)
        {
            if (string.Equals(args[i], flag, StringComparison.OrdinalIgnoreCase) &&
                int.TryParse(args[i + 1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
            {
                return parsed;
            }
        }

        return defaultValue;
    }

    private static string? ParseOutPath(IReadOnlyList<string> args)
    {
        for (var i = 0; i < args.Count - 1; i++)
        {
            if (string.Equals(args[i], "--out", StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }

        return null;
    }

    private static async Task WriteSnapshotSafeAsync(string outPath)
    {
        Snapshot snapshot;
        try
        {
            snapshot = await CaptureSnapshotAsync();
        }
        catch (Exception ex)
        {
            snapshot = new Snapshot
            {
                Status = "ERROR",
                UpdatedAtUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                ErrorMessage = Sanitize(ex.Message)
            };
        }

        await WriteTextAtomicAsync(outPath, Serialize(snapshot));
    }

    private static async Task WriteTextAtomicAsync(string outPath, string content)
    {
        var tempPath = outPath + ".tmp";
        await File.WriteAllTextAsync(tempPath, content, new UTF8Encoding(false));
        File.Move(tempPath, outPath, true);
    }

    private static async Task<Snapshot> CaptureSnapshotAsync()
    {
        var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        var session = manager.GetCurrentSession();
        if (session is null)
        {
            return new Snapshot
            {
                Status = "EMPTY",
                UpdatedAtUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            };
        }

        var playbackInfo = session.GetPlaybackInfo();
        var mediaProperties = await session.TryGetMediaPropertiesAsync();
        var timeline = session.GetTimelineProperties();

        var title = Sanitize(mediaProperties.Title);
        var artist = Sanitize(mediaProperties.Artist);
        var albumTitle = Sanitize(mediaProperties.AlbumTitle);

        if (string.IsNullOrWhiteSpace(title) && string.IsNullOrWhiteSpace(artist))
        {
            return new Snapshot
            {
                Status = "EMPTY",
                UpdatedAtUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            };
        }

        var start = timeline.StartTime;
        var end = timeline.EndTime;
        var position = timeline.Position;

        var durationMs = Math.Max(0L, (long)Math.Round((end - start).TotalMilliseconds));
        var positionMs = Math.Max(0L, (long)Math.Round((position - start).TotalMilliseconds));
        if (durationMs > 0)
        {
            positionMs = Math.Min(positionMs, durationMs);
        }

        return new Snapshot
        {
            Status = "OK",
            UpdatedAtUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            PlaybackStatus = playbackInfo.PlaybackStatus.ToString(),
            Title = title,
            Artist = artist,
            AlbumTitle = albumTitle,
            SourceAppUserModelId = Sanitize(session.SourceAppUserModelId),
            PositionMs = positionMs,
            DurationMs = durationMs,
            PositionText = FormatTime(positionMs),
            LengthText = FormatTime(durationMs)
        };
    }

    private static string Serialize(Snapshot snapshot)
    {
        var values = new Dictionary<string, string>
        {
            ["Status"] = snapshot.Status,
            ["UpdatedAtUnixMs"] = snapshot.UpdatedAtUnixMs.ToString(CultureInfo.InvariantCulture),
            ["PlaybackStatus"] = snapshot.PlaybackStatus,
            ["Title"] = snapshot.Title,
            ["Artist"] = snapshot.Artist,
            ["AlbumTitle"] = snapshot.AlbumTitle,
            ["SourceAppUserModelId"] = snapshot.SourceAppUserModelId,
            ["PositionMs"] = snapshot.PositionMs.ToString(CultureInfo.InvariantCulture),
            ["DurationMs"] = snapshot.DurationMs.ToString(CultureInfo.InvariantCulture),
            ["PositionText"] = snapshot.PositionText,
            ["LengthText"] = snapshot.LengthText,
            ["ErrorMessage"] = snapshot.ErrorMessage
        };

        var builder = new StringBuilder();
        foreach (var pair in values)
        {
            builder.Append(pair.Key);
            builder.Append('=');
            builder.AppendLine(Sanitize(pair.Value));
        }

        return builder.ToString();
    }

    private static string FormatTime(long milliseconds)
    {
        if (milliseconds <= 0)
        {
            return string.Empty;
        }

        var span = TimeSpan.FromMilliseconds(milliseconds);
        return span.TotalHours >= 1
            ? span.ToString(@"h\:mm\:ss", CultureInfo.InvariantCulture)
            : span.ToString(@"m\:ss", CultureInfo.InvariantCulture);
    }

    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\r", " ").Replace("\n", " ").Trim();

    private static string BuildMutexName(string outPath)
    {
        var normalized = Path.GetFullPath(outPath).ToLowerInvariant();
        var chars = normalized
            .Select(c => char.IsLetterOrDigit(c) ? c : '_')
            .ToArray();
        return @"Local\NowPlayingSession_" + new string(chars);
    }
}
