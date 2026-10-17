# LayoutPilot: local ZLE buffer only. No eval, terminal backspaces, history or command execution.
[[ -o interactive && -z ${_layoutpilot_loaded-} ]] || return
case ${TERM_PROGRAM-} in
  ghostty) typeset -g _layoutpilot_host=com.mitchellh.ghostty ;;
  Apple_Terminal) typeset -g _layoutpilot_host=com.apple.Terminal ;;
  *) return ;;
esac
zmodload zsh/net/socket || return
autoload -Uz add-zle-hook-widget
typeset -g _layoutpilot_loaded=1 _layoutpilot_fd='' _layoutpilot_nonce=$(/usr/bin/uuidgen)
typeset -g _layoutpilot_undo_left='' _layoutpilot_undo_right='' _layoutpilot_after_left='' _layoutpilot_after_right=''
typeset -gA _layoutpilot_space_widgets

_layoutpilot_finish() {
  if [[ -n $_layoutpilot_fd ]]; then
    zle -F $_layoutpilot_fd 2>/dev/null
    exec {_layoutpilot_fd}>&-
  fi
  _layoutpilot_fd=''
  _layoutpilot_after_left=''; _layoutpilot_undo_left=''
  _layoutpilot_after_right=''; _layoutpilot_undo_right=''
}
_layoutpilot_init() {
  [[ -z $_layoutpilot_fd ]] || return
  zsocket "$HOME/Library/Application Support/LayoutPilot/terminal.sock" 2>/dev/null || return
  _layoutpilot_fd=$REPLY
  print -r -u $_layoutpilot_fd -- $'hello\t'$_layoutpilot_host$'\t'$_layoutpilot_nonce
  local reply title=${${PWD:t}//[[:cntrl:]]/}
  if ! IFS= read -r -t 0.5 -u $_layoutpilot_fd reply || [[ $reply != ready ]]; then _layoutpilot_finish; return; fi
  printf '\e]0;%s [LP:%s]\a' "${title:-zsh}" "$_layoutpilot_nonce"
  zle -F $_layoutpilot_fd _layoutpilot_message
}
_layoutpilot_edit() {
  [[ -n $_layoutpilot_fd ]] || return 1
  local mode=$1 left=$LBUFFER right=$RBUFFER word=${LBUFFER##*[[:space:]]} reply replacement
  [[ -n $word && ${#word} -le 128 && $word != *[[:cntrl:]]* ]] || return 1
  [[ -z $right || ${right[1]} == [[:space:]] ]] || return 1
  print -r -u $_layoutpilot_fd -- $mode$'\t'$word
  local attempt
  for attempt in 1 2 3 4; do
    if ! IFS= read -r -t 0.25 -u $_layoutpilot_fd reply; then _layoutpilot_finish; return 1; fi
    [[ $reply == manual || $reply == undo ]] || break
  done
  [[ $reply == edit$'\t'* && $LBUFFER == "$left" && $RBUFFER == "$right" ]] || return 1
  replacement=${reply#*$'\t'}
  [[ -n $replacement && $replacement != *[[:cntrl:]]* && ${#replacement} -le 4096 ]] || return 1
  _layoutpilot_undo_left=$left; _layoutpilot_undo_right=$right
  LBUFFER="${left[1,${#left}-${#word}]}${replacement}"
  _layoutpilot_after_left=$LBUFFER; _layoutpilot_after_right=$RBUFFER
  print -r -u $_layoutpilot_fd -- applied
  return 0
}
_layoutpilot_manual() { _layoutpilot_edit manual; zle -R; }
_layoutpilot_undo() {
  [[ -n $_layoutpilot_fd && -n $_layoutpilot_after_left && $LBUFFER == "$_layoutpilot_after_left" && $RBUFFER == "$_layoutpilot_after_right" ]] || return
  LBUFFER=$_layoutpilot_undo_left; RBUFFER=$_layoutpilot_undo_right
  _layoutpilot_after_left=''; _layoutpilot_after_right=''
  print -r -u $_layoutpilot_fd -- undone
  zle -R
}
_layoutpilot_message() {
  local message
  if [[ -n ${2-} ]] || ! IFS= read -r -t 0.1 -u $1 message; then _layoutpilot_finish; return; fi
  case $message in
    manual) zle _layoutpilot_manual ;;
    undo) zle _layoutpilot_undo ;;
  esac
}
_layoutpilot_space() {
  local edited=1 old=${_layoutpilot_space_widgets[$KEYMAP]:-self-insert}
  _layoutpilot_after_left=''; _layoutpilot_after_right=''
  _layoutpilot_edit auto && edited=0
  zle "$old"
  if (( edited == 0 )) && [[ $LBUFFER == "$_layoutpilot_after_left " && $RBUFFER == "$_layoutpilot_after_right" ]]; then
    _layoutpilot_undo_left+=' '; _layoutpilot_after_left=$LBUFFER
  else
    _layoutpilot_after_left=''; _layoutpilot_after_right=''
  fi
}
zle -N _layoutpilot_manual
zle -N _layoutpilot_undo
zle -N _layoutpilot_space
typeset _layoutpilot_map
typeset -a _layoutpilot_binding
for _layoutpilot_map in emacs viins main; do
  _layoutpilot_binding=(${(z)"$(bindkey -M $_layoutpilot_map ' ')"})
  _layoutpilot_space_widgets[$_layoutpilot_map]=${_layoutpilot_binding[2]:-self-insert}
done
for _layoutpilot_map in emacs viins main; do bindkey -M $_layoutpilot_map ' ' _layoutpilot_space; done
unset _layoutpilot_map _layoutpilot_binding
add-zle-hook-widget line-init _layoutpilot_init
add-zle-hook-widget line-finish _layoutpilot_finish
