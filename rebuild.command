#!/bin/bash
# Пересобрать и перезапустить NotchApp. Лог — в .rebuild.log рядом.
cd "$(dirname "$0")"
LOG=".rebuild.log"
{
  echo "=== $(date) ==="
  ./scripts/build.sh release
  STATUS=$?
  echo "=== build exit: ${STATUS} ==="
  if [ ${STATUS} -eq 0 ]; then
    # Разовый перенос: gh-кнопки уехали на вкладку «Git».
    CMDS="$HOME/Library/Application Support/NotchApp/commands.json"
    if [ -f "${CMDS}" ] && grep -qE '"gh [as]uth ' "${CMDS}"; then
      cp "${CMDS}" "${CMDS}.bak"
      /usr/bin/python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); k=[b for b in d if not b["command"].startswith(("gh auth ","gh suth "))]; json.dump(k,open(p,"w"),indent=2,ensure_ascii=False); print("=== убрал gh-команд:", len(d)-len(k), "===")' "${CMDS}"
    fi
    open dist/NotchApp.app && echo "=== launched ==="
  fi
} 2>&1 | tee "${LOG}"
echo
echo "Окно можно закрыть."
