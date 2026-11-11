#!/bin/bash
# A fake droiddock-engine that returns made-up phone data, for README screenshots.
# Usage: DROIDDOCK_ENGINE=packaging/demo/demo-engine.sh  (images from make_demo_images.swift
# must be in DEMO_IMAGES, default: build/demo-images)
IMAGES="${DEMO_IMAGES:-$(cd "$(dirname "$0")/../.." && pwd)/build/demo-images}"
NOW=1794300000

case "$1" in
  devices)
    echo '{"devices":[
      {"serial":"R5CX12345","state":"device","model":"Demo Phone","wifi":false,"secure":true},
      {"serial":"adb-R5CX12345-a1b2c3._adb-tls-connect._tcp","state":"device","model":"Demo Phone","wifi":true,"secure":true}
    ],"recent":["192.168.1.40:41237"]}' ;;
  mdns)
    echo '{"items":[{"name":"adb-T9QZ77777-x9y8z7","kind":"connect","addr":"192.168.1.52:37415"}]}' ;;
  ls)
    sleep "${DEMO_LS_DELAY:-0}" # set to act like a slow phone folder (for timing tests)
    case "$3" in
      */Camera)
        items=""
        names=(IMG_20261109_082506 IMG_20261108_154851 IMG_20261108_154849 VID_20261108_140250
               IMG_20261107_090212 IMG_20261105_075002 VID_20261104_172531 IMG_20261031_120634
               IMG_20261031_114936 IMG_20261031_090034 IMG_20261026_164655 IMG_20261025_122530)
        for i in "${!names[@]}"; do
          n=${names[$i]}; t=$((NOW - i * 86000))
          if [[ $n == VID* ]]; then f="$n.mp4"; s=$((40000000 + i * 3100000)); else f="$n.jpg"; s=$((2100000 + i * 97000)); fi
          items+="{\"name\":\"$f\",\"path\":\"$3/$f\",\"dir\":false,\"size\":$s,\"mtime\":$t},"
        done
        echo "{\"items\":[${items%,}]}" ;;
      *)
        echo '{"items":[
          {"name":"Alarms","path":"/sdcard/Alarms","dir":true,"size":0,"mtime":1790000000},
          {"name":"DCIM","path":"/sdcard/DCIM","dir":true,"size":0,"mtime":1794300000},
          {"name":"Documents","path":"/sdcard/Documents","dir":true,"size":0,"mtime":1793000000},
          {"name":"Download","path":"/sdcard/Download","dir":true,"size":0,"mtime":1794200000},
          {"name":"Movies","path":"/sdcard/Movies","dir":true,"size":0,"mtime":1792000000},
          {"name":"Music","path":"/sdcard/Music","dir":true,"size":0,"mtime":1791000000},
          {"name":"Pictures","path":"/sdcard/Pictures","dir":true,"size":0,"mtime":1794250000},
          {"name":"Holiday plan.pdf","path":"/sdcard/Holiday plan.pdf","dir":false,"size":482113,"mtime":1794100000},
          {"name":"Notes.txt","path":"/sdcard/Notes.txt","dir":false,"size":2048,"mtime":1793900000}
        ]}' ;;
    esac ;;
  head)
    # Pick a sample image from the file name, so each photo looks different.
    n=$(printf '%s' "$3" | cksum | cut -d' ' -f1); cp "$IMAGES/demo$((n % 6)).jpg" "$5"; echo '{"ok":true}' ;;
  pull|push)
    echo '{"done":[],"failed":[]}' ;;
  *)
    echo '{"ok":true}' ;;
esac
