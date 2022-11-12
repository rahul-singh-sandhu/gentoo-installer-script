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

INSTALLER_SRC_DIR=$(pwd)

lsblk
read -p 'Enter the drive name: ' drive
read -p 'Would you like to use swap? (Y/n) ' use_swap_temp
read -p 'Would you like to use luks encryption (Y/n) ' use_luks_temp
read -p 'Enter any make opts: ' user_make_opts
use_swap=$(echo ${use_swap_temp,,})
use_luks=$(echo ${use_luks_temp,,})
unset use_swap_temp
unset use_luks_temp

case $use_swap in
	yes|y|"")
		use_swap_final=1
		;;
	*)
		use_swap_final=0
		;;
esac
case $use_luks in
	yes|y|"")
		use_luks_final=1
		;;
	*)
		use_luks_final=0
		;;
esac

if [[ $use_swap_final == 1 ]]
then
	read -p 'Enter a size for swap space in GB ' swap_space_temp
	swap_space=$(echo -e "$swap_space_temp" | sed 's/[^0-9]*//g')
	echo $swap_space
fi

if [[ $use_luks_final == 1 ]]
then
        read -p 'Enter your luks keyphrase ' luks_password
fi

check_drive_type() {
	if [[ $drive == *"nvme"* ]]
	then
		nvme=1
	else
		nvme=0
	fi
}

partition_drives() {
	sgdisk -Z $drive && wipefs -a $drive
	if [[ $use_swap_final == 1 ]]
	then
		sgdisk -o -n 1::+500M -t 1:EF00 -c 1:"boot" -n 2::+${swap_space}gb -t 2:8200 -c 2:"swap" -n 3::: -t 3:8300 -c 3:"root" -p $drive
	else
		sgdisk -o -n 1::+500M -t 1:EF00 -c 1:"boot" -n 2::: -t 2:8300 -c 2:"root" -p $drive
	fi
}
format_drives() {
	mkdir -pv /mnt/gentoo
	if [[ $nvme == 1 ]]
	then
		mkfs.vfat -F32 ${drive}p1
		if [[ $use_swap_final == 1 ]]
		then
			mkswap ${drive}p2
			swapon ${drive}p2
			if [[ $use_luks_final == 1 ]]
			then
				echo -en $luks_password | cryptsetup -q luksFormat ${drive}p3
				echo -en $luks_password | cryptsetup open ${drive}p3 gentoolukstest
				mkfs.btrfs /dev/mapper/gentoolukstest -L root
				mount /dev/mapper/gentoolukstest /mnt/gentoo
				btrfs_drive_path="/dev/mapper/gentoolukstest"
			else
				mkfs.btrfs ${drive}p3 -L root
				mount ${drive}p3 /mnt/gentoo
				btrfs_drive_path="$drive"p3
			fi
		else
			if [[ $use_luks_final == 1 ]]
			then
				echo -en $luks_password | cryptsetup -q luksFormat ${drive}p2
				echo -en $luks_password | cryptsetup open ${drive}p2 gentoolukstest
				mkfs.btrfs /dev/mapper/gentoolukstest -L root
				mount /dev/mapper/gentoolukstest /mnt/gentoo
				btrfs_drive_path="/dev/mapper/gentoolukstest"
			else
				mkfs.btrfs ${drive}p2 -L root
				mount ${drive}p2 /mnt/gentoo
				btrfs_drive_path="$drive"p2
			fi
		fi
	else
		mkfs.vfat -F32 ${drive}1
		if [[ $use_swap_final == 1 ]]
        then
            mkswap ${drive}2
            swapon ${drive}2
            if [[ $use_luks_final == 1 ]]
            then
            	echo -en $luks_password | cryptsetup -q luksFormat ${drive}3
                echo -en $luks_password | cryptsetup open ${drive}3 gentoolukstest
				mkfs.btrfs /dev/mapper/gentoolukstest -L root
                mount /dev/mapper/gentoolukstest /mnt/gentoo
				btrfs_drive_mount="/dev/mapper/gentoolukstest"
            else
                mkfs.btrfs ${drive}3 -L root
                mount ${drive}3 /mnt/gentoo
				btrfs_drive_mount="$drive"3
            fi
		else
			if [[ $use_luks_final == 1 ]] 
			then
				echo -en $luks_password | cryptsetup -q luksFormat ${drive}2
				echo -en $luks_password | cryptsetup open ${drive}2 gentoolukstest
				mkfs.btrfs /dev/mapper/gentoolukstest -L root
				mount /dev/mapper/gentoolukstest /mnt/gentoo
				btrfs_drive_mount="/dev/mapper/gentoolukstest"
			else
				mkfs.btrfs ${drive}2 -L root
				mount ${drive}2 /mnt/gentoo
				btrfs_drive_mount="$drive"2
			fi
        fi
	fi
}

create_subvols() {
	btrfs sub create /mnt/gentoo/@
	btrfs sub create /mnt/gentoo/@home
	umount /mnt/gentoo
	mount -o noatime,nodiratime,compress=zstd:1,ssd,subvol=@ ${btrfs_drive_path} /mnt/gentoo
}

fetch_stage3() {
	cd /mnt/gentoo
	wget https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-desktop-systemd.txt
	sed -i '1d;2d' latest-stage3-amd64-desktop-systemd.txt
	sed -i 's/.*\///' latest-stage3-amd64-desktop-systemd.txt
	sed -i 's/\s.*$//' latest-stage3-amd64-desktop-systemd.txt
	latest_stage3=$(cat latest-stage3-amd64-desktop-systemd.txt)
	wget https://mirror.bytemark.co.uk/gentoo/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd/${latest_stage3}
	tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
}

configure_stage3() {
	sed -i 's/COMMON_FLAGS="/&-march=native /' /mnt/gentoo/etc/portage/make.conf
	sed -i "/FFLAGS/aMAKEOPTS=\"${user_make_opts}\"" /mnt/gentoo/etc/portage/make.conf
	mkdir --parents /mnt/gentoo/etc/portage/repos.conf
	cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
	cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
}

chroot_mount_fs() {
	mount --types proc /proc /mnt/gentoo/proc
	mount --rbind /sys /mnt/gentoo/sys 
	mount --make-rslave /mnt/gentoo/sys
	mount --rbind /dev /mnt/gentoo/dev 
	mount --make-rslave /mnt/gentoo/dev 
	mount --bind /run /mnt/gentoo/run 
	mount --make-slave /mnt/gentoo/run 
	test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
	mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm 
	chmod 1777 /dev/shm /run/shm
}

mount_volumes() {
	mount -o noatime,nodiratime,compress=zstd:1,ssd,subvol=@home ${btrfs_drive_path} /mnt/gentoo/home
	if [[ $nvme = 1 ]]
	then
		mount ${drive}p1 /mnt/gentoo/boot
	else
		mount ${drive}1 /mnt/gentoo/boot
	fi 
}

chroot_first_run() {
	cp ${INSTALLER_SRC_DIR}/gentoo-install-part2.sh /mnt/gentoo/root/gentoo-install-part2.sh
	chroot /mnt/gentoo chmod +x /root/gentoo-install-part2.sh
	chroot /mnt/gentoo /bin/bash /root/gentoo-install-part2.sh
}

check_drive_type
partition_drives
format_drives
create_subvols
fetch_stage3
configure_stage3
chroot_mount_fs
mount_volumes
chroot_first_run
