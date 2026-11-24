#!/bin/bash
cd "$(dirname "$0")"
PORT=8080
echo "FoodGo shuru hocche... http://localhost:$PORT"
(sleep 2; (open http://localhost:$PORT || xdg-open http://localhost:$PORT) >/dev/null 2>&1) &
if command -v python3 >/dev/null; then python3 -m http.server $PORT
elif command -v npx >/dev/null; then npx --yes serve -l $PORT .
else echo "Python3 ba Node.js install koro, tarpor abar chalao."; read -p "Enter chapo..."; fi
