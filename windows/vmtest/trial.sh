#!/bin/bash
# trial.sh <回合編號> <快照名>：還原快照→裝安裝程式→偵測→打字測試→報告，輸出到 ${CJ_VMTEST_DIR:?}/trials/<n>/
n=$1; snap=${2:-base4}; D=${CJ_VMTEST_DIR:?}/trials/$n; mkdir -p $D; exec > >(tee $D/run.txt) 2>&1
W=${CJ_VMTEST_DIR:?}/w; SCP="scp -q -o UserKnownHostsFile=${CJ_VMTEST_DIR:?}/kh -i ${CJ_VM_KEY:?} -P ${CJ_VM_PORT:?}"
V() { timeout 120 ssh ${CJ_LIBVIRT_HOST:?} "virsh -c qemu:///system $*"; }
key() { for k in "$@"; do timeout 20 ssh ${CJ_LIBVIRT_HOST:?} "virsh -c qemu:///system send-key cj-win10 $k" >/dev/null; sleep 0.3; done; }
echo "== trial $n from $snap $(date +%T)"
V snapshot-revert cj-win10 $snap >/dev/null || { echo REVERT_FAIL; exit 1; }
for i in $(seq 1 30); do T=10 $W 'echo up' >/dev/null 2>&1 && break; sleep 3; done
for f in runi.ps1 probe.ps1 autoclick.ps1 focus.ps1 readnote.ps1 go.ps1; do $SCP ${CJ_VMTEST_DIR:?}/$f ${CJ_VM_USER:?}@${CJ_VM_HOST:?}:$f; done
$SCP "$SETUP" ${CJ_VM_USER:?}@${CJ_VM_HOST:?}:setup.exe
if [ -n "${TIP:-}" ]; then printf "%s" "$TIP" > $D/tip.txt; $SCP $D/tip.txt ${CJ_VM_USER:?}@${CJ_VM_HOST:?}:tip.txt; fi
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 start'
t0=$(date +%s)
while :; do sleep 15; st=$(T=30 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 status' 2>&1)
  echo "$st" | head -1 | grep -q 'setup_running=False' && break
  [ $(( $(date +%s) - t0 )) -gt 1000 ] && { echo "TIMEOUT setup still running"; break; }
done
echo "setup took $(( $(date +%s) - t0 ))s"
${CJ_VMTEST_DIR:?}/shot $D/after-install.png
echo "== type into existing notepad"
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 focus-old'; key KEY_A KEY_B KEY_C
echo "== type cangjie into new notepad"
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 focus-new'; key KEY_H KEY_Q KEY_I KEY_SPACE; sleep 1
${CJ_VMTEST_DIR:?}/shot $D/after-type.png
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 read'
sleep 5
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 report'
T=60 $W 'powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\go.ps1 tips'
echo "== done $(date +%T)"
