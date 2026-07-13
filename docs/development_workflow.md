# NovaOS Development Workflow

This workflow is for fast iteration on NovaOS without rebuilding the ISO for every change.

## Recommended loop

1. Install Alpine Linux into a virtual disk inside VMware or VirtualBox.
2. Clone this repository inside the Alpine VM.
3. Run the local setup script:

```bash
sudo bash scripts/setup_dev_env.sh
```

4. Run the quick repository checks before changing anything else:

```bash
bash scripts/dev_check.sh
```

5. Make config changes in `configs/`, `packages/`, `branding/`, or `installer/`.
6. Re-run `bash scripts/dev_check.sh` after each meaningful change.
7. Restart the display manager from a TTY when you want to verify the desktop:

```bash
sudo rc-service lightdm restart
```

8. Rebuild the ISO only when the desktop path is stable:

```bash
sudo bash scripts/build_iso.sh
```

## What to test in the development VM

- LightDM login and autologin.
- LXQt session startup.
- Panel, wallpaper, and terminal launch.
- NetworkManager, Bluetooth, and Firefox startup.
- Installer launcher on the desktop.

## Fast debugging commands

If the desktop is black or does not load, check these from a TTY:

```bash
id nova
ls /usr/share/xsessions
cat /var/log/lightdm/lightdm.log
grep EE /var/log/Xorg.0.log
```

## Notes

- Use the development VM for fast iteration.
- Use the ISO builder only for final release output.
- Keep the repo checks green before every release build.