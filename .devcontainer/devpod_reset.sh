#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Close the editor window to disconnect from Devpod."
read -n 1 -s -r -p "Press any key once closed to continue..."
echo

MATCHES=()
for c in $(docker ps -a -q); do
  MOUNTS=$(docker inspect "$c" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null || true)
  if echo "$MOUNTS" | grep -qF "$PROJECT_DIR"; then
    MATCHES+=("$c")
  fi
done

if [ ${#MATCHES[@]} -eq 0 ]; then
  echo "No Devpod containers found for this project."
  exit 0
fi

remove_container() {
  local c="$1"
  docker stop "$c" 2>/dev/null || true
  docker rm -f "$c" 2>/dev/null || true
}

if [ ${#MATCHES[@]} -eq 1 ]; then
  echo "Removing container ${MATCHES[0]}"
  remove_container "${MATCHES[0]}"
else
  echo "Multiple containers match:"
  for i in "${!MATCHES[@]}"; do
    STATUS=$(docker inspect "${MATCHES[$i]}" --format '{{.State.Status}}')
    NAME=$(docker inspect "${MATCHES[$i]}" --format '{{.Name}}' | sed 's|/||')
    echo "  $((i+1))) ${MATCHES[$i]} ($NAME, $STATUS)"
  done
  read -p "Which one to remove? (enter number, or 'all'): " CHOICE
  if [ "$CHOICE" = "all" ]; then
    for c in "${MATCHES[@]}"; do
      remove_container "$c"
    done
  elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#MATCHES[@]}" ]; then
    remove_container "${MATCHES[$((CHOICE-1))]}"
  else
    echo "Invalid choice."
    exit 1
  fi
fi

docker image prune -f 2>/dev/null || true
echo "Done. Reopen the project to trigger a fresh build."
