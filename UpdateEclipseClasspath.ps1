$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition;
Set-Location -Path $scriptPath;

[string]$global:packagenamestart = "putnamehere";
[string]$global:comparisonpackagename = -join(" ", $global:packagenamestart);
[string]$global:spacestab = "    ";
[string]$global:srcstart = -join($global:spacestab, "<classpathentry kind=`"src`" path=`"");
[string]$global:srcend = "`"/>";
[string]$global:libstart = -join($global:spacestab, "<classpathentry kind=`"lib`" path=`"");
[string]$global:libfolder = "libs/";
[string]$global:libdirectend = "`"/>";
[string]$global:libsourcemiddle = -join("`" sourcepath=`"",$global:libfolder);
[string]$global:libpartialend = "`">";
[string]$global:libattributestart = -join($global:spacestab, $global:spacestab, "<attributes>");
[string]$global:libattributeend = -join($global:spacestab, $global:spacestab, "</attributes>");
[string]$global:libclasspathentryend = -join($global:spacestab, "</classpathentry>");
[string]$global:libbeforejavadoc=-join($global:spacestab, $global:spacestab, $global:spacestab, "<attribute name=`"javadoc_location`" value=`"jar:platform:/resource/");
[string]$global:libbetweenprojectnameandjavadoc=-join("/",$global:libfolder);
[string]$global:libafterjavadoc= "!/`"/>";
[string]$global:newline = "`r`n";
[string]$global:javadocfileend = "-javadoc.jar";
[string]$global:sourcefileend = "-sources.jar";


# TODO Maybe update project name too
function UpdateBuildProperties([string]$folderpath, [string[]]$srcfolders) {
    Write-Host $srcfolders;
    $buildstring = "";
    for ($i = 0; $i -lt $srcfolders.Length; $i++) {
        if ($i -gt 0) {
            $buildstring += ",";
        }
        $buildstring += -join($srcfolders[$i], "/");
    }
    $files = Get-ChildItem -Path $folderpath -File
    foreach ($file in $files) {
        if ($file.Name.ToLower().Equals("build.properties")) {
            [string]$path = [io.path]::combine($folderpath, $file);
            [string[]]$filecontent = Get-Content -Path $path;
            for ($line = 0; $line -lt $filecontent.Length; $line++) {
                if ($filecontent[$line].StartsWith("source..")) {
                    $filecontent[$line] = -join("source.. = ", $buildstring);
                    $filecontent | Set-Content -Path $path;
                    break;
                }
            }
            break;
        }
    }
}

function AddBundle([string[]]$projects, [int]$index) {
    if ($index -eq $projects.Count-1) {
        return -join(" ", $projects[$index]);
    }
    else {
        return -join(" ", $projects[$index], ",");
    }
}

function UpdateManifest([string]$folderpath, [string[]]$projects) {
    if ($projects.Count -eq 0) {
        return;
    }
    $folders = Get-ChildItem -Path $folderpath -Directory | Where-Object {$_.Name.Equals("META-INF")}
    foreach ($folder in $folders) {
        $files = Get-ChildItem -Path $folder.FullName -File | Where-Object {$_.Name.Equals("MANIFEST.MF")}
        #only one file 
        foreach ($file in $files) {
            [string[]]$filecontent = Get-Content -Path $file.FullName;
            foreach ($t in $filecontent) {
                Write-Host $t;
            }
            Write-Host "---------------------";
            [string[]]$newfilecontent = @();
            for ($i = 0; $i -lt $filecontent.Length; $i++) {
                if ($filecontent[$i].StartsWith("Require-Bundle:")) {
                    $bundle = AddBundle $projects 0
                    $newfilecontent += -join("Require-Bundle:", $bundle);
                    [int]$p = 1;
                    for ($j = $i+1; $j -lt $filecontent.Length; $j++) {
                        if ($filecontent[$j].StartsWith($global:comparisonpackagename)) {
                            if ($p -lt $projects.Count) {
                                $nbundle = AddBundle $projects $p
                                $newfilecontent += $nbundle;
                                $p++;
                            }
                            $i++;
                        }
                        else {
                            break;
                        }
                    }
                    while ($p -lt $projects.Count) {
                        $xbundle = AddBundle $projects $p
                        $newfilecontent += $xbundle;
                        $p++;
                    }
                } else {
                    $newfilecontent += $filecontent[$i];
                }
            }
            foreach ($tt in $newfilecontent) {
                Write-Host $tt;
            }
            Write-Host "---------------------";
            $newfilecontent | Set-Content -Path $file.FullName;
        }

    }
}

function GetMavenSourcePaths([string] $folderpath) {
    $srcmainjava = [io.path]::combine("src", "main", "java");
    $srcmainresources = [io.path]::combine("src", "main", "resources");
    $srcmainwebapp = [io.path]::combine("src", "main", "webapp");
    $srctestjava = [io.path]::combine("src", "test", "java");
    $srctestresources = [io.path]::combine("src", "test", "resources");
    $srcit = [io.path]::combine("src", "it");
    $folders = @($srcmainjava,$srcmainresources,$srcmainwebapp,$srctestjava,$srctestresources,$srcit);
    $existingfolders = @();
    foreach ($folder in $folders) {
        $fullfolder = [io.path]::combine($folderpath, $folder);
        if (Test-Path $fullfolder) {
            $files = Get-ChildItem -Path $fullfolder -Recurse -Force;
            if ($files.Length -gt 0) {
                $myPath = $folder -replace "\\", "/"
                $existingfolders += $myPath;
            }
        }
    }
    return $existingfolders;
}

function GetLibs([string]$folderpath, [int]$code) {
    $libsfolder = Get-ChildItem -Path $folderpath -Directory | Where-Object {$_.Name.Equals("libs")};
    [string[]]$libs = @();
    if ($libsfolder -and $libsfolder.Length -eq 1) {
        $libsf = $libsfolder[0].FullName; 
        if ($code -eq 0) {
            $libs = Get-ChildItem -Path $libsf -File | Where-Object {$_.Name.EndsWith(".jar") -and !$_.Name.EndsWith("-sources.jar") -and !$_.Name.EndsWith("-javadoc.jar")};
        }
        else {
            if ($code -eq 1) {
                $libs = Get-ChildItem -Path $libsf -File | Where-Object {$_.Name.EndsWith("-sources.jar")};
            }
            else {
                $libs = Get-ChildItem -Path $libsf -File | Where-Object {$_.Name.EndsWith("-javadoc.jar")};
            }
        }
    }
    return $libs;
}

function GetClassPathSrcEntries([string[]]$srcfolders) {
    [string[]]$res = @();
    foreach ($s in $srcfolders) {
        $res += -join($global:srcstart,$s,$global:srcend);
    }
    return $res;
}

#TODO efficiency with arrays

function UpdateClassPath([string]$folderpath, [string[]]$srcfolders) {
    $projectname = Split-Path $folderpath -Leaf;
    [string[]]$libs = GetLibs $folderpath 0;
    [string[]]$srclibs = GetLibs $folderpath 1;
    [string[]]$doclibs = GetLibs $folderpath 2;
    [bool]$first = $false; 
    $files = Get-ChildItem -Path $folderpath -File
    foreach ($file in $files) {
        if ($file.Name.ToLower().Equals(".classpath")) {
            [string]$path = [io.path]::combine($folderpath, $file)
            [string[]]$filecontent = Get-Content -Path $path;
            [string[]]$newfilecontentbefore = @();
            [string[]]$newfilecontentmiddle = @();
            [string[]]$newfilecontentafter = @();
            $classpathsrcentries = GetClassPathSrcEntries $srcfolders;
            foreach ($src in $classpathsrcentries) {
                $newfilecontentmiddle += $src;
            }
            foreach ($lib in $libs) {
                [string]$filename = [System.IO.Path]::GetFileNameWithoutExtension($lib);
                [string]$srcfilename = -join($filename, $global:sourcefileend);
                [string]$docfilename = -join($filename, $global:javadocfileend);
                if ($doclibs -contains $docfilename) {
                    if ($srclibs -contains $srcfilename) {
                        $newfilecontentmiddle += -join($global:libstart,$global:libfolder,$lib,$global:libsourcemiddle,$srcfilename,$global:libpartialend);
                    }
                    else {
                        $newfilecontentmiddle += -join($global:libstart,$global:libfolder,$lib,$global:libpartialend);
                    }
                    $newfilecontentmiddle += $global:libattributestart;
                    $newfilecontentmiddle += -join($global:libbeforejavadoc, $projectname, $global:libbetweenprojectnameandjavadoc, $docfilename, $global:libafterjavadoc);
                    $newfilecontentmiddle += $global:libattributeend;
                    $newfilecontentmiddle += $global:libclasspathentryend;
                } else {
                    if ($srclibs -contains $srcfilename) {
                        $newfilecontentmiddle += -join($global:libstart,$global:libfolder,$lib,$global:libsourcemiddle,$srcfilename,$global:libdirectend);
                    }
                    else {
                        $newfilecontentmiddle += -join($global:libstart,$global:libfolder,$lib,$global:libdirectend);
                    }
                }
            }
            for ($i=0; $i -lt $filecontent.Length; $i++) {
                [string]$str = $filecontent[$i].Trim(); #TODO format later
                if ($str.StartsWith($global:srcstart.Trim()) -or $str.StartsWith($global:libstart.Trim())) {
                    $first = $true;
                    if (!$str.EndsWith("/>")) {
                        for ($j = $i; $j -lt $filecontent.Length; $j++) {
                            [string]$str2 = $filecontent[$j].Trim();
                            if ($str2.Contains("</classpathentry>")) {
                                $i=$j;
                                break;
                            }
                        }
                    }
                }
                else {
                    if (!$first) {
                        $newfilecontentbefore += $filecontent[$i];
                    }
                    else {
                        $newfilecontentafter += $filecontent[$i];
                    }
                }
            }
            $filecontent = $newfilecontentbefore + $newfilecontentmiddle + $newfilecontentafter;
            foreach ($line in $filecontent) {
                Write-Host $line;
            }
            $filecontent | Set-Content -Path $path;
            break;
        }
    }
}

function UpdateAll([string] $folderpath) {
    
    [string[]]$folders = GetMavenSourcePaths $folderpath;
    Write-Host "`nStarting Update!`n";
    
    UpdateBuildProperties $folderpath $folders;
    UpdateClassPath $folderpath $folders;
}


$folders = Get-ChildItem -Directory;
foreach ($folder in $folders) {
    [string]$folderpath = $folder.FullName;
    foreach ($file in Get-ChildItem $folderpath -File)
	{
        [string]$filepath = $file.FullName;
        if ($filepath.EndsWith("pom.xml")) {
            [string[]]$projects = @();
            Write-Host $filepath;
            [xml]$pom = Get-Content -Path $filepath
            foreach ($i in $pom.project.dependencies.dependency.artifactId) {
                if ($i.StartsWith($global:packagenamestart)) {
                    Write-Host $i
                    $projects += $i;
                }
            }
            UpdateManifest $folderpath $projects
            #Write-Host $XmlDocument;
            UpdateAll $folderpath;
        }
    }
}