param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [Parameter(Mandatory = $true)]
    [string]$DataSourceId,

    [Parameter(Mandatory = $true)]
    [string]$OutFile,

    [string]$NotionVersion = '2026-03-11',
    [int]$PageSize = 12
)

$ErrorActionPreference = 'Stop'

$dir = Split-Path -Parent $OutFile
if ($dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

function Write-ErrorCache {
    param([string]$Message)
    @(
        'Status=ERROR'
        ('ErrorMessage=' + ($Message -replace "[\r\n]+", ' '))
    ) | Set-Content -Path $OutFile -Encoding utf8
}

function Get-Color {
    param(
        [string]$Priority,
        [datetime]$DueDate
    )

    switch ($Priority) {
        '高' { return '227,128,128' }
        '中' { return '244,216,120' }
        '低' { return '151,225,179' }
        '試験' { return '255,178,92' }
    }

    if ($DueDate.Date -eq (Get-Date).Date) {
        return '142,192,216'
    }

    return '255,255,255'
}

function Format-Meta {
    param(
        [datetime]$DueDate,
        [bool]$HasTime,
        [string]$Priority,
        [string]$Status
    )

    $jpWeekdays = @('日', '月', '火', '水', '木', '金', '土')
    $dayDiff = [int](($DueDate.Date - (Get-Date).Date).TotalDays)
    if ($dayDiff -le 0) {
        $relative = 'Today'
    } elseif ($dayDiff -eq 1) {
        $relative = 'Tomorrow'
    } else {
        $relative = "$dayDiff days left"
    }

    $weekday = $jpWeekdays[[int]$DueDate.DayOfWeek]
    $dueText = '{0}月{1}日 ({2})' -f $DueDate.Month, $DueDate.Day, $weekday
    if ($HasTime) {
        $ampm = if ($DueDate.Hour -lt 12) { '午前' } else { '午後' }
        $timeText = '{0} {1}:{2:00}' -f $ampm, ((($DueDate.Hour + 11) % 12) + 1), $DueDate.Minute
        $dueText = $dueText + ' ' + $timeText
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($dueText)
    if ($Priority) { $parts.Add("優先度 $Priority") }
    $parts.Add($relative)
    if ($Status -and $Status -ne '未着手') { $parts.Add($Status) }
    return ($parts -join ' ・ ')
}

try {
    $today = Get-Date -Format 'yyyy-MM-dd'
    $body = @{
        filter = @{
            and = @(
                @{
                    property = '@S=r'
                    date = @{
                        on_or_after = $today
                    }
                },
                @{
                    property = 'Djp]'
                    date = @{
                        is_empty = $true
                    }
                }
            )
        }
        sorts = @(
            @{
                property = '@S=r'
                direction = 'ascending'
            }
        )
        page_size = $PageSize
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{
        Authorization = "Bearer $Token"
        'Notion-Version' = $NotionVersion
        'Content-Type' = 'application/json; charset=utf-8'
    }

    $response = Invoke-RestMethod -Method Post -Headers $headers -Uri "https://api.notion.com/v1/data_sources/$DataSourceId/query" -Body $body

    $lines = [System.Collections.Generic.List[string]]::new()
    $items = @()

    foreach ($page in $response.results) {
        $props = $page.properties
        $displayName = $props.'Display Name'.formula.string
        $title = $props.'課題タイトル'.title.plain_text -join ''
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = $title
        }
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = 'Untitled assignment'
        }

        $dueRaw = $props.'期限'.date.start
        if ([string]::IsNullOrWhiteSpace($dueRaw)) {
            continue
        }

        $due = [datetimeoffset]::Parse($dueRaw).LocalDateTime
        $hasTime = $dueRaw.Contains('T')
        $priority = $props.'優先度'.select.name
        $status = $props.'ステータス'.status.name
        $color = Get-Color -Priority $priority -DueDate $due
        $meta = Format-Meta -DueDate $due -HasTime $hasTime -Priority $priority -Status $status

        $items += [pscustomobject]@{
            Title = ($displayName -replace "[\r\n]+", ' ')
            Meta = ($meta -replace "[\r\n]+", ' ')
            Color = $color
            Url = $page.url
            Due = $due
        }
    }

    $items = $items | Sort-Object Due, Title
    $visible = [Math]::Max(1, $items.Count)

    $lines.Add('Status=OK')
    $lines.Add("VisibleItems=$visible")

    for ($i = 0; $i -lt $PageSize; $i++) {
        $index = $i + 1
        if ($i -lt $items.Count) {
            $item = $items[$i]
            $lines.Add("Item${index}Title=$($item.Title)")
            $lines.Add("Item${index}Meta=$($item.Meta)")
            $lines.Add("Item${index}Color=$($item.Color)")
            $lines.Add("Item${index}Url=$($item.Url)")
        } else {
            $lines.Add("Item${index}Title=")
            $lines.Add("Item${index}Meta=")
            $lines.Add("Item${index}Color=255,255,255")
            $lines.Add("Item${index}Url=")
        }
    }

    $lines | Set-Content -Path $OutFile -Encoding utf8
} catch {
    Write-ErrorCache -Message $_.Exception.Message
}
