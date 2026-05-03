# Option 1: Auto-load VirtIO SCSI driver with `autounattend.xml`

## Implemented in this repo

`packer/answer/Autounattend.in.xml` adds `<DriverPaths>` under `Microsoft-Windows-Setup` (windows PE pass) with three candidate paths `D:/`, `E:/`, and `F:/` plus a relative folder controlled by **`PKR_VAR_virtio_vioscsi_rel_path`** (default `vioscsi/w11/amd64`). Run **`packer/scripts/render-autounattend.sh`** (or `.ps1`) before build so `answer/Autounattend.xml` is generated.

Use **merged supplemental ISO** (`build-supplemental-iso.sh`, `PKR_VAR_supplemental_iso_file`) **or** attach stock **virtio-win.iso** (`PKR_VAR_virtio_iso_file`) plus a **cidata-only** ISO from `packer/scripts/build-cidata-only-iso.sh` (`PKR_VAR_cidata_iso_file`) — split mode avoids extracting virtio into a custom merge. The folder layout on the virtio CD must match `PKR_VAR_virtio_vioscsi_rel_path`. The existing **RunSynchronous** `drvload` script remains as a fallback.

---

This approach avoids manually clicking **Load driver** during Windows Setup by telling the `windowsPE` phase to scan the VirtIO driver path on the attached VirtIO ISO.[cite:18][cite:24]

## What this does

When the VM boots into Windows Setup, the `Microsoft-Windows-Setup` component can read additional driver locations from `DriverPaths` during the `windowsPE` pass.[cite:24]
If the path points to the correct VirtIO SCSI folder, Windows Setup loads the storage driver early enough for the virtual disk to appear automatically on the disk selection screen.[cite:18][cite:23][cite:24]

## Packer requirements

The build should attach the Windows installer ISO as the main install media and the VirtIO ISO as a second CD-ROM so Setup can read the storage driver files.[cite:14][cite:24]
A typical Packer block looks like this:

```hcl
additional_iso_files {
  device   = "ide3"
  iso_file = "local:iso/virtio-win-0.1.262.iso"
  unmount  = true
}
```

The exact `device` can vary, but it must be a valid CD-ROM slot that actually appears in the VM hardware during boot.[cite:14]
The `iso_file` value must exactly match the VirtIO ISO path stored in Proxmox ISO storage.[cite:14]

## `autounattend.xml` example

Add the driver path in the `windowsPE` pass under `Microsoft-Windows-Setup`.

```xml
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

      <DriverPaths>
        <PathAndCredentials wcm:action="add" wcm:keyValue="1">
          <Path>E:\vioscsi\2k22\amd64</Path>
        </PathAndCredentials>
      </DriverPaths>

      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>1</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>

    </component>
  </settings>
</unattend>
```

For Windows Server 2022, the relevant VirtIO SCSI folder is commonly `vioscsi\2k22\amd64` on the VirtIO ISO.[cite:18]
The path must point to the folder that contains the correct `.inf` for the storage driver, not just the root of the ISO.[cite:18][cite:23]

## Important detail: drive letter

The biggest source of failure is the CD-ROM drive letter in WinPE.[cite:24]
If the VirtIO ISO is mounted as `D:` instead of `E:`, the path in `DriverPaths` must match that letter exactly or the driver will not load.[cite:24]

A practical way to verify this is to boot once, open a command prompt in Setup, and confirm where the VirtIO ISO is mounted before finalizing the unattended file.[cite:24]

## Recommended settings

For a Proxmox VM using a VirtIO SCSI disk, use a SCSI disk type together with a VirtIO SCSI controller and the VirtIO ISO attached as secondary media.[cite:18][cite:23]
That combination is normal, but Windows Setup needs the matching `vioscsi` driver during install unless the driver has already been slipstreamed into the install media.[cite:18][cite:25]

## Troubleshooting

- Disk still missing: verify the `DriverPaths` folder matches the guest OS version, architecture, and actual drive letter in WinPE.[cite:18][cite:24]
- VirtIO ISO not found: confirm the second ISO is actually attached in Proxmox hardware during the build.[cite:14]
- Wrong driver folder: use `vioscsi` for VirtIO SCSI storage, not a network driver folder such as `NetKVM`.[cite:18]
- No disk in Proxmox hardware: confirm the Packer `disks` block created a SCSI disk on the expected storage pool before Setup starts.[cite:14]

## Minimal Packer pattern

```hcl
source "proxmox-iso" "windows" {
  iso_file         = "local:iso/WindowsServer2022.iso"
  scsi_controller  = "virtio-scsi-pci"

  disks {
    storage_pool = "local-lvm"
    type         = "scsi"
    disk_size    = "40G"
    format       = "raw"
  }

  additional_iso_files {
    device   = "ide3"
    iso_file = "local:iso/virtio-win-0.1.262.iso"
    unmount  = true
  }
}
```

This pattern works with the unattended driver path method as long as the `autounattend.xml` is available to Setup and the driver path matches the mounted VirtIO media.[cite:14][cite:24]
