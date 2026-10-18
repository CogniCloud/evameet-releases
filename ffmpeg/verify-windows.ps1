$ErrorActionPreference = 'Stop'
gh release download $env:RELEASE_TAG --repo $env:BUILD_REPO --dir .
if ($LASTEXITCODE -ne 0) { throw 'Download failed' }
Expand-Archive ffmpeg-8.0.3-evameet-win64.zip .
$binary = './ffmpeg-8.0.3-evameet-win64/bin/ffmpeg.exe'
$expected = (Get-Content SHA256SUMS.txt | Where-Object { $_ -match '/bin/ffmpeg.exe$' }) -split '\s+'
if ((Get-FileHash $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[0]) { throw 'Binary digest mismatch' }
& $binary -version
if ($LASTEXITCODE -ne 0) { throw 'Binary does not run' }
$license = & $binary -L 2>&1 | Out-String
Write-Host $license
if ($LASTEXITCODE -ne 0 -or $license -notmatch 'GNU Lesser General Public\s+License' -or $license -notmatch 'version\s+2\.1') { throw 'Unexpected license' }
& $binary -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=2' -ar 48000 -ac 2 -f f32le -y synthetic.pcm
if ($LASTEXITCODE -ne 0) { throw 'Synthetic PCM generation failed' }
& $binary -hide_banner -loglevel error -f f32le -ar 48000 -ac 2 -i synthetic.pcm -c:a aac -b:a 192k -profile:a aac_low -movflags +faststart -f mp4 -y first.mp4
if ($LASTEXITCODE -ne 0) { throw 'EvaMeet AAC-LC encoding failed' }
Copy-Item first.mp4 second.mp4
"file 'first.mp4'`nfile 'second.mp4'" | Set-Content concat.txt -Encoding ascii
& $binary -hide_banner -loglevel error -f concat -safe 0 -i concat.txt -c copy -y meeting.mp4
if ($LASTEXITCODE -ne 0) { throw 'EvaMeet finalization/recovery concat failed' }
& $binary -hide_banner -loglevel error -i meeting.mp4 -vn -acodec pcm_s16le -y decoded.wav
if ($LASTEXITCODE -ne 0 -or (Get-Item decoded.wav).Length -lt 700000) { throw 'EvaMeet import decode failed or duration truncated' }
$audioResult = 'Windows Server 2022 x64: binary checksum, LGPL license, PCM to AAC-LC MP4, two-chunk concat/recovery and WAV decoding passed.'

# VIDEO. The encoders EvaMeet tries, in its order, and the licence they must
# not change. A runner has no GPU: NVENC and AMF are checked as compiled in and
# as refusing cleanly, the way a post without that card refuses them.
$encoders = & $binary -hide_banner -encoders 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Encoder listing failed' }
foreach ($name in 'h264_nvenc', 'hevc_nvenc', 'h264_amf', 'hevc_amf', 'h264_mf', 'hevc_mf') {
  if ($encoders -notmatch "(?m)^\s*V\S{5}\s+$name\s") { throw "Video encoder missing: $name" }
}
if ($encoders -match '(?m)^\s*V\S{5}\s+lib(x264|x265|openh264)\s') { throw 'Unexpected software H.264/HEVC encoder' }
$configuration = & $binary -hide_banner -buildconf 2>&1 | Out-String
if ($configuration -match '--enable-(gpl|nonfree|version3)\b') { throw 'Licence-changing configure option' }
$devices = & $binary -hide_banner -f dshow -list_devices true -i dummy 2>&1 | Out-String
if ($devices -match 'Unknown input format') { throw 'DirectShow camera capture missing' }

# EvaMeet's probe of each encoder: five frames of a black pattern. A refusal
# must be an FFmpeg error, never a crash. FFmpeg exits with its own error code,
# an errno or an AVERROR, negative on Windows (-22 is EINVAL); a crash exits
# with an NTSTATUS such as 0xC0000005.
function Test-Crash([int]$code) { $code -ne 0 -and ('{0:X8}' -f $code) -like 'C000*' }
$probe = @('-hide_banner', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=black:s=640x360:r=30', '-frames:v', '5', '-an')
$probes = foreach ($candidate in 'h264_nvenc', 'h264_amf', 'h264_mf -hw_encoding 1', 'h264_mf') {
  $encoder = $candidate -split ' '
  & $binary @probe -c:v @encoder -pix_fmt nv12 -f null - 2> probe.log
  $code = $LASTEXITCODE
  if (Test-Crash $code) { Get-Content probe.log; throw "Encoder probe crashed: $candidate (0x$('{0:X8}' -f $code))" }
  $last = (Get-Content probe.log | Select-Object -Last 1) -replace '\s+', ' '
  "${candidate}: $(if ($code -eq 0) { 'usable' } else { "refused ($last)" })"
}

# Media Foundation, as EvaMeet films: two-second key frames, fragmented MP4
# segments listed in a CSV. Windows Server may lack Media Foundation or its
# H.264 encoder: install the feature when the runner allows. A recording that
# runs is checked in full; a clean refusal is recorded (posts run Windows 10
# and 11, where Media Foundation is part of the system); a crash fails.
$mfplat = Join-Path $env:SystemRoot 'System32\mfplat.dll'
$mfBefore = Test-Path $mfplat
if (-not $mfBefore -and (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) {
  Install-WindowsFeature Server-Media-Foundation -ErrorAction SilentlyContinue | Out-Null
}
$video = Join-Path $PWD 'video'
New-Item -ItemType Directory -Force $video | Out-Null
& $binary -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1280x720:rate=30' -t 7 -an `
  -vf 'fps=30,format=nv12' -c:v h264_mf -rate_control u_vbr -scenario camera_record `
  -b:v 2500k -maxrate 3750k -bufsize 5000k -g 60 -force_key_frames 'expr:gte(t,n_forced*2)' -pix_fmt nv12 `
  -f segment -segment_time 2 -segment_format mp4 -segment_format_options 'movflags=+frag_keyframe+empty_moov+default_base_moof' `
  -reset_timestamps 1 -segment_list_type csv -segment_list (Join-Path $video 'passe_001.csv') (Join-Path $video 'segment_%05d.mp4') 2> mf.log
$mfCode = $LASTEXITCODE
$mfLast = (Get-Content mf.log -ErrorAction SilentlyContinue | Select-Object -Last 1) -replace '\s+', ' '
if ($mfCode -eq 0) {
  $segments = @(Get-ChildItem $video -Filter 'segment_*.mp4')
  if ($segments.Count -lt 3) { throw "Expected at least three two-second segments, got $($segments.Count)" }
  foreach ($segment in $segments) {
    & $binary -hide_banner -loglevel error -i $segment.FullName -f null -
    if ($LASTEXITCODE -ne 0) { throw "Segment does not decode: $($segment.Name)" }
  }
  $listed = @(Get-Content (Join-Path $video 'passe_001.csv')).Count
  if ($listed -ne $segments.Count) { throw "Segment list has $listed entries for $($segments.Count) segments" }
  $origin = if ($mfBefore) { 'present on the runner' } else { 'installed by this job' }
  $videoResult = "Media Foundation H.264 ($origin): $($segments.Count) fragmented MP4 segments of two seconds, all listed, all decode."
} elseif (Test-Crash $mfCode) {
  Get-Content mf.log
  throw "Media Foundation recording crashed (0x$('{0:X8}' -f $mfCode))"
} else {
  $why = if (-not (Test-Path $mfplat)) { 'no Media Foundation on this runner' } elseif (-not $mfBefore) { 'Media Foundation installed by this job, not usable before a restart' } else { 'Media Foundation without a usable H.264 encoder on this Windows Server' }
  $videoResult = "h264_mf refused cleanly ($why): $mfLast. FFmpeg still ran the audio pipeline above."
}
@($audioResult, 'Video encoders compiled in: h264_nvenc, hevc_nvenc, h264_amf, hevc_amf, h264_mf, hevc_mf; no GPL, nonfree or version 3 option; DirectShow capture present.', $videoResult, 'Probes on this GPU-less runner:') + $probes | Set-Content validation.txt
Get-Content validation.txt
gh release upload $env:RELEASE_TAG validation.txt --repo $env:BUILD_REPO
if ($LASTEXITCODE -ne 0) { throw 'Evidence upload failed' }
gh release edit $env:RELEASE_TAG --repo $env:BUILD_REPO --draft=false --latest=false
if ($LASTEXITCODE -ne 0) { throw 'Publishing verified dependency failed' }
