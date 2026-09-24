<# Native always-on-top cost gauge. All usage stays on the local machine. #>
$ErrorActionPreference = 'Stop'
$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\CodexUsageMonitorWidget', [ref]$created)
if (-not $created) { $mutex.Dispose(); exit }
$stateRoot = if ($env:CODEX_USAGE_MONITOR_STATE_ROOT) { $env:CODEX_USAGE_MONITOR_STATE_ROOT } else { Join-Path $env:USERPROFILE '.codex-usage-monitor' }
[IO.Directory]::CreateDirectory($stateRoot) | Out-Null
$errorPath = Join-Path $stateRoot 'widget-error.log'
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing, System.Net.Http
    Add-Type -Path (Join-Path $PSScriptRoot 'SmoothGauge.cs') -ReferencedAssemblies @(
        [Windows.FrameworkElement].Assembly.Location,
        [Windows.Media.DrawingContext].Assembly.Location,
        [Windows.DependencyObject].Assembly.Location,
        [Windows.Markup.IQueryAmbient].Assembly.Location
    )
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Codex Usage Monitor Widget" Width="320" Height="300" WindowStyle="None" ResizeMode="NoResize"
    AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ShowActivated="False">
  <Border x:Name="Frame" Background="#121B29" BorderBrush="#33465B" BorderThickness="1" CornerRadius="18" Padding="16">
    <Grid>
    <Grid x:Name="CompactPanel" Visibility="Collapsed">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="CompactRate" Text="-- /30s" Foreground="#F1F7FF" FontSize="18" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Center"/>
      <Button x:Name="ExpandButton" Grid.Column="1" Content="+" Height="24" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Expand gauge"/>
    </Grid>
    <Grid x:Name="DetailPanel">
      <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="142"/><RowDefinition Height="23"/><RowDefinition Height="55"/><RowDefinition Height="20"/></Grid.RowDefinitions>
      <TextBlock Text="CODEX  /  LIVE COST" Foreground="#A5BAD0" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <Button x:Name="HideButton" Content="&#x2212;" Width="26" Height="22" HorizontalAlignment="Right" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Collapse to cost bar"/>
      <Canvas x:Name="GaugeCanvas" Grid.Row="1" Width="284" Height="142">
        <Path Stroke="#29394D" StrokeThickness="12" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M 32,114 A 110,110 0 0 1 252,114"/>
        <Border Background="#121B29" Canvas.Left="72" Canvas.Top="64" Width="140" Height="43">
          <StackPanel><TextBlock x:Name="Rate" Text="--" Foreground="#F1F7FF" FontSize="28" FontWeight="SemiBold" HorizontalAlignment="Center"/>
          </StackPanel>
        </Border>
        <TextBlock Text="USD / 30 sec" Foreground="#8FA6BF" FontSize="10" Canvas.Top="99" Canvas.Left="110"/>
        <TextBlock Text="0" Foreground="#8FA6BF" FontSize="10" Canvas.Left="27" Canvas.Top="126"/>
        <TextBlock x:Name="Scale" Text="$0.60/30s" Foreground="#8FA6BF" FontSize="10" Canvas.Right="20" Canvas.Top="126"/>
      </Canvas>
      <TextBlock x:Name="Status" Grid.Row="2" Text="Connecting..." Foreground="#8FA6BF" FontSize="11" HorizontalAlignment="Center"/>
      <Canvas Grid.Row="3" x:Name="Chart" Width="284" Height="55" ClipToBounds="True" Background="#162334">
        <Line X1="0" X2="284" Y1="18" Y2="18" Stroke="#26384B"/><Line X1="0" X2="284" Y1="36" Y2="36" Stroke="#26384B"/>
        <Polygon x:Name="Area" Fill="#24574F"/>
        <Polyline x:Name="History" Stroke="#57D7B2" StrokeThickness="1.5"/>
      </Canvas>
      <TextBlock Grid.Row="4" Text="5 MIN AGO" Foreground="#6F879F" FontSize="9" VerticalAlignment="Bottom"/>
      <TextBlock Grid.Row="4" Text="NOW" Foreground="#6F879F" FontSize="9" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
    </Grid>
    </Grid>
  </Border>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
    $rate = $window.FindName('Rate'); $status = $window.FindName('Status')
    $gauge = New-Object CodexUsageMonitor.SmoothGauge
    $gauge.Width = 284; $gauge.Height = 142
    $gauge.IsHitTestVisible = $false
    $window.FindName('GaugeCanvas').Children.Insert(1, $gauge)
    $history = $window.FindName('History'); $area = $window.FindName('Area')
    $chartMotion = New-Object Windows.Media.TranslateTransform
    $history.RenderTransform = $chartMotion
    $area.RenderTransform = $chartMotion
    $screen = [Windows.SystemParameters]::WorkArea
    $window.Left = $screen.Right - $window.Width - 16
    $window.Top = $screen.Bottom - $window.Height - 16
    $window.Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq 'Left') { $window.DragMove() } })
    $compactRate = $window.FindName('CompactRate')
    $preferencesPath = Join-Path $stateRoot 'widget-preferences.json'
    $script:compact = $false
    function Set-CompactMode([bool]$compact) {
        # Keep the bottom-right corner fixed when folding or expanding.
        $right = $window.Left + $window.Width
        $bottom = $window.Top + $window.Height
        $script:compact = $compact
        $window.FindName('DetailPanel').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
        $window.FindName('CompactPanel').Visibility = if ($compact) { 'Visible' } else { 'Collapsed' }
        $window.FindName('Frame').Padding = if ($compact) { '10,6' } else { '16' }
        $window.FindName('Frame').CornerRadius = if ($compact) { '10' } else { '18' }
        $window.Width = if ($compact) { 210 } else { 320 }
        $window.Height = if ($compact) { 44 } else { 300 }
        $window.Left = [Math]::Max([double]0, $right - $window.Width)
        $window.Top = [Math]::Max([double]0, $bottom - $window.Height)
        [IO.File]::WriteAllText($preferencesPath, (@{compact=$compact} | ConvertTo-Json), [Text.Encoding]::UTF8)
        $script:snapshotSaved = $false
        $script:lastDiagnostic = [DateTime]::MinValue
    }
    $window.FindName('HideButton').Add_Click({ Set-CompactMode $true })
    $window.FindName('ExpandButton').Add_Click({ Set-CompactMode $false })
    if (Test-Path -LiteralPath $preferencesPath) {
        try { Set-CompactMode ([bool]((Get-Content -LiteralPath $preferencesPath -Encoding UTF8 -Raw | ConvertFrom-Json).compact)) }
        catch { [IO.File]::AppendAllText($errorPath, ($_ | Out-String)) }
    }
    $tray = New-Object Windows.Forms.NotifyIcon
    $tray.Icon = [Drawing.SystemIcons]::Information
    $tray.Text = 'Codex Usage Monitor - API equivalent cost'
    $tray.Visible = $true
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $showItem = $menu.Items.Add('Show widget')
    $showItem.Add_Click({ $window.Show() })
    $resetItem = $menu.Items.Add('Move to bottom right')
    $resetItem.Add_Click({
        $workArea = [Windows.SystemParameters]::WorkArea
        $window.Left = $workArea.Right - $window.Width - 16
        $window.Top = $workArea.Bottom - $window.Height - 16
        $window.Show()
    })
    $dashboardItem = $menu.Items.Add('Open dashboard')
    $dashboardItem.Add_Click({ Start-Process 'http://127.0.0.1:47831/' })
    $exitItem = $menu.Items.Add('Exit widget')
    $exitItem.Add_Click({ $window.Close() })
    $tray.ContextMenuStrip = $menu
    $tray.Add_DoubleClick({ $window.Show() })
    $client = New-Object Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(3)
    $script:request = $null
    $script:lastGood = [DateTime]::MinValue
    $script:nextRequest = [DateTime]::MinValue
    $script:ceiling = 0.60
    $script:lastDiagnostic = [DateTime]::MinValue
    $script:snapshotSaved = $false
    $script:startedAt = [DateTime]::UtcNow
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        try {
            if ($script:request -and $script:request.IsCompleted) {
                try {
                    $data = ($script:request.GetAwaiter().GetResult()) | ConvertFrom-Json
                    if ($data.state -ne 'watching') { throw 'Monitor is scanning or unavailable.' }
                    $script:lastGood = [DateTime]::UtcNow
                    # Convert the API's per-second average to the recorded 30-second total.
                    # Keep the gauge and chart fixed at $0.60; only visual fill is clamped.
                    $value = [double]$data.usdPerSecond * 30
                    $rate.Text = '$' + $value.ToString('F4', [Globalization.CultureInfo]::InvariantCulture)
                    $status.Text = if ($data.unpricedCalls -gt 0) { '30s total - some model prices missing' } else { 'Last 30s total - API equivalent' }
                    $status.Foreground = if ($data.unpricedCalls -gt 0) { '#F5BD73' } else { '#8FA6BF' }
                    $fraction = [Math]::Min([double]1, ($value / $script:ceiling))
                    $gauge.AnimateTo($fraction)
                    $line = New-Object Windows.Media.PointCollection
                    $fill = New-Object Windows.Media.PointCollection
                    $fill.Add((New-Object Windows.Point(0, 55)))
                    for ($i = 0; $i -lt $data.points.Count; $i++) {
                        $chartFraction = [Math]::Min([double]1, ([double]$data.points[$i] * 30 / $script:ceiling))
                        $point = New-Object Windows.Point(($i * 284.0 / 299), (53 - 50 * $chartFraction))
                        $line.Add($point); $fill.Add($point)
                    }
                    $fill.Add((New-Object Windows.Point(284, 55)))
                    $history.Points = $line; $area.Points = $fill
                    # Scroll one sample width between server samples using native animation.
                    $scroll = New-Object Windows.Media.Animation.DoubleAnimation(0, (-284.0 / 299), ([TimeSpan]::FromSeconds(1)))
                    $chartMotion.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $scroll)
                } catch {
                    $status.Text = 'Connecting to monitor...'
                    [IO.File]::AppendAllText($errorPath, ([DateTime]::UtcNow.ToString('o') + ' ' + $_.Exception.Message + [Environment]::NewLine))
                } finally { $script:request = $null }
            }
            if (([DateTime]::UtcNow - $script:lastGood).TotalSeconds -gt 5) {
                $rate.Text = '--'
                $status.Text = 'Monitor offline - reconnecting'
                $status.Foreground = '#F5BD73'
                $gauge.Reset(); $history.Points.Clear(); $area.Points.Clear()
                $chartMotion.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
            }
            $compactRate.Text = $rate.Text + ' /30s'
            $compactRate.ToolTip = $status.Text
            $compactRate.Foreground = if ($status.Text -eq 'Last 30s total - API equivalent') { '#F1F7FF' } else { '#F5BD73' }
            if (-not $script:request -and [DateTime]::UtcNow -ge $script:nextRequest) {
                $script:request = $client.GetStringAsync('http://127.0.0.1:47831/api/widget')
                $script:nextRequest = [DateTime]::UtcNow.AddSeconds(1)
            }
            if (([DateTime]::UtcNow - $script:lastDiagnostic).TotalSeconds -ge 5) {
                $script:lastDiagnostic = [DateTime]::UtcNow
                $diagnostic = @{ pid = $PID; visible = $window.IsVisible; compact = $script:compact; left = $window.Left; top = $window.Top; width = $window.Width; height = $window.Height; lastGood = $script:lastGood.ToString('o'); rate = $rate.Text; status = $status.Text; ceiling = $script:ceiling }
                [IO.File]::WriteAllText((Join-Path $stateRoot 'widget-status.json'), ($diagnostic | ConvertTo-Json), [Text.Encoding]::UTF8)
            }
            # Save one rendering for installation verification without capturing other apps.
            if (-not $script:snapshotSaved -and ([DateTime]::UtcNow - $script:startedAt).TotalSeconds -gt 3 -and $script:lastGood -gt [DateTime]::MinValue -and $window.IsVisible) {
                $window.UpdateLayout()
                $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.Width, [int]$window.Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window)
                $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream = [IO.File]::Create((Join-Path $stateRoot 'widget-preview.png'))
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
                $script:snapshotSaved = $true
            }
        } catch {
            [IO.File]::AppendAllText($errorPath, ($_ | Out-String))
        }
    })
    $window.Add_Closed({ $timer.Stop() })
    $timer.Start()
    $window.ShowDialog() | Out-Null
} catch {
    [IO.File]::AppendAllText($errorPath, ($_ | Out-String))
    throw
} finally {
    if ($timer) { $timer.Stop() }
    if ($client) { $client.Dispose() }
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
