# emp_control_panel.ps1 — Windows click-to-start panel (API + frontend together).
# Double-click companion: Start-EMP-Panel.bat  or  create desktop shortcut.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. "$PSScriptRoot\windows_r_utils.ps1"
Initialize-EMPPaths $PSScriptRoot
$Root = Get-EMPRepoRoot
Import-EMPRuntimeConfig
$ApiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
$WebPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { "8080" }

function Test-EmpUrl([string]$Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
    return ($r.StatusCode -eq 200)
  } catch { return $false }
}

function Get-EmpStatusText {
  $api = Test-EmpUrl "http://127.0.0.1:$ApiPort/api/health"
  $web = Test-EmpUrl "http://127.0.0.1:$WebPort/"
  if ($api -and $web) { return "状态：前后端均已运行  |  网页 http://127.0.0.1:$WebPort  |  API :$ApiPort" }
  if ($api -and -not $web) { return "状态：仅后端运行（前端未起来）— 请点「启动」" }
  if (-not $api -and $web) { return "状态：仅前端运行（后端未起来）— 请点「启动」" }
  return "状态：未启动 — 点击「启动」同时打开前端 + 后端"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "EasyMultiProfiler Web — 一键启动"
$form.Size = New-Object System.Drawing.Size(520, 260)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.TopMost = $false
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Location = New-Object System.Drawing.Point(16, 16)
$lbl.Size = New-Object System.Drawing.Size(470, 56)
$lbl.Text = Get-EmpStatusText

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "启动（前端 + 后端）"
$btnStart.Location = New-Object System.Drawing.Point(16, 88)
$btnStart.Size = New-Object System.Drawing.Size(220, 40)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "停止"
$btnStop.Location = New-Object System.Drawing.Point(252, 88)
$btnStop.Size = New-Object System.Drawing.Size(110, 40)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "打开网页"
$btnOpen.Location = New-Object System.Drawing.Point(378, 88)
$btnOpen.Size = New-Object System.Drawing.Size(110, 40)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Location = New-Object System.Drawing.Point(16, 148)
$lblHint.Size = New-Object System.Drawing.Size(470, 60)
$lblHint.ForeColor = [System.Drawing.Color]::DimGray
$lblHint.Text = "启动会同时拉起 R API (:$ApiPort) 与网页 (:$WebPort)，就绪后自动打开浏览器。`n关闭本窗口不会停止服务；要用「停止」或 Stop-EMP-Web-Windows.bat。"

$form.Controls.AddRange(@($lbl, $btnStart, $btnStop, $btnOpen, $lblHint))

$busy = $false
function Set-Busy([bool]$On) {
  $script:busy = $On
  $btnStart.Enabled = -not $On
  $btnStop.Enabled = -not $On
  $btnOpen.Enabled = -not $On
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ if (-not $script:busy) { $lbl.Text = Get-EmpStatusText } })
$timer.Start()

$btnStart.Add_Click({
  if ($script:busy) { return }
  Set-Busy $true
  $lbl.Text = "正在启动前端 + 后端，请稍候（首次加载 R 包可能要 30–90 秒）…"
  $form.Refresh()
  try {
    $launch = Join-Path $PSScriptRoot "launch_emp_web.ps1"
    # Separate process so the button UI stays alive while R/Python boot.
    $p = Start-Process -FilePath "powershell.exe" `
      -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (ConvertTo-EMPProcessArgument $launch), "-NoPause", "-CreateDesktopShortcut") `
      -WorkingDirectory $Root `
      -Wait `
      -PassThru `
      -WindowStyle Minimized
    if ($p.ExitCode -ne 0) { throw "launch_emp_web.ps1 exit $($p.ExitCode)" }
    $lbl.Text = Get-EmpStatusText
    if (-not (Test-EmpUrl "http://127.0.0.1:$ApiPort/api/health") -or -not (Test-EmpUrl "http://127.0.0.1:$WebPort/")) {
      throw "启动脚本已退出，但前后端未同时就绪。请查看 .local_run\api.log / web.log"
    }
    [System.Windows.Forms.MessageBox]::Show(
      "启动完成：前端 + 后端均已运行。",
      "EasyMultiProfiler",
      "OK",
      "Information"
    ) | Out-Null
  } catch {
    $lbl.Text = "启动失败：$($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
      "启动失败：`n$($_.Exception.Message)`n`n可查看 .local_run\api.log / web.log，或运行 Repair-and-Start-EMP-Web.bat",
      "EasyMultiProfiler",
      "OK",
      "Error"
    ) | Out-Null
  } finally {
    Set-Busy $false
    $lbl.Text = Get-EmpStatusText
  }
})

$btnStop.Add_Click({
  if ($script:busy) { return }
  Set-Busy $true
  $lbl.Text = "正在停止…"
  $form.Refresh()
  try {
    & "$PSScriptRoot\stop_local_windows.ps1"
    $lbl.Text = Get-EmpStatusText
  } catch {
    [System.Windows.Forms.MessageBox]::Show("停止失败：$($_.Exception.Message)", "EasyMultiProfiler", "OK", "Error") | Out-Null
  } finally {
    Set-Busy $false
    $lbl.Text = Get-EmpStatusText
  }
})

$btnOpen.Add_Click({
  Start-Process "http://127.0.0.1:$WebPort/"
})

$form.Add_FormClosed({ $timer.Stop() })
[void]$form.ShowDialog()
