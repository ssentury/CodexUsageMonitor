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
    Title="Codex Usage Monitor Widget" Width="320" SizeToContent="Height" WindowStyle="None" ResizeMode="NoResize"
    AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ShowActivated="False">
  <Border x:Name="Frame" Background="#121B29" BorderBrush="#33465B" BorderThickness="1" CornerRadius="18" Padding="16">
    <Grid>
    <Grid x:Name="CompactPanel" Visibility="Collapsed">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="CompactRate" Text="-- /30s" Foreground="#F1F7FF" FontSize="18" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Center"/>
      <Button x:Name="ExpandButton" Grid.Column="1" Content="+" Height="24" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Expand gauge"/>
    </Grid>
    <Grid x:Name="DetailPanel">
      <Grid.RowDefinitions><RowDefinition Height="28"/><RowDefinition Height="142"/><RowDefinition Height="23"/><RowDefinition Height="55"/><RowDefinition Height="20"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock Text="CODEX  /  LIVE COST" Foreground="#A5BAD0" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="ConfigButton" Content="&#x2699;" Width="26" Height="22" Margin="0,0,4,0" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Widget settings"/>
        <Button x:Name="HideButton" Content="&#x2212;" Width="26" Height="22" Margin="0,0,4,0" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Collapse to cost bar"/>
        <Button x:Name="CloseButton" Content="x" Width="26" Height="22" Background="#223249" Foreground="#D8E6F5" BorderThickness="0" ToolTip="Exit widget"/>
      </StackPanel>
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
        <Canvas x:Name="ModelLayers" Width="284" Height="55"/>
      </Canvas>
      <TextBlock x:Name="HistoryStartLabel" Grid.Row="4" Text="5 MIN AGO" Foreground="#6F879F" FontSize="9" VerticalAlignment="Bottom"/>
      <TextBlock Grid.Row="4" Text="NOW" Foreground="#6F879F" FontSize="9" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
      <TextBlock x:Name="RunningModels" Grid.Row="5" Foreground="#89939F" FontSize="9" Margin="0,7,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
      <Border x:Name="SettingsPanel" Grid.Row="1" Grid.RowSpan="4" Visibility="Collapsed" Background="#121B29" Panel.ZIndex="5">
        <StackPanel Margin="8,5,8,0">
          <TextBlock Text="WIDGET SETTINGS" Foreground="#F1F7FF" FontSize="15" FontWeight="SemiBold"/>
          <TextBlock Text="Gauge maximum (USD / 30 sec)" Foreground="#A5BAD0" FontSize="11" Margin="0,12,0,4"/>
          <TextBox x:Name="CeilingInput" Height="28" Padding="7,3" Background="#162334" Foreground="#F1F7FF" BorderBrush="#33465B"/>
          <TextBlock Text="Graph history (minutes)" Foreground="#A5BAD0" FontSize="11" Margin="0,10,0,4"/>
          <TextBox x:Name="HistoryMinutesInput" Height="28" Padding="7,3" Background="#162334" Foreground="#F1F7FF" BorderBrush="#33465B"/>
          <TextBlock Text="Allowed range: 1–60 minutes" Foreground="#6F879F" FontSize="10" Margin="0,4,0,0"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="CancelSettingsButton" Content="Cancel" Width="68" Height="28" Margin="0,0,6,0" Background="#223249" Foreground="#D8E6F5" BorderThickness="0"/>
            <Button x:Name="SaveSettingsButton" Content="Save" Width="68" Height="28" Background="#57D7B2" Foreground="#10231F" BorderThickness="0" FontWeight="SemiBold"/>
          </StackPanel>
          <TextBlock x:Name="SettingsError" Foreground="#FF8C8C" FontSize="10" Margin="0,5,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </Border>
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
    $modelLayers = $window.FindName('ModelLayers')
    $running = $window.FindName('RunningModels')
    $chartMotion = New-Object Windows.Media.TranslateTransform
    $modelLayers.RenderTransform = $chartMotion
    $screen = [Windows.SystemParameters]::WorkArea
    $window.Left = $screen.Right - $window.Width - 16
    $window.Top = $screen.Bottom - 302 - 16
    $window.Add_SizeChanged({
        $workArea = [Windows.SystemParameters]::WorkArea
        if ($window.Top + $window.ActualHeight -gt $workArea.Bottom) {
            $window.Top = [Math]::Max($workArea.Top, $workArea.Bottom - $window.ActualHeight)
        }
    })
    $window.Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq 'Left') { $window.DragMove() } })
    $compactRate = $window.FindName('CompactRate')
    $preferencesPath = Join-Path $stateRoot 'widget-preferences.json'
    $script:compact = $false
    $script:ceiling = 0.60
    $script:historyMinutes = 5
    $script:settingsVisible = $false
    function Save-Preferences {
        $preferences = @{
            compact = $script:compact
            ceiling = $script:ceiling
            historyMinutes = $script:historyMinutes
        }
        [IO.File]::WriteAllText($preferencesPath, ($preferences | ConvertTo-Json), [Text.Encoding]::UTF8)
    }
    function Set-SettingsVisibility([bool]$visible) {
        $script:settingsVisible = $visible
        $window.FindName('SettingsPanel').Visibility = if ($visible) { 'Visible' } else { 'Collapsed' }
        $window.FindName('ConfigButton').Content = if ($visible) { [char]0x2190 } else { [char]0x2699 }
        if ($visible) {
            $window.FindName('CeilingInput').Text = $script:ceiling.ToString('0.####', [Globalization.CultureInfo]::InvariantCulture)
            $window.FindName('HistoryMinutesInput').Text = [string]$script:historyMinutes
            $window.FindName('SettingsError').Text = ''
        }
    }
    function Update-ConfigurationLabels {
        $window.FindName('Scale').Text = '$' + $script:ceiling.ToString('0.####', [Globalization.CultureInfo]::InvariantCulture) + '/30s'
        $window.FindName('HistoryStartLabel').Text = [string]$script:historyMinutes + ' MIN AGO'
    }
    function Set-CompactMode([bool]$compact, [bool]$persist = $true) {
        # Keep the bottom-right corner fixed when folding or expanding.
        $right = $window.Left + $window.Width
        $bottom = $window.Top + $window.ActualHeight
        $script:compact = $compact
        $window.FindName('DetailPanel').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
        $window.FindName('CompactPanel').Visibility = if ($compact) { 'Visible' } else { 'Collapsed' }
        $window.FindName('Frame').Padding = if ($compact) { '10,6' } else { '16' }
        $window.FindName('Frame').CornerRadius = if ($compact) { '10' } else { '18' }
        $window.Width = if ($compact) { 210 } else { 320 }
        $window.SizeToContent = if ($compact) { 'Manual' } else { 'Height' }
        if ($compact) { $window.Height = 44 } else { $window.Height = [double]::NaN }
        $window.UpdateLayout()
        $window.Left = [Math]::Max([double]0, $right - $window.Width)
        $window.Top = [Math]::Max([double]0, $bottom - $window.ActualHeight)
        if ($compact) { Set-SettingsVisibility $false }
        if ($persist) { Save-Preferences }
        $script:snapshotSaved = $false
        $script:lastDiagnostic = [DateTime]::MinValue
    }
    $window.FindName('HideButton').Add_Click({ Set-CompactMode $true })
    $window.FindName('ExpandButton').Add_Click({ Set-CompactMode $false })
    $window.FindName('CloseButton').Add_Click({ $window.Close() })
    $window.FindName('ConfigButton').Add_Click({ Set-SettingsVisibility (-not $script:settingsVisible) })
    $window.FindName('CancelSettingsButton').Add_Click({ Set-SettingsVisibility $false })
    $window.FindName('SaveSettingsButton').Add_Click({
        $parsedCeiling = [double]0
        $parsedMinutes = [int]0
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $validCeiling = [double]::TryParse($window.FindName('CeilingInput').Text, [Globalization.NumberStyles]::Float, $culture, [ref]$parsedCeiling)
        $validMinutes = [int]::TryParse($window.FindName('HistoryMinutesInput').Text, [ref]$parsedMinutes)
        if (-not $validCeiling -or $parsedCeiling -le 0 -or $parsedCeiling -gt 1000) {
            $window.FindName('SettingsError').Text = 'Gauge maximum must be greater than 0 and at most 1000.'
            return
        }
        if (-not $validMinutes -or $parsedMinutes -lt 1 -or $parsedMinutes -gt 60) {
            $window.FindName('SettingsError').Text = 'Graph history must be a whole number from 1 to 60.'
            return
        }
        $script:ceiling = $parsedCeiling
        $script:historyMinutes = $parsedMinutes
        Update-ConfigurationLabels
        Save-Preferences
        $script:nextRequest = [DateTime]::MinValue
        Set-SettingsVisibility $false
    })
    if (Test-Path -LiteralPath $preferencesPath) {
        try {
            $savedPreferences = Get-Content -LiteralPath $preferencesPath -Encoding UTF8 -Raw | ConvertFrom-Json
            if ($null -ne $savedPreferences.ceiling -and [double]$savedPreferences.ceiling -gt 0 -and [double]$savedPreferences.ceiling -le 1000) {
                $script:ceiling = [double]$savedPreferences.ceiling
            }
            if ($null -ne $savedPreferences.historyMinutes -and [int]$savedPreferences.historyMinutes -ge 1 -and [int]$savedPreferences.historyMinutes -le 60) {
                $script:historyMinutes = [int]$savedPreferences.historyMinutes
            }
            Set-CompactMode ([bool]$savedPreferences.compact) $false
        }
        catch { [IO.File]::AppendAllText($errorPath, ($_ | Out-String)) }
    }
    Update-ConfigurationLabels
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
        $window.Top = $workArea.Bottom - $window.ActualHeight - 16
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
                    # The configured maximum only clamps the visual fill; the number stays exact.
                    $value = [double]$data.usdPerSecond * 30
                    $rate.Text = '$' + $value.ToString('F4', [Globalization.CultureInfo]::InvariantCulture)
                    $status.Text = if ($data.unpricedCalls -gt 0) { '30s total - some model prices missing' } else { 'Last 30s total - API equivalent' }
                    $status.Foreground = if ($data.unpricedCalls -gt 0) { '#F5BD73' } else { '#8FA6BF' }
                    $fraction = [Math]::Min([double]1, ($value / $script:ceiling))
                    $gauge.AnimateTo($fraction)
                    $pointCount = [Math]::Max(1, $data.points.Count - 1)
                    $modelLayers.Children.Clear()
                    $totals = New-Object 'double[]' $data.points.Count
                    foreach ($series in $data.series) {
                        $fill = New-Object Windows.Media.PointCollection
                        $line = New-Object Windows.Media.PointCollection
                        $lower = New-Object Windows.Media.PointCollection
                        for ($i = 0; $i -lt $data.points.Count; $i++) {
                            $x = $i * 284.0 / $pointCount
                            # Normalize all bands together above the ceiling, preserving their proportions.
                            $scale = [Math]::Max($script:ceiling / 30, [double]$data.points[$i])
                            $lower.Add((New-Object Windows.Point($x, (53 - 50 * $totals[$i] / $scale))))
                            $totals[$i] += [double]$series.points[$i]
                            $point = New-Object Windows.Point($x, (53 - 50 * $totals[$i] / $scale))
                            $fill.Add($point); $line.Add($point)
                        }
                        for ($i = $lower.Count - 1; $i -ge 0; $i--) { $fill.Add($lower[$i]) }
                        if (($series.points | Measure-Object -Maximum).Maximum -gt 0) {
                            $area = New-Object Windows.Shapes.Polygon
                            $area.Points = $fill; $area.Fill = $series.color; $area.Opacity = 0.65
                            # Zero-width bands share the previous model's boundary. Do not
                            # stroke those intervals, including tiny rolling-sum residue.
                            $geometry = New-Object Windows.Media.StreamGeometry
                            $drawing = $geometry.Open()
                            try {
                                $drawing.BeginFigure($line[0], $false, $false)
                                for ($i = 1; $i -lt $line.Count; $i++) {
                                    $hasUsage = [double]$series.points[$i - 1] -gt 1e-12 -or [double]$series.points[$i] -gt 1e-12
                                    $drawing.LineTo($line[$i], $hasUsage, $false)
                                }
                            } finally { $drawing.Close() }
                            $geometry.Freeze()
                            $history = New-Object Windows.Shapes.Path
                            $history.Data = $geometry; $history.Stroke = $series.color; $history.StrokeThickness = 1
                            $modelLayers.Children.Add($area) | Out-Null
                            $modelLayers.Children.Add($history) | Out-Null
                        }
                    }
                    $activeModels = @($data.runningModels | Where-Object { $_.count -gt 0 })
                    $running.Inlines.Clear()
                    if ($activeModels.Count) {
                        $running.Inlines.Add((New-Object Windows.Documents.Run('Running: ')))
                        for ($i = 0; $i -lt $activeModels.Count; $i++) {
                            if ($i -gt 0) { $running.Inlines.Add((New-Object Windows.Documents.Run((' ' + [char]0x00B7 + ' ')))) }
                            $modelRun = New-Object Windows.Documents.Run(($activeModels[$i].label + ' x' + $activeModels[$i].count))
                            $modelRun.Foreground = $activeModels[$i].color
                            $running.Inlines.Add($modelRun)
                        }
                    }
                    $running.Visibility = if ($activeModels.Count) { 'Visible' } else { 'Collapsed' }
                    # Scroll one sample width between server samples using native animation.
                    $scroll = New-Object Windows.Media.Animation.DoubleAnimation(0, (-284.0 / $pointCount), ([TimeSpan]::FromSeconds(1)))
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
                $gauge.Reset(); $modelLayers.Children.Clear()
                $running.Text = ''; $running.Visibility = 'Collapsed'
                $chartMotion.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
            }
            $compactRate.Text = $rate.Text + ' /30s'
            $compactRate.ToolTip = $status.Text
            $compactRate.Foreground = if ($status.Text -eq 'Last 30s total - API equivalent') { '#F1F7FF' } else { '#F5BD73' }
            if (-not $script:request -and [DateTime]::UtcNow -ge $script:nextRequest) {
                $script:request = $client.GetStringAsync('http://127.0.0.1:47831/api/widget?minutes=' + [string]$script:historyMinutes)
                $script:nextRequest = [DateTime]::UtcNow.AddSeconds(1)
            }
            if (([DateTime]::UtcNow - $script:lastDiagnostic).TotalSeconds -ge 5) {
                $script:lastDiagnostic = [DateTime]::UtcNow
                $diagnostic = @{ pid = $PID; visible = $window.IsVisible; compact = $script:compact; left = $window.Left; top = $window.Top; width = $window.ActualWidth; height = $window.ActualHeight; lastGood = $script:lastGood.ToString('o'); rate = $rate.Text; status = $status.Text; running = $running.Text; ceiling = $script:ceiling; historyMinutes = $script:historyMinutes }
                [IO.File]::WriteAllText((Join-Path $stateRoot 'widget-status.json'), ($diagnostic | ConvertTo-Json), [Text.Encoding]::UTF8)
            }
            # Save one rendering for installation verification without capturing other apps.
            if (-not $script:snapshotSaved -and ([DateTime]::UtcNow - $script:startedAt).TotalSeconds -gt 3 -and $script:lastGood -gt [DateTime]::MinValue -and $window.IsVisible) {
                $window.UpdateLayout()
                $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
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
