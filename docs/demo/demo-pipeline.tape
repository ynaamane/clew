# Regenerates docs/demo-pipeline.gif. Run from the repo root: vhs docs/demo/demo-pipeline.tape
# The demo is a scripted simulation rendered by the real CLI code paths; see simulate_demo.py.

Output docs/demo-pipeline.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 760
Set Padding 24
Set WindowBar Colorful
Set Theme { "name": "clew", "background": "#1d1d18", "foreground": "#e8e6dc", "cursor": "#e8e6dc", "selection": "#3a3a30", "black": "#1d1d18", "red": "#e06c75", "green": "#98c379", "yellow": "#e0af68", "blue": "#7aa2f7", "magenta": "#c678dd", "cyan": "#56b6c2", "white": "#e8e6dc", "brightBlack": "#5c5c50", "brightRed": "#e06c75", "brightGreen": "#98c379", "brightYellow": "#e0af68", "brightBlue": "#7aa2f7", "brightMagenta": "#c678dd", "brightCyan": "#56b6c2", "brightWhite": "#ffffff" }

Hide
Type `clew() { uv run --quiet python docs/demo/simulate_demo.py "$@"; }; clew warm; PS1='$ '; clear`
Enter
Sleep 6s
Show

Type "clew"
Sleep 500ms
Enter
Sleep 18s
Sleep 3s
