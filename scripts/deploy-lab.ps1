# deploy-lab.ps1 - Deploie les 3 VM de la maquette SAE 5.02 a partir de l'OVA de base
#
# Usage :
#   .\deploy-lab.ps1           -> importe les VM qui n'existent pas encore
#   .\deploy-lab.ps1 -Force    -> supprime et recree les 3 VM (repartir de zero)
#
# Par defaut, l'OVA est cherchee dans le meme dossier que ce script, et le
# reseau host-only utilise est celui dont l'IP est 192.168.56.1 (detecte
# automatiquement). Le script fonctionne donc sur n'importe quel PC.
#
# Chaque VM recoit une MAC fixe sur la carte host-only : 08:00:27:56:00:XX.
# Au premier demarrage, lab-firstboot.sh (inclus dans l'OVA) en deduit
# son nom et son IP. Aucune saisie en console n'est necessaire.

param(
    [string]$Ova = (Join-Path $PSScriptRoot "SAE5-05_base.ova"),
    [string]$HostOnly = "",
    [switch]$Force
)

$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vbm)) { Write-Error "VirtualBox introuvable : $vbm"; exit 1 }

$vms = @(
    @{ Name = "VM-manager";  Ip = 10; Mem = 2048; Cpu = 1 },
    @{ Name = "VM-services"; Ip = 11; Mem = 4096; Cpu = 2 },
    @{ Name = "VM-backup";   Ip = 12; Mem = 2048; Cpu = 1 }
)

if (-not (Test-Path $Ova)) { Write-Error "OVA introuvable : $Ova"; exit 1 }

# Detection du reseau host-only en 192.168.56.1
if (-not $HostOnly) {
    $blocks = ((& $vbm list hostonlyifs) -join "`n") -split "`n\s*`n"
    $found = $blocks | Where-Object { $_ -match "(?m)^IPAddress:\s+192\.168\.56\.1\s*$" } | Select-Object -First 1
    if ($found -and $found -match "(?m)^Name:\s+(.+)$") {
        $HostOnly = $Matches[1].Trim()
    } else {
        Write-Error "Aucun reseau host-only en 192.168.56.1. Le creer (voir la doc) puis relancer."
        exit 1
    }
}
Write-Host "Reseau host-only utilise : $HostOnly" -ForegroundColor Cyan

$existing = & $vbm list vms

foreach ($vm in $vms) {
    $name = $vm.Name

    if (@($existing) -match "^`"$name`"") {
        if (-not $Force) {
            Write-Host "$name existe deja, ignoree (utiliser -Force pour la recreer)" -ForegroundColor Yellow
            continue
        }
        Write-Host "Suppression de $name..." -ForegroundColor Yellow
        & $vbm controlvm $name poweroff 2>$null | Out-Null
        Start-Sleep -Seconds 3
        & $vbm unregistervm $name --delete
    }

    Write-Host "Import de $name..." -ForegroundColor Cyan
    & $vbm import $Ova --vsys 0 --vmname $name --memory $vm.Mem --cpus $vm.Cpu
    if ($LASTEXITCODE -ne 0) { Write-Error "Echec de l'import de $name"; exit 1 }

    $mac = "0800275600{0:X2}" -f $vm.Ip
    & $vbm modifyvm $name --nic1 nat --nic2 hostonly --hostonlyadapter2 $HostOnly --macaddress2 $mac

    & $vbm startvm $name --type headless
    Write-Host "$name demarree -> 192.168.56.$($vm.Ip)" -ForegroundColor Green

    # Oublier l'ancienne empreinte SSH de cette IP
    ssh-keygen -R "192.168.56.$($vm.Ip)" 2>$null | Out-Null
}

Write-Host ""
Write-Host "Attendre environ 1 minute, puis : ssh ansible@192.168.56.10 (ou .11 / .12)"
