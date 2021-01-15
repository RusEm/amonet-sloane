#!/bin/bash

PAYLOAD_BLOCK=60407

PART_PREFIX=/dev/block/platform/mtk-msdc.0/by-name

set -e

. functions.inc

adb wait-for-device

check_device "sloane" " - Amazon Fire TV (2nd generation) - "

get_root

set +e
echo "Looking for partition-suffix"
adb shell su -c \"ls -l ${PART_PREFIX}\" | grep recovery_tmp
if [ $? -ne 0 ] ; then
  adb shell su -c \"ls -l ${PART_PREFIX}\" | grep recovery_x
  if [ $? -ne 0 ] ; then
    echo "Didn't find new partitions, did you do step-1.sh first?"
    exit 1
  else
    echo "Found \"_x\" suffix, it looks like you are rerunning step-2.sh"
    echo "If this is expected, press enter, otherwise terminate with Ctrl+C"
    read
    suffix=""
    suffix_b="_x"
  fi
else
  suffix="_tmp"
  suffix_b=""
fi
set -e
echo ""

if [ ! -f "gpt/gpt.bin.step2.gpt" ]; then
  echo "Couldn't find GPT files, regenerating from device"
  echo ""

  echo "Dumping GPT"
  [ ! -d gpt-regen ] && mkdir gpt-regen
  adb shell su -c \"dd if=/dev/block/mmcblk0 bs=512 count=34 of=/data/local/tmp/gpt.bin\" 
  adb shell su -c \"chmod 644 /data/local/tmp/gpt.bin\" 
  adb pull /data/local/tmp/gpt.bin gpt-regen/gpt.bin
  echo ""

  echo "Unpatching GPT"
  modules/gpt.py unpatch gpt-regen/gpt.bin
  [ ! -d gpt ] && mkdir gpt
  cp gpt-regen/gpt.bin.unpatched.gpt gpt/gpt.bin
  echo ""

  echo "Modifying GPT"
  modules/gpt.py patch gpt/gpt.bin
  echo ""
fi


echo "Flashing exploit"
adb push bin/boot.hdr /data/local/tmp/
adb push bin/boot.payload /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/boot.hdr of=${PART_PREFIX}/boot${suffix} bs=512\" 
adb shell su -c \"dd if=/data/local/tmp/boot.payload of=${PART_PREFIX}/boot${suffix} bs=512 seek=${PAYLOAD_BLOCK}\" 
adb shell su -c \"dd if=/data/local/tmp/boot.hdr of=${PART_PREFIX}/recovery${suffix} bs=512\" 
adb shell su -c \"dd if=/data/local/tmp/boot.payload of=${PART_PREFIX}/recovery${suffix} bs=512 seek=${PAYLOAD_BLOCK}\" 
echo ""

echo "Flashing LK"
adb push bin/lk.bin /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/lk.bin of=${PART_PREFIX}/lk bs=512\" 
echo ""

echo "Flashing TZ"
adb push bin/tz.img /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/tz.img of=${PART_PREFIX}/TEE1 bs=512\"
adb shell su -c \"dd if=/data/local/tmp/tz.img of=${PART_PREFIX}/TEE2 bs=512\"
echo ""

echo "Flashing Preloader"
adb shell su -c \"echo 0 \> /sys/block/mmcblk0boot0/force_ro\"
adb push bin/preloader.bin /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/preloader.bin of=/dev/block/mmcblk0boot0 bs=512\" 
echo ""

echo "Flashing final GPT"
adb push gpt/gpt.bin.step2.gpt /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/gpt.bin.step2.gpt of=/dev/block/mmcblk0 bs=512 count=34\" 
echo ""
if [ -f "gpt/gpt.bin.offset" ] ; then
  OFFSET=$(cat gpt/gpt.bin.offset)
  # Check if $OFFSET has some sane value
  if [ $OFFSET -gt 25000000 ] ; then
    echo "Flashing final GPT (backup)"
    adb push gpt/gpt.bin.step2.bak /data/local/tmp/
    adb shell su -c \"dd if=/data/local/tmp/gpt.bin.step2.bak of=/dev/block/mmcblk0 bs=512 seek=${OFFSET}\" 
    echo ""
  fi
fi

echo "Flashing TWRP"
adb push bin/twrp.img /data/local/tmp/
adb shell su -c \"dd if=/data/local/tmp/twrp.img of=${PART_PREFIX}/recovery${suffix_b} bs=512\"
echo ""

echo "Rebooting into TWRP"
adb reboot recovery
