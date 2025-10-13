<#
    ==========================================================
      PowerShell Script: User Cleanup Automation (Template)
      Doel: Automatisch verwijderen van gearchiveerde gebruikersmappen
      Versie: Template (zonder vertrouwelijke info)
      Auteur: [Jouw naam]
      Datum: [Datum]
      Project: BLUEBOT – Automatisering & Standaardisatie ICT
    ==========================================================
#>

# ================================
# Modules laden
# ================================
Import-Module ActiveDirectory

# ================================
# Instellingen
# ================================
# >>> Vul hier je eigen locaties in (UNC-paden naar gebruikersmappen)
# Voorbeeld:
# "\\servernaam\E$\ctxusers"
# "\\servernaam\F$\users"
# "\\fslogix-server\E$\ProfileContainers"
# "\\fslogix-server\F$\OfficeContainers"

$Locations = @(
    "\\SERVERNAAM1\PAD1",
    "\\SERVERNAAM2\PAD2",
    "\\SERVERNAAM3\PAD3"
)

# Regex voor gebruikersnaam (bijv. p-nummer)
# Pas aan volgens jouw naamgevingsconventie (vb. '^p\d+$' of '^pz\d+$')
$UserPattern = '^p\d+$'

# Opslag voor rapport
$Report = @()

# ================================
# Functie: bereken mapgrootte
# ================================
function Get-FolderSize($Path) {
    if (Test-Path $Path) {
        return (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
    } else {
        return 0
    }
}

# ================================
# Stap 1: haal gearchiveerde gebruikers uit AD
# ================================
# >>> PAS AAN: Gebruik de juiste OU-structuur van jouw domein
# Voorbeeld: "OU=Archived Users,OU=PZ Oostende,DC=pzoostende,DC=be"

$SearchBaseOU = "OU=Archived Users,OU=ORGANISATIENAAM,DC=domein,DC=be"

$ArchivedUsers = Get-ADUser -SearchBase $SearchBaseOU -Filter * -Properties DisplayName | 
    Select-Object SamAccountName, DisplayName

# ================================
# Stap 2: doorloop alle locaties
# ================================
foreach ($Loc in $Locations) {
    Write-Host "`n>>> Controleren op locatie: $Loc" -ForegroundColor Cyan

    if (Test-Path $Loc) {
        $Folders = Get-ChildItem $Loc -Directory

        foreach ($Folder in $Folders) {
            $FolderName = $Folder.Name

            # Controleer naamconventie
            if ($FolderName -notmatch $UserPattern) {
                Write-Host "Overslaan: $FolderName (geen geldig patroon)" -ForegroundColor Yellow
                continue
            }

            # Controleer of gebruiker in Archived OU zit
            $User = $ArchivedUsers | Where-Object { $_.SamAccountName -eq $FolderName }
            if ($null -eq $User) {
                Write-Host "Gebruiker $FolderName is NIET gearchiveerd, overslaan." -ForegroundColor Gray
                continue
            }

            # Toon informatie
            $SizeBefore = Get-FolderSize -Path $Folder.FullName
            $SizeMB = [Math]::Round($SizeBefore / 1MB, 2)
            Write-Host "`n--- GEVONDEN ---" -ForegroundColor Green
            Write-Host "Gebruiker : $($User.DisplayName) ($FolderName)"
            Write-Host "Locatie  : $($Folder.FullName)"
            Write-Host "Grootte  : $SizeMB MB"

            # Vraag bevestiging
            $Confirm = Read-Host "Wil je deze map verwijderen? (Y/N)"
            if ($Confirm -eq "Y") {
                try {
                    Remove-Item -Path $Folder.FullName -Recurse -Force -ErrorAction Stop
                    Write-Host "Map verwijderd." -ForegroundColor Red
                    $Report += [PSCustomObject]@{
                        Gebruiker    = $User.SamAccountName
                        Locatie      = $Folder.FullName
                        VrijgemaaktMB = $SizeMB
                    }
                } catch {
                    Write-Host "FOUT bij verwijderen: $_" -ForegroundColor DarkRed
                }
            } else {
                Write-Host "Verwijderen overgeslagen." -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "Pad $Loc niet bereikbaar!" -ForegroundColor DarkRed
    }
}

# ================================
# Stap 3: toon overzicht
# ================================
Write-Host "`n========= RAPPORT =========" -ForegroundColor Cyan
$Report | Format-Table -AutoSize

$TotalFreed = ($Report | Measure-Object -Property VrijgemaaktMB -Sum).Sum
Write-Host "`nTOTAAL vrijgemaakt: $TotalFreed MB" -ForegroundColor Green
