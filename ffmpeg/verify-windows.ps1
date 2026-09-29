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
if ($license -notmatch 'GNU Lesser General Public License' -or $license -notmatch 'version 2.1') { throw 'Unexpected license' }
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
'Windows Server 2022 x64: binary checksum, LGPL license, PCM to AAC-LC MP4, two-chunk concat/recovery and WAV decoding passed.' | Set-Content validation.txt
gh release upload $env:RELEASE_TAG validation.txt --repo $env:BUILD_REPO
if ($LASTEXITCODE -ne 0) { throw 'Evidence upload failed' }
gh release edit $env:RELEASE_TAG --repo $env:BUILD_REPO --draft=false --latest=false
if ($LASTEXITCODE -ne 0) { throw 'Publishing verified dependency failed' }
