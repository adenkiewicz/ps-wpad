<#
.SYNOPSIS
    Serves modified WPAD file with extra redirection rules
.DESCRIPTION
    This script binds to :80 on loopback device and serves modified WPAD file.
    The original WPAD file might be your corporate WPAD, while the rules file
    is simple set of target=redirect values, each in new line. Lines starting
    with # are treated as comments and are ignored.

    You probably want to use Local Admin power to replace the location of WPAD
    file in Internet Options or use HOSTS file to make it point to localhost.

    Since returned WPAD is based on corporate PAC file, you will be able to
    reach normal network while having the chance to redirect selected hosts.

    This script injects rules in format:
        'if (shExpMatch(host, "' + $NAME + '")) return "PROXY ' + $REDIR + '";'
    where:
        NAME is the name of service to redirect
        REDIR is where the host is redirected, usually it is another proxy

.NOTES
    Author: Adrian Denkiewicz
#>

$wpad = 'C:\Path\To\Corporate\wpad.dat'
$rules = 'C:\Path\To\Your\wpad.rules'
$addr = [system.net.ipaddress]::Loopback
$port = 80

function parseRules {
    $config = @{}
    $content = Get-Content $rules
    foreach ($line in $content) {
        switch -regex ($line) {
            "^#.*" {
                # skip #'ed entries
                Write-Host ("Skipped: {0}" -f $matches[0])
                break
            }
            "(.*)=(.*)" {
                $target, $redirect = $matches[1..2]
                $config[$target] = $redirect
                Write-Host ("New rule: {0} -> {1}" -f $matches[1], $matches[2])
                break
            }
        }
    }

    return $config
}

$localRules = @()
$config = parseRules
foreach ($pair in $config.GetEnumerator()) {
    $localRules += 'if (shExpMatch(host, "' + $($pair.Name) +
        '")) return "PROXY ' + $($pair.Value) + '";'
}

$content = Get-Content $wpad
$pac = $content[0..1] + $localRules + $content[2..$content.length]

$contentLength = 0;
foreach ($line in $pac) {
    $contentLength += $line.length + 2; # 2 extra bytes for \r, \n
}

$headers = @('HTTP/1.1 200 OK', "Content-Length: $contentLength",
    'Content-Type: application/x-ns-proxy-autoconfig', 'Connection: Close', '')

$endpoint = New-Object System.Net.IPEndPoint($addr, $port)
$listener = New-Object System.Net.Sockets.TcpListener $endpoint
$listener.server.ReceiveTimeout = 3000
$listener.start()

try {
    while (1) {
        if (!$listener.Pending()) {
            Start-Sleep -Seconds 1
                continue;
        }

        $client = $listener.AcceptTcpClient()

        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader $stream
        $writer = New-Object System.IO.StreamWriter $stream

        Write-Host "New Connection..."

        while ($stream.DataAvailable) {
            $input = $reader.ReadLine() # we have to read, otherwise Browser is sad
        }

        foreach ($line in $headers) {
            try {
                $writer.WriteLine($line)
            }
            catch {
                Write-Error $_
                break
            }
        }

        foreach ($line in $pac) {
            try {
                $writer.WriteLine($line)
            }
            catch {
                Write-Error $_
                break
            }
        }

        $writer.dispose()
        $reader.dispose()
        $stream.dispose()
        $client.close()
    }

}

catch {
    Write-Error $_
}

finally {
    $listener.stop()
}
