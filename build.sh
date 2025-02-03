#!/bin/bash

set -e

kernel_config_dir=$PWD/config
source_dir=$PWD/source
build_dir=$PWD/build
patches_dir=$PWD/patches

kernel_version="6.12.11"
tarball_url="https://cdn.kernel.org/pub/linux/kernel/v${kernel_version:0:1}.x/linux-${kernel_version}.tar.xz"
tarball_name="$(echo $tarball_url | cut -f 8 -d '/')"

variant='stoney'
arch=x86_64

# Install amdgpu firmware
firmware_dir=${source_dir}/${variant}/stoney_firmware
mkdir -p ${firmware_dir}/amdgpu
cp -r /lib/firmware/amdgpu/stoney* ${firmware_dir}/amdgpu

xz_count=`ls -1 ${firmware_dir}/amdgpu/stoney*.xz 2>/dev/null | wc -l`
zst_count=`ls -1 ${firmware_dir}/amdgpu/stoney*.zst 2>/dev/null | wc -l`
if [ $xz_count != 0 ]; then
    xz -d ${firmware_dir}/amdgpu/stoney*.xz &> /dev/null || true
fi
if [ $zst_count != 0 ]; then
    zstd -d ${firmware_dir}/amdgpu/stoney*.zst &> /dev/null || true
fi

kernel_source_dir=${source_dir}/${variant}/linux-${kernel_version}
output_dir=${build_dir}/${variant}
module_dir=${output_dir}/modules
header_dir=${output_dir}/headers

echo "Building $variant kernel"

curl -L $tarball_url -o ${source_dir}/${variant}/${tarball_name}
tar xf ${source_dir}/${variant}/${tarball_name} -C ${source_dir}/${variant}/
cd $kernel_source_dir
for f in ${patches_dir}/${variant}/*; do
    patch -p1 < $f &> /dev/null || true
done

cp ${kernel_config_dir}/${variant}.config .config
make ARCH=$arch olddefconfig
make ARCH=$arch -j$(nproc)

mkdir -p $output_dir
make modules_install install \
    ARCH=$arch \
    INSTALL_MOD_PATH=$module_dir \
    INSTALL_MOD_STRIP=1 \
    INSTALL_PATH=$output_dir

cp .config $output_dir/config
cp System.map $output_dir/System.map
cp include/config/kernel.release $output_dir/kernel.release

mkdir -p $header_dir
install -Dt "$header_dir" -m644 .config Makefile Module.symvers System.map vmlinux
install -Dt "$header_dir/kernel" -m644 kernel/Makefile
install -Dt "$header_dir/arch/x86" -m644 arch/x86/Makefile
cp -t "$header_dir" -a scripts
cp -t "$header_dir" -a include
cp -t "$header_dir/arch/x86" -a arch/x86/include
install -Dt "$header_dir/arch/x86/kernel" -m644 arch/x86/kernel/asm-offsets.s
install -Dt "$header_dir/drivers/md" -m644 drivers/md/*.h
install -Dt "$header_dir/net/mac80211" -m644 net/mac80211/*.h
install -Dt "$header_dir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h
install -Dt "$header_dir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
install -Dt "$header_dir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
install -Dt "$header_dir/drivers/media/tuners" -m644 drivers/media/tuners/*.h
install -Dt "$header_dir/drivers/iio/common/hid-sensors" -m644 drivers/iio/common/hid-sensors/*.h

find . -name 'Kconfig*' -exec install -Dm644 {} "$header_dir/{}" \;
rm -r "$header_dir/Documentation"
find -L "$header_dir" -type l -delete
find "$header_dir" -type f -name '*.o' -delete

while read -rd '' file; do
    case "$(file -Sib "$file")" in
        application/x-sharedlib\;*) strip "$file" ;;
        application/x-archive\;*) strip "$file" ;;
        application/x-executable\;*) strip "$file" ;;
        application/x-pie-executable\;*) strip "$file" ;;
    esac
done < <(find "$header_dir" -type f -perm -u+x ! -name vmlinux -print0)
strip $header_dir/vmlinux
