#!/bin/bash

# _____   ______
# |  __ \ / ____| Rahul Sandhu
# | |__) | (___   rahul@sandhuservices.dev
# |  _  / \___ \  https://sandhuservices.dev/
# | | \ \ ____) | https://gitlab.sandhuservices.dev/rahulsandhu/
# |_|  \_\_____/  https://github.com/rahul-singh-sandhu

NAME="Gentoo Installer"
CODENAME="gentooinstaller"
COPYRIGHT="Copyright (C) 2022 Rahul Sandhu"
LICENSE="GNU General Public License 3.0"
VERSION="0.1"

source /etc/profile
source /root/variables
echo $nvme
sleep 15
emerge-webrsync
emerge --sync
eselect profile set 7
emerge --verbose --update --deep --newuse @world
emerge app-portage/cpuid2cpuflags
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
echo ACCEPT_LICENSE=\"*\" >> /etc/portage/make.conf

ln -sf /usr/share/zoneinfo/${user_timezone} /etc/localtime
echo -en "${user_locale} UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set ${user_locale}
ln -sf /proc/self/mounts /etc/mtab
emerge sys-kernel/dracut
if [[ $use_luks_final=1 ]]
then
	echo sys-apps/systemd gnuefi cryptsetup > /etc/portage/package.use/systemd
else
	echo sys-apps/systemd gnuefi > /etc/portage/package.use/systemd
fi
emerge sys-apps/systemd
systemd-machine-id-setup
systemctl preset-all
echo -en "KEYMAP=${user_keymap}" > /etc/vconsole.conf
cpu_vendor_id_temp=$(cat /proc/cpuinfo | grep vendor_id | sed '1!d')
cpu_vendor_id=$(echo ${cpu_vendor_id_temp,,})
if [[ $cpu_vendor_id = *"intel"* ]]
then
	cpu_type="intel"
	unicode_file="intel-uc.img"

elif [[ $cpu_vendor_id = *"amd"* ]]
then
	cpu_type="amd"
	unicode_file="amd-uc.img"
else
	cpu_type="other"
fi
case $cpu_type in
	"intel")
		echo sys-firmware/intel-microcode initramfs > /etc/portage/package.use/intel-microcode
		emerge intel-microcode
		;;
	"amd")
		echo sys-kernel/linux-firmware initramfs > /etc/portage/package.use/linux-firmware
		;;
	*)
		echo "CPU type not recognised - no microcode will be installed..."
		;;
esac
echo -e "${machine_hostname}" > /etc/hostname
echo -e "127.0.0.1 localhost" > /etc/hosts
echo -e "::1 localhost" >> /etc/hosts
echo -e "127.0.1.1 ${machine_hostname}.localdomain ${machine_hostname}" >> /etc/hosts
emerge linux-firmware btrfs-progs
emerge sys-kernel/gentoo-kernel
kernel_version=$(ls /lib/modules)
dracut --kver=${kernel_version} --force
emerge networkmanager nm-applet networkmanager-openvpn
systemctl enable NetworkManager
bootctl --path=/boot install
echo -en "default gentoo.conf\ntimeout 3\n#editor no" > /boot/loader/loader.conf
echo -e "title Gentoo Linux" > /boot/loader/entries/gentoo.conf
echo -e "linux /vmlinuz-${kernel_version}" >> /boot/loader/entries/gentoo.conf
if [[ $cpu_type != "amd" ]] && [[ $cpu_type != "intel" ]]
then
	echo "Microde not added to bootloader..."
else
	echo -e "initrd /${unicode_file}" >> /boot/loader/entries/gentoo.conf
fi
echo -e "initrd /initramfs-${kernel_version}.img" >> /boot/loader/entries/gentoo.conf
if [[ $nvme == 0 ]]
then
	if [[ $use_swap_final == 0 ]]
	then
		blkid_drive=$(blkid -s UUID -o value ${drive}2)
	else
		blkid_drive=$(blkid -s UUID -o value ${drive}3)
	fi
else
	if [[ $use_swap_final == 0 ]]
	then
		blkid_drive=$(blkid -s UUID -o value ${drive}p2)
	else
		blkid_drive=$(blkid -s UUID -o value ${drive}p3)
	fi
fi

if [[ $use_luks_final == 1 ]]
then
	echo -e "options rd.luks.name=${blkid_drive}=gentoolukstest root=/dev/mapper/gentoolukstest rootflags=subvol=@ rd.luks.options=${blkid_drive} rw" >> /boot/loader/entries/gentoo.conf

else
	echo -e "rootfstype=btrfs rootflags=subvol=@ rw" >> /boot/loader/entries/gentoo.conf
fi

echo -en "$user_root_password\n$root_password" | passwd

exit
