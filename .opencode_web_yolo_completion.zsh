#compdef opencode_web_yolo

_opencode_web_yolo_completion() {
  local -a opts
  opts=(
    '--pull:Force rebuild with docker pull'
    '--no-pull:Skip default pull-on-start for this run'
    '--detach:Run in background mode'
    '-d:Run in background mode'
    '--foreground:Run attached in current terminal'
    '-f:Run attached in current terminal'
    '--mount-ssh:Mount ~/.ssh into container (read-only)'
    '-gh:Mount authenticated GitHub CLI config'
    '--gh:Mount authenticated GitHub CLI config'
    '--health:Run diagnostics checks'
    'diagnostics:Run diagnostics checks'
    'health:Run diagnostics checks'
    'config:Generate sample config file'
    '--help:Show wrapper help'
    '-h:Show wrapper help'
    'help:Show wrapper help'
    '--version:Print wrapper version'
    'version:Print wrapper version'
    '--verbose:Enable verbose logs'
    '-v:Enable verbose logs'
  )

  _arguments '*: :->args'
  _describe 'opencode_web_yolo options' opts
}

_opencode_web_yolo_completion "$@"
