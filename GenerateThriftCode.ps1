# Don't use commented namespaces in thrift files (//namespace csharp => will be uncommented by this script) -> do //xnamespace csharp

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition;
Set-Location -Path $scriptPath;

[string]$global:thriftversion = "0.9.3";
[string]$global:javalang = "java";
[string]$global:csharplang = "csharp";
[string]$global:commentstring = "//";
[string]$global:namespacefind = "namespace ";
[string]$global:commentnamespacefind = -join($global:commentstring, $global:namespacefind);
[string]$global:javanamespacestart = "namespace java ";
[string]$global:javanamespaceafterprefix = "thriftContract.";
[string]$global:csharpnamespacestart = "namespace csharp ";
[string]$global:csharpnamespaceafterprefix = "ThriftContract.";
[string]$global:javadefaultnamespace = "thriftContract"; 
[string]$global:csharpdefaultnamespace = "ThriftContract"; # also the default folder in case a namespace was defined in the thrift file
[bool]$global:noseparation = $true; #put everything in the default folder
[bool]$global:usefoldernames = $true; #instead of file names
#[bool]$global:foldernameduplication = $false; TODO later to prevent creating to many folders

# <string, System.Collections.Generic.HashSet[string]>
$global:generatedNamespaceFileNameMap = @{};

function uncommentNamespaces([string] $file, [string[]] $filecontent) {
    for ($i=0; $i -lt $filecontent.Length; $i++) {
        if ($filecontent[$i].StartsWith($global:commentnamespacefind)) {
            $filecontent[$i] = $filecontent[$i].Substring(2);
        }
    }
    $filecontent | Set-Content -Path $file;
    return;
}

function commentNamespacesAndReturnLineNumberArray([string] $file, [string[]] $filecontent, [string] $lang) {
    $findstring = -join($global:namespacefind,$lang);
    $findstringcom = -join($global:commentnamespacefind,$lang);
    [int[]]$namespacelines = @();
    for ($i=0; $i -lt $filecontent.Length; $i++) {
        $str = $filecontent[$i].Trim();
        if ($str.StartsWith($findstring) -or $str.StartsWith($findstringcom)) {
            $namespacelines += $i; #expensive
        }
        if ($str.StartsWith($global:namespacefind)) {
            $filecontent[$i] = -join($global:commentstring, $str);
        }
    }
    $filecontent | Set-Content -Path $file;
    return $namespacelines;
}

function getNamespaceBeforePrefix([string] $lang) {
    if ($lang.Equals($global:javalang)) {
        return $global:javanamespacestart;
    }
    else {
        if ($lang.Equals($global:csharplang)) {
            return $global:csharpnamespacestart;
        }
    }
}
# Cuts down the 'namespace csharp Namespace' -> just 'Namespace'
function getNamespacePrefix([string] $namespace, [string] $lang) {
    [string]$prefix = "";
    if ($lang.Equals($global:javalang)) {
        $prefix = $namespace.Substring($global:javanamespacestart.Length-1).Trim();
    }
    else {
        if ($lang.Equals($global:csharplang)) {
            $prefix = $namespace.Substring($global:csharpnamespacestart.Length-1).Trim();
        }
    }
    if (-Not $prefix.Trim().Equals("")) {
        $prefix = -join($prefix, ".");
    }
    return $prefix;
}

function getParentFolderName([string] $file) {
    if (-Not $file.Contains("/") -And -Not $file.Contains("\")) {
        return "";
    }
    return Split-Path (Split-Path $file -Parent) -Leaf;
}

function getNamespaceSuffix([string] $file, [string] $lang) {
    [string]$filename = [System.IO.Path]::GetFileNameWithoutExtension($file);
    if ($global:usefoldernames) {
        [string]$filename = getParentFolderName $file;
    }
    [string]$namespacesuffix = "";
    if ($global:noseparation) {
        return $namespacesuffix;
    }
    if ($filename.Equals("")) {
        $filename = "..";
    }
    if ($lang.Equals($global:javalang)) {
        [string]$filename = $filename.ToLower();
        $namespacesuffix = -join($global:javanamespaceafterprefix, $filename);
    } else {
        if ($lang.Equals($global:csharplang)) {
            $filename = -join($filename.Substring(0,1).ToUpper(), $filename.Substring(1));
            $namespacesuffix = -join($global:csharpnamespaceafterprefix, $filename);
        }
    }
    $length = $namespacesuffix.Length;
    if ($namespacesuffix.EndsWith("..")) {
        return $namespacesuffix.Substring(0, $length-2)
    }
    if ($namespacesuffix.EndsWith("...")) {
        return $namespacesuffix.Substring(0, $length-3)
    }
    return $namespacesuffix;
}

function getIncludeFiles([string[]] $filecontent) {
    $r = "include `"";
    $rt = "../";
    [string[]]$files = @();
    for ($i=0; $i -lt $filecontent.Length; $i++) {
        if ($filecontent[$i].StartsWith($r)) {
            [string]$l = $filecontent[$i];
            [int]$length = ($l.Length - 1 - $r.Length);
            [string]$file = $l.Substring($r.Length, $length);
            if ($file.StartsWith($rt)) {
                $file = $file.Substring($rt.Length);
            }
            $files += $file; #expensive for many files
        }
    }
    return $files;
}

#Only for common files
# they should not have includes
function setNamespaceAndGenerate([string] $file, [string] $namespace, [string] $lang) {
    [string[]]$filecontent = Get-Content -Path $file;
    [int[]]$namespacelines = commentNamespacesAndReturnLineNumberArray $file $filecontent $lang;
    if ($namespacelines.Length -ne 0) {
        Write-Host "Included files cannot have namespace declarations";
        uncommentNamespaces $file $filecontent;
        return $false;
    }
    [int]$line = 0;
    for ($i=0; $i -lt $filecontent.Length; $i++) {
        if ($filecontent[$i].Trim().Equals("")) {
            $line = $i
            break;
        }
    }
    $filecontent[$line] = $namespace;
    $filecontent | Set-Content -Path $file;
    if ($global:generatedNamespaceFileNameMap.ContainsKey($namespace)) {
        if ($global:generatedNamespaceFileNameMap[$namespace].Contains($file)) {
            Write-Host "`nAlready generated File: "$file" with Namespace: "$namespace`n;
            return $true;
        }
        else {
            $global:generatedNamespaceFileNameMap[$namespace].Add($file);
        }
    }
    else {
        $list = New-Object 'System.Collections.Generic.HashSet[string]';
        $list.Add($file);
        $global:generatedNamespaceFileNameMap.Add($namespace, $list);
    }
    Write-Host "ThriftCommand (Included File): ..\thrift-$global:thriftversion.exe -out gen-Contract/$lang --gen $lang $file";
    $exe = "..\thrift-$global:thriftversion.exe";
    &$exe -out gen-Contract/$lang --gen $lang $file;
    return $true;
}

function cleanNamespace([string] $file) {
    [string[]]$filecontent = Get-Content -Path $file;
    for ($i=0; $i -lt $filecontent.Length; $i++) {
        if ($filecontent[$i].StartsWith($global:namespacefind)) {
            $filecontent[$i] = "";
        }
    }
    $filecontent | Set-Content -Path $file;
    return;
}

function getActualNamespace([string]$prefix, [string]$suffix, [string]$lang) {
    if ($prefix.EndsWith(".") -and $suffix.Equals("")) {
        if ($global:noseparation) {
            return $prefix.Substring(0, $prefix.Length-1);
        }
        if ($lang.Equals($global:javalang)) {
            $suffix = $global:javadefaultnamespace;
        } else {
            if ($lang.Equals($global:csharplang)) {
                $suffix = $global:csharpdefaultnamespace;
            }
        }
    }
    [string]$actualnamespace = -join($prefix, $suffix);
    if ($actualnamespace.Trim().Equals("")) {
        if ($lang.Equals($global:javalang)) {
            return $global:javadefaultnamespace;
        } else {
            if ($lang.Equals($global:csharplang)) {
                return $global:csharpdefaultnamespace;
            }
        }
    }
    return $actualnamespace;
}

function getCorrectPath([string] $includefile, [string] $parentfile) {
    $correctpath = $includefile;
    [string]$parentfolder = getParentFolderName $includefile; 
    if ($parentfolder.Equals("")) {
        [string]$higherparentfolder = getParentFolderName $file;                
        $correctpath = Join-Path $higherparentfolder -ChildPath $includefile;
    }
    return $correctpath;
}

# only include common for now!
function generateCode([string] $file, [string] $lang) {
    [string[]]$filecontent = Get-Content -Path $file;
    [int[]]$namespacelines = commentNamespacesAndReturnLineNumberArray $file $filecontent $lang;
    if ($namespacelines.Length -eq 0) {
        return;
    }
    foreach ($line in $namespacelines) {
        [string]$namespacesx1 = getNamespaceSuffix $file $lang
        [string]$originalnamespace = $filecontent[$line];
        [string]$uncomoriginal = $filecontent[$line].Substring(2).Trim();
        [string]$nn = getNamespaceBeforePrefix $lang;
        if ($uncomoriginal.Trim().Equals($nn.Trim())) {
            [string]$nam = getActualNamespace "" $namespacesx1 $lang 
            $filecontent[$line] = -join($nn, $nam);
        }
        else {
            if ($namespacesx1.Trim().Equals("")) {
                $filecontent[$line] = $uncomoriginal;
            } 
            else {
                $filecontent[$line] = -join($uncomoriginal, ".",$namespacesx1);
            }
        }
        Write-Host "`nThrift File: $file";
        Write-Host "Full Namespace:"$filecontent[$line];
        $filecontent | Set-Content -Path $file;
        $includefiles = getIncludeFiles $filecontent;
        Write-Host "`nStart Include Files.";
        foreach ($includefile in $includefiles) {
            $includefile = getCorrectPath $includefile $file
            Write-Host "Included Thrift File: $includefile";
            [string]$namespacebp = getNamespaceBeforePrefix $lang;
            [string]$namespacep = getNamespacePrefix $uncomoriginal $lang
            [string]$namespacesx = getNamespaceSuffix $includefile $lang
            [string]$actualnamespace = getActualNamespace $namespacep $namespacesx $lang
            [string]$finalnamespace = -join($namespacebp, $actualnamespace)
            Write-Host "Full Namespace: $finalnamespace";
            [bool]$success = setNamespaceAndGenerate $includefile $finalnamespace $lang;
            if (!$success) {
                Write-Host "`n`nCannot generate the included file so stopping everything!`n`n"
                $filecontent[$line] = $originalnamespace;
                foreach ($includefile in $includefiles) {
                    $includefile = getCorrectPath $includefile $file 
                    cleanNamespace $includefile;
                }
                uncommentNamespaces $file $filecontent
                return;
            }
        }
        Write-Host "End Include Files.`n";
        Write-Host "Thrift Command: ..\thrift-$global:thriftversion.exe -out gen-Contract/$lang --gen $lang $file";
        $exe = "..\thrift-$global:thriftversion.exe";
        &$exe -out gen-Contract/$lang --gen $lang $file;
        $filecontent[$line] = $originalnamespace;
        foreach ($includefile in $includefiles) {
            $includefile = getCorrectPath $includefile $file
            cleanNamespace $includefile;
        }
    }
    uncommentNamespaces $file $filecontent
    return;
}
# Here the code generation starts
# All *.thrift files are collected and then code is generated for each file
$thriftfiles = Get-ChildItem -Path *.thrift -Recurse -Force;
foreach ($file in $thriftfiles) {
    $filepath = $file.FullName;
    Write-Host "File Path: $filepath`n";
    generateCode $filepath $global:javalang;
    generateCode $filepath $global:csharplang;
}

