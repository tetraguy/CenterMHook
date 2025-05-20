# Center-M Hook is a tool to remap MSI Center M button in your Claw to any application you want.

# Admin Rights Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
	[System.Windows.Forms.MessageBox]::Show("Adrenaline Hook must be run as Administrator for full functionality.", "Admin Rights Required", "OK", "Warning")
	
	exit
}

Add-Type -AssemblyName System.Windows.Forms

$msiApp = Get-AppxPackage | ForEach-Object {
	$manifestPath = Join-Path $_.InstallLocation "AppxManifest.xml"
	if (Test-Path $manifestPath)
	{
		try
		{
			[xml]$manifest = Get-Content $manifestPath -ErrorAction Stop
			$displayName = $manifest.Package.Properties.DisplayName
			
			if ($displayName -eq "MSI Center M")
			{
				return $_
			}
		}
		catch
		{
			
		}
	}
}

if ($msiApp)
{
	$result = [System.Windows.Forms.MessageBox]::Show(
		"MSI Center M must be uninstalled for this tool to work. Do you want to uninstall it?",
		"MSI Center M Detected",
		[System.Windows.Forms.MessageBoxButtons]::YesNo,
		[System.Windows.Forms.MessageBoxIcon]::Warning
	)
	
	if ($result -eq [System.Windows.Forms.DialogResult]::Yes)
	{
		try
		{
			Remove-AppxPackage -Package $msiApp.PackageFullName -ErrorAction Stop
			[System.Windows.Forms.MessageBox]::Show("MSI Center M has been uninstalled.", "Uninstallation Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
		}
		catch
		{
			[System.Windows.Forms.MessageBox]::Show("Failed to uninstall MSI Center M.`nError: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
		}
	}
	else
	{
		[System.Windows.Forms.MessageBox]::Show("It is required to uninstall MSI Center M in order to re-map the button.", "Uninstallation Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
		exit
	}
}

Add-Type -AssemblyName "System.EnterpriseServices"
$publish = [System.EnterpriseServices.Internal.Publish]::new()

$dlls = @(
	'System.Memory.dll',
	'System.Numerics.Vectors.dll',
	'System.Runtime.CompilerServices.Unsafe.dll',
	'System.Security.Principal.Windows.dll'
)

foreach ($dll in $dlls)
{
	$dllPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\$dll"
	$publish.GacInstall($dllPath)
}

Add-Type -AssemblyName PresentationFramework

function Check-ForUpdate
{
	$repo = "https://api.github.com/repos/tetraguy/CenterMHook/releases/latest"
	try
	{
		$response = Invoke-RestMethod -Uri $repo -UseBasicParsing
		$latest = $response.tag_name
		$htmlUrl = $response.html_url
		$current = "1.0.0" # actual version
		
		if ($latest -ne $current)
		{
			$popup = New-Object Windows.Forms.Form
			$popup.Text = "Update Available"
			$popup.Size = New-Object Drawing.Size(400, 150)
			$popup.StartPosition = "CenterParent"
			$popup.FormBorderStyle = 'FixedDialog'
			$popup.MaximizeBox = $false
			$popup.MinimizeBox = $false
			
			$label = New-Object Windows.Forms.Label
			$label.Text = "A new version ($latest) is available."
			$label.SetBounds(10, 20, 380, 30)
			
			$btnDownload = New-Object Windows.Forms.Button
			$btnDownload.Text = "Download Update"
			$btnDownload.SetBounds(80, 60, 120, 30)
			$btnDownload.Add_Click({
					Start-Process $htmlUrl
					$popup.Close()
				})
			
			$btnNotNow = New-Object Windows.Forms.Button
			$btnNotNow.Text = "Not Now"
			$btnNotNow.SetBounds(210, 60, 120, 30)
			$btnNotNow.Add_Click({ $popup.Close() })
			
			$popup.Controls.AddRange(@($label, $btnDownload, $btnNotNow))
			$popup.ShowDialog() | Out-Null
		}
	}
	catch
	{
		Write-Log "Update check failed: $_"
	}
}

Check-ForUpdate

$appName = "MSI Center M"
$msiApp = Get-AppxPackage | Where-Object { $_.Name -like "*MSICenterM*" -or $_.Name -like "*MSI*" -and $_.PackageFullName -like "*MSICenterM*" }

if ($msiApp)
{
	$result = [System.Windows.MessageBox]::Show("MSI Center M must be uninstalled for this tool to work. Do you want to uninstall it?", "MSI Center M Detected", "YesNo", "Warning")
	
	if ($result -eq "Yes")
	{
		# Uninstall the app
		try
		{
			Remove-AppxPackage -Package $msiApp.PackageFullName -ErrorAction Stop
			[System.Windows.MessageBox]::Show("MSI Center M has been uninstalled successfully.", "Uninstallation Complete", "OK", "Information")
		}
		catch
		{
			[System.Windows.MessageBox]::Show("Failed to uninstall MSI Center M: $_", "Error", "OK", "Error")
		}
	}
	else
	{
		[System.Windows.MessageBox]::Show("It is required to uninstall MSI Center M in order to re-map the button.", "Uninstallation Required", "OK", "Error")
		exit
	}
}
else
{
	Write-Host "MSI Center M is not installed."
}

$form_Load={
}

#region Control Helper Functions
function Update-ListViewColumnSort
{
<#
	.SYNOPSIS
		Sort the ListView's item using the specified column.
	
	.DESCRIPTION
		Sort the ListView's item using the specified column.
		This function uses Add-Type to define a class that sort the items.
		The ListView's Tag property is used to keep track of the sorting.
	
	.PARAMETER ListView
		The ListView control to sort.
	
	.PARAMETER ColumnIndex
		The index of the column to use for sorting.
	
	.PARAMETER SortOrder
		The direction to sort the items. If not specified or set to None, it will toggle.
	
	.EXAMPLE
		Update-ListViewColumnSort -ListView $listview1 -ColumnIndex 0
	
	.NOTES
		Additional information about the function.
#>
	
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNull()]
		[System.Windows.Forms.ListView]
		$ListView,
		[Parameter(Mandatory = $true)]
		[int]
		$ColumnIndex,
		[System.Windows.Forms.SortOrder]
		$SortOrder = 'None'
	)
	
	if (($ListView.Items.Count -eq 0) -or ($ColumnIndex -lt 0) -or ($ColumnIndex -ge $ListView.Columns.Count))
	{
		return;
	}
	
	#region Define ListViewItemComparer
	try
	{
		[ListViewItemComparer] | Out-Null
	}
	catch
	{
		Add-Type -ReferencedAssemblies ('System.Windows.Forms') -TypeDefinition  @" 
	using System;
	using System.Windows.Forms;
	using System.Collections;
	public class ListViewItemComparer : IComparer
	{
	    public int column;
	    public SortOrder sortOrder;
	    public ListViewItemComparer()
	    {
	        column = 0;
			sortOrder = SortOrder.Ascending;
	    }
	    public ListViewItemComparer(int column, SortOrder sort)
	    {
	        this.column = column;
			sortOrder = sort;
	    }
	    public int Compare(object x, object y)
	    {
			if(column >= ((ListViewItem)x).SubItems.Count)
				return  sortOrder == SortOrder.Ascending ? -1 : 1;
		
			if(column >= ((ListViewItem)y).SubItems.Count)
				return sortOrder == SortOrder.Ascending ? 1 : -1;
		
			if(sortOrder == SortOrder.Ascending)
	        	return String.Compare(((ListViewItem)x).SubItems[column].Text, ((ListViewItem)y).SubItems[column].Text);
			else
				return String.Compare(((ListViewItem)y).SubItems[column].Text, ((ListViewItem)x).SubItems[column].Text);
	    }
	}
"@ | Out-Null
	}
	#endregion
	
	if ($ListView.Tag -is [ListViewItemComparer])
	{
		#Toggle the Sort Order
		if ($SortOrder -eq [System.Windows.Forms.SortOrder]::None)
		{
			if ($ListView.Tag.column -eq $ColumnIndex -and $ListView.Tag.sortOrder -eq 'Ascending')
			{
				$ListView.Tag.sortOrder = 'Descending'
			}
			else
			{
				$ListView.Tag.sortOrder = 'Ascending'
			}
		}
		else
		{
			$ListView.Tag.sortOrder = $SortOrder
		}
		
		$ListView.Tag.column = $ColumnIndex
		$ListView.Sort() #Sort the items
	}
	else
	{
		if ($SortOrder -eq [System.Windows.Forms.SortOrder]::None)
		{
			$SortOrder = [System.Windows.Forms.SortOrder]::Ascending
		}
		
		#Set to Tag because for some reason in PowerShell ListViewItemSorter prop returns null
		$ListView.Tag = New-Object ListViewItemComparer ($ColumnIndex, $SortOrder)
		$ListView.ListViewItemSorter = $ListView.Tag #Automatically sorts
	}
}



function Add-ListViewItem
{
<#
	.SYNOPSIS
		Adds the item(s) to the ListView and stores the object in the ListViewItem's Tag property.

	.DESCRIPTION
		Adds the item(s) to the ListView and stores the object in the ListViewItem's Tag property.

	.PARAMETER ListView
		The ListView control to add the items to.

	.PARAMETER Items
		The object or objects you wish to load into the ListView's Items collection.
		
	.PARAMETER  ImageIndex
		The index of a predefined image in the ListView's ImageList.
	
	.PARAMETER  SubItems
		List of strings to add as Subitems.
	
	.PARAMETER Group
		The group to place the item(s) in.
	
	.PARAMETER Clear
		This switch clears the ListView's Items before adding the new item(s).
	
	.EXAMPLE
		Add-ListViewItem -ListView $listview1 -Items "Test" -Group $listview1.Groups[0] -ImageIndex 0 -SubItems "Installed"
#>
	
	Param( 
	[ValidateNotNull()]
	[Parameter(Mandatory=$true)]
	[System.Windows.Forms.ListView]$ListView,
	[ValidateNotNull()]
	[Parameter(Mandatory=$true)]
	$Items,
	[int]$ImageIndex = -1,
	[string[]]$SubItems,
	$Group,
	[switch]$Clear)
	
	if($Clear)
	{
		$ListView.Items.Clear();
    }
    
    $lvGroup = $null
    if ($Group -is [System.Windows.Forms.ListViewGroup])
    {
        $lvGroup = $Group
    }
    elseif ($Group -is [string])
    {
        #$lvGroup = $ListView.Group[$Group] # Case sensitive
        foreach ($groupItem in $ListView.Groups)
        {
            if ($groupItem.Name -eq $Group)
            {
                $lvGroup = $groupItem
                break
            }
        }
        
        if ($null -eq $lvGroup)
        {
            $lvGroup = $ListView.Groups.Add($Group, $Group)
        }
    }
    
	if($Items -is [Array])
	{
		$ListView.BeginUpdate()
		foreach ($item in $Items)
		{		
			$listitem  = $ListView.Items.Add($item.ToString(), $ImageIndex)
			#Store the object in the Tag
			$listitem.Tag = $item
			
			if($null -ne $SubItems)
			{
				$listitem.SubItems.AddRange($SubItems)
			}
			
			if($null -ne $lvGroup)
			{
				$listitem.Group = $lvGroup
			}
		}
		$ListView.EndUpdate()
	}
	else
	{
		$listitem  = $ListView.Items.Add($Items.ToString(), $ImageIndex)
		$listitem.Tag = $Items
		
		if($null -ne $SubItems)
		{
			$listitem.SubItems.AddRange($SubItems)
		}
		
		if($null -ne $lvGroup)
		{
			$listitem.Group = $lvGroup
		}
	}
}


$buttonSearch_Click={
	
	$searchTerm = $txtSearch.Text.Trim()
	if (-not $searchTerm)
	{
		[System.Windows.Forms.MessageBox]::Show("Please enter a search term.", "Notice", "OK", "Information")
		return
	}
	$listView.Items.Clear()
	
	$paths = @(
		"HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
		"HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
	)
	foreach ($path in $paths)
	{
		Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$searchTerm*" } | ForEach-Object {
			if ($_.DisplayName -and $_.InstallLocation -and (Test-Path $_.InstallLocation))
			{
				$exePath = Get-ChildItem $_.InstallLocation -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
				if ($exePath)
				{
					$item = $listView.Items.Add($_.DisplayName)
					$item.SubItems.Add($exePath.FullName)
					$item.Tag = @{ image_info = $exePath.FullName }
					
				}
			}
		}
	}
	
	Get-AppxPackage | Where-Object { $_.Name -like "*$searchTerm*" } | ForEach-Object {
		$manifestPath = Join-Path $_.InstallLocation "AppxManifest.xml"
		if (Test-Path $manifestPath)
		{
			try
			{
				[xml]$manifest = Get-Content $manifestPath -ErrorAction Stop
				$displayName = $manifest.Package.Properties.DisplayName
				if ($displayName -match "(?i)ms-resource|WindowsAppRuntime|AppManifest|DisplayName")
				{
					return
				}
				
				$logoPath = $manifest.Package.Properties.Logo
				$fullLogoPath = Join-Path $_.InstallLocation $logoPath
				$gameConfigPath = Join-Path $_.InstallLocation "MicrosoftGame.config"
				$exePath = $null
				
				if (Test-Path $gameConfigPath)
				{
					[xml]$gameConfig = Get-Content $gameConfigPath -ErrorAction Stop
					$exeName = $gameConfig.SelectSingleNode("//ExecutableList/Executable").Name
					if ($exeName)
					{
						$exeFile = Get-ChildItem -Path $_.InstallLocation -Recurse -Filter $exeName -ErrorAction SilentlyContinue | Select-Object -First 1
						if ($exeFile)
						{
							$exePath = $exeFile.FullName
						}
					}
				}
				
				if (-not $exePath)
				{
					$exeFile = Get-ChildItem $_.InstallLocation -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
					if ($exeFile)
					{
						$exePath = $exeFile.FullName
					}
				}
				
				if ($exePath -and (Test-Path $exePath))
				{
					$item = $listView.Items.Add($displayName)
					$item.SubItems.Add($exePath)
					$item.Tag = @{ image_info = $fullLogoPath }
					
					if ($existingGameTitles -contains $displayName)
					{
						$item.ForeColor = [System.Drawing.Color]::DarkRed
					}
				}
			}
			catch
			{
				Write-Warning "Could not read manifest or config for $($_.Name)"
			}
		}
	}
	
	$contextMenu = New-Object System.Windows.Forms.ContextMenu
	$menuHook = New-Object System.Windows.Forms.MenuItem "Hook This"
	$menuOpen = New-Object System.Windows.Forms.MenuItem "Open Install Location"
	
	$menuHook.add_Click({
			$item = $listView.SelectedItems[0]
			[System.Windows.Forms.MessageBox]::Show("To hook: " + $item.Text + ", click on the checkbox next to it and click on Hook Applicatio(s).")
		})
	
	$menuOpen.add_Click({
			$path = $listView.SelectedItems[0].SubItems[1].Text
			if (Test-Path $path)
			{
				Start-Process -FilePath (Split-Path $path -Parent)
			}
		})
	
	$contextMenu.MenuItems.AddRange(@($menuHook, $menuOpen))
	$listView.ContextMenu = $contextMenu
}

$buttonHookSelection_Click={
	
	$selectedItems = $listView.CheckedItems | ForEach-Object {
		[PSCustomObject]@{
			Name  = $_.Text
			Path  = $_.SubItems[1].Text
			Image = $_.Tag.image_info
		}
	}
	
	$exePath = $selectedItems.Path
	
	if ($selectedItems.Count -eq 0)
	{
		[System.Windows.Forms.MessageBox]::Show("No items selected!", "Error", "OK", "Error")
		return
	}
	
	$msg = "Do you want to hook the following app?`n`n" + ($selectedItems | ForEach-Object { " `n - " + $_.Name }) -join "`n"
	$result = [System.Windows.Forms.MessageBox]::Show($msg, "Confirm", "YesNo", "Question")
	
	if ($result -eq "No")
	{
		[System.Windows.Forms.MessageBox]::Show("Hook Aborted!", "Canceled", "OK", "Information")
		return
	}
	
	$protocolKey = "HKCU:\Software\Classes\msi-mcm"
	
	if (Test-Path $protocolKey)
	{
		$backupPath = "$env:USERPROFILE\Desktop\msi-mcm-backup.reg"
		reg export "HKCU\Software\Classes\msi-mcm" "$backupPath" /y
		Write-Host "Backup of existing protocol handler saved to $backupPath"
	}

	Remove-Item -Path $protocolKey -Recurse -Force -ErrorAction SilentlyContinue

	New-Item -Path $protocolKey -Force | Out-Null
	Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Custom MSI MCM Protocol"
	Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""

	$commandPath = Join-Path $protocolKey "shell\open\command"
	New-Item -Path $commandPath -Force | Out-Null
	Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "`"$exePath`" `"%1`""
	
	[System.Windows.Forms.MessageBox]::Show("$title hooked successfully!", "Success", "OK", "Information")
	
}

$buttonHookProgramManually_Click= {
	
	while ($true)
	{
		$dialog = New-Object Windows.Forms.OpenFileDialog
		$dialog.Filter = "Executable Files (*.exe)|*.exe"
		$dialog.InitialDirectory = "c:\"
		$dialog.Title = "Select an Executable"
		if ($dialog.ShowDialog() -eq "OK")
		{
			$exePath = $dialog.FileName
			$exeName = [System.IO.Path]::GetFileName($exePath)
			$title = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
			$result = [System.Windows.Forms.MessageBox]::Show("Do you want to hook '$exeName' to Center M button?", "Confirm", "YesNo", "Question")
			if ($result -eq "Yes")
			{

				$protocolKey = "HKCU:\Software\Classes\msi-mcm"

				if (Test-Path $protocolKey)
				{
					$backupPath = "$env:USERPROFILE\Desktop\msi-mcm-backup.reg"
					reg export "HKCU\Software\Classes\msi-mcm" "$backupPath" /y
					Write-Host "Backup of existing protocol handler saved to $backupPath"
				}

				Remove-Item -Path $protocolKey -Recurse -Force -ErrorAction SilentlyContinue

				New-Item -Path $protocolKey -Force | Out-Null
				Set-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:Custom MSI MCM Protocol"
				Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""
				$commandPath = Join-Path $protocolKey "shell\open\command"
				New-Item -Path $commandPath -Force | Out-Null
				Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "`"$exePath`" `"%1`""
				
				[System.Windows.Forms.MessageBox]::Show("$title hooked successfully!", "Success", "OK", "Information")
				break
				
			}
			else
			{
				break
			}
		}
	}
}

$buttonScanUWPApps_Click = {
			
			
			$listView.Items.Clear()
			$contextMenu = New-Object System.Windows.Forms.ContextMenu
			$menuHook = New-Object System.Windows.Forms.MenuItem "Hook This"
			$menuOpen = New-Object System.Windows.Forms.MenuItem "Open Install Location"
			$menuDetails = New-Object System.Windows.Forms.MenuItem "Application Details"
			
			$menuHook.add_Click({
					$item = $listView.SelectedItems[0]
					[System.Windows.Forms.MessageBox]::Show("To hook: " + $item.Text + ", click on the checkbox next to it and click on Hook Applicatio(s).")
				})
			
			$menuOpen.add_Click({
					$path = $listView.SelectedItems[0].SubItems[1].Text
					if (Test-Path $path)
					{
						Start-Process -FilePath (Split-Path $path -Parent)
					}
				})
			
			$menuDetails.add_Click({
					$item = $listView.SelectedItems[0]
					$appName = $item.Text
					$installPath = $item.SubItems[1].Text
					$logoPath = $item.Tag.image_info
					$publisher = $item.Tag.publisher
					$version = $item.Tag.version
					$architecture = $item.Tag.architecture
					
					$detailsForm = New-Object Windows.Forms.Form
					$detailsForm.Text = "Application Details"
					$detailsForm.Size = New-Object Drawing.Size(400, 300)
					$detailsForm.StartPosition = "CenterParent"
					$detailsForm.FormBorderStyle = 'FixedDialog'
					$detailsForm.MaximizeBox = $false
					$detailsForm.MinimizeBox = $false
					
					
					if (Test-Path $logoPath)
					{
						$logo = New-Object Windows.Forms.PictureBox
						$logo.Image = [System.Drawing.Image]::FromFile($logoPath)
						$logo.SizeMode = 'Zoom'
						$logo.SetBounds(10, 10, 64, 64)
						$detailsForm.Controls.Add($logo)
					}
					
					$lblName = New-Object Windows.Forms.Label
					$lblName.Text = "Application Name: $appName"
					$lblName.SetBounds(80, 10, 300, 20)
					
					$lblPublisher = New-Object Windows.Forms.Label
					$lblPublisher.Text = "Publisher: $publisher"
					$lblPublisher.SetBounds(80, 40, 300, 20)
					
					$lblPath = New-Object Windows.Forms.Label
					$lblPath.Text = "Install Location: $installPath"
					$lblPath.SetBounds(80, 70, 300, 20)
					
					$lblVersion = New-Object Windows.Forms.Label
					$lblVersion.Text = "Version: $version"
					$lblVersion.SetBounds(80, 100, 300, 20)
					
					$lblArch = New-Object Windows.Forms.Label
					$lblArch.Text = "Architecture: $architecture"
					$lblArch.SetBounds(80, 130, 300, 20)
					
					$btnClose = New-Object Windows.Forms.Button
					$btnClose.Text = "Close"
					$btnClose.SetBounds(150, 220, 100, 30)
					$btnClose.Add_Click({ $detailsForm.Close() })
					
					$detailsForm.Controls.AddRange(@($lblName, $lblPublisher, $lblPath, $lblVersion, $lblArch, $btnClose))
					$detailsForm.ShowDialog() | Out-Null
				})
			
			$contextMenu.MenuItems.AddRange(@($menuHook, $menuOpen, $menuDetails))
			$listView.ContextMenu = $contextMenu

			Get-AppxPackage | ForEach-Object {
				$manifestPath = Join-Path $_.InstallLocation "AppxManifest.xml"
				if (Test-Path $manifestPath)
				{
					try
					{
						[xml]$manifest = Get-Content $manifestPath -ErrorAction Stop
						$displayName = $manifest.Package.Properties.DisplayName

						if ($displayName -match "(?i)ms-resource|WindowsAppRuntime|AppManifest|DisplayName")
						{
							return
						}
						
						$logoPath = $manifest.Package.Properties.Logo
						$fullLogoPath = Join-Path $_.InstallLocation $logoPath
						
						$gameConfigPath = Join-Path $_.InstallLocation "MicrosoftGame.config"
						$exePath = $null
						if (Test-Path $gameConfigPath)
						{
							[xml]$gameConfig = Get-Content $gameConfigPath -ErrorAction Stop
							$exeName = $gameConfig.SelectSingleNode("//ExecutableList/Executable").Name
							if ($exeName)
							{
								$exeFile = Get-ChildItem -Path $_.InstallLocation -Recurse -Filter $exeName -ErrorAction SilentlyContinue | Select-Object -First 1
								if ($exeFile)
								{
									$exePath = $exeFile.FullName
								}
							}
						}
						
						if (-not $exePath)
						{
							$exeFile = Get-ChildItem $_.InstallLocation -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
							if ($exeFile)
							{
								$exePath = $exeFile.FullName
							}
						}
						
						if ($exePath -and (Test-Path $exePath))
						{
							$publisher = $_.Publisher -replace '.*CN=', ''
							$version = $_.Version
							$architecture = $_.Architecture
							
							$item = $listView.Items.Add($displayName)
							$item.SubItems.Add($exePath)
							$item.Tag = @{
								image_info	     = $fullLogoPath
								publisher	     = $publisher
								version		     = $version
								architecture	 = $architecture
								install_location = $exePath
							}
							
							if ($existingGameTitles -contains $displayName)
							{
								$item.ForeColor = [System.Drawing.Color]::DarkRed
							}
						}
					}
					catch
					{
						Write-Warning "Could not read manifest or config for $($_.Name)"
					}
				}
	}
	
	$listView.Add_ItemCheck({
			param ($sender,
				$e)

			if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
			{
				for ($i = 0; $i -lt $listView.Items.Count; $i++)
				{
					if ($i -ne $e.Index)
					{
						$listView.Items[$i].Checked = $false
					}
				}
			}
		})
	
}

$buttonScanInstalledProgram_Click={
	
	$listView.Items.Clear()
	
	
	$paths = @(
		"HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
		"HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
	)
	foreach ($path in $paths)
	{
		Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
			if ($_.DisplayName -and $_.InstallLocation -and (Test-Path $_.InstallLocation))
			{
				$exe = Get-ChildItem -Path $_.InstallLocation -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
				if ($exe)
				{
					$item = $listView.Items.Add($_.DisplayName)
					$item.SubItems.Add($exe.FullName)
					$listView.Sorting = 'Ascending'
					$item.Tag = @{
						image_info = $exe.FullName
					}
				}
			}
		}
		function Get-ExeIcon ($exePath)
		{
			if (Test-Path $exePath)
			{
				try
				{
					return [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
				}
				catch
				{
					return [System.Drawing.SystemIcons]::Application
				}
			}
			return [System.Drawing.SystemIcons]::Application
		}
		Get-ExeIcon
	}
	
	$contextMenu = New-Object System.Windows.Forms.ContextMenu
	$menuHook = New-Object System.Windows.Forms.MenuItem "Hook This"
	$menuOpen = New-Object System.Windows.Forms.MenuItem "Open Install Location"
	
	$menuHook.add_Click({
			$item = $listView.SelectedItems[0]
			[System.Windows.Forms.MessageBox]::Show("To hook: " + $item.Text + ", click on the checkbox next to it and click on Hook Applicatio(s).")
		})
	
	$menuOpen.add_Click({
			$path = $listView.SelectedItems[0].SubItems[1].Text
			if (Test-Path $path)
			{
				Start-Process -FilePath (Split-Path $path -Parent)
			}
		})
	
	$contextMenu.MenuItems.AddRange(@($menuHook, $menuOpen))
	$listView.ContextMenu = $contextMenu
	
	$listView.Add_ItemCheck({
			param ($sender,
				$e)

			if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
			{
				for ($i = 0; $i -lt $listView.Items.Count; $i++)
				{
					if ($i -ne $e.Index)
					{
						$listView.Items[$i].Checked = $false
					}
				}
			}
		})
	
	$listView.Add_ItemCheck({
			param ($sender,
				$e)

			if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
			{
				for ($i = 0; $i -lt $listView.Items.Count; $i++)
				{
					if ($i -ne $e.Index)
					{
						$listView.Items[$i].Checked = $false
					}
				}
			}
		})
	
}

$button_Click={
	
	
	$searchTerm = $txtSearch.Text.Trim()
	if (-not $searchTerm)
	{
		[System.Windows.Forms.MessageBox]::Show("Please enter a search term.", "Notice", "OK", "Information")
		return
	}
	$listView.Items.Clear()

	$paths = @(
		"HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
		"HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
	)
	foreach ($path in $paths)
	{
		Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$searchTerm*" } | ForEach-Object {
			if ($_.DisplayName -and $_.InstallLocation -and (Test-Path $_.InstallLocation))
			{
				$exePath = Get-ChildItem $_.InstallLocation -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
				if ($exePath)
				{
					$item = $listView.Items.Add($_.DisplayName)
					$item.SubItems.Add($exePath.FullName)
					$item.Tag = @{ image_info = $exePath.FullName }
					
					if ($existingGameTitles -contains $_.DisplayName)
					{
						$item.ForeColor = [System.Drawing.Color]::DarkRed
					}
				}
			}
		}
	}
	
	Get-AppxPackage | Where-Object { $_.Name -like "*$searchTerm*" } | ForEach-Object {
		$manifestPath = Join-Path $_.InstallLocation "AppxManifest.xml"
		if (Test-Path $manifestPath)
		{
			try
			{
				[xml]$manifest = Get-Content $manifestPath -ErrorAction Stop
				$displayName = $manifest.Package.Properties.DisplayName
				if ($displayName -match "(?i)ms-resource|WindowsAppRuntime|AppManifest|DisplayName")
				{
					return
				}
				
				$logoPath = $manifest.Package.Properties.Logo
				$fullLogoPath = Join-Path $_.InstallLocation $logoPath
				$gameConfigPath = Join-Path $_.InstallLocation "MicrosoftGame.config"
				$exePath = $null
				
				if (Test-Path $gameConfigPath)
				{
					[xml]$gameConfig = Get-Content $gameConfigPath -ErrorAction Stop
					$exeName = $gameConfig.SelectSingleNode("//ExecutableList/Executable").Name
					if ($exeName)
					{
						$exeFile = Get-ChildItem -Path $_.InstallLocation -Recurse -Filter $exeName -ErrorAction SilentlyContinue | Select-Object -First 1
						if ($exeFile)
						{
							$exePath = $exeFile.FullName
						}
					}
				}
				
				if (-not $exePath)
				{
					$exeFile = Get-ChildItem $_.InstallLocation -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
					if ($exeFile)
					{
						$exePath = $exeFile.FullName
					}
				}
				
				if ($exePath -and (Test-Path $exePath))
				{
					$item = $listView.Items.Add($displayName)
					$item.SubItems.Add($exePath)
					$item.Tag = @{ image_info = $fullLogoPath }
					
					if ($existingGameTitles -contains $displayName)
					{
						$item.ForeColor = [System.Drawing.Color]::DarkRed
					}
				}
			}
			catch
			{
				Write-Warning "Could not read manifest or config for $($_.Name)"
			}
		}
	}
	
	$contextMenu = New-Object System.Windows.Forms.ContextMenu
	$menuHook = New-Object System.Windows.Forms.MenuItem "Hook This"
	$menuOpen = New-Object System.Windows.Forms.MenuItem "Open Install Location"
	
	$menuHook.add_Click({
			$item = $listView.SelectedItems[0]
			[System.Windows.Forms.MessageBox]::Show("To hook: " + $item.Text + ", click on the checkbox next to it and click on Hook Applicatio(s).")
		})
	
	$menuOpen.add_Click({
			$path = $listView.SelectedItems[0].SubItems[1].Text
			if (Test-Path $path)
			{
				Start-Process -FilePath (Split-Path $path -Parent)
			}
		})
	
	$contextMenu.MenuItems.AddRange(@($menuHook, $menuOpen))
	$listView.ContextMenu = $contextMenu
	
	
}

$buttonDownloadMSIMCenter_Click={
	
	Start-Process "https://www.msi.com/Handheld/Claw-A1MX/support?sub_product=Claw-A1M#utility"
	
}

$buttonVerifyButtonMap_Click = {
	
	Add-Type -AssemblyName PresentationFramework
	
	# Function to get current handler
	function Get-MSIMCMHandler
	{
		$globalKey = "HKCR:\msi-mcm\shell\open\command"
		$userKey = "HKCU:\Software\Classes\msi-mcm\shell\open\command"
		
		function Get-Handler($regPath)
		{
			if (Test-Path $regPath)
			{
				return (Get-ItemProperty -Path $regPath -Name '(Default)').'(Default)'
			}
			return $null
		}
		
		$userHandler = Get-Handler $userKey
		$globalHandler = Get-Handler $globalKey
		
		if ($userHandler)
		{
			return "User-level handler:`n$userHandler"
		}
		elseif ($globalHandler)
		{
			return "System-level handler:`n$globalHandler"
		}
		else
		{
			return "No application is currently associated with 'MSI Center M button'"
		}
	}
	
	# Get info and display in pop-up
	$message = Get-MSIMCMHandler
	[System.Windows.MessageBox]::Show($message, "MSI-MCM Mapping Info", "OK", "Information")
	
}

$buttonGithub_Click={
	
	Start-Process "https://github.com/tetraguy/CenterMHook"
	
}
