# =====================================================================
# Project: Citrix SMB Drive Mapper 
# Auteur: Maryam Al-mzaiel
# Doel: Automatisch verbinden met netwerkdrives in Citrix-omgeving
# Datum: 2025
# =====================================================================

# === BELANGRIJK ===
# Variabelen instellen voor de te mappen netwerkdrives
$Drive1 = "T"
$Drive2 = "H"
$Path1  = "\\fileserver01\Bedrijfsdata"         # Algemene drive
$Path2  = "\\fileserver01\Gebruikersdata"       # Persoonlijke drive-root

# === BELANGRIJK ===
# Logging instellen zodat fouten en acties worden opgeslagen
$logFolder = Join-Path $Env:LOCALAPPDATA -ChildPath "DriveMapper"
if (!(Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder | Out-Null }
$logFile = Join-Path $logFolder -ChildPath "SMBdriveMapper.log"
Start-Transcript -Path $logFile -Force

Write-Output "=== Start automatische Citrix drive mapping ==="

# ---------------------------------------------------------------------
# 1. Verwijder bestaande mappings om conflicten te voorkomen
# ---------------------------------------------------------------------
function Remove-ExistingMapping {
    param([string]$DriveLetter, [string]$SharePath)
    try {
        Write-Output "INFO: Verwijderen bestaande mapping $DriveLetter..."
        cmd /c "net use ${DriveLetter}: /delete /y" | Out-Null
        cmd /c "net use `"$SharePath`" /delete /y" | Out-Null
        Write-Output "INFO: Oude mapping $DriveLetter verwijderd (indien aanwezig)."
    } catch {
        Write-Output "WARNING: Kon mapping $DriveLetter niet verwijderen: $_"
    }
}

Remove-ExistingMapping -DriveLetter $Drive1 -SharePath $Path1
Remove-ExistingMapping -DriveLetter $Drive2 -SharePath $Path2

# ---------------------------------------------------------------------
# 2. Toon authenticatievenster (GUI) voor gebruikerslogin
# ---------------------------------------------------------------------
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$authenticated = $false

do {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Drive Mapping - Inloggen"
    $form.Size = New-Object System.Drawing.Size(300,200)
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Point(75,120)
    $OKButton.Size = New-Object System.Drawing.Size(75,23)
    $OKButton.Text = 'Aanmelden'
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $OKButton                   # === BELANGRIJK === Enter activeert “Aanmelden”
    $form.Controls.Add($OKButton)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Point(150,120)
    $CancelButton.Size = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text = 'Annuleren'
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $CancelButton               # === BELANGRIJK === Escape sluit venster
    $form.Controls.Add($CancelButton)

    $label1 = New-Object System.Windows.Forms.Label
    $label1.Location = New-Object System.Drawing.Point(10,20)
    $label1.Size = New-Object System.Drawing.Size(280,20)
    $label1.Text = "Gebruikersnaam:"
    $form.Controls.Add($label1)

    $usernameBox = New-Object System.Windows.Forms.TextBox
    $usernameBox.Location = New-Object System.Drawing.Point(10,40)
    $usernameBox.Size = New-Object System.Drawing.Size(260,20)
    $form.Controls.Add($usernameBox)

    $label2 = New-Object System.Windows.Forms.Label
    $label2.Location = New-Object System.Drawing.Point(10,60)
    $label2.Size = New-Object System.Drawing.Size(280,20)
    $label2.Text = 'Wachtwoord:'
    $form.Controls.Add($label2)

    $passwordBox = New-Object System.Windows.Forms.MaskedTextBox
    $passwordBox.PasswordChar = '*'
    $passwordBox.Location = New-Object System.Drawing.Point(10,80)
    $passwordBox.Size = New-Object System.Drawing.Size(260,20)
    $form.Controls.Add($passwordBox)

    $form.Add_Shown({$passwordBox.Select()})
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
        Write-Output "INFO: Authenticatie geannuleerd door gebruiker."
        Stop-Transcript
        Exit
    }

    # -----------------------------------------------------------------
    # 3. Controleer ingevoerde login via 'net use'
    # -----------------------------------------------------------------
    $Username = $usernameBox.Text
    $Password = $passwordBox.Text
    $testCmd = "net use `"$Path1`" `"$Password`" /user:`"$Username`""
    $output = cmd /c $testCmd 2>&1
    $exitCode = $LASTEXITCODE
    cmd /c "net use `"$Path1`" /delete /y" | Out-Null

    if ($exitCode -eq 0) {
        Write-Output "INFO: Authenticatie succesvol voor $Username"
        $authenticated = $true
    } else {
        Write-Output "ERROR: Onjuiste login voor $Username. Code: $exitCode"
        [System.Windows.Forms.MessageBox]::Show(
            "De ingevoerde gebruikersnaam of het wachtwoord is onjuist.`nProbeer opnieuw.",
            "Authenticatie mislukt",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }

} until ($authenticated -eq $true)

# ---------------------------------------------------------------------
# 4. Maak de netwerkdrives aan met de correcte credentials
# ---------------------------------------------------------------------
try {
    Write-Output "INFO: Mapping toevoegen ${Drive1}:..."
    cmd /c "net use ${Drive1}: `"$Path1`" `"$Password`" /user:`"$Username`" /persistent:yes" | Out-Null
    Write-Output "INFO: ${Drive1}: succesvol verbonden."
} catch {
    Write-Output "ERROR: Kon ${Drive1}: niet aanmaken."
}

try {
    Write-Output "INFO: Mapping toevoegen ${Drive2}:..."
    cmd /c "net use ${Drive2}: `"$Path2\p123456`" `"$Password`" /user:`"$Username`" /persistent:yes" | Out-Null
    Write-Output "INFO: ${Drive2}: succesvol verbonden."
} catch {
    Write-Output "ERROR: Kon ${Drive2}: niet aanmaken."
}

# ---------------------------------------------------------------------
# 5. Herstart Windows Verkenner zodat drives zichtbaar worden
# ---------------------------------------------------------------------
Write-Output "INFO: Herstarten van Windows Verkenner..."
Stop-Process -ProcessName explorer -Force

# ---------------------------------------------------------------------
# 6. Einde script
# ---------------------------------------------------------------------
Write-Output "=== Drive Mapping voltooid ==="
Stop-Transcript

