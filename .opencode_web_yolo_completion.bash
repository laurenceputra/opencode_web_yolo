_opencode_web_yolo_completion() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  local opts
  opts="--pull --no-pull --detach -d --foreground -f --mount-ssh -gh --gh --health diagnostics health config --version version --verbose -v --help -h help --"

  COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
}

complete -F _opencode_web_yolo_completion opencode_web_yolo
